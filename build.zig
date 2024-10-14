// SPDX-License-Identifier: MIT
// Copyright (c) 2024 Michael Ortmann

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

    const zeit = b.dependency("zeit", .{
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("zeit", zeit.module("zeit"));
    b.installArtifact(exe);
}
