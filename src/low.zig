const std = @import("std");

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
// Public functions
//

pub fn mapLow(alloc: std.mem.Allocator, keys: *const []const u8) ![183]u32 {
    var map = std.AutoHashMap(u32, u32).init(alloc);
    defer map.deinit();

    var line_iter = std.mem.splitScalar(u8, keys.*, '\n');
    while (line_iter.next()) |line| {
        if (line.len == 0 or !HEX.isSet(line[0])) continue;

        var split_semi = std.mem.splitScalar(u8, line, ';');

        var points_str = split_semi.next() orelse return error.InvalidData;
        points_str = std.mem.trim(u8, points_str, " ");

        var points = std.ArrayList(u32).init(alloc);
        defer points.deinit();

        var split_space = std.mem.splitScalar(u8, points_str, ' ');
        while (split_space.next()) |cp_str| {
            const cp = try std.fmt.parseInt(u32, cp_str, 16);
            try points.append(cp);
        }

        std.debug.assert(1 <= points.items.len and points.items.len <= 3);

        if (points.items[0] > 0xB6) continue;
        if (points.items[0] == 0x4C or points.items[0] == 0x6C) continue; // L/l

        std.debug.assert(points.items.len == 1);
        const code_point = points.items[0];

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

        const weights_packed = packWeights(variable, primary, secondary, tertiary);
        try map.put(code_point, weights_packed);
    }

    var arr = std.mem.zeroes([183]u32);
    var it = map.iterator();
    while (it.next()) |kv| arr[kv.key_ptr.*] = kv.value_ptr.*;

    return arr;
}

pub fn saveLowBin(map: *const std.AutoHashMap(u32, u32), path: []const u8) !void {
    var file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();

    var bw = std.io.bufferedWriter(file.writer());
    try bw.writer().writeInt(u32, @intCast(map.count()), .little);

    var it = map.iterator();
    while (it.next()) |kv| {
        const e = LowEntry{
            .key = std.mem.nativeToLittle(u32, kv.key_ptr.*),
            .value = std.mem.nativeToLittle(u32, kv.value_ptr.*),
        };

        try bw.writer().writeStruct(e);
    }

    try bw.flush();
}

pub fn saveLowJson(arr: *const [183]u32, path: []const u8) !void {
    const file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();

    var ws = std.json.writeStream(file.writer(), .{});

    try ws.beginArray();
    for (arr) |value| try ws.write(value);
    try ws.endArray();
}

//
// Private functions
//

fn packWeights(variable: bool, primary: u16, secondary: u16, tertiary: u8) u32 {
    const upper: u32 = (@as(u32, primary) << 16);
    const v_int: u16 = @intFromBool(variable);
    const lower: u16 = (v_int << 15) | (@as(u16, tertiary) << 9) | secondary;
    return upper | @as(u32, lower);
}
