const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const datetime_tests = b.addTest(.{
        .root_source_file = b.path("src/DateTime.zig"),
        .target = target,
        .optimize = optimize,
    });
    const datetime_unit_tests = b.addRunArtifact(datetime_tests);

    const timezone_tests = b.addTest(.{
        .root_source_file = b.path("src/TimeZone.zig"),
        .target = target,
        .optimize = optimize,
    });
    const timezone_unit_tests = b.addRunArtifact(timezone_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&datetime_unit_tests.step);
    test_step.dependOn(&timezone_unit_tests.step);
}
