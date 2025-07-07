const std = @import("std");

//
// Types
//

pub const MultiMap = struct {
    map: std.AutoHashMap(u64, []const u32),
    backing: ?[]const u32,
    alloc: std.mem.Allocator,

    pub fn deinit(self: *MultiMap) void {
        if (self.backing) |backing| {
            self.alloc.free(backing);
        } else {
            var it = self.map.iterator();
            while (it.next()) |entry| self.alloc.free(entry.value_ptr.*);
        }

        self.map.deinit();
    }
};

pub const SinglesMap = struct {
    map: std.AutoHashMap(u32, []const u32),
    backing: ?[]const u32,
    alloc: std.mem.Allocator,

    pub fn deinit(self: *SinglesMap) void {
        if (self.backing) |backing| {
            self.alloc.free(backing);
        } else {
            var it = self.map.iterator();
            while (it.next()) |entry| self.alloc.free(entry.value_ptr.*);
        }

        self.map.deinit();
    }
};

const Range = struct {
    start: u32,
    end: u32,

    pub fn contains(self: Range, value: u32) bool {
        return value >= self.start and value <= self.end;
    }
};

//
// Constants
//

pub const HEX: std.bit_set.ArrayBitSet(usize, 256) = blk: {
    var set = std.StaticBitSet(256).initEmpty();
    for ('0'..':') |c| set.set(c);
    for ('A'..'G') |c| set.set(c);
    break :blk set;
};

pub const IGNORED_RANGES = [_]Range{
    Range{ .start = 0x3400, .end = 0x4DBF }, // CJK ext A
    Range{ .start = 0x4E00, .end = 0x9FFF }, // CJK
    Range{ .start = 0xAC00, .end = 0xD7A3 }, // Hangul
    Range{ .start = 0xD800, .end = 0xDFFF }, // Surrogates
    Range{ .start = 0xE000, .end = 0xF8FF }, // Private use
    Range{ .start = 0x17000, .end = 0x187F7 }, // Tangut
    Range{ .start = 0x18D00, .end = 0x18D08 }, // Tangut suppl
    Range{ .start = 0x20000, .end = 0x2A6DF }, // CJK ext B
    Range{ .start = 0x2A700, .end = 0x2B738 }, // CJK ext C
    Range{ .start = 0x2B740, .end = 0x2B81D }, // CJK ext D
    Range{ .start = 0x2B820, .end = 0x2CEA1 }, // CJK ext E
    Range{ .start = 0x2CEB0, .end = 0x2EBE0 }, // CJK ext F
    Range{ .start = 0x30000, .end = 0x3134A }, // CJK ext G
    Range{ .start = 0xF0000, .end = 0xFFFFD }, // Plane 15 private use
    Range{ .start = 0x10_0000, .end = 0x10_FFFD }, // Plane 16 private use
};

//
// Functions
//

pub fn packWeights(variable: bool, primary: u16, secondary: u16, tertiary: u8) u32 {
    const upper: u32 = (@as(u32, primary) << 16);
    const v_int: u16 = @intFromBool(variable);
    const lower: u16 = (v_int << 15) | (@as(u16, tertiary) << 9) | secondary;
    return upper | @as(u32, lower);
}
