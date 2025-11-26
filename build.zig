var check_step: *Step = undefined;

pub fn build(b: *Build) void {
    check_step = b.step("check", "check the project");

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const tig = b.addModule("tig", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    examples(b, tig, target, optimize);

    const tests = b.addTest(.{ .root_module = tig });
    check_step.dependOn(&tests.step);

    const run_tests = b.addRunArtifact(tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}

fn examples(
    b: *Build,
    tig: *Module,
    target: Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) void {
    const example_step = b.step("examples", "Run all examples");

    const current_time = b.addExecutable(.{
        .name = "current_time",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/getCurrentTime.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "tig", .module = tig },
            },
        }),
    });
    check_step.dependOn(&current_time.step);
    example_step.dependOn(&b.addRunArtifact(current_time).step);

    const formatting_time = b.addExecutable(.{
        .name = "formatting_time",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/formattingTime.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "tig", .module = tig },
            },
        }),
    });
    check_step.dependOn(&formatting_time.step);
    example_step.dependOn(&b.addRunArtifact(formatting_time).step);
}

const std = @import("std");
const Build = std.Build;
const Module = Build.Module;
const Step = Build.Step;
