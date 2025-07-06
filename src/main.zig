const std = @import("std");

const ccc = @import("ccc");
const decomp = @import("decomp");
const fcd = @import("fcd");
const low = @import("low");
const multi = @import("multi");
const single = @import("single");

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

    try ccc.saveCccBin(alloc, &ccc_map, "bin/ccc.bin");
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

    try decomp.saveDecompBin(alloc, &decomps, "bin/decomp.bin");
    try decomp.saveDecompJson(alloc, &decomps, "json/decomp.json");

    //
    // FCD
    //

    var fcd_map = try fcd.mapFCD(alloc, &uni_data);
    defer fcd_map.deinit();

    try fcd.saveFcdBin(alloc, &fcd_map, "bin/fcd.bin");
    try fcd.saveFcdJson(alloc, &fcd_map, "json/fcd.json");

    //
    // Low code point weights
    //

    const low_ducet = try low.mapLow(alloc, &keys_ducet);
    const low_cldr = try low.mapLow(alloc, &keys_cldr);

    try low.saveLowJson(&low_ducet, "json/low.json");
    try low.saveLowJson(&low_cldr, "json/low_cldr.json");

    //
    // Single-code-point weights
    //

    var singles_ducet = try single.mapSingles(alloc, &keys_ducet);
    defer {
        var it = singles_ducet.iterator();
        while (it.next()) |kv| alloc.free(kv.value_ptr.*);
        singles_ducet.deinit();
    }

    var singles_cldr = try single.mapSingles(alloc, &keys_cldr);
    defer {
        var it = singles_cldr.iterator();
        while (it.next()) |kv| alloc.free(kv.value_ptr.*);
        singles_cldr.deinit();
    }

    try single.saveSinglesBin(alloc, &singles_ducet, "bin/singles.bin");
    try single.saveSinglesBin(alloc, &singles_cldr, "bin/singles_cldr.bin");

    try single.saveSinglesJson(alloc, &singles_ducet, "json/singles.json");
    try single.saveSinglesJson(alloc, &singles_cldr, "json/singles_cldr.json");

    //
    // Multi-code-point weights
    //

    var multi_ducet = try multi.mapMulti(alloc, &keys_ducet);
    defer {
        var it = multi_ducet.iterator();
        while (it.next()) |kv| alloc.free(kv.value_ptr.*);
        multi_ducet.deinit();
    }

    var multi_cldr = try multi.mapMulti(alloc, &keys_cldr);
    defer {
        var it = multi_cldr.iterator();
        while (it.next()) |kv| alloc.free(kv.value_ptr.*);
        multi_cldr.deinit();
    }

    try multi.saveMultiBin(alloc, &multi_ducet, "bin/multi.bin");
    try multi.saveMultiBin(alloc, &multi_cldr, "bin/multi_cldr.bin");

    try multi.saveMultiJson(alloc, &multi_ducet, "json/multi.json");
    try multi.saveMultiJson(alloc, &multi_cldr, "json/multi_cldr.json");
}
