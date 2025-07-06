const std = @import("std");

const ccc = @import("ccc");
const decomp = @import("decomp");
const low = @import("low");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer std.debug.assert(gpa.deinit() == .ok);
    const alloc = gpa.allocator();

    //
    // Load data
    //

    const cwd = std.fs.cwd();

    const uni_data = try cwd.readFileAlloc(alloc, "data/UnicodeData.txt", 3 * 1024 * 1024);
    defer alloc.free(uni_data);

    const keys_ducet = try cwd.readFileAlloc(alloc, "data/allkeys.txt", 3 * 1024 * 1024);
    defer alloc.free(keys_ducet);

    const keys_cldr = try cwd.readFileAlloc(alloc, "data/allkeys_cldr.txt", 3 * 1024 * 1024);
    defer alloc.free(keys_cldr);

    //
    // Canonical combining classes
    //

    var ccc_map = try ccc.mapCCC(alloc, &uni_data);
    defer ccc_map.deinit();

    try ccc.saveCccBin(&ccc_map, "bin/ccc.bin");
    try ccc.saveCccJson(alloc, &ccc_map, "json/ccc.json");

    //
    // Decompositions
    //

    var decomps = try decomp.mapDecomps(alloc, &uni_data);
    defer {
        var it = decomps.iterator();
        while (it.next()) |entry| alloc.free(entry.value_ptr.*);
        decomps.deinit();
    }

    try decomp.saveDecompBin(&decomps, "bin/decomp.bin");
    try decomp.saveDecompJson(alloc, &decomps, "json/decomp.json");

    //
    // Low code point weights
    //

    const low_ducet = try low.mapLow(alloc, &keys_ducet);
    const low_cldr = try low.mapLow(alloc, &keys_cldr);

    try low.saveLowJson(&low_ducet, "json/low.json");
    try low.saveLowJson(&low_cldr, "json/low_cldr.json");
}
