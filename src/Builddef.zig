// SPDX-License-Identifier: Apache-2.0
// Copyright © 2025 Maxine R Bonnette. All rights reserved.

const fs = @import("std").fs;
const fmt = @import("std").fmt;
const Build = @import("std").Build;
const Mode = @import("std").builtin.OptimizeMode;
const Compile = @import("std").Build.Step.Compile;
const Target = @import("std").Build.ResolvedTarget;

build: *Build,

pub fn init(def: *Build) @This() {
    return .{ .build = def };
}
pub fn stdOptions(
    def: *@This(),
    target_opts: Build.StandardTargetOptionsArgs,
    optimize_opts: Build.StandardOptimizeOptionOptions,
) struct { Target, Mode } {
    const target = def.build.standardTargetOptions(target_opts);
    const optimize = def.build.standardOptimizeOption(optimize_opts);
    def.universalSettings(target);
    return .{ target, optimize };
}
pub fn universalSettings(def: *@This(), target: Target) void {
    const t = target.result.cpu.arch == .x86_64;
    def.build.enable_wine = t and target.result.os.tag == .windows;
    def.build.enable_rosetta = t and target.result.os.tag == .macos;
}

pub fn runArtifact(def: *@This(), comp: *Compile, args: ?[]const []const u8) *Build.Step.Run {
    const run = def.build.addRunArtifact(comp);
    run.step.dependOn(&comp.step);
    if (args) |v| run.addArgs(v);
    return run;
}
pub fn @"test"(def: *@This(), root: ?[]const u8, target: Target, optimize: Mode) *Compile {
    const comp = Build.addTest(def.build, .{
        .unwind_tables = if (optimize == .Debug or optimize == .ReleaseSafe) .sync else .none,
        .omit_frame_pointer = optimize == .Debug or optimize == .ReleaseSafe,
        .error_tracing = optimize == .Debug or optimize == .ReleaseSafe,
        .strip = optimize == .ReleaseFast or optimize == .ReleaseSmall,
        .root_source_file = if (root) |v| def.build.path(v) else null,
        .optimize = optimize,
        .target = target,
        .pic = true,
    });
    comp.want_lto = !target.result.os.tag.isDarwin(); // https://github.com/ziglang/zig/issues/8680
    comp.compress_debug_sections = .zstd;
    comp.link_function_sections = true;
    comp.link_data_sections = true;
    comp.link_gc_sections = true;
    return comp;
}
pub fn executable(def: *@This(), name: []const u8, root: ?[]const u8, target: Target, optimize: Mode) *Compile {
    return def.compile(Build.addExecutable, name, root, target, optimize);
}
pub fn staticLib(def: *@This(), name: []const u8, root: ?[]const u8, target: Target, optimize: Mode) *Compile {
    return def.compile(Build.addStaticLibrary, name, root, target, optimize);
}
pub fn sharedLib(def: *@This(), name: []const u8, root: ?[]const u8, target: Target, optimize: Mode) *Compile {
    return def.compile(Build.addSharedLibrary, name, root, target, optimize);
}
pub fn compile(def: *@This(), step: anytype, name: []const u8, root: ?[]const u8, target: Target, optimize: Mode) *Compile {
    const comp = step(def.build, .{
        .unwind_tables = if (optimize == .Debug or optimize == .ReleaseSafe) .sync else .none,
        .omit_frame_pointer = optimize == .ReleaseFast or optimize == .ReleaseSmall,
        .error_tracing = optimize == .Debug or optimize == .ReleaseSafe,
        .strip = optimize == .ReleaseFast or optimize == .ReleaseSmall,
        .root_source_file = if (root) |v| def.build.path(v) else null,
        .optimize = optimize,
        .target = target,
        .name = name,
        .pic = true,
    });
    comp.want_lto = !target.result.os.tag.isDarwin(); // https://github.com/ziglang/zig/issues/8680
    comp.compress_debug_sections = .zstd;
    comp.link_function_sections = true;
    comp.link_data_sections = true;
    comp.link_gc_sections = true;
    return comp;
}

pub fn addCSources(def: *@This(), comp: *Compile, sources: []const CSources) void {
    var buf: [fs.max_path_bytes]u8 = undefined;
    for (sources) |v| {
        for (v.header_paths orelse &.{}) |vv| {
            const path = fmt.bufPrint(&buf, "{s}" ++ fs.path.sep_str ++ "{s}", .{ v.root orelse "", vv }) catch unreachable;
            comp.addIncludePath(def.build.path(path));
        }
        comp.addCSourceFiles(.{
            .root = if (v.root) |vv| def.build.path(vv) else null,
            .files = v.c_sources orelse &.{},
            .flags = v.flags orelse &.{},
        });
    }
}
pub const CSources = struct {
    header_paths: ?[]const []const u8 = null,
    c_sources: ?[]const []const u8 = null,
    flags: ?[]const []const u8 = null,
    root: ?[]const u8 = ".",
};
