const std = @import("std");

pub fn mapCCC(alloc: std.mem.Allocator, data: []const u8) !std.AutoHashMap(u32, u8) {
    var map = std.AutoHashMap(u32, u8).init(alloc);
    errdefer map.deinit();

    var fields: std.ArrayList([]const u8) = .empty;
    defer fields.deinit(alloc);

    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;

        fields.clearRetainingCapacity();

        var field_iter = std.mem.splitScalar(u8, line, ';');
        while (field_iter.next()) |field| try fields.append(alloc, field);

        const code_point = try std.fmt.parseInt(u32, fields.items[0], 16);

        const ccc_column = fields.items[3];
        std.debug.assert(1 <= ccc_column.len and ccc_column.len <= 3);

        const ccc = try std.fmt.parseInt(u8, ccc_column, 10);
        if (ccc == 0) continue;

        try map.put(code_point, ccc);
    }

    return map;
}

pub fn loadCccBin(io: std.Io, alloc: std.mem.Allocator, path: []const u8) !std.AutoHashMap(u32, u8) {
    const data = try std.Io.Dir.cwd().readFileAlloc(io, path, alloc, .limited(8 * 1024));
    defer alloc.free(data);

    const entry_size = @sizeOf(u32) + @sizeOf(u8);
    const count: u32 = @intCast(data.len / entry_size);

    var map = std.AutoHashMap(u32, u8).init(alloc);
    errdefer map.deinit();

    try map.ensureTotalCapacity(count);

    for (0..count) |i| {
        const offset = i * entry_size;

        const key_bytes = data[offset..][0..@sizeOf(u32)];
        const key = std.mem.readInt(u32, key_bytes, .little);
        const value = data[offset + @sizeOf(u32)];

        map.putAssumeCapacityNoClobber(key, value);
    }

    return map;
}

pub fn loadCccJson(io: std.Io, alloc: std.mem.Allocator, path: []const u8) !std.AutoHashMap(u32, u8) {
    const data = try std.Io.Dir.cwd().readFileAlloc(io, path, alloc, .limited(16 * 1024));
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
    io: std.Io,
    alloc: std.mem.Allocator,
    map: *const std.AutoHashMap(u32, u8),
    path: []const u8,
) !void {
    var buffer: std.ArrayList(u8) = .empty;
    defer buffer.deinit(alloc);

    var it = map.iterator();
    while (it.next()) |kv| {
        const key = std.mem.nativeToLittle(u32, kv.key_ptr.*);
        try buffer.appendSlice(alloc, std.mem.asBytes(&key));
        try buffer.append(alloc, kv.value_ptr.*);
    }

    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = buffer.items });
}

pub fn saveCccJson(
    io: std.Io,
    alloc: std.mem.Allocator,
    map: *const std.AutoHashMap(u32, u8),
    path: []const u8,
) !void {
    var buffer = std.Io.Writer.Allocating.init(alloc);
    defer buffer.deinit();

    var ws: std.json.Stringify = .{ .writer = &buffer.writer };

    try ws.beginObject();

    var key_buf: [16]u8 = undefined;

    var it = map.iterator();
    while (it.next()) |entry| {
        const key_str = try std.fmt.bufPrint(&key_buf, "{}", .{entry.key_ptr.*});
        try ws.objectField(key_str);

        try ws.write(entry.value_ptr.*);
    }

    try ws.endObject();

    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = buffer.written() });
}
