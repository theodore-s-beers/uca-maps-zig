const std = @import("std");
const low = @import("low");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer std.debug.assert(gpa.deinit() == .ok);
    const alloc = gpa.allocator();

    const cwd = std.fs.cwd();

    const keys_ducet = try cwd.readFileAlloc(alloc, "data/allkeys.txt", 3 * 1024 * 1024);
    defer alloc.free(keys_ducet);

    const keys_cldr = try cwd.readFileAlloc(alloc, "data/allkeys_cldr.txt", 3 * 1024 * 1024);
    defer alloc.free(keys_cldr);

    const low_ducet = try low.mapLow(alloc, keys_ducet);
    const low_cldr = try low.mapLow(alloc, keys_cldr);

    // Write to JSON for convenience
    try low.saveLowJson(&low_ducet, "json/low.json");
    try low.saveLowJson(&low_cldr, "json/low_cldr.json");
}
