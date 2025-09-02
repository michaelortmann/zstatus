// SPDX-License-Identifier: MIT
// Copyright (c) 2024 - 2025 Michael Ortmann

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "zstatus",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add build option config.git_commit;
    const options = b.addOptions();
    const git_commit = b.option([]const u8, "git-commit", "Git commit") orelse std.mem.trimRight(u8, b.run(&.{ "git", "rev-parse", "--verify", "HEAD" }), "\n");
    options.addOption([]const u8, "git_commit", git_commit);
    exe.root_module.addOptions("config", options);

    b.installArtifact(exe);
}
