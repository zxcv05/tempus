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

    exe.root_module.addImport("datetime", b.dependency("datetime", .{}).module("zig-datetime"));

    // TODO: Uncomment when build error gets fixed
    // const time_h = b.addTranslateC(.{
    //     .optimize = optimize,
    //     .target = target,
    //     .root_source_file = .{ .cwd_relative = "/usr/include/time.h" },
    // });

    // exe.root_module.addImport("time_h", time_h.addModule("time_h"));

    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    const step = b.step("run", "Run program");

    if (b.args) |args| run.addArgs(args);

    step.dependOn(&run.step);
}
