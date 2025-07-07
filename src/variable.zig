const std = @import("std");

const util = @import("util");

pub fn mapVariable(alloc: std.mem.Allocator, data: []const u8) !std.AutoHashMap(u32, void) {
    var map = std.AutoHashMap(u32, void).init(alloc);
    errdefer map.deinit();

    var points = std.ArrayList(u32).init(alloc);
    defer points.deinit();

    var line_it = std.mem.splitScalar(u8, data, '\n');
    outer: while (line_it.next()) |line| {
        if (line.len == 0 or !util.HEX.isSet(line[0])) continue;

        var split_semi = std.mem.splitScalar(u8, line, ';');

        var points_str = split_semi.next() orelse return error.InvalidData;
        points_str = std.mem.trim(u8, points_str, " ");

        points.clearRetainingCapacity();

        var split_space = std.mem.splitScalar(u8, points_str, ' ');
        while (split_space.next()) |cp_str| {
            const cp = try std.fmt.parseInt(u32, cp_str, 16);
            try points.append(cp);
        }

        std.debug.assert(1 <= points.items.len and points.items.len <= 3);
        if (points.items.len > 1) continue;

        const key = points.items[0];

        const remainder = split_semi.next() orelse return error.InvalidData;
        var split_hash = std.mem.splitScalar(u8, remainder, '#');

        var weights_str = split_hash.next() orelse return error.InvalidData;
        weights_str = std.mem.trim(u8, weights_str, " []");

        var split_bracket = std.mem.splitScalar(u8, weights_str, '[');
        while (split_bracket.next()) |segment| {
            var weight_str = std.mem.trim(u8, segment, " ]");
            if (weight_str.len == 0) continue;

            std.debug.assert(weight_str.len == 15); // One set of weights

            const variable = weight_str[0] == '*';

            weight_str = std.mem.trim(u8, weight_str, ".*");
            var split_period = std.mem.splitScalar(u8, weight_str, '.');

            const primary_str = split_period.next() orelse return error.InvalidData;
            const primary = try std.fmt.parseInt(u16, primary_str, 16);

            if (variable or primary == 0) {
                try map.put(key, {});
                continue :outer;
            }
        }
    }

    return map;
}

pub fn loadVariableBin(alloc: std.mem.Allocator, path: []const u8) !std.AutoHashMap(u32, void) {
    const data = try std.fs.cwd().readFileAlloc(alloc, path, 64 * 1024);
    defer alloc.free(data);

    const count: usize = data.len / @sizeOf(u32);

    var map = std.AutoHashMap(u32, void).init(alloc);
    errdefer map.deinit();

    try map.ensureTotalCapacity(@intCast(count));

    for (0..count) |i| {
        const offset = i * @sizeOf(u32);

        const bytes = data[offset..][0..@sizeOf(u32)];
        const code_point = std.mem.readInt(u32, bytes, .little);

        map.putAssumeCapacityNoClobber(code_point, {});
    }

    return map;
}

pub fn loadVariableJson(alloc: std.mem.Allocator, path: []const u8) !std.AutoHashMap(u32, void) {
    const data = try std.fs.cwd().readFileAlloc(alloc, path, 128 * 1024);
    defer alloc.free(data);

    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, data, .{});
    defer parsed.deinit();

    const array = parsed.value.array;

    var map = std.AutoHashMap(u32, void).init(alloc);
    errdefer map.deinit();

    try map.ensureTotalCapacity(@intCast(array.items.len));

    for (array.items) |item| {
        const code_point = switch (item) {
            .integer => |i| @as(u32, @intCast(i)),
            else => return error.InvalidData,
        };

        map.putAssumeCapacityNoClobber(code_point, {});
    }

    return map;
}

pub fn saveVariableBin(
    alloc: std.mem.Allocator,
    map: *const std.AutoHashMap(u32, void),
    path: []const u8,
) !void {
    var list = std.ArrayList(u32).init(alloc);
    defer list.deinit();

    var it = map.iterator();
    while (it.next()) |entry| {
        try list.append(std.mem.nativeToLittle(u32, entry.key_ptr.*));
    }

    std.mem.sort(u32, list.items, {}, comptime std.sort.asc(u32));

    const file = try std.fs.cwd().createFile(path, .{});
    defer file.close();

    const bytes = std.mem.sliceAsBytes(list.items);
    try file.writeAll(bytes);
}

pub fn saveVariableJson(
    alloc: std.mem.Allocator,
    map: *const std.AutoHashMap(u32, void),
    path: []const u8,
) !void {
    var list = std.ArrayList(u32).init(alloc);
    defer list.deinit();

    var it = map.iterator();
    while (it.next()) |entry| {
        try list.append(entry.key_ptr.*);
    }

    std.mem.sort(u32, list.items, {}, comptime std.sort.asc(u32));

    var buffer = std.ArrayList(u8).init(alloc);
    defer buffer.deinit();

    var ws = std.json.writeStream(buffer.writer(), .{});

    try ws.beginArray();
    for (list.items) |code_point| try ws.write(code_point);
    try ws.endArray();

    const file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();

    try file.writeAll(buffer.items);
}
