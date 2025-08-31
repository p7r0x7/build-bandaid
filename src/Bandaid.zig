// SPDX-License-Identifier: Apache-2.0
// Copyright © 2025 Maxine R Bonnette. All rights reserved.

const std = @import("std");
const fmt = @import("std").fmt;
const Build = @import("std").Build;
const Module = @import("std").Build.Module;
const Mode = @import("std").builtin.OptimizeMode;
const Compile = @import("std").Build.Step.Compile;
const Target = @import("std").Build.ResolvedTarget;

b: *Build,

pub fn stdOptions(
    aid: *@This(),
    target_opts: Build.StandardTargetOptionsArgs,
    optimize_opts: Build.StandardOptimizeOptionOptions,
) struct { Target, Mode } {
    const target = aid.b.standardTargetOptions(target_opts);
    const optimize = aid.b.standardOptimizeOption(optimize_opts);
    aid.universalSettings(target);
    return .{ target, optimize };
}

pub fn universalSettings(aid: *@This(), target: Target) void {
    aid.b.allocator = std.heap.raw_c_allocator;
    const t = target.result.cpu.arch == .x86_64;
    aid.b.enable_wine = t and target.result.os.tag == .windows;
    aid.b.enable_rosetta = t and target.result.os.tag == .macos;
}

pub const Opts = struct {
    max_rss: usize = 0,
    use_lld: ?bool = null,
    use_llvm: ?bool = null,
    root_module: ?*Module = null,
    zig_lib_dir: ?Build.LazyPath = null,

    version: ?std.SemanticVersion = null,
    linkage: ?std.builtin.LinkMode = null,
    win32_manifest: ?Build.LazyPath = null,
    test_runner: ?Compile.TestRunner = null,
};

fn compile(aid: *@This(), step: anytype, OptT: type, name: []const u8, root: ?[]const u8, target: Target, optimize: Mode, opts: Opts) *Compile {
    var o: OptT = switch (OptT) {
        Build.TestOptions => .{
            .name = name,
            .test_runner = opts.test_runner,
            .root_module = opts.root_module orelse aid.module(name, root, target, optimize, .{}),
        },
        Build.ExecutableOptions, Build.LibraryOptions => .{
            .name = name,
            .version = opts.version,
            .linkage = opts.linkage,
            .win32_manifest = opts.win32_manifest,
            .root_module = opts.root_module orelse aid.module(name, root, target, optimize, .{}),
        },
        else => unreachable,
    };
    o.zig_lib_dir = opts.zig_lib_dir;
    o.use_llvm = opts.use_llvm;
    o.use_lld = opts.use_lld;
    o.max_rss = opts.max_rss;

    var c = step(aid.b, o);
    c.want_lto = !target.result.os.tag.isDarwin(); // https://github.com/ziglang/zig/issues/8680
    c.compress_debug_sections = .zstd;
    c.link_function_sections = true;
    c.link_data_sections = true;
    c.link_gc_sections = true;
    return c;
}

pub fn module(aid: *@This(), name: []const u8, root: ?[]const u8, target: Target, optimize: Mode, opts: Module.CreateOptions) *Module {
    var o = opts;
    o.target = o.target orelse target;
    o.optimize = o.optimize orelse optimize;
    o.root_source_file = o.root_source_file orelse if (root) |v| aid.b.path(v) else null;

    o.pic = true;
    o.strip = optimize == .ReleaseFast or optimize == .ReleaseSmall;
    o.error_tracing = optimize == .Debug or optimize == .ReleaseSafe;
    o.omit_frame_pointer = optimize == .ReleaseFast or optimize == .ReleaseSmall;
    o.unwind_tables = if (optimize == .Debug or optimize == .ReleaseSafe) .sync else .none;
    return aid.b.addModule(name, o);
}

pub fn library(aid: *@This(), name: []const u8, root: ?[]const u8, target: Target, optimize: Mode, opts: Opts) *Compile {
    return aid.compile(Build.addLibrary, Build.LibraryOptions, name, root, target, optimize, opts);
}

pub fn executable(aid: *@This(), name: []const u8, root: ?[]const u8, target: Target, optimize: Mode, opts: Opts) *Compile {
    return aid.compile(Build.addExecutable, Build.ExecutableOptions, name, root, target, optimize, opts);
}

pub fn @"test"(aid: *@This(), root: ?[]const u8, target: Target, optimize: Mode, opts: Opts) *Compile {
    return aid.compile(Build.addTest, Build.TestOptions, "test", root, target, optimize, opts);
}

pub fn runArtifact(aid: *@This(), comp: *Compile, args: ?[]const []const u8) *Build.Step.Run {
    const run = aid.b.addRunArtifact(comp);
    run.step.dependOn(&comp.step);
    if (args) |v| run.addArgs(v);
    return run;
}

pub fn addCSources(aid: *@This(), comp: *Compile, sources: []const CSources) void {
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    for (sources) |v| {
        for (v.header_paths orelse &.{}) |vv| {
            const path = fmt.bufPrint(&buf, "{s}" ++ std.fs.path.sep_str ++ "{s}", .{ v.root, vv }) catch unreachable;
            comp.addIncludePath(aid.b.path(path));
        }
        comp.addCSourceFiles(.{
            .root = if (v.root) |vv| aid.b.path(vv) else null,
            .files = v.c_sources orelse &.{},
            .flags = v.flags orelse &.{},
        });
    }
}

pub const CSources = struct {
    header_paths: ?[]const []const u8 = null,
    c_sources: ?[]const []const u8 = null,
    flags: ?[]const []const u8 = null,
    root: []const u8 = ".",
};
