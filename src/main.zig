const std = @import("std");

const ccc = @import("ccc");
const decomp = @import("decomp");
const fcd = @import("fcd");
const low = @import("low");
const multi = @import("multi");
const single = @import("single");
const variable = @import("variable");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer std.debug.assert(gpa.deinit() == .ok);
    const alloc = gpa.allocator();

    //
    // Load data
    //

    var start = std.time.milliTimestamp();

    const cwd = std.fs.cwd();

    const uni_data = try cwd.readFileAlloc(alloc, "data/UnicodeData.txt", 3 * 1024 * 1024);
    defer alloc.free(uni_data);

    const keys_ducet = try cwd.readFileAlloc(alloc, "data/allkeys.txt", 3 * 1024 * 1024);
    defer alloc.free(keys_ducet);

    const keys_cldr = try cwd.readFileAlloc(alloc, "data/allkeys_cldr.txt", 3 * 1024 * 1024);
    defer alloc.free(keys_cldr);

    var end = std.time.milliTimestamp();
    std.debug.print("Load data: {} ms\n", .{end - start});

    //
    // Generate CCC map
    //

    start = std.time.milliTimestamp();

    var ccc_map = try ccc.mapCCC(alloc, &uni_data);
    defer ccc_map.deinit();

    try ccc.saveCccBin(alloc, &ccc_map, "bin/ccc.bin");
    try ccc.saveCccJson(alloc, &ccc_map, "json/ccc.json");

    end = std.time.milliTimestamp();
    std.debug.print("CCC: {} ms\n", .{end - start});

    //
    // Test loading CCC map
    //

    var ccc_from_bin = try ccc.loadCccBin(alloc, "bin/ccc.bin");
    defer ccc_from_bin.deinit();

    var ccc_from_json = try ccc.loadCccJson(alloc, "json/ccc.json");
    defer ccc_from_json.deinit();

    std.debug.assert(ccc_from_bin.count() == ccc_from_json.count());
    std.debug.assert(ccc_from_bin.count() == ccc_map.count());

    //
    // Generate decomposition map
    //

    start = std.time.milliTimestamp();

    var decomps = try decomp.mapDecomps(alloc, &uni_data);
    defer decomps.deinit();

    try decomp.saveDecompBin(alloc, &decomps.map, "bin/decomp.bin");
    try decomp.saveDecompJson(alloc, &decomps.map, "json/decomp.json");

    end = std.time.milliTimestamp();
    std.debug.print("Decompositions: {} ms\n", .{end - start});

    //
    // Test loading decomposition map
    //

    var decomp_from_bin = try decomp.loadDecompBin(alloc, "bin/decomp.bin");
    defer decomp_from_bin.deinit();

    var decomp_from_json = try decomp.loadDecompJson(alloc, "json/decomp.json");
    defer decomp_from_json.deinit();

    std.debug.assert(decomp_from_bin.map.count() == decomp_from_json.map.count());
    std.debug.assert(decomp_from_bin.map.count() == decomps.map.count());

    //
    // Generate FCD map
    //

    start = std.time.milliTimestamp();

    var fcd_map = try fcd.mapFCD(alloc, &uni_data);
    defer fcd_map.deinit();

    try fcd.saveFcdBin(alloc, &fcd_map, "bin/fcd.bin");
    try fcd.saveFcdJson(alloc, &fcd_map, "json/fcd.json");

    end = std.time.milliTimestamp();
    std.debug.print("FCD: {} ms\n", .{end - start});

    //
    // Test loading FCD map
    //

    var fcd_from_bin = try fcd.loadFcdBin(alloc, "bin/fcd.bin");
    defer fcd_from_bin.deinit();

    var fcd_from_json = try fcd.loadFcdJson(alloc, "json/fcd.json");
    defer fcd_from_json.deinit();

    std.debug.assert(fcd_from_bin.count() == fcd_from_json.count());
    std.debug.assert(fcd_from_bin.count() == fcd_map.count());

    //
    // Generate low code point maps
    //

    start = std.time.milliTimestamp();

    const low_ducet = try low.mapLow(alloc, &keys_ducet);
    try low.saveLowJson(&low_ducet, "json/low.json");

    end = std.time.milliTimestamp();
    std.debug.print("Low-code-point (DUCET): {} ms\n", .{end - start});

    start = std.time.milliTimestamp();

    const low_cldr = try low.mapLow(alloc, &keys_cldr);
    try low.saveLowJson(&low_cldr, "json/low_cldr.json");

    end = std.time.milliTimestamp();
    std.debug.print("Low-code-point (CLDR): {} ms\n", .{end - start});

    //
    // Test loading low code point maps
    //

    const low_from_json_ducet = try low.loadLowJson(alloc, "json/low.json");
    const low_from_json_cldr = try low.loadLowJson(alloc, "json/low_cldr.json");

    std.debug.assert(std.mem.eql(u32, &low_ducet, &low_from_json_ducet));
    std.debug.assert(std.mem.eql(u32, &low_cldr, &low_from_json_cldr));

    //
    // Generate single-code-point maps
    //

    start = std.time.milliTimestamp();

    var singles_ducet = try single.mapSingles(alloc, &keys_ducet);
    defer singles_ducet.deinit();

    try single.saveSinglesBin(alloc, &singles_ducet.map, "bin/singles.bin");
    try single.saveSinglesJson(alloc, &singles_ducet.map, "json/singles.json");

    end = std.time.milliTimestamp();
    std.debug.print("Single-code-point (DUCET): {} ms\n", .{end - start});

    start = std.time.milliTimestamp();

    var singles_cldr = try single.mapSingles(alloc, &keys_cldr);
    defer singles_cldr.deinit();

    try single.saveSinglesBin(alloc, &singles_cldr.map, "bin/singles_cldr.bin");
    try single.saveSinglesJson(alloc, &singles_cldr.map, "json/singles_cldr.json");

    end = std.time.milliTimestamp();
    std.debug.print("Single-code-point (CLDR): {} ms\n", .{end - start});

    //
    // Test loading single-code-point maps
    //

    var singles_from_bin = try single.loadSinglesBin(alloc, "bin/singles.bin");
    defer singles_from_bin.deinit();

    var singles_from_json = try single.loadSinglesJson(alloc, "json/singles.json");
    defer singles_from_json.deinit();

    std.debug.assert(singles_from_bin.map.count() == singles_from_json.map.count());
    std.debug.assert(singles_from_bin.map.count() == singles_ducet.map.count());

    var singles_from_bin_cldr = try single.loadSinglesBin(alloc, "bin/singles_cldr.bin");
    defer singles_from_bin_cldr.deinit();

    var singles_from_json_cldr = try single.loadSinglesJson(alloc, "json/singles_cldr.json");
    defer singles_from_json_cldr.deinit();

    std.debug.assert(singles_from_bin_cldr.map.count() == singles_from_json_cldr.map.count());
    std.debug.assert(singles_from_bin_cldr.map.count() == singles_cldr.map.count());

    //
    // Multi-code-point weights
    //

    start = std.time.milliTimestamp();

    var multi_ducet = try multi.mapMulti(alloc, &keys_ducet);
    defer {
        var it = multi_ducet.iterator();
        while (it.next()) |kv| alloc.free(kv.value_ptr.*);
        multi_ducet.deinit();
    }

    try multi.saveMultiBin(alloc, &multi_ducet, "bin/multi.bin");
    try multi.saveMultiJson(alloc, &multi_ducet, "json/multi.json");

    end = std.time.milliTimestamp();
    std.debug.print("Multi-code-point (DUCET): {} ms\n", .{end - start});

    start = std.time.milliTimestamp();

    var multi_cldr = try multi.mapMulti(alloc, &keys_cldr);
    defer {
        var it = multi_cldr.iterator();
        while (it.next()) |kv| alloc.free(kv.value_ptr.*);
        multi_cldr.deinit();
    }

    try multi.saveMultiBin(alloc, &multi_cldr, "bin/multi_cldr.bin");
    try multi.saveMultiJson(alloc, &multi_cldr, "json/multi_cldr.json");

    end = std.time.milliTimestamp();
    std.debug.print("Multi-code-point (CLDR): {} ms\n", .{end - start});

    //
    // Variable weights
    //

    start = std.time.milliTimestamp();

    var variable_set = try variable.mapVariable(alloc, &keys_ducet);
    defer variable_set.deinit();

    try variable.saveVariableBin(alloc, &variable_set, "bin/variable.bin");
    try variable.saveVariableJson(alloc, &variable_set, "json/variable.json");

    end = std.time.milliTimestamp();
    std.debug.print("Variable weights: {} ms\n", .{end - start});

    var variable_from_bin = try variable.loadVariableBin(alloc, "bin/variable.bin");
    defer variable_from_bin.deinit();

    var variable_from_json = try variable.loadVariableJson(alloc, "json/variable.json");
    defer variable_from_json.deinit();

    std.debug.assert(variable_from_bin.count() == variable_from_json.count());
    std.debug.assert(variable_from_bin.count() == variable_set.count());
}
