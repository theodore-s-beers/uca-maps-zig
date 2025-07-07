const std = @import("std");

const util = @import("util");

//
// Public functions
//

pub fn mapSingles(alloc: std.mem.Allocator, data: []const u8) !util.SinglesMap {
    var map = std.AutoHashMap(u32, []const u32).init(alloc);
    errdefer {
        var it = map.iterator();
        while (it.next()) |entry| alloc.free(entry.value_ptr.*);
        map.deinit();
    }

    var points = std.ArrayList(u32).init(alloc);
    defer points.deinit();

    var weights = std.ArrayList(u32).init(alloc);
    defer weights.deinit();

    var line_it = std.mem.splitScalar(u8, data, '\n');
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
        if (points.items.len > 1) continue;

        const key = points.items[0];

        const remainder = split_semi.next() orelse return error.InvalidData;
        var split_hash = std.mem.splitScalar(u8, remainder, '#');

        var weights_str = split_hash.next() orelse return error.InvalidData;
        weights_str = std.mem.trim(u8, weights_str, " []");

        weights.clearRetainingCapacity();

        var split_bracket = std.mem.splitScalar(u8, weights_str, '[');
        while (split_bracket.next()) |segment| {
            var weight_str = std.mem.trim(u8, segment, " ]");
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

    return util.SinglesMap{
        .map = map,
        .backing = null,
        .alloc = alloc,
    };
}

pub fn loadSinglesBin(alloc: std.mem.Allocator, path: []const u8) !util.SinglesMap {
    const data = try std.fs.cwd().readFileAlloc(alloc, path, 512 * 1024);
    defer alloc.free(data);

    const count = std.mem.readInt(u32, data[0..@sizeOf(u32)], .little); // Map header
    const payload = data[@sizeOf(u32)..];

    const entry_header_size = @sizeOf(u32) + @sizeOf(u8);
    const val_count = (payload.len - (count * entry_header_size)) / @sizeOf(u32);

    const vals = try alloc.alloc(u32, val_count);
    errdefer alloc.free(vals);

    var map = std.AutoHashMap(u32, []const u32).init(alloc);
    errdefer map.deinit();

    try map.ensureTotalCapacity(count);

    var offset: usize = 0;
    var vals_offset: usize = 0;
    var n: u32 = 0;

    while (n < count) : (n += 1) {
        // Entry header: key
        const key_bytes = payload[offset..][0..@sizeOf(u32)];
        const key = std.mem.readInt(u32, key_bytes, .little);
        offset += @sizeOf(u32);

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

    return util.SinglesMap{
        .map = map,
        .backing = vals,
        .alloc = alloc,
    };
}

pub fn loadSinglesJson(alloc: std.mem.Allocator, path: []const u8) !util.SinglesMap {
    const data = try std.fs.cwd().readFileAlloc(alloc, path, 1024 * 1024);
    defer alloc.free(data);

    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, data, .{});
    defer parsed.deinit();

    const object = parsed.value.object;

    var map = std.AutoHashMap(u32, []const u32).init(alloc);
    errdefer map.deinit();

    var it = object.iterator();
    while (it.next()) |entry| {
        const key = try std.fmt.parseInt(u32, entry.key_ptr.*, 10);

        const array = entry.value_ptr.*.array;
        const vals = try alloc.alloc(u32, array.items.len);
        errdefer alloc.free(vals);

        for (array.items, vals) |item, *dst| {
            dst.* = switch (item) {
                .integer => |i| @as(u32, @intCast(i)),
                else => return error.InvalidData,
            };
        }

        try map.put(key, vals);
    }

    return util.SinglesMap{
        .map = map,
        .backing = null,
        .alloc = alloc,
    };
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
        // Entry header
        payload_bytes += @sizeOf(u32); // Key
        payload_bytes += @sizeOf(u8); // Length

        // Entry values
        payload_bytes += @intCast(kv.value_ptr.len * @sizeOf(u32));
    }

    // Map header
    const count = std.mem.nativeToLittle(u32, @intCast(map.count()));
    try buffer.appendSlice(std.mem.asBytes(&count));

    var write_iter = map.iterator();
    while (write_iter.next()) |kv| {
        const key = std.mem.nativeToLittle(u32, kv.key_ptr.*);
        const len: u8 = @intCast(kv.value_ptr.len); // u8 has no endianness

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

pub fn saveSinglesJson(
    alloc: std.mem.Allocator,
    map: *const std.AutoHashMap(u32, []const u32),
    path: []const u8,
) !void {
    var buffer = std.ArrayList(u8).init(alloc);
    defer buffer.deinit();

    var ws = std.json.writeStream(buffer.writer(), .{});

    try ws.beginObject();

    var key_buf: [16]u8 = undefined;

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
