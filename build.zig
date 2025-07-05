const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    // Optimization level to be set by user
    const optimize = b.standardOptimizeOption(.{});

    const decomp_mod = b.createModule(.{
        .root_source_file = b.path("src/decomp.zig"),
        .target = target,
        .optimize = optimize,
    });

    const low_mod = b.createModule(.{
        .root_source_file = b.path("src/low.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe_mod.addImport("decomp", decomp_mod);
    exe_mod.addImport("low", low_mod);

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

    const decomp_unit_tests = b.addTest(.{ .root_module = decomp_mod });
    const run_decomp_unit_tests = b.addRunArtifact(decomp_unit_tests);

    const low_unit_tests = b.addTest(.{ .root_module = low_mod });
    const run_low_unit_tests = b.addRunArtifact(low_unit_tests);

    const exe_unit_tests = b.addTest(.{ .root_module = exe_mod });
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_decomp_unit_tests.step);
    test_step.dependOn(&run_low_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);
}
