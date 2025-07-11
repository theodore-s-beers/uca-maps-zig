const std = @import("std");

const ccc = @import("ccc");
const decomp = @import("decomp");
const util = @import("util");

pub fn mapFCD(alloc: std.mem.Allocator, data: []const u8) !std.AutoHashMap(u32, u16) {
    //
    // Load decomposition map
    //

    var decomp_data = try decomp.loadDecompBin(alloc, "bin/decomp.bin");
    defer decomp_data.deinit();

    //
    // Load CCC map
    //

    var ccc_map = try ccc.loadCccBin(alloc, "bin/ccc.bin");
    defer ccc_map.deinit();

    //
    // Set up FCD map
    //

    var fcd_map = std.AutoHashMap(u32, u16).init(alloc);
    errdefer fcd_map.deinit();

    //
    // Iterate over lines and find combining classes
    //

    var fields = std.ArrayList([]const u8).init(alloc);
    defer fields.deinit();

    var line_iter = std.mem.splitScalar(u8, data, '\n');

    while (line_iter.next()) |line| {
        if (line.len == 0) continue;

        fields.clearRetainingCapacity();

        var field_iter = std.mem.splitScalar(u8, line, ';');
        while (field_iter.next()) |field| try fields.append(field);

        const code_point = try std.fmt.parseInt(u32, fields.items[0], 16);

        for (util.IGNORED_RANGES) |range| {
            if (range.contains(code_point)) continue;
        }

        const decomps: []const u32 = decomp_data.map.get(code_point) orelse continue;

        const first_ccc: u8 = ccc_map.get(decomps[0]) orelse 0;
        const last_ccc: u8 = ccc_map.get(decomps[decomps.len - 1]) orelse 0;

        const fcd: u16 = @as(u16, first_ccc) << 8 | @as(u16, last_ccc);
        if (fcd == 0) continue;

        try fcd_map.put(code_point, fcd);
    }

    return fcd_map;
}

pub fn loadFcdBin(alloc: std.mem.Allocator, path: []const u8) !std.AutoHashMap(u32, u16) {
    const data = try std.fs.cwd().readFileAlloc(alloc, path, 8 * 1024);
    defer alloc.free(data);

    const entry_size = @sizeOf(u32) + @sizeOf(u16);
    const count: u32 = @intCast(data.len / entry_size);

    var map = std.AutoHashMap(u32, u16).init(alloc);
    errdefer map.deinit();

    try map.ensureTotalCapacity(count);

    var offset: usize = 0;
    while (offset < data.len) : (offset += entry_size) {
        const key_bytes = data[offset..][0..@sizeOf(u32)];
        const key = std.mem.readInt(u32, key_bytes, .little);

        const value_bytes = data[offset + @sizeOf(u32) ..][0..@sizeOf(u16)];
        const value = std.mem.readInt(u16, value_bytes, .little);

        map.putAssumeCapacityNoClobber(key, value);
    }

    return map;
}

pub fn loadFcdJson(alloc: std.mem.Allocator, path: []const u8) !std.AutoHashMap(u32, u16) {
    const data = try std.fs.cwd().readFileAlloc(alloc, path, 16 * 1024);
    defer alloc.free(data);

    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, data, .{});
    defer parsed.deinit();

    const object = parsed.value.object;

    var map = std.AutoHashMap(u32, u16).init(alloc);
    errdefer map.deinit();

    try map.ensureTotalCapacity(@intCast(object.count()));

    var it = object.iterator();
    while (it.next()) |entry| {
        const key = try std.fmt.parseInt(u32, entry.key_ptr.*, 10);
        const value = switch (entry.value_ptr.*) {
            .integer => |i| @as(u16, @intCast(i)),
            else => return error.InvalidData,
        };

        map.putAssumeCapacityNoClobber(key, value);
    }

    return map;
}

pub fn saveFcdBin(
    alloc: std.mem.Allocator,
    map: *const std.AutoHashMap(u32, u16),
    path: []const u8,
) !void {
    var buffer = std.ArrayList(u8).init(alloc);
    defer buffer.deinit();

    var it = map.iterator();
    while (it.next()) |kv| {
        const key = std.mem.nativeToLittle(u32, kv.key_ptr.*);
        const value = std.mem.nativeToLittle(u16, kv.value_ptr.*);

        try buffer.appendSlice(std.mem.asBytes(&key));
        try buffer.appendSlice(std.mem.asBytes(&value));
    }

    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();

    try file.writeAll(buffer.items);
}

pub fn saveFcdJson(
    alloc: std.mem.Allocator,
    map: *const std.AutoHashMap(u32, u16),
    path: []const u8,
) !void {
    var buffer = std.ArrayList(u8).init(alloc);
    defer buffer.deinit();

    var ws = std.json.writeStream(buffer.writer(), .{});

    try ws.beginObject();

    var key_buf: [16]u8 = undefined;

    var map_iter = map.iterator();
    while (map_iter.next()) |entry| {
        const key_str = try std.fmt.bufPrint(&key_buf, "{}", .{entry.key_ptr.*});
        try ws.objectField(key_str);

        try ws.write(entry.value_ptr.*);
    }

    try ws.endObject();

    const file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();

    try file.writeAll(buffer.items);
}
