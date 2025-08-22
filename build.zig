const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const elfy = b.addModule("elfy", .{ .root_source_file = b.path("src/root.zig") });

    const lib_test = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("test/test.zig"),
        .target = target,
        .optimize = optimize,
    }) });
    lib_test.root_module.addImport("elfy", elfy);

    const tests_step = b.step("test", "Run tests");
    tests_step.dependOn(&b.addRunArtifact(lib_test).step);
}
