const std = @import("std");

const util = @import("util");

//
// Types
//

const SinglesEntryHeader = packed struct {
    key: u32,
    len: u8,
};

const SinglesMapHeader = packed struct {
    count: u32,
    total_bytes: u32,
};

//
// Public functions
//

pub fn mapSingles(alloc: std.mem.Allocator, data: *const []const u8) !std.AutoHashMap(u32, []const u32) {
    var map = std.AutoHashMap(u32, []const u32).init(alloc);
    errdefer {
        var it = map.iterator();
        while (it.next()) |entry| alloc.free(entry.value_ptr.*);
        map.deinit();
    }

    var line_it = std.mem.splitScalar(u8, data.*, '\n');
    while (line_it.next()) |line| {
        if (line.len == 0 or !util.HEX.isSet(line[0])) continue;

        var split_semi = std.mem.splitScalar(u8, line, ';');

        var points_str = split_semi.next() orelse return error.InvalidData;
        points_str = std.mem.trim(u8, points_str, " ");

        var points = std.ArrayList(u32).init(alloc);
        defer points.deinit();

        var split_space = std.mem.splitScalar(u8, points_str, ' ');
        while (split_space.next()) |cp_str| {
            const cp = try std.fmt.parseInt(u32, cp_str, 16);
            try points.append(cp);
        }

        std.debug.assert(1 <= points.items.len and points.items.len <= 3);
        if (points.items.len > 1) continue;

        const key = points.items[0];

        const remainder = split_semi.next() orelse return error.InvalidData;
        var split_hash = std.mem.splitScalar(u8, remainder, '#');

        var weights_str = split_hash.next() orelse return error.InvalidData;
        weights_str = std.mem.trim(u8, weights_str, " []");

        var weights = std.ArrayList(u32).init(alloc);
        errdefer weights.deinit();

        var split_bracket = std.mem.splitScalar(u8, weights_str, '[');
        while (split_bracket.next()) |x| {
            var weight_str = std.mem.trim(u8, x, " ]");
            if (weight_str.len == 0) continue;

            std.debug.assert(weight_str.len == 15); // One set of weights

            const variable = weight_str[0] == '*';

            weight_str = std.mem.trim(u8, weight_str, ".*");
            var split_period = std.mem.splitScalar(u8, weight_str, '.');

            const primary_str = split_period.next() orelse return error.InvalidData;
            const primary = try std.fmt.parseInt(u16, primary_str, 16);

            const secondary_str = split_period.next() orelse return error.InvalidData;
            const secondary = try std.fmt.parseInt(u16, secondary_str, 16);

            const tertiary_str = split_period.next() orelse return error.InvalidData;
            const tertiary = try std.fmt.parseInt(u8, tertiary_str, 16);

            const weights_packed = util.packWeights(variable, primary, secondary, tertiary);
            try weights.append(weights_packed);
        }

        std.debug.assert(1 <= weights.items.len and weights.items.len <= 18);
        try map.put(key, try weights.toOwnedSlice());
    }

    return map;
}

pub fn loadSingles(alloc: std.mem.Allocator, path: []const u8) !std.AutoHashMap(u32, []u32) {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    var br = std.io.bufferedReader(file.reader());

    const main_header = try br.reader().readStruct(SinglesMapHeader);
    const count = std.mem.littleToNative(u32, main_header.count);

    const total_bytes = std.mem.littleToNative(u32, main_header.total_bytes);
    if (total_bytes > 1024 * 1024) return error.FileTooLarge;

    const payload = try alloc.alloc(u8, total_bytes);
    defer alloc.free(payload);

    try br.reader().readNoEof(payload);

    var map = std.AutoHashMap(u32, []u32).init(alloc);
    try map.ensureTotalCapacity(count);

    var offset: usize = 0;
    var n: u32 = 0;

    while (n < count) : (n += 1) {
        const header = std.mem.bytesToValue(
            SinglesEntryHeader,
            payload[offset..][0..@sizeOf(SinglesEntryHeader)],
        );
        offset += @sizeOf(SinglesEntryHeader);

        const key = std.mem.littleToNative(u32, header.key);

        const values_len = header.len; // u8 has no endianness
        const value_bytes = values_len * @sizeOf(u32);

        const vals = try alloc.alloc(u32, values_len);
        errdefer alloc.free(vals);

        const payload_vals = std.mem.bytesAsSlice(u32, payload[offset..][0..value_bytes]);
        for (payload_vals, vals) |src, *dst| {
            dst.* = std.mem.littleToNative(u32, src);
        }

        map.putAssumeCapacityNoClobber(key, vals);
        offset += value_bytes;
    }

    return map;
}

pub fn saveSinglesBin(
    alloc: std.mem.Allocator,
    map: *const std.AutoHashMap(u32, []const u32),
    path: []const u8,
) !void {
    var buffer = std.ArrayList(u8).init(alloc);
    defer buffer.deinit();

    var payload_bytes: u32 = 0;
    var payload_iter = map.iterator();
    while (payload_iter.next()) |kv| {
        const values = kv.value_ptr.*;
        payload_bytes += @sizeOf(SinglesEntryHeader);
        payload_bytes += @intCast(values.len * @sizeOf(u32));
    }

    const main_header = SinglesMapHeader{
        .count = std.mem.nativeToLittle(u32, @intCast(map.count())),
        .total_bytes = std.mem.nativeToLittle(u32, payload_bytes),
    };
    try buffer.appendSlice(std.mem.asBytes(&main_header));

    var write_iter = map.iterator();
    while (write_iter.next()) |kv| {
        const values = kv.value_ptr.*;
        const entry_header = SinglesEntryHeader{
            .key = std.mem.nativeToLittle(u32, kv.key_ptr.*),
            .len = @intCast(values.len), // u8 has no endianness
        };

        try buffer.appendSlice(std.mem.asBytes(&entry_header));
        for (values) |v| {
            try buffer.appendSlice(std.mem.asBytes(&std.mem.nativeToLittle(u32, v)));
        }
    }

    const file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();

    try file.writeAll(buffer.items);
}

pub fn saveSinglesJson(
    alloc: std.mem.Allocator,
    map: *const std.AutoHashMap(u32, []const u32),
    path: []const u8,
) !void {
    const file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();

    var ws = std.json.writeStream(file.writer(), .{});
    try ws.beginObject();

    var it = map.iterator();
    while (it.next()) |entry| {
        const key_str = try std.fmt.allocPrint(alloc, "{}", .{entry.key_ptr.*});

        try ws.objectField(key_str);
        alloc.free(key_str);

        try ws.beginArray();
        for (entry.value_ptr.*) |value| try ws.write(value);
        try ws.endArray();
    }

    try ws.endObject();
}
