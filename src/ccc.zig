const std = @import("std");

pub fn mapCCC(alloc: std.mem.Allocator, data: *const []const u8) !std.AutoHashMap(u32, u8) {
    var map = std.AutoHashMap(u32, u8).init(alloc);

    var fields = std.ArrayList([]const u8).init(alloc);
    defer fields.deinit();

    var lines = std.mem.splitScalar(u8, data.*, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;

        fields.clearRetainingCapacity();

        var field_iter = std.mem.splitScalar(u8, line, ';');
        while (field_iter.next()) |field| try fields.append(field);

        const code_point = try std.fmt.parseInt(u32, fields.items[0], 16);

        const ccc_column = fields.items[3];
        std.debug.assert(1 <= ccc_column.len and ccc_column.len <= 3);

        const ccc = try std.fmt.parseInt(u8, ccc_column, 10);
        if (ccc == 0) continue;

        try map.put(code_point, ccc);
    }

    return map;
}

pub fn loadCccBin(alloc: std.mem.Allocator, path: []const u8) !std.AutoHashMap(u32, u8) {
    const data = try std.fs.cwd().readFileAlloc(alloc, path, 8 * 1024);
    defer alloc.free(data);

    const count = std.mem.readInt(u32, data[0..@sizeOf(u32)], .little);
    const payload = data[@sizeOf(u32)..];

    var map = std.AutoHashMap(u32, u8).init(alloc);
    errdefer map.deinit();

    try map.ensureTotalCapacity(count);

    const entry_size = @sizeOf(u32) + @sizeOf(u8);

    for (0..count) |i| {
        const offset = i * entry_size;

        const key_bytes = payload[offset..][0..@sizeOf(u32)];
        const key = std.mem.readInt(u32, key_bytes, .little);
        const value = payload[offset + @sizeOf(u32)];

        map.putAssumeCapacityNoClobber(key, value);
    }

    return map;
}

pub fn loadCccJson(alloc: std.mem.Allocator, path: []const u8) !std.AutoHashMap(u32, u8) {
    const data = try std.fs.cwd().readFileAlloc(alloc, path, 16 * 1024);
    defer alloc.free(data);

    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, data, .{});
    defer parsed.deinit();

    const object = parsed.value.object;

    var map = std.AutoHashMap(u32, u8).init(alloc);
    errdefer map.deinit();

    try map.ensureTotalCapacity(@intCast(object.count()));

    var it = object.iterator();
    while (it.next()) |entry| {
        const key = try std.fmt.parseInt(u32, entry.key_ptr.*, 10);
        const value = switch (entry.value_ptr.*) {
            .integer => |i| @as(u8, @intCast(i)),
            else => return error.InvalidData,
        };

        map.putAssumeCapacityNoClobber(key, value);
    }

    return map;
}

pub fn saveCccBin(
    alloc: std.mem.Allocator,
    map: *const std.AutoHashMap(u32, u8),
    path: []const u8,
) !void {
    var buffer = std.ArrayList(u8).init(alloc);
    defer buffer.deinit();

    const count = std.mem.nativeToLittle(u32, @intCast(map.count()));
    try buffer.appendSlice(std.mem.asBytes(&count)); // Map header

    var it = map.iterator();
    while (it.next()) |kv| {
        const key = std.mem.nativeToLittle(u32, kv.key_ptr.*);
        try buffer.appendSlice(std.mem.asBytes(&key));
        try buffer.append(kv.value_ptr.*);
    }

    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();

    try file.writeAll(buffer.items);
}

pub fn saveCccJson(
    alloc: std.mem.Allocator,
    map: *const std.AutoHashMap(u32, u8),
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

        try ws.write(entry.value_ptr.*);
    }

    try ws.endObject();

    const file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();

    try file.writeAll(buffer.items);
}
