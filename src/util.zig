const std = @import("std");

//
// Types
//

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

//
// Constants
//

pub const HEX: std.bit_set.ArrayBitSet(usize, 256) = blk: {
    var set = std.StaticBitSet(256).initEmpty();
    for ('0'..':') |c| set.set(c);
    for ('A'..'G') |c| set.set(c);
    break :blk set;
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
