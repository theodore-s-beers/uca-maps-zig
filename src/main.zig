const std = @import("std");

const unicode = @import("unicode.zig");
const compact = @import("compact");
const ccc = @import("ccc");
const decomp = @import("decomp");
const fcd = @import("fcd");
const low = @import("low");
const multi = @import("multi");
const single = @import("single");
const variable = @import("variable");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const alloc = init.gpa;

    //
    // Load data
    //

    var start = std.Io.Timestamp.now(io, .awake).toMilliseconds();

    const cwd = std.Io.Dir.cwd();

    const uni_data = try cwd.readFileAlloc(io, "data/UnicodeData.txt", alloc, .limited(3 * 1024 * 1024));
    defer alloc.free(uni_data);

    const keys_ducet = try cwd.readFileAlloc(io, "data/allkeys.txt", alloc, .limited(3 * 1024 * 1024));
    defer alloc.free(keys_ducet);

    const keys_cldr = try cwd.readFileAlloc(io, "data/allkeys_CLDR.txt", alloc, .limited(3 * 1024 * 1024));
    defer alloc.free(keys_cldr);

    var end = std.Io.Timestamp.now(io, .awake).toMilliseconds();
    std.debug.print("Load data: {} ms\n", .{end - start});
    std.debug.print("\n", .{});

    //
    // Generate CCC map
    //

    start = std.Io.Timestamp.now(io, .awake).toMilliseconds();

    var ccc_map = try ccc.mapCCC(alloc, uni_data);
    defer ccc_map.deinit();

    try ccc.saveCccBin(io, alloc, &ccc_map, "bin/ccc.bin");
    try ccc.saveCccJson(io, alloc, &ccc_map, "json/ccc.json");

    end = std.Io.Timestamp.now(io, .awake).toMilliseconds();
    std.debug.print("Generate CCC map: {} ms\n", .{end - start});

    //
    // Test loading CCC map
    //

    var start_load = std.Io.Timestamp.now(io, .awake).toMicroseconds();

    var ccc_from_bin = try ccc.loadCccBin(io, alloc, "bin/ccc.bin");
    defer ccc_from_bin.deinit();

    var end_load = std.Io.Timestamp.now(io, .awake).toMicroseconds();
    std.debug.print("Load CCC map from bin: {} us\n", .{end_load - start_load});
    std.debug.print("\n", .{});

    var ccc_from_json = try ccc.loadCccJson(io, alloc, "json/ccc.json");
    defer ccc_from_json.deinit();

    std.debug.assert(ccc_from_bin.count() == ccc_from_json.count());
    std.debug.assert(ccc_from_bin.count() == ccc_map.count());

    //
    // Generate decomposition map
    //

    start = std.Io.Timestamp.now(io, .awake).toMilliseconds();

    var decomps = try decomp.mapDecomps(alloc, uni_data);
    defer decomps.deinit();

    try decomp.saveDecompBin(io, alloc, &decomps.map, "bin/decomp.bin");
    try decomp.saveDecompJson(io, alloc, &decomps.map, "json/decomp.json");

    end = std.Io.Timestamp.now(io, .awake).toMilliseconds();
    std.debug.print("Generate decomposition map: {} ms\n", .{end - start});

    //
    // Test loading decomposition map
    //

    start_load = std.Io.Timestamp.now(io, .awake).toMicroseconds();

    var decomp_from_bin = try decomp.loadDecompBin(io, alloc, "bin/decomp.bin");
    defer decomp_from_bin.deinit();

    end_load = std.Io.Timestamp.now(io, .awake).toMicroseconds();
    std.debug.print("Load decomposition map from bin: {} us\n", .{end_load - start_load});
    std.debug.print("\n", .{});

    var decomp_from_json = try decomp.loadDecompJson(io, alloc, "json/decomp.json");
    defer decomp_from_json.deinit();

    std.debug.assert(decomp_from_bin.map.count() == decomp_from_json.map.count());
    std.debug.assert(decomp_from_bin.map.count() == decomps.map.count());

    //
    // Generate FCD map
    //

    start = std.Io.Timestamp.now(io, .awake).toMilliseconds();

    var fcd_map = try fcd.mapFCD(io, alloc, uni_data);
    defer fcd_map.deinit();

    try fcd.saveFcdBin(io, alloc, &fcd_map, "bin/fcd.bin");
    try fcd.saveFcdJson(io, alloc, &fcd_map, "json/fcd.json");

    end = std.Io.Timestamp.now(io, .awake).toMilliseconds();
    std.debug.print("Generate FCD map: {} ms\n", .{end - start});

    //
    // Test loading FCD map
    //

    start_load = std.Io.Timestamp.now(io, .awake).toMicroseconds();

    var fcd_from_bin = try fcd.loadFcdBin(io, alloc, "bin/fcd.bin");
    defer fcd_from_bin.deinit();

    end_load = std.Io.Timestamp.now(io, .awake).toMicroseconds();
    std.debug.print("Load FCD map from bin: {} us\n", .{end_load - start_load});
    std.debug.print("\n", .{});

    var fcd_from_json = try fcd.loadFcdJson(io, alloc, "json/fcd.json");
    defer fcd_from_json.deinit();

    std.debug.assert(fcd_from_bin.count() == fcd_from_json.count());
    std.debug.assert(fcd_from_bin.count() == fcd_map.count());

    //
    // Generate low code point maps
    //

    start = std.Io.Timestamp.now(io, .awake).toMilliseconds();

    const low_ducet = try low.mapLow(alloc, keys_ducet);
    try low.saveLowJson(io, &low_ducet, "json/low.json");

    end = std.Io.Timestamp.now(io, .awake).toMilliseconds();
    std.debug.print("Generate low code point map (DUCET): {} ms\n", .{end - start});

    start = std.Io.Timestamp.now(io, .awake).toMilliseconds();

    const low_cldr = try low.mapLow(alloc, keys_cldr);
    try low.saveLowJson(io, &low_cldr, "json/low_cldr.json");

    end = std.Io.Timestamp.now(io, .awake).toMilliseconds();
    std.debug.print("Generate low code point map (CLDR): {} ms\n", .{end - start});
    std.debug.print("\n", .{});

    try unicode.write(io, alloc, uni_data, keys_ducet, &low_ducet, &low_cldr);

    //
    // Test loading low code point maps
    //

    const low_from_json_ducet = try low.loadLowJson(io, alloc, "json/low.json");
    const low_from_json_cldr = try low.loadLowJson(io, alloc, "json/low_cldr.json");

    std.debug.assert(std.mem.eql(u32, &low_ducet, &low_from_json_ducet));
    std.debug.assert(std.mem.eql(u32, &low_cldr, &low_from_json_cldr));

    //
    // Generate single-code-point maps
    //

    start = std.Io.Timestamp.now(io, .awake).toMilliseconds();

    var singles_ducet = try single.mapSingles(alloc, keys_ducet);
    defer singles_ducet.deinit();

    try single.saveSinglesBin(io, alloc, &singles_ducet.map, "bin/singles.bin");
    try single.saveSinglesJson(io, alloc, &singles_ducet.map, "json/singles.json");

    end = std.Io.Timestamp.now(io, .awake).toMilliseconds();
    std.debug.print("Generate single-code-point map (DUCET): {} ms\n", .{end - start});

    start = std.Io.Timestamp.now(io, .awake).toMilliseconds();

    var singles_cldr = try single.mapSingles(alloc, keys_cldr);
    defer singles_cldr.deinit();

    try single.saveSinglesBin(io, alloc, &singles_cldr.map, "bin/singles_cldr.bin");
    try single.saveSinglesJson(io, alloc, &singles_cldr.map, "json/singles_cldr.json");

    end = std.Io.Timestamp.now(io, .awake).toMilliseconds();
    std.debug.print("Generate single-code-point map (CLDR): {} ms\n", .{end - start});
    std.debug.print("\n", .{});

    //
    // Test loading single-code-point maps
    //

    start_load = std.Io.Timestamp.now(io, .awake).toMicroseconds();

    var singles_from_bin = try single.loadSinglesBin(io, alloc, "bin/singles.bin");
    defer singles_from_bin.deinit();

    end_load = std.Io.Timestamp.now(io, .awake).toMicroseconds();
    std.debug.print("Load single-code-point map from bin (DUCET): {} us\n", .{end_load - start_load});

    var singles_from_json = try single.loadSinglesJson(io, alloc, "json/singles.json");
    defer singles_from_json.deinit();

    std.debug.assert(singles_from_bin.map.count() == singles_from_json.map.count());
    std.debug.assert(singles_from_bin.map.count() == singles_ducet.map.count());

    start_load = std.Io.Timestamp.now(io, .awake).toMicroseconds();

    var singles_from_bin_cldr = try single.loadSinglesBin(io, alloc, "bin/singles_cldr.bin");
    defer singles_from_bin_cldr.deinit();

    end_load = std.Io.Timestamp.now(io, .awake).toMicroseconds();
    std.debug.print("Load single-code-point map from bin (CLDR): {} us\n", .{end_load - start_load});
    std.debug.print("\n", .{});

    var singles_from_json_cldr = try single.loadSinglesJson(io, alloc, "json/singles_cldr.json");
    defer singles_from_json_cldr.deinit();

    std.debug.assert(singles_from_bin_cldr.map.count() == singles_from_json_cldr.map.count());
    std.debug.assert(singles_from_bin_cldr.map.count() == singles_cldr.map.count());

    //
    // Generate multi-code-point maps
    //

    start = std.Io.Timestamp.now(io, .awake).toMilliseconds();

    var multi_ducet = try multi.mapMulti(alloc, keys_ducet);
    defer multi_ducet.deinit();

    try multi.saveMultiBin(io, alloc, &multi_ducet.map, "bin/multi.bin");
    try multi.saveMultiJson(io, alloc, &multi_ducet.map, "json/multi.json");

    end = std.Io.Timestamp.now(io, .awake).toMilliseconds();
    std.debug.print("Generate multi-code-point map (DUCET): {} ms\n", .{end - start});

    start = std.Io.Timestamp.now(io, .awake).toMilliseconds();

    var multi_cldr = try multi.mapMulti(alloc, keys_cldr);
    defer multi_cldr.deinit();

    try multi.saveMultiBin(io, alloc, &multi_cldr.map, "bin/multi_cldr.bin");
    try multi.saveMultiJson(io, alloc, &multi_cldr.map, "json/multi_cldr.json");

    end = std.Io.Timestamp.now(io, .awake).toMilliseconds();
    std.debug.print("Generate multi-code-point map (CLDR): {} ms\n", .{end - start});
    std.debug.print("\n", .{});

    //
    // Test loading multi-code-point maps
    //

    start_load = std.Io.Timestamp.now(io, .awake).toMicroseconds();

    var multi_from_bin = try multi.loadMultiBin(io, alloc, "bin/multi.bin");
    defer multi_from_bin.deinit();

    end_load = std.Io.Timestamp.now(io, .awake).toMicroseconds();
    std.debug.print("Load multi-code-point map from bin (DUCET): {} us\n", .{end_load - start_load});

    var multi_from_json = try multi.loadMultiJson(io, alloc, "json/multi.json");
    defer multi_from_json.deinit();

    std.debug.assert(multi_from_bin.map.count() == multi_from_json.map.count());
    std.debug.assert(multi_from_bin.map.count() == multi_ducet.map.count());

    start_load = std.Io.Timestamp.now(io, .awake).toMicroseconds();

    var multi_from_bin_cldr = try multi.loadMultiBin(io, alloc, "bin/multi_cldr.bin");
    defer multi_from_bin_cldr.deinit();

    end_load = std.Io.Timestamp.now(io, .awake).toMicroseconds();
    std.debug.print("Load multi-code-point map from bin (CLDR): {} us\n", .{end_load - start_load});
    std.debug.print("\n", .{});

    var multi_from_json_cldr = try multi.loadMultiJson(io, alloc, "json/multi_cldr.json");
    defer multi_from_json_cldr.deinit();

    std.debug.assert(multi_from_bin_cldr.map.count() == multi_from_json_cldr.map.count());
    std.debug.assert(multi_from_bin_cldr.map.count() == multi_cldr.map.count());

    try compact.write(io, alloc, &singles_ducet.map, &multi_ducet.map, "bin/collation.bin");
    try compact.write(io, alloc, &singles_cldr.map, &multi_cldr.map, "bin/collation_cldr.bin");

    //
    // Generate variable weight map
    //

    start = std.Io.Timestamp.now(io, .awake).toMilliseconds();

    var variable_set = try variable.mapVariable(alloc, keys_ducet);
    defer variable_set.deinit();

    try variable.saveVariableBin(io, alloc, &variable_set, "bin/variable.bin");
    try variable.saveVariableJson(io, alloc, &variable_set, "json/variable.json");

    end = std.Io.Timestamp.now(io, .awake).toMilliseconds();
    std.debug.print("Generate variable weight map: {} ms\n", .{end - start});

    //
    // Test loading variable weight map
    //

    start_load = std.Io.Timestamp.now(io, .awake).toMicroseconds();

    var variable_from_bin = try variable.loadVariableBin(io, alloc, "bin/variable.bin");
    defer variable_from_bin.deinit();

    end_load = std.Io.Timestamp.now(io, .awake).toMicroseconds();
    std.debug.print("Load variable weight map from bin: {} us\n", .{end_load - start_load});

    var variable_from_json = try variable.loadVariableJson(io, alloc, "json/variable.json");
    defer variable_from_json.deinit();

    std.debug.assert(variable_from_bin.count() == variable_from_json.count());
    std.debug.assert(variable_from_bin.count() == variable_set.count());
}
