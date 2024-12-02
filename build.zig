const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const libRoot = b.path("src/root.zig");

    const module = b.addModule("lys", .{
        .root_source_file = libRoot,
        .target = target,
        .optimize = optimize,
    });
    const chameleon = b.dependency("chameleon", .{
        .target = target,
        .optimize = optimize,
    });
    module.addImport("chameleon", chameleon.module("chameleon"));

    const libTests = b.addTest(.{
        .root_source_file = libRoot,
        .target = target,
        .optimize = optimize,
    });
    libTests.root_module.addImport("chameleon", chameleon.module("chameleon"));

    const libTestsRun = b.addRunArtifact(libTests);

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&libTestsRun.step);
}
