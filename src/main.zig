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
    // Canonical combining classes
    //

    start = std.time.milliTimestamp();

    var ccc_map = try ccc.mapCCC(alloc, &uni_data);
    defer ccc_map.deinit();

    try ccc.saveCccBin(alloc, &ccc_map, "bin/ccc.bin");
    try ccc.saveCccJson(alloc, &ccc_map, "json/ccc.json");

    end = std.time.milliTimestamp();
    std.debug.print("CCC: {} ms\n", .{end - start});

    //
    // Decompositions
    //

    start = std.time.milliTimestamp();

    var decomps = try decomp.mapDecomps(alloc, &uni_data);
    defer {
        var it = decomps.iterator();
        while (it.next()) |entry| alloc.free(entry.value_ptr.*);
        decomps.deinit();
    }

    try decomp.saveDecompBin(alloc, &decomps, "bin/decomp.bin");
    try decomp.saveDecompJson(alloc, &decomps, "json/decomp.json");

    end = std.time.milliTimestamp();
    std.debug.print("Decompositions: {} ms\n", .{end - start});

    //
    // FCD
    //

    start = std.time.milliTimestamp();

    var fcd_map = try fcd.mapFCD(alloc, &uni_data);
    defer fcd_map.deinit();

    try fcd.saveFcdBin(alloc, &fcd_map, "bin/fcd.bin");
    try fcd.saveFcdJson(alloc, &fcd_map, "json/fcd.json");

    end = std.time.milliTimestamp();
    std.debug.print("FCD: {} ms\n", .{end - start});

    //
    // Low code point weights
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
    // Single-code-point weights
    //

    start = std.time.milliTimestamp();

    var singles_ducet = try single.mapSingles(alloc, &keys_ducet);
    defer {
        var it = singles_ducet.iterator();
        while (it.next()) |kv| alloc.free(kv.value_ptr.*);
        singles_ducet.deinit();
    }

    try single.saveSinglesBin(alloc, &singles_ducet, "bin/singles.bin");
    try single.saveSinglesJson(alloc, &singles_ducet, "json/singles.json");

    end = std.time.milliTimestamp();
    std.debug.print("Single-code-point (DUCET): {} ms\n", .{end - start});

    start = std.time.milliTimestamp();

    var singles_cldr = try single.mapSingles(alloc, &keys_cldr);
    defer {
        var it = singles_cldr.iterator();
        while (it.next()) |kv| alloc.free(kv.value_ptr.*);
        singles_cldr.deinit();
    }

    try single.saveSinglesBin(alloc, &singles_cldr, "bin/singles_cldr.bin");
    try single.saveSinglesJson(alloc, &singles_cldr, "json/singles_cldr.json");

    end = std.time.milliTimestamp();
    std.debug.print("Single-code-point (CLDR): {} ms\n", .{end - start});

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

    var variable_loaded = try variable.loadVariableBin(alloc, "bin/variable.bin");
    defer variable_loaded.deinit();
}
