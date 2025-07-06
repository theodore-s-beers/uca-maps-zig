const std = @import("std");

const ccc = @import("ccc");
const decomp = @import("decomp");

const FcdEntry = packed struct {
    key: u32,
    value: u16,
};

pub fn mapFCD(alloc: std.mem.Allocator, data: *const []const u8) !std.AutoHashMap(u32, u16) {
    //
    // Load decomposition map
    //

    var decomp_map = try decomp.loadDecomps(alloc, "bin/decomp.bin");
    defer {
        var it = decomp_map.iterator();
        while (it.next()) |entry| alloc.free(entry.value_ptr.*);
        decomp_map.deinit();
    }

    //
    // Load CCC map
    //

    var ccc_map = try ccc.loadCCC(alloc, "bin/ccc.bin");
    defer ccc_map.deinit();

    //
    // Set up FCD map
    //

    var fcd_map = std.AutoHashMap(u32, u16).init(alloc);

    //
    // Iterate over lines and find combining classes
    //

    var line_iter = std.mem.splitScalar(u8, data.*, '\n');

    while (line_iter.next()) |line| {
        if (line.len == 0) continue;

        var fields = std.ArrayList([]const u8).init(alloc);
        defer fields.deinit();

        var field_iter = std.mem.splitScalar(u8, line, ';');
        while (field_iter.next()) |field| {
            try fields.append(field);
        }

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

        const decomps: []const u32 = decomp_map.get(code_point) orelse continue;

        const first_ccc: u8 = ccc_map.get(decomps[0]) orelse 0;
        const last_ccc: u8 = ccc_map.get(decomps[decomps.len - 1]) orelse 0;

        const fcd: u16 = @as(u16, first_ccc) << 8 | @as(u16, last_ccc);
        if (fcd == 0) continue;

        try fcd_map.put(code_point, fcd);
    }

    return fcd_map;
}

pub fn saveFcdBin(map: *const std.AutoHashMap(u32, u16), path: []const u8) !void {
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();

    var bw = std.io.bufferedWriter(file.writer());
    try bw.writer().writeInt(u32, @intCast(map.count()), .little);

    var it = map.iterator();
    while (it.next()) |kv| {
        const e = FcdEntry{
            .key = std.mem.nativeToLittle(u32, kv.key_ptr.*),
            .value = std.mem.nativeToLittle(u16, kv.value_ptr.*),
        };

        try bw.writer().writeStruct(e);
    }

    try bw.flush();
}

pub fn saveFcdJson(
    alloc: std.mem.Allocator,
    map: *const std.AutoHashMap(u32, u16),
    path: []const u8,
) !void {
    const file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();

    var ws = std.json.writeStream(file.writer(), .{});
    try ws.beginObject();

    var map_iter = map.iterator();
    while (map_iter.next()) |entry| {
        const key_str = try std.fmt.allocPrint(alloc, "{}", .{entry.key_ptr.*});
        try ws.objectField(key_str);
        try ws.write(entry.value_ptr.*);

        alloc.free(key_str);
    }

    try ws.endObject();
}
