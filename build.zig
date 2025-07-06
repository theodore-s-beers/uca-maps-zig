const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    // Optimization level to be set by user
    const optimize = b.standardOptimizeOption(.{});

    const ccc_mod = b.createModule(.{
        .root_source_file = b.path("src/ccc.zig"),
        .target = target,
        .optimize = optimize,
    });

    const decomp_mod = b.createModule(.{
        .root_source_file = b.path("src/decomp.zig"),
        .target = target,
        .optimize = optimize,
    });

    const fcd_mod = b.createModule(.{
        .root_source_file = b.path("src/fcd.zig"),
        .target = target,
        .optimize = optimize,
    });

    const low_mod = b.createModule(.{
        .root_source_file = b.path("src/low.zig"),
        .target = target,
        .optimize = optimize,
    });

    const multi_mod = b.createModule(.{
        .root_source_file = b.path("src/multi.zig"),
        .target = target,
        .optimize = optimize,
    });

    const util_mod = b.createModule(.{
        .root_source_file = b.path("src/util.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    fcd_mod.addImport("ccc", ccc_mod);
    fcd_mod.addImport("decomp", decomp_mod);

    low_mod.addImport("util", util_mod);

    multi_mod.addImport("util", util_mod);

    exe_mod.addImport("ccc", ccc_mod);
    exe_mod.addImport("decomp", decomp_mod);
    exe_mod.addImport("fcd", fcd_mod);
    exe_mod.addImport("low", low_mod);
    exe_mod.addImport("multi", multi_mod);

    const exe = b.addExecutable(.{
        .name = "uca_maps_zig",
        .root_module = exe_mod,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| run_cmd.addArgs(args);

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const ccc_unit_tests = b.addTest(.{ .root_module = ccc_mod });
    const run_ccc_unit_tests = b.addRunArtifact(ccc_unit_tests);

    const decomp_unit_tests = b.addTest(.{ .root_module = decomp_mod });
    const run_decomp_unit_tests = b.addRunArtifact(decomp_unit_tests);

    const fcd_unit_tests = b.addTest(.{ .root_module = fcd_mod });
    const run_fcd_unit_tests = b.addRunArtifact(fcd_unit_tests);

    const low_unit_tests = b.addTest(.{ .root_module = low_mod });
    const run_low_unit_tests = b.addRunArtifact(low_unit_tests);

    const multi_unit_tests = b.addTest(.{ .root_module = multi_mod });
    const run_multi_unit_tests = b.addRunArtifact(multi_unit_tests);

    const util_unit_tests = b.addTest(.{ .root_module = util_mod });
    const run_util_unit_tests = b.addRunArtifact(util_unit_tests);

    const exe_unit_tests = b.addTest(.{ .root_module = exe_mod });
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_ccc_unit_tests.step);
    test_step.dependOn(&run_decomp_unit_tests.step);
    test_step.dependOn(&run_fcd_unit_tests.step);
    test_step.dependOn(&run_low_unit_tests.step);
    test_step.dependOn(&run_multi_unit_tests.step);
    test_step.dependOn(&run_util_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);
}
