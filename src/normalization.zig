const std = @import("std");
const source = @import("source.zig");
const empty = std.math.maxInt(u16);

// Deduplicate nonempty pages; the sentinel requires no stored zero page.
fn Pages(comptime T: type, comptime width: usize) type {
    return struct {
        index: [0x1100]u16 = @splat(empty),
        values: std.ArrayList(T) = .empty,
        unique: std.AutoHashMap([width]T, u16),
        const Self = @This();

        fn init(alloc: std.mem.Allocator) Self {
            return .{ .unique = std.AutoHashMap([width]T, u16).init(alloc) };
        }
        fn deinit(self: *Self) void {
            self.values.deinit(self.unique.allocator);
            self.unique.deinit();
        }
        fn add(self: *Self, page: usize, values: [width]T) !void {
            if (std.mem.allEqual(T, &values, 0)) return;
            const slot = try self.unique.getOrPut(values);
            if (!slot.found_existing) {
                const id = self.values.items.len / width;
                if (id >= empty) return error.TooManyPages;
                slot.value_ptr.* = @intCast(id);
                try self.values.appendSlice(self.unique.allocator, &values);
            }
            self.index[page] = slot.value_ptr.*;
        }
        fn get(self: *const Self, page: usize, offset: usize) T {
            const id = self.index[page];
            return if (id == empty) 0 else self.values.items[@as(usize, id) * width + offset];
        }
        fn emit(self: *const Self, w: *std.Io.Writer, comptime name: []const u8) !void {
            try source.array(w, u16, name ++ "_INDEX", &self.index);
            try source.array(w, T, name ++ "_PAGES", self.values.items);
        }
    };
}

pub fn write(io: std.Io, alloc: std.mem.Allocator, decomps: *const std.AutoHashMap(u32, []const u32), fcd: *const std.AutoHashMap(u32, u16), variable: *const std.AutoHashMap(u32, void)) !void {
    var d = Pages(u64, 256).init(alloc);
    defer d.deinit();
    var f = Pages(u16, 256).init(alloc);
    defer f.deinit();
    var v = Pages(u64, 4).init(alloc);
    defer v.deinit();
    var values: std.ArrayList(u32) = .empty;
    defer values.deinit(alloc);
    // Keys refer to stable input rows, not the growing values buffer.
    var rows = std.StringHashMap(u64).init(alloc);
    defer rows.deinit();
    for (0..0x1100) |page| {
        var dp: [256]u64 = @splat(0);
        var fp: [256]u16 = @splat(0);
        var vp: [4]u64 = @splat(0);
        for (0..256) |offset| {
            const cp: u32 = @intCast(page * 256 + offset);
            if (decomps.get(cp)) |row| {
                if (row.len == 0 or row.len > 0xffff or values.items.len > std.math.maxInt(u32)) return error.InvalidDecomposition;
                const slot = try rows.getOrPut(std.mem.sliceAsBytes(row));
                if (!slot.found_existing) {
                    slot.value_ptr.* = (@as(u64, @intCast(values.items.len)) << 16) | row.len;
                    try values.appendSlice(alloc, row);
                }
                dp[offset] = slot.value_ptr.*;
            }
            fp[offset] = fcd.get(cp) orelse 0;
            if (variable.contains(cp)) vp[offset >> 6] |= @as(u64, 1) << @intCast(offset & 63);
        }
        try d.add(page, dp);
        try f.add(page, fp);
        try v.add(page, vp);
    }
    for (0..0x110000) |codepoint| {
        const cp: u32 = @intCast(codepoint);
        const page = cp >> 8;
        const offset = cp & 255;
        const entry = d.get(page, offset);
        const len = entry & 0xffff;
        const start = entry >> 16;
        if (decomps.get(cp)) |expected| {
            if (!std.mem.eql(u32, expected, values.items[start..][0..len])) return error.DecompositionMismatch;
        } else if (len != 0) return error.DecompositionMismatch;
        const actual_fcd = f.get(page, offset);
        const optional_fcd: ?u16 = if (actual_fcd == 0) null else actual_fcd;
        if (optional_fcd != fcd.get(cp)) return error.FcdMismatch;
        const actual_variable = (v.get(page, offset >> 6) & (@as(u64, 1) << @intCast(offset & 63))) != 0;
        if (actual_variable != variable.contains(cp)) return error.VariableMismatch;
    }
    var output = std.Io.Writer.Allocating.init(alloc);
    defer output.deinit();
    const w = &output.writer;
    try w.writeAll(source.header);
    try w.writeAll(
        \\// Pages contain 256 code points; 0xffff denotes an empty page.
        \\pub fn getDecomp(cp: u32) ?[]const u32 {
        \\    if (cp > 0x10ffff) return null;
        \\    const page = DECOMP_INDEX[cp >> 8];
        \\    if (page == 0xffff) return null;
        \\    const entry = DECOMP_PAGES[@as(usize, page) * 256 + (cp & 255)];
        \\    const len: usize = @intCast(entry & 0xffff);
        \\    if (len == 0) return null;
        \\    const start: usize = @intCast(entry >> 16);
        \\    return DECOMP_VALUES[start..][0..len];
        \\}
        \\pub fn getFCD(cp: u32) ?u16 {
        \\    if (cp > 0x10ffff) return null;
        \\    const page = FCD_INDEX[cp >> 8];
        \\    if (page == 0xffff) return null;
        \\    const value = FCD_PAGES[@as(usize, page) * 256 + (cp & 255)];
        \\    return if (value == 0) null else value;
        \\}
        \\pub fn isVariable(cp: u32) bool {
        \\    if (cp > 0x10ffff) return false;
        \\    const page = VARIABLE_INDEX[cp >> 8];
        \\    if (page == 0xffff) return false;
        \\    const word = VARIABLE_PAGES[@as(usize, page) * 4 + ((cp & 255) >> 6)];
        \\    return (word & (@as(u64, 1) << @intCast(cp & 63))) != 0;
        \\}
        \\
    );
    try d.emit(w, "DECOMP");
    try source.array(w, u32, "DECOMP_VALUES", values.items);
    try f.emit(w, "FCD");
    try v.emit(w, "VARIABLE");
    try source.save(io, alloc, "generated/normalization_tables.zig", output.written());
}

test "indexed pages share duplicates and preserve empty and final pages" {
    var pages = Pages(u64, 4).init(std.testing.allocator);
    defer pages.deinit();
    const bits: [4]u64 = .{ 1, 1 << 63, 0, 1 << 63 };
    try pages.add(0, bits);
    try pages.add(1, @splat(0));
    try pages.add(0x10ff, bits);
    try std.testing.expectEqual(@as(usize, 4), pages.values.items.len);
    try std.testing.expectEqual(pages.index[0], pages.index[0x10ff]);
    try std.testing.expectEqual(empty, pages.index[1]);
    try std.testing.expectEqual(@as(u64, 0), pages.get(1, 3));
    try std.testing.expectEqual(bits[3], pages.get(0x10ff, 3));
}
