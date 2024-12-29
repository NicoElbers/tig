const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const datetime_tests = b.addTest(.{
        .root_source_file = b.path("src/DateTime.zig"),
        .target = target,
        .optimize = optimize,
        // .use_llvm = false,
        // .use_lld = false,
    });
    const datetime_unit_tests = b.addRunArtifact(datetime_tests);

    const tzstring_tests = b.addTest(.{
        .root_source_file = b.path("src/TZString.zig"),
        .target = target,
        .optimize = optimize,
        // .use_llvm = false,
        // .use_lld = false,
    });
    const tzstring_unit_tests = b.addRunArtifact(tzstring_tests);

    const tzif_tests = b.addTest(.{
        .root_source_file = b.path("src/TZif.zig"),
        .target = target,
        .optimize = optimize,
        // .use_llvm = false,
        // .use_lld = false,
    });
    const tzif_unit_tests = b.addRunArtifact(tzif_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&datetime_unit_tests.step);
    test_step.dependOn(&tzstring_unit_tests.step);
    test_step.dependOn(&tzif_unit_tests.step);
}
