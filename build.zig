const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const libRoot = b.path("src/root.zig");

    const lib = b.addStaticLibrary(.{
        .name = "lys",
        .root_source_file = libRoot,
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(lib);

    const libTests = b.addTest(.{
        .root_source_file = libRoot,
        .target = target,
        .optimize = optimize,
    });

    const libTestsRun = b.addRunArtifact(libTests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&libTestsRun.step);
}
