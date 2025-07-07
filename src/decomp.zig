const std = @import("std");

//
// Types
//

const DecompMap = struct {
    map: std.AutoHashMap(u32, []const u32),
    backing: ?[]const u32,
    alloc: std.mem.Allocator,

    pub fn deinit(self: *DecompMap) void {
        if (self.backing) |backing| {
            self.alloc.free(backing);
        } else {
            var it = self.map.iterator();
            while (it.next()) |entry| self.alloc.free(entry.value_ptr.*);
        }

        self.map.deinit();
    }
};

//
// Public functions
//

pub fn mapDecomps(alloc: std.mem.Allocator, data: *const []const u8) !DecompMap {
    var listed = std.AutoHashMap(u32, []const u32).init(alloc);
    defer {
        var it = listed.iterator();
        while (it.next()) |entry| alloc.free(entry.value_ptr.*);
        listed.deinit();
    }

    var canonical = std.AutoHashMap(u32, []const u32).init(alloc);

    var fields = std.ArrayList([]const u8).init(alloc);
    defer fields.deinit();

    var listed_decomps = std.ArrayList(u32).init(alloc);
    defer listed_decomps.deinit();

    var line_it = std.mem.splitScalar(u8, data.*, '\n');

    while (line_it.next()) |line| {
        if (line.len == 0) continue;

        fields.clearRetainingCapacity();

        var field_iter = std.mem.splitScalar(u8, line, ';');
        while (field_iter.next()) |field| try fields.append(field);

        const code_point = try std.fmt.parseInt(u32, fields.items[0], 16);

        if ((0x3400 <= code_point and code_point <= 0x4DBF) // CJK ext A
        or (0x4E00 <= code_point and code_point <= 0x9FFF) // CJK
        or (0xAC00 <= code_point and code_point <= 0xD7A3) // Hangul
        or (0xD800 <= code_point and code_point <= 0xDFFF) // Surrogates
        or (0xE000 <= code_point and code_point <= 0xF8FF) // Private use
        or (0x17000 <= code_point and code_point <= 0x187F7) // Tangut
        or (0x18D00 <= code_point and code_point <= 0x18D08) // Tangut suppl
        or (0x20000 <= code_point and code_point <= 0x2A6DF) // CJK ext B
        or (0x2A700 <= code_point and code_point <= 0x2B738) // CJK ext C
        or (0x2B740 <= code_point and code_point <= 0x2B81D) // CJK ext D
        or (0x2B820 <= code_point and code_point <= 0x2CEA1) // CJK ext E
        or (0x2CEB0 <= code_point and code_point <= 0x2EBE0) // CJK ext F
        or (0x30000 <= code_point and code_point <= 0x3134A) // CJK ext G
        or (0xF0000 <= code_point and code_point <= 0xFFFFD) // Plane 15 private use
        or (0x10_0000 <= code_point and code_point <= 0x10_FFFD) // Plane 16 private use
        ) {
            continue;
        }

        const decomp_column = fields.items[5];
        if (decomp_column.len == 0) continue; // No decomposition

        if (std.mem.indexOfScalar(u8, decomp_column, '<')) |_| {
            continue; // Non-canonical decomposition
        }

        listed_decomps.clearRetainingCapacity();

        var decomp_iter = std.mem.splitScalar(u8, decomp_column, ' ');
        while (decomp_iter.next()) |decomp_str| {
            std.debug.assert(4 <= decomp_str.len and decomp_str.len <= 5);

            const decomp = try std.fmt.parseInt(u32, decomp_str, 16);
            try listed_decomps.append(decomp);
        }

        std.debug.assert(listed_decomps.items.len > 0);

        try listed.put(code_point, try listed_decomps.toOwnedSlice());
    }

    var result = std.ArrayList(u32).init(alloc);
    defer result.deinit();

    var listed_it = listed.iterator();

    while (listed_it.next()) |kv| {
        const code_point = kv.key_ptr.*;
        const decomps = kv.value_ptr.*;

        const final_decomp: []const u32 = blk: {
            if (decomps.len == 1) {
                // Single-code-point decomposition; recurse simply
                break :blk try getCanonicalDecomp(alloc, &listed, decomps[0]);
            } else {
                // Multi-code-point decomposition; recurse badly
                result.clearRetainingCapacity();

                for (decomps) |d| {
                    const c = try getCanonicalDecomp(alloc, &listed, d);
                    defer alloc.free(c);

                    try result.appendSlice(c);
                }

                break :blk try result.toOwnedSlice();
            }
        };

        try canonical.put(code_point, final_decomp);
    }

    return DecompMap{
        .map = canonical,
        .backing = null,
        .alloc = alloc,
    };
}

pub fn loadDecompBin(alloc: std.mem.Allocator, path: []const u8) !DecompMap {
    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    var br = std.io.bufferedReader(file.reader());

    const count = try br.reader().readInt(u32, .little);
    const total_bytes = try br.reader().readInt(u32, .little);
    if (total_bytes > 50 * 1024) return error.FileTooLarge;

    const payload = try alloc.alloc(u8, total_bytes);
    defer alloc.free(payload);

    try br.reader().readNoEof(payload);

    const val_count = (total_bytes - (count * 5)) / 4;
    const vals = try alloc.alloc(u32, val_count);
    errdefer alloc.free(vals);

    var map = std.AutoHashMap(u32, []const u32).init(alloc);
    try map.ensureTotalCapacity(count);

    var offset: usize = 0;
    var vals_offset: usize = 0;
    var n: u32 = 0;

    while (n < count) : (n += 1) {
        const key_bytes = payload[offset..][0..@sizeOf(u32)];
        const key = std.mem.readInt(u32, key_bytes, .little);
        offset += @sizeOf(u32);

        const len = payload[offset];
        offset += @sizeOf(u8);

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

    return DecompMap{
        .map = map,
        .backing = vals,
        .alloc = alloc,
    };
}

pub fn loadDecompJson(alloc: std.mem.Allocator, path: []const u8) !DecompMap {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const file_size = try file.getEndPos();
    const contents = try alloc.alloc(u8, file_size);
    defer alloc.free(contents);

    var br = std.io.bufferedReader(file.reader());
    try br.reader().readNoEof(contents);

    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, contents, .{});
    defer parsed.deinit();

    const object = parsed.value.object;

    var map = std.AutoHashMap(u32, []const u32).init(alloc);
    errdefer map.deinit();

    var it = object.iterator();
    while (it.next()) |entry| {
        const key = try std.fmt.parseInt(u32, entry.key_ptr.*, 10);

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

    return DecompMap{
        .map = map,
        .backing = null,
        .alloc = alloc,
    };
}

pub fn saveDecompBin(
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

    const count = std.mem.nativeToLittle(u32, @intCast(map.count()));
    const total_bytes = std.mem.nativeToLittle(u32, payload_bytes);

    // Map header
    try buffer.appendSlice(std.mem.asBytes(&count));
    try buffer.appendSlice(std.mem.asBytes(&total_bytes));

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

pub fn saveDecompJson(
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

//
// Private functions
//

fn getCanonicalDecomp(
    alloc: std.mem.Allocator,
    listed: *const std.AutoHashMap(u32, []const u32),
    code_point: u32,
) ![]const u32 {
    const decomp = listed.get(code_point) orelse {
        const result = try alloc.alloc(u32, 1);
        result[0] = code_point;
        return result;
    };

    // If the decomposition is a single code point, return it directly
    if (decomp.len == 1) {
        const result = try alloc.alloc(u32, 1);
        result[0] = decomp[0];
        return result;
    }

    // Otherwise, we need to recurse for the canonical decomposition
    var result = std.ArrayList(u32).init(alloc);

    for (decomp) |d| {
        const c = try getCanonicalDecomp(alloc, listed, d);
        defer alloc.free(c);

        try result.appendSlice(c);
    }

    return result.toOwnedSlice();
}
