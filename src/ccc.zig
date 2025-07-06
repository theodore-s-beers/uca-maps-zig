const std = @import("std");

const CccEntry = packed struct {
    key: u32,
    value: u8,
};

pub fn mapCCC(alloc: std.mem.Allocator, data: *const []const u8) !std.AutoHashMap(u32, u8) {
    var map = std.AutoHashMap(u32, u8).init(alloc);

    var lines = std.mem.splitScalar(u8, data.*, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;

        var fields = std.ArrayList([]const u8).init(alloc);
        defer fields.deinit();

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

pub fn loadCCC(alloc: std.mem.Allocator, path: []const u8) !std.AutoHashMap(u32, u8) {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    var br = std.io.bufferedReader(file.reader());

    const count = try br.reader().readInt(u32, .little);
    const bytes_needed: usize = @as(usize, count) * @sizeOf(CccEntry);
    if (bytes_needed > 10 * 1024) return error.FileTooLarge;

    const payload = try alloc.alloc(u8, bytes_needed);
    defer alloc.free(payload);

    try br.reader().readNoEof(payload);
    const entries = std.mem.bytesAsSlice(CccEntry, payload);
    std.debug.assert(entries.len == count);

    var map = std.AutoHashMap(u32, u8).init(alloc);
    try map.ensureTotalCapacity(count);

    for (entries) |e| {
        const key = std.mem.littleToNative(u32, e.key);
        const value = e.value; // u8 has no endianness
        try map.put(key, value);
    }

    return map;
}

pub fn saveCccBin(map: *const std.AutoHashMap(u32, u8), path: []const u8) !void {
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();

    var bw = std.io.bufferedWriter(file.writer());
    try bw.writer().writeInt(u32, @intCast(map.count()), .little);

    var it = map.iterator();
    while (it.next()) |kv| {
        const e = CccEntry{
            .key = std.mem.nativeToLittle(u32, kv.key_ptr.*),
            .value = kv.value_ptr.*, // u8 has no endianness
        };

        try bw.writer().writeStruct(e);
    }

    try bw.flush();
}

pub fn saveCccJson(
    alloc: std.mem.Allocator,
    map: *const std.AutoHashMap(u32, u8),
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
        try ws.write(entry.value_ptr.*);

        alloc.free(key_str);
    }

    try ws.endObject();
}
