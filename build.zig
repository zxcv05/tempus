const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .root_source_file = b.path("src/main.zig"),
        .name = "tempus",

        .optimize = optimize,
        .target = target,

        .link_libc = true,
        .strip = optimize != .Debug,
    });

    exe.link_gc_sections = true;
    exe.root_module.addImport("zeit", b.dependency("zeit", .{}).module("zeit"));

    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    const step = b.step("run", "Run program");

    if (b.args) |args| run.addArgs(args);

    step.dependOn(&run.step);
}
