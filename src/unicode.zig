const std = @import("std");
const source = @import("source.zig");
const header = source.header;
const save = source.save;
const array = source.array;
const Range = struct { first: u32, last: u32 };
const Rule = struct { range: Range, base: u32 };

fn range(text: []const u8) !Range {
    var parts = std.mem.splitSequence(u8, std.mem.trim(u8, text, " \t"), "..");
    const first = try std.fmt.parseInt(u32, parts.next().?, 16);
    return .{ .first = first, .last = if (parts.next()) |last| try std.fmt.parseInt(u32, last, 16) else first };
}

// Generate the static runtime tables from the same pinned inputs as the binaries.
pub fn write(io: std.Io, alloc: std.mem.Allocator, data: []const u8, keys: []const u8, low: []const u32, low_cldr: []const u32) !void {
    const assigned = try alloc.alloc(bool, 0x110000);
    defer alloc.free(assigned);
    @memset(assigned, false);
    const classes = try alloc.alloc(u8, 0x110000);
    defer alloc.free(classes);
    @memset(classes, 0);
    var first: ?u32 = null;
    var lines = std.mem.tokenizeScalar(u8, data, '\n');
    while (lines.next()) |line| {
        var fields = std.mem.splitScalar(u8, line, ';');
        const cp = try std.fmt.parseInt(u32, fields.next().?, 16);
        const name = fields.next().?;
        _ = fields.next();
        const cc = try std.fmt.parseInt(u8, fields.next().?, 10);
        if (std.mem.endsWith(u8, name, ", First>")) {
            first = cp;
            continue;
        }
        const start = if (std.mem.endsWith(u8, name, ", Last>")) first orelse return error.InvalidRange else cp;
        first = null;
        @memset(assigned[start .. cp + 1], true);
        @memset(classes[start .. cp + 1], cc);
    }
    if (first != null) return error.InvalidRange;

    var last: usize = classes.len - 1;
    while (classes[last] == 0) : (last -= 1) {}
    var offsets: std.ArrayList(u16) = .empty;
    defer offsets.deinit(alloc);
    var blocks: std.ArrayList(u8) = .empty;
    defer blocks.deinit(alloc);
    var pages = std.AutoHashMap([256]u8, u16).init(alloc);
    defer pages.deinit();
    for (0..last / 256 + 1) |page| {
        const block = classes[page * 256 ..][0..256];
        const slot = try pages.getOrPut(block.*);
        if (!slot.found_existing) {
            slot.value_ptr.* = @intCast(blocks.items.len);
            try blocks.appendSlice(alloc, block);
        }
        try offsets.append(alloc, slot.value_ptr.*);
    }
    // Exhaustively verify the deduplicated lookup before emitting it.
    for (classes, 0..) |cc, cp| {
        const actual = if (cp <= last) blocks.items[@as(usize, offsets.items[cp >> 8]) + (cp & 255)] else 0;
        if (actual != cc) return error.CombiningClassMismatch;
    }
    var output = std.Io.Writer.Allocating.init(alloc);
    defer output.deinit();
    const w = &output.writer;
    try w.writeAll(header);
    try w.print("pub fn getCombiningClass(cp: u32) u8 {{\nif (cp > {d}) return 0;\nreturn BLOCKS[@as(usize, OFFSETS[cp >> 8]) + (cp & 255)];\n}}\n", .{last});
    try array(w, u16, "OFFSETS", offsets.items);
    try array(w, u8, "BLOCKS", blocks.items);
    try save(io, alloc, "generated/ccc.zig", output.written());

    output.clearRetainingCapacity();
    try w.writeAll(header);
    try array(w, u32, "LOW", low);
    try array(w, u32, "LOW_CLDR", low_cldr);
    try save(io, alloc, "generated/consts.zig", output.written());

    var rules: std.ArrayList(Rule) = .empty;
    defer rules.deinit(alloc);
    lines = std.mem.tokenizeScalar(u8, keys, '\n');
    while (lines.next()) |line| {
        const prefix = "@implicitweights ";
        if (!std.mem.startsWith(u8, line, prefix)) continue;
        var parts = std.mem.splitScalar(u8, line[prefix.len..], ';');
        const r = try range(parts.next().?);
        var rest = std.mem.tokenizeAny(u8, parts.next().?, " \t#");
        try rules.append(alloc, .{ .range = r, .base = try std.fmt.parseInt(u32, rest.next().?, 16) });
    }
    if (rules.items.len == 0) return error.MissingImplicitRules;
    output.clearRetainingCapacity();
    try w.writeAll(header);
    try w.writeAll("pub fn weights(cp: u32) struct { u32, u32 } {\nconst pair: struct { u32, u32 } = switch (cp) {\n");
    for (rules.items) |rule| {
        var offset = rule.range.first;
        for (rules.items) |other| if (other.base == rule.base) {
            offset = @min(offset, other.range.first);
        };
        var cp = rule.range.first;
        while (cp <= rule.range.last) {
            if (!assigned[cp]) {
                cp += 1;
                continue;
            }
            const start = cp;
            while (cp < rule.range.last and assigned[cp + 1]) : (cp += 1) {}
            try w.print("0x{X}...0x{X} => .{{ 0x{X}, cp - 0x{X} }},\n", .{ start, cp, rule.base, offset });
            cp += 1;
        }
    }
    const properties = try std.Io.Dir.cwd().readFileAlloc(io, "data/PropList.txt", alloc, .limited(1024 * 1024));
    defer alloc.free(properties);
    lines = std.mem.tokenizeScalar(u8, properties, '\n');
    while (lines.next()) |line| {
        var uncommented = std.mem.splitScalar(u8, line, '#');
        var fields = std.mem.splitScalar(u8, uncommented.next().?, ';');
        const span = fields.next().?;
        const property = fields.next() orelse continue;
        if (!std.mem.eql(u8, std.mem.trim(u8, property, " \t"), "Unified_Ideograph")) continue;
        const r = try range(span);
        const base: u32 = if ((r.first >= 0x4E00 and r.first <= 0x9FFF) or (r.first >= 0xF900 and r.first <= 0xFAFF)) 0xFB40 else 0xFB80;
        try w.print("0x{X}...0x{X} => .{{ 0x{X} + (cp >> 15), cp & 0x7FFF }},\n", .{ r.first, r.last, base });
    }
    try w.writeAll("else => .{ 0xFBC0 + (cp >> 15), cp & 0x7FFF },\n};\nreturn .{pair[0], pair[1] | 0x8000};\n}\n");
    try save(io, alloc, "generated/implicit.zig", output.written());
}
