const std = @import("std");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer std.debug.assert(gpa.deinit() == .ok);

    const allocator = gpa.allocator();

    const keys_ducet = try std.fs.cwd().readFileAlloc(allocator, "allkeys.txt", 3 * 1024 * 1024);
    defer allocator.free(keys_ducet);

    const keys_cldr = try std.fs.cwd().readFileAlloc(allocator, "allkeys_cldr.txt", 3 * 1024 * 1024);
    defer allocator.free(keys_cldr);

    var ducet_map = try mapLow(allocator, keys_ducet);
    defer ducet_map.deinit();

    var ducet_file = try std.fs.cwd().createFile("low.bin", .{ .truncate = true });
    defer ducet_file.close();

    var ducet_bw = std.io.bufferedWriter(ducet_file.writer());
    try saveLowMap(&ducet_map, ducet_bw.writer());
    try ducet_bw.flush();

    var cldr_map = try mapLow(allocator, keys_cldr);
    defer cldr_map.deinit();

    var cldr_file = try std.fs.cwd().createFile("low_cldr.bin", .{ .truncate = true });
    defer cldr_file.close();

    var cldr_bw = std.io.bufferedWriter(cldr_file.writer());
    try saveLowMap(&cldr_map, cldr_bw.writer());
    try cldr_bw.flush();
}

//
// Types
//

const LowEntry = packed struct {
    key: u32,
    value: u32,
};

//
// Constants
//

const HEX: std.bit_set.ArrayBitSet(usize, 256) = blk: {
    var set = std.StaticBitSet(256).initEmpty();
    for ('0'..':') |c| set.set(c);
    for ('A'..'G') |c| set.set(c);
    break :blk set;
};

//
// Helper functions
//

fn mapLow(allocator: std.mem.Allocator, keys: []const u8) !std.AutoHashMap(u32, u32) {
    var map = std.AutoHashMap(u32, u32).init(allocator);
    errdefer map.deinit();

    var line_iter = std.mem.splitScalar(u8, keys, '\n');
    while (line_iter.next()) |line| {
        if (line.len == 0 or !HEX.isSet(line[0])) continue;

        var split_semi = std.mem.splitScalar(u8, line, ';');

        var code_points_str = split_semi.next() orelse return error.InvalidData;
        code_points_str = std.mem.trim(u8, code_points_str, " ");

        var code_points = std.ArrayList(u32).init(allocator);
        defer code_points.deinit();

        var split_space = std.mem.splitScalar(u8, code_points_str, ' ');
        while (split_space.next()) |cp_str| {
            const cp = try std.fmt.parseInt(u32, cp_str, 16);
            try code_points.append(cp);
        }

        std.debug.assert(1 <= code_points.items.len and code_points.items.len <= 3);

        if (code_points.items[0] > 0xB6) continue;
        if (code_points.items[0] == 0x4C or code_points.items[0] == 0x6C) continue; // L/l

        std.debug.assert(code_points.items.len == 1);
        const code_point = code_points.items[0];

        const remainder = split_semi.next() orelse return error.InvalidData;
        var split_hash = std.mem.splitScalar(u8, remainder, '#');

        var weights_str = split_hash.next() orelse return error.InvalidData;
        weights_str = std.mem.trim(u8, weights_str, " []");
        std.debug.assert(weights_str.len == 15); // One set of weights

        const variable = weights_str[0] == '*';

        weights_str = std.mem.trim(u8, weights_str, ".*");
        var split_period = std.mem.splitScalar(u8, weights_str, '.');

        const primary_str = split_period.next() orelse return error.InvalidData;
        const primary = try std.fmt.parseInt(u16, primary_str, 16);

        const secondary_str = split_period.next() orelse return error.InvalidData;
        const secondary = try std.fmt.parseInt(u16, secondary_str, 16);

        const tertiary_str = split_period.next() orelse return error.InvalidData;
        const tertiary = try std.fmt.parseInt(u8, tertiary_str, 16);

        const packed_weights = packWeights(variable, primary, secondary, tertiary);
        try map.put(code_point, packed_weights);
    }

    return map;
}

fn packWeights(variable: bool, primary: u16, secondary: u16, tertiary: u8) u32 {
    const upper: u32 = (@as(u32, primary) << 16);
    const v_int: u16 = @intFromBool(variable);
    const lower: u16 = (v_int << 15) | (@as(u16, tertiary) << 9) | secondary;
    return upper | @as(u32, lower);
}

fn saveLowMap(map: *const std.AutoHashMap(u32, u32), writer: anytype) !void {
    try writer.writeInt(u32, @intCast(map.count()), .little);

    var it = map.iterator();
    while (it.next()) |kv| {
        const e = LowEntry{
            .key = std.mem.nativeToLittle(u32, kv.key_ptr.*),
            .value = std.mem.nativeToLittle(u32, kv.value_ptr.*),
        };

        try writer.writeStruct(e);
    }
}
