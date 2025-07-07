const std = @import("std");

const util = @import("util");

//
// Public functions
//

pub fn mapMulti(alloc: std.mem.Allocator, data: *const []const u8) !util.MultiMap {
    var map = std.AutoHashMap(u64, []const u32).init(alloc);
    errdefer {
        var it = map.iterator();
        while (it.next()) |entry| alloc.free(entry.value_ptr.*);
        map.deinit();
    }

    var points = std.ArrayList(u32).init(alloc);
    defer points.deinit();

    var weights = std.ArrayList(u32).init(alloc);
    errdefer weights.deinit();

    var line_it = std.mem.splitScalar(u8, data.*, '\n');
    while (line_it.next()) |line| {
        if (line.len == 0 or !util.HEX.isSet(line[0])) continue;

        var split_semi = std.mem.splitScalar(u8, line, ';');

        var points_str = split_semi.next() orelse return error.InvalidData;
        points_str = std.mem.trim(u8, points_str, " ");

        points.clearRetainingCapacity();

        var split_space = std.mem.splitScalar(u8, points_str, ' ');
        while (split_space.next()) |cp_str| {
            const cp = try std.fmt.parseInt(u32, cp_str, 16);
            try points.append(cp);
        }

        std.debug.assert(1 <= points.items.len and points.items.len <= 3);
        if (points.items.len == 1) continue;

        const key = packCodePoints(&points.items);

        const remainder = split_semi.next() orelse return error.InvalidData;
        var split_hash = std.mem.splitScalar(u8, remainder, '#');

        var weights_str = split_hash.next() orelse return error.InvalidData;
        weights_str = std.mem.trim(u8, weights_str, " []");

        weights.clearRetainingCapacity();

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

        std.debug.assert(1 <= weights.items.len and weights.items.len <= 3);
        try map.put(key, try weights.toOwnedSlice());
    }

    return util.MultiMap{
        .map = map,
        .backing = null,
        .alloc = alloc,
    };
}

pub fn loadMultiBin(alloc: std.mem.Allocator, path: []const u8) !util.MultiMap {
    const data = try std.fs.cwd().readFileAlloc(alloc, path, 32 * 1024);
    defer alloc.free(data);

    // Map header
    const count = std.mem.readInt(u16, data[0..@sizeOf(u16)], .little);
    const payload = data[@sizeOf(u16)..];

    const entry_header_size = @sizeOf(u64) + @sizeOf(u8);
    const val_count = (payload.len - (count * entry_header_size)) / @sizeOf(u32);

    const vals = try alloc.alloc(u32, val_count);
    errdefer alloc.free(vals);

    var map = std.AutoHashMap(u64, []const u32).init(alloc);
    errdefer map.deinit();

    try map.ensureTotalCapacity(count);

    var offset: usize = 0;
    var vals_offset: usize = 0;
    var n: u16 = 0;

    while (n < count) : (n += 1) {
        // Entry header: key
        const key_bytes = payload[offset..][0..@sizeOf(u64)];
        const key = std.mem.readInt(u64, key_bytes, .little);
        offset += @sizeOf(u64);

        // Entry header: length
        const len = payload[offset];
        offset += @sizeOf(u8);

        // Entry values
        const val_bytes = len * @sizeOf(u32);
        const entry_vals = vals[vals_offset .. vals_offset + len];
        vals_offset += len;

        const payload_vals = std.mem.bytesAsSlice(u32, payload[offset..][0..val_bytes]);
        for (payload_vals, entry_vals) |src, *dst| {
            dst.* = std.mem.littleToNative(u32, src);
        }

        map.putAssumeCapacityNoClobber(key, entry_vals);
        offset += val_bytes;
    }

    return util.MultiMap{
        .map = map,
        .backing = vals,
        .alloc = alloc,
    };
}

pub fn loadMultiJson(alloc: std.mem.Allocator, path: []const u8) !util.MultiMap {
    const data = try std.fs.cwd().readFileAlloc(alloc, path, 64 * 1024);
    defer alloc.free(data);

    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, data, .{});
    defer parsed.deinit();

    const object = parsed.value.object;

    var map = std.AutoHashMap(u64, []const u32).init(alloc);
    errdefer {
        var it = map.iterator();
        while (it.next()) |entry| alloc.free(entry.value_ptr.*);
        map.deinit();
    }

    var it = object.iterator();
    while (it.next()) |entry| {
        const key = try std.fmt.parseInt(u64, entry.key_ptr.*, 10);

        const array = entry.value_ptr.*.array;
        const vals = try alloc.alloc(u32, array.items.len);

        for (array.items, vals) |item, *dst| {
            dst.* = switch (item) {
                .integer => |i| @as(u32, @intCast(i)),
                else => return error.InvalidData,
            };
        }

        try map.put(key, vals);
    }

    return util.MultiMap{
        .map = map,
        .backing = null,
        .alloc = alloc,
    };
}

pub fn saveMultiBin(
    alloc: std.mem.Allocator,
    map: *const std.AutoHashMap(u64, []const u32),
    path: []const u8,
) !void {
    var buffer = std.ArrayList(u8).init(alloc);
    defer buffer.deinit();

    var payload_bytes: u16 = 0;

    var payload_iter = map.iterator();
    while (payload_iter.next()) |kv| {
        // Entry header
        payload_bytes += @sizeOf(u64); // Key
        payload_bytes += @sizeOf(u8); // Length

        // Entry values
        payload_bytes += @intCast(kv.value_ptr.len * @sizeOf(u32));
    }

    // Map header
    const count = std.mem.nativeToLittle(u16, @intCast(map.count()));
    try buffer.appendSlice(std.mem.asBytes(&count));

    var write_iter = map.iterator();
    while (write_iter.next()) |kv| {
        const key = std.mem.nativeToLittle(u64, kv.key_ptr.*);
        const len: u8 = @intCast(kv.value_ptr.len);

        // Entry header
        try buffer.appendSlice(std.mem.asBytes(&key));
        try buffer.appendSlice(std.mem.asBytes(&len));

        // Entry values
        for (kv.value_ptr.*) |v| {
            try buffer.appendSlice(std.mem.asBytes(&std.mem.nativeToLittle(u32, v)));
        }
    }

    const file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();

    try file.writeAll(buffer.items);
}

pub fn saveMultiJson(
    alloc: std.mem.Allocator,
    map: *const std.AutoHashMap(u64, []const u32),
    path: []const u8,
) !void {
    var buffer = std.ArrayList(u8).init(alloc);
    defer buffer.deinit();

    var ws = std.json.writeStream(buffer.writer(), .{});

    try ws.beginObject();

    var key_buf: [32]u8 = undefined;

    var it = map.iterator();
    while (it.next()) |entry| {
        const key_str = try std.fmt.bufPrint(&key_buf, "{}", .{entry.key_ptr.*});
        try ws.objectField(key_str);

        try ws.beginArray();
        for (entry.value_ptr.*) |value| try ws.write(value);
        try ws.endArray();
    }

    try ws.endObject();

    const file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();

    try file.writeAll(buffer.items);
}

//
// Private functions
//

fn packCodePoints(code_points: *const []const u32) u64 {
    switch (code_points.len) {
        2 => {
            return (@as(u64, code_points.*[0]) << 21) | @as(u64, code_points.*[1]);
        },
        3 => {
            return (@as(u64, code_points.*[0]) << 42) |
                (@as(u64, code_points.*[1]) << 21) |
                @as(u64, code_points.*[2]);
        },
        else => unreachable,
    }
}
