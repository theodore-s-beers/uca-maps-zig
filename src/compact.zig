const std = @import("std");
const single = @import("single");
const multi = @import("multi");
const format = @import("collation_table.zig");

const Singles = std.AutoHashMap(u32, []const u32);
const Multis = std.AutoHashMap(u64, []const u32);
const Row = struct { start: u32, len: u16 };
const Node = struct {
    row: Row = .{ .start = 0, .len = 0 },
    children: std.AutoHashMap(u32, *Node),
    max_len: u8 = 1,
};

// All builder allocations belong to one arena and are released after writing.
const Builder = struct {
    alloc: std.mem.Allocator,
    rows: std.StringHashMap(Row),
    weights: std.ArrayList(u32),
    edges: std.ArrayList(format.Edge),
    meta: std.ArrayList(format.Meta),

    fn intern(self: *Builder, weights: []const u32) !Row {
        if (weights.len == 0 or weights.len > 18) return error.InvalidWeightCount;
        const slot = try self.rows.getOrPut(std.mem.sliceAsBytes(weights));
        if (!slot.found_existing) {
            slot.value_ptr.* = .{ .start = @intCast(self.weights.items.len), .len = @intCast(weights.len) };
            try self.weights.appendSlice(weights);
        }
        return slot.value_ptr.*;
    }

    fn node(self: *Builder) !*Node {
        const result = try self.alloc.create(Node);
        result.* = .{ .children = std.AutoHashMap(u32, *Node).init(self.alloc) };
        return result;
    }

    fn writeEdges(self: *Builder, node_: *const Node) anyerror!u16 {
        const keys = try self.alloc.alloc(u32, node_.children.count());
        var it = node_.children.keyIterator();
        var n: usize = 0;
        while (it.next()) |key| : (n += 1) keys[n] = key.*;
        std.mem.sort(u32, keys, {}, std.sort.asc(u32));

        const start = self.edges.items.len;
        for (keys) |key| {
            const child = node_.children.get(key).?;
            try self.edges.append(.{
                .codepoint = key,
                .next_first_edge = 0,
                .weight_start = child.row.start,
                .next_edge_len = 0,
                .weight_len = child.row.len,
            });
        }
        for (keys, 0..) |key, i| {
            const child = node_.children.get(key).?;
            if (child.children.count() == 0) continue;
            const child_start: u32 = @intCast(self.edges.items.len);
            const child_len = try self.writeEdges(child);
            self.edges.items[start + i].next_first_edge = child_start;
            self.edges.items[start + i].next_edge_len = child_len;
        }
        return @intCast(keys.len);
    }
};

fn unpack(key: u64) struct { points: [3]u32, len: usize } {
    const mask = 0x1FFFFF;
    if (key >> 42 != 0) return .{
        .points = .{ @intCast(key >> 42), @intCast((key >> 21) & mask), @intCast(key & mask) },
        .len = 3,
    };
    return .{ .points = .{ @intCast(key >> 21), @intCast(key & mask), 0 }, .len = 2 };
}

fn packEntry(row: Row, meta: ?u16) !u64 {
    if (meta) |index| {
        if (index >= 1 << 14) return error.TooManyContractions;
        return 2 | (@as(u64, row.len) << 2) | (@as(u64, row.start) << 18) | (@as(u64, index) << 50);
    }
    return 1 | (@as(u64, row.len) << 2) | (@as(u64, row.start) << 18);
}

fn int(buffer: *std.ArrayList(u8), comptime T: type, value: T) !void {
    var bytes: [@sizeOf(T)]u8 = undefined;
    std.mem.writeInt(T, &bytes, value, .little);
    try buffer.appendSlice(&bytes);
}

fn build(alloc: std.mem.Allocator, singles: *const Singles, multis: *const Multis) ![]const u8 {
    var builder = Builder{
        .alloc = alloc,
        .rows = std.StringHashMap(Row).init(alloc),
        .weights = std.ArrayList(u32).init(alloc),
        .edges = std.ArrayList(format.Edge).init(alloc),
        .meta = std.ArrayList(format.Meta).init(alloc),
    };
    var roots = std.AutoHashMap(u32, *Node).init(alloc);
    const multi_keys = try alloc.alloc(u64, multis.count());
    var key_it = multis.keyIterator();
    var key_index: usize = 0;
    while (key_it.next()) |key| : (key_index += 1) multi_keys[key_index] = key.*;
    std.mem.sort(u64, multi_keys, {}, std.sort.asc(u64));
    for (multi_keys) |key| {
        const seq = unpack(key);
        for (seq.points[0..seq.len]) |cp| {
            if (cp > 0x10FFFF) return error.InvalidCodepoint;
        }
        const slot = try roots.getOrPut(seq.points[0]);
        if (!slot.found_existing) slot.value_ptr.* = try builder.node();
        var node = slot.value_ptr.*;
        node.max_len = @max(node.max_len, @as(u8, @intCast(seq.len)));
        for (seq.points[1..seq.len]) |cp| {
            const child = try node.children.getOrPut(cp);
            if (!child.found_existing) child.value_ptr.* = try builder.node();
            node = child.value_ptr.*;
        }
        node.row = try builder.intern(multis.get(key).?);
    }

    var pages = std.ArrayList(u16).init(alloc);
    var entries = std.ArrayList(u64).init(alloc);
    var page_ids = std.AutoHashMap([256]u64, u16).init(alloc);
    for (0..0x1100) |page_index| {
        var page: [256]u64 = @splat(0);
        for (&page, 0..) |*entry, offset| {
            const cp: u32 = @intCast(page_index * 256 + offset);
            const weights = singles.get(cp);
            if (roots.get(cp)) |root| {
                const row = try builder.intern(weights orelse return error.MissingSingle);
                const meta_index: u16 = @intCast(builder.meta.items.len);
                const first_edge: u32 = @intCast(builder.edges.items.len);
                const edge_len = try builder.writeEdges(root);
                try builder.meta.append(.{ .first_edge = first_edge, .edge_len = edge_len, .max_len = root.max_len });
                entry.* = try packEntry(row, meta_index);
            } else if (weights) |values| entry.* = try packEntry(try builder.intern(values), null);
        }
        const slot = try page_ids.getOrPut(page);
        if (!slot.found_existing) {
            slot.value_ptr.* = @intCast(entries.items.len / 256);
            try entries.appendSlice(&page);
        }
        try pages.append(slot.value_ptr.*);
    }

    var bytes = std.ArrayList(u8).init(alloc);
    try bytes.appendSlice("LCT1");
    for ([_]usize{ pages.items.len, entries.items.len, builder.meta.items.len, builder.edges.items.len, builder.weights.items.len }) |count|
        try int(&bytes, u32, @intCast(count));
    for (pages.items) |value| try int(&bytes, u16, value);
    for (entries.items) |value| try int(&bytes, u64, value);
    for (builder.meta.items) |value| {
        try int(&bytes, u32, value.first_edge);
        try int(&bytes, u16, value.edge_len);
        try int(&bytes, u8, value.max_len);
    }
    for (builder.edges.items) |value| {
        try int(&bytes, u32, value.codepoint);
        try int(&bytes, u32, value.next_first_edge);
        try int(&bytes, u32, value.weight_start);
        try int(&bytes, u16, value.next_edge_len);
        try int(&bytes, u16, value.weight_len);
    }
    for (builder.weights.items) |value| try int(&bytes, u32, value);
    return bytes.items;
}

fn expectRow(expected: ?[]const u32, actual: ?[]const u32) !void {
    if (expected) |row| {
        if (actual == null or !std.mem.eql(u32, row, actual.?)) return error.MappingMismatch;
    } else if (actual != null) return error.MappingMismatch;
}

fn verify(alloc: std.mem.Allocator, bytes: []const u8, singles: *const Singles, multis: *const Multis) !void {
    var table = try format.Table.load(alloc, bytes);
    defer table.deinit(alloc);
    var terminal_count: usize = 0;
    for (0..0x110000) |cp_| {
        const cp: u32 = @intCast(cp_);
        const entry = table.entry(cp);
        try expectRow(singles.get(cp), table.simpleRow(entry));
        if (entry & 3 != 2) continue;
        const meta = table.meta[entry >> 50];
        var max_len: usize = 2;
        for (table.edges[meta.first_edge..][0..meta.edge_len]) |second| {
            const key2 = (@as(u64, cp) << 21) | second.codepoint;
            try expectRow(multis.get(key2), table.get2(entry, second.codepoint));
            if (second.weight_len > 0) terminal_count += 1;
            if (second.next_edge_len > 0) max_len = 3;
            for (table.edges[second.next_first_edge..][0..second.next_edge_len]) |third| {
                const key3 = (@as(u64, cp) << 42) | (@as(u64, second.codepoint) << 21) | third.codepoint;
                try expectRow(multis.get(key3), table.get3(entry, second.codepoint, third.codepoint));
                if (third.weight_len > 0) terminal_count += 1;
            }
        }
        if (max_len != table.maxLen(entry)) return error.LookaheadMismatch;
    }
    if (terminal_count != multis.count()) return error.MappingMismatch;
    var it = multis.iterator();
    while (it.next()) |kv| {
        const seq = unpack(kv.key_ptr.*);
        const entry = table.entry(seq.points[0]);
        const actual = if (seq.len == 2) table.get2(entry, seq.points[1]) else table.get3(entry, seq.points[1], seq.points[2]);
        try expectRow(kv.value_ptr.*, actual);
    }
}

pub fn write(alloc: std.mem.Allocator, singles: *const Singles, multis: *const Multis, path: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(alloc);
    defer arena.deinit();
    const bytes = try build(arena.allocator(), singles, multis);
    try verify(arena.allocator(), bytes, singles, multis);
    try std.fs.cwd().writeFile(.{ .sub_path = path, .data = bytes });
    std.debug.print("{s}: {d} bytes; verified all scalar slots and {d} contractions\n", .{ path, bytes.len, multis.count() });
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer std.debug.assert(gpa.deinit() == .ok);
    const alloc = gpa.allocator();
    inline for (.{ "", "_cldr" }) |suffix| {
        var singles = try single.loadSinglesBin(alloc, "bin/singles" ++ suffix ++ ".bin");
        defer singles.deinit();
        var multis = try multi.loadMultiBin(alloc, "bin/multi" ++ suffix ++ ".bin");
        defer multis.deinit();
        try write(alloc, &singles.map, &multis.map, "bin/collation" ++ suffix ++ ".bin");
    }
}

test "compact tables are deterministic and preserve contraction-only prefixes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    var singles = Singles.init(alloc);
    try singles.put('a', &.{1});
    try singles.put('b', &.{1}); // Identical weight rows are pooled.
    var multis = Multis.init(alloc);
    // Force binary-search edges, including a two-character prefix without a row.
    for (0..6) |i| try multis.put((@as(u64, 'a') << 42) | (@as(u64, @intCast('b' + i)) << 21) | 'z', &.{ 2, 3 });
    try multis.put((@as(u64, 'a') << 21) | 'b', &.{4});
    const bytes = try build(alloc, &singles, &multis);
    try verify(alloc, bytes, &singles, &multis);
    var reversed = Multis.init(alloc);
    var it = multis.iterator();
    var keys = std.ArrayList(u64).init(alloc);
    while (it.next()) |kv| try keys.append(kv.key_ptr.*);
    std.mem.sort(u64, keys.items, {}, std.sort.desc(u64));
    for (keys.items) |key| try reversed.put(key, multis.get(key).?);
    try std.testing.expectEqualSlices(u8, bytes, try build(alloc, &singles, &reversed));
    var table = try format.Table.load(alloc, bytes);
    defer table.deinit(alloc);
    try std.testing.expectEqual(null, table.get2(table.entry('a'), 'q'));
    try std.testing.expectEqual(null, table.get3(table.entry('a'), 'b', 'q'));
    try std.testing.expectError(error.InvalidData, format.Table.load(alloc, bytes[0 .. bytes.len - 1]));
}
