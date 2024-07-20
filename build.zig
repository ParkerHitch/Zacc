const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zaccMod = b.addModule("zacc", .{ .root_source_file = b.path("zacc.zig") });

    const verboseParsing = b.option(bool, "vparsing", "Print All Parsing Actions") orelse false;
    const verboseLexing = b.option(bool, "vlexing", "Print All Lexing Info") orelse false;

    const options = b.addOptions();
    options.addOption(bool, "verboseParsing", verboseParsing);
    options.addOption(bool, "verboseLexing", verboseLexing);

    zaccMod.addOptions("config", options);

    const zacc_tests_exe = b.addTest(.{ .name = "zacctest", .root_source_file = b.path("zacc.zig"), .target = target, .optimize = optimize });

    zacc_tests_exe.root_module.addOptions("config", options);
    b.installArtifact(zacc_tests_exe);

    const run_tests_cmd = b.addRunArtifact(zacc_tests_exe);
    run_tests_cmd.has_side_effects = true;
    run_tests_cmd.step.dependOn(b.getInstallStep());

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&run_tests_cmd.step);
}
