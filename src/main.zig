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

    var low_ducet = try low.mapLow(alloc, keys_ducet);
    defer low_ducet.deinit();

    var low_cldr = try low.mapLow(alloc, keys_cldr);
    defer low_cldr.deinit();

    try low.saveLowBin(&low_ducet, "bin/low.bin");
    try low.saveLowBin(&low_cldr, "bin/low_cldr.bin");

    // Also write to JSON for debugging
    try low.saveLowJson(alloc, &low_ducet, "json/low.json");
    try low.saveLowJson(alloc, &low_cldr, "json/low_cldr.json");
}
