const std = @import("std");

const util = @import("util");

//
// Public functions
//

pub fn mapDecomps(alloc: std.mem.Allocator, data: []const u8) !util.SinglesMap {
    var listed = std.AutoHashMap(u32, []const u32).init(alloc);
    defer {
        var it = listed.iterator();
        while (it.next()) |entry| alloc.free(entry.value_ptr.*);
        listed.deinit();
    }

    var canonical = std.AutoHashMap(u32, []const u32).init(alloc);
    errdefer {
        var it = canonical.iterator();
        while (it.next()) |entry| alloc.free(entry.value_ptr.*);
        canonical.deinit();
    }

    var fields: std.ArrayList([]const u8) = .empty;
    defer fields.deinit(alloc);

    var listed_decomps: std.ArrayList(u32) = .empty;
    defer listed_decomps.deinit(alloc);

    var line_it = std.mem.splitScalar(u8, data, '\n');

    while (line_it.next()) |line| {
        if (line.len == 0) continue;

        fields.clearRetainingCapacity();

        var field_iter = std.mem.splitScalar(u8, line, ';');
        while (field_iter.next()) |field| try fields.append(alloc, field);

        const code_point = try std.fmt.parseInt(u32, fields.items[0], 16);

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
            try listed_decomps.append(alloc, decomp);
        }

        std.debug.assert(listed_decomps.items.len > 0);

        const row = try listed_decomps.toOwnedSlice(alloc);
        errdefer alloc.free(row);
        try listed.put(code_point, row);
    }

    var result: std.ArrayList(u32) = .empty;
    defer result.deinit(alloc);

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

                    try result.appendSlice(alloc, c);
                }

                break :blk try result.toOwnedSlice(alloc);
            }
        };

        errdefer alloc.free(final_decomp);
        try canonical.put(code_point, final_decomp);
    }

    return util.SinglesMap{
        .map = canonical,
        .backing = null,
        .alloc = alloc,
    };
}

pub fn loadDecompBin(io: std.Io, alloc: std.mem.Allocator, path: []const u8) !util.SinglesMap {
    const data = try std.Io.Dir.cwd().readFileAlloc(io, path, alloc, .limited(32 * 1024));
    defer alloc.free(data);

    // Map header
    const count = std.mem.readInt(u32, data[0..@sizeOf(u32)], .little);
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

pub fn loadDecompJson(io: std.Io, alloc: std.mem.Allocator, path: []const u8) !util.SinglesMap {
    const data = try std.Io.Dir.cwd().readFileAlloc(io, path, alloc, .limited(64 * 1024));
    defer alloc.free(data);

    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, data, .{});
    defer parsed.deinit();

    const object = parsed.value.object;

    var map = std.AutoHashMap(u32, []const u32).init(alloc);
    errdefer {
        var it = map.iterator();
        while (it.next()) |entry| alloc.free(entry.value_ptr.*);
        map.deinit();
    }

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

pub fn saveDecompBin(
    io: std.Io,
    alloc: std.mem.Allocator,
    map: *const std.AutoHashMap(u32, []const u32),
    path: []const u8,
) !void {
    var buffer: std.ArrayList(u8) = .empty;
    defer buffer.deinit(alloc);

    // Map header
    const count = std.mem.nativeToLittle(u32, @intCast(map.count()));
    try buffer.appendSlice(alloc, std.mem.asBytes(&count));

    var write_iter = map.iterator();
    while (write_iter.next()) |kv| {
        const key = std.mem.nativeToLittle(u32, kv.key_ptr.*);
        const len: u8 = @intCast(kv.value_ptr.len); // u8 has no endianness

        // Entry header
        try buffer.appendSlice(alloc, std.mem.asBytes(&key));
        try buffer.appendSlice(alloc, std.mem.asBytes(&len));

        // Entry values
        for (kv.value_ptr.*) |v| {
            try buffer.appendSlice(alloc, std.mem.asBytes(&std.mem.nativeToLittle(u32, v)));
        }
    }

    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = buffer.items });
}

pub fn saveDecompJson(
    io: std.Io,
    alloc: std.mem.Allocator,
    map: *const std.AutoHashMap(u32, []const u32),
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

        try ws.beginArray();
        for (entry.value_ptr.*) |value| try ws.write(value);
        try ws.endArray();
    }

    try ws.endObject();

    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = buffer.written() });
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
    var result: std.ArrayList(u32) = .empty;
    errdefer result.deinit(alloc);

    for (decomp) |d| {
        const c = try getCanonicalDecomp(alloc, listed, d);
        defer alloc.free(c);

        try result.appendSlice(alloc, c);
    }

    return result.toOwnedSlice(alloc);
}

fn checkDecompAllocations(alloc: std.mem.Allocator) !void {
    var result = try mapDecomps(alloc, "00C0;TEST;Lu;0;L;0041 0300\n00C1;TEST;Lu;0;L;00C0 0301\n00C2;TEST;Lu;0;L;00C1 0302\n00C3;TEST;Lu;0;L;00C2 0303\n00C4;TEST;Lu;0;L;0041\n00C5;TEST;Lu;0;L;0042\n00C6;TEST;Lu;0;L;0043\n00C7;TEST;Lu;0;L;0044\n");
    defer result.deinit();
    try std.testing.expectEqual(8, result.map.count());
    try std.testing.expectEqualSlices(u32, &.{ 0x41, 0x300, 0x301, 0x302, 0x303 }, result.map.get(0xC3).?);
}

test "decomposition mapping cleans up every allocation failure" {
    // Force resize/remap to allocate so the failure sequence is deterministic.
    var no_resize = std.testing.FailingAllocator.init(std.testing.allocator, .{ .resize_fail_index = 0 });
    try std.testing.checkAllAllocationFailures(no_resize.allocator(), checkDecompAllocations, .{});
}

test "decompositions follow Unicode mappings rather than block ranges" {
    var result = try mapDecomps(std.testing.allocator,
        \\3400;CJK;Lo;0;L;
        \\AC00;HANGUL;Lo;0;L;
        \\E000;PRIVATE USE;Co;0;L;
        \\FB01;LIGATURE FI;Ll;0;L;<compat> 0066 0069
        \\00C0;A WITH GRAVE;Lu;0;L;0041 0300
        \\F900;CJK COMPATIBILITY IDEOGRAPH;Lo;0;L;8C48
    );
    defer result.deinit();
    try std.testing.expectEqual(2, result.map.count());
    try std.testing.expectEqualSlices(u32, &.{ 0x41, 0x300 }, result.map.get(0xC0).?);
    try std.testing.expectEqualSlices(u32, &.{0x8C48}, result.map.get(0xF900).?);
}
