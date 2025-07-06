const std = @import("std");

const util = @import("util");

//
// Types
//

const MultiEntry = struct {
    key: u64,
    values: []const u32,
};

const MultiEntryHeader = packed struct {
    key: u64,
    len: u8,
};

const MultiMapHeader = packed struct {
    count: u16,
    total_bytes: u16,
};

//
// Public functions
//

pub fn mapMulti(alloc: std.mem.Allocator, data: *const []const u8) !std.AutoHashMap(u64, []const u32) {
    var map = std.AutoHashMap(u64, []const u32).init(alloc);
    errdefer {
        var it = map.iterator();
        while (it.next()) |entry| alloc.free(entry.value_ptr.*);
        map.deinit();
    }

    var line_it = std.mem.splitScalar(u8, data.*, '\n');
    while (line_it.next()) |line| {
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
        if (points.items.len == 1) continue;

        const key = packCodePoints(&points.items);

        const remainder = split_semi.next() orelse return error.InvalidData;
        var split_hash = std.mem.splitScalar(u8, remainder, '#');

        var weights_str = split_hash.next() orelse return error.InvalidData;
        weights_str = std.mem.trim(u8, weights_str, " []");

        var weights = std.ArrayList(u32).init(alloc);
        errdefer weights.deinit();

        var split_bracket = std.mem.splitScalar(u8, weights_str, '[');
        while (split_bracket.next()) |x| {
            var weight_str = std.mem.trim(u8, x, " ]");
            if (weight_str.len == 0) continue;

            std.debug.assert(weight_str.len == 15); // One set of weights

            const variable = weight_str[0] == '*';

            weight_str = std.mem.trim(u8, weight_str, ".*");
            var split_period = std.mem.splitScalar(u8, weight_str, '.');

            const primary_str = split_period.next() orelse return error.InvalidData;
            const primary = try std.fmt.parseInt(u16, primary_str, 16);

            const secondary_str = split_period.next() orelse return error.InvalidData;
            const secondary = try std.fmt.parseInt(u16, secondary_str, 16);

            const tertiary_str = split_period.next() orelse return error.InvalidData;
            const tertiary = try std.fmt.parseInt(u8, tertiary_str, 16);

            const weights_packed = util.packWeights(variable, primary, secondary, tertiary);
            try weights.append(weights_packed);
        }

        std.debug.assert(1 <= weights.items.len and weights.items.len <= 3);
        try map.put(key, try weights.toOwnedSlice());
    }

    return map;
}

pub fn saveMultiBin(
    alloc: std.mem.Allocator,
    map: *const std.AutoHashMap(u64, []const u32),
    path: []const u8,
) !void {
    const file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();

    var bw = std.io.bufferedWriter(file.writer());

    var entries = std.ArrayList(MultiEntry).init(alloc);
    defer entries.deinit();

    var it = map.iterator();
    while (it.next()) |kv| {
        try entries.append(MultiEntry{ .key = kv.key_ptr.*, .values = kv.value_ptr.* });
    }

    std.mem.sort(MultiEntry, entries.items, {}, comptime struct {
        fn lessThan(_: void, lhs: MultiEntry, rhs: MultiEntry) bool {
            return lhs.key < rhs.key;
        }
    }.lessThan);

    var payload_bytes: u16 = 0;
    for (entries.items) |entry| {
        payload_bytes += @sizeOf(MultiEntryHeader);
        payload_bytes += @intCast(entry.values.len * @sizeOf(u32));
    }

    const main_header = MultiMapHeader{
        .count = std.mem.nativeToLittle(u16, @intCast(map.count())),
        .total_bytes = std.mem.nativeToLittle(u16, payload_bytes),
    };
    try bw.writer().writeStruct(main_header);

    for (entries.items) |entry| {
        const entry_header = MultiEntryHeader{
            .key = std.mem.nativeToLittle(u64, entry.key),
            .len = @intCast(entry.values.len), // u8 has no endianness
        };

        try bw.writer().writeStruct(entry_header);
        for (entry.values) |v| try bw.writer().writeInt(u32, v, .little);
    }

    try bw.flush();
}

pub fn saveMultiJson(
    alloc: std.mem.Allocator,
    map: *const std.AutoHashMap(u64, []const u32),
    path: []const u8,
) !void {
    const file = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer file.close();

    var ws = std.json.writeStream(file.writer(), .{});
    try ws.beginObject();

    var it = map.iterator();
    while (it.next()) |entry| {
        const key_str = try std.fmt.allocPrint(alloc, "{}", .{entry.key_ptr.*});
        defer alloc.free(key_str);

        try ws.objectField(key_str);

        try ws.beginArray();
        for (entry.value_ptr.*) |value| try ws.write(value);
        try ws.endArray();
    }

    try ws.endObject();
}

//
// Private functions
//

fn packCodePoints(code_points: *const []const u32) u64 {
    switch (code_points.*.len) {
        2 => {
            return (@as(u64, code_points.*[0]) << 21) | @as(u64, code_points.*[1]);
        },
        3 => {
            return (@as(u64, code_points.*[0]) << 42) |
                (@as(u64, code_points.*[1]) << 21) |
                @as(u64, code_points.*[2]);
        },
        else => unreachable,
    }
}
