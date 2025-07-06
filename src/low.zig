const std = @import("std");

const util = @import("util");

//
// Public functions
//

pub fn mapLow(alloc: std.mem.Allocator, keys: *const []const u8) ![183]u32 {
    var map = std.AutoHashMap(u32, u32).init(alloc);
    defer map.deinit();

    var line_iter = std.mem.splitScalar(u8, keys.*, '\n');
    while (line_iter.next()) |line| {
        if (line.len == 0 or !util.HEX.isSet(line[0])) continue;

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

        const weights_packed = util.packWeights(variable, primary, secondary, tertiary);
        try map.put(code_point, weights_packed);
    }

    var arr = std.mem.zeroes([183]u32);
    var it = map.iterator();
    while (it.next()) |kv| arr[kv.key_ptr.*] = kv.value_ptr.*;

    return arr;
}

pub fn saveLowJson(arr: *const [183]u32, path: []const u8) !void {
    const file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();

    var ws = std.json.writeStream(file.writer(), .{});

    try ws.beginArray();
    for (arr) |value| try ws.write(value);
    try ws.endArray();
}
