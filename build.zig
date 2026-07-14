const std = @import("std");

/// Static description of one shippable example program.
const Example = struct {
    name: []const u8,
    source: []const u8,
    run_step: []const u8,
    run_desc: []const u8,
    system_libs: []const []const u8 = &.{},
};

const examples = [_]Example{
    .{
        .name = "basic",
        .source = "examples/basic_app.zig",
        .run_step = "run-basic",
        .run_desc = "Run App(Config) example",
    },
    .{
        .name = "tree",
        .source = "examples/command_tree.zig",
        .run_step = "run-tree",
        .run_desc = "Run CommandBuilder example",
    },
    .{
        .name = "subs",
        .source = "examples/subcommands.zig",
        .run_step = "run-subs",
        .run_desc = "Run declarative subcommands example",
    },
    .{
        .name = "ping",
        .source = "examples/ping.zig",
        .run_step = "run-ping",
        .run_desc = "Run ICMP ping example (Windows)",
        .system_libs = &.{ "iphlpapi", "ws2_32" },
    },
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Library module exported to dependents via `dependency("zigcli").module("cli")`.
    const cli_mod = b.addModule("cli", .{
        .root_source_file = b.path("src/root.zig"),
    });

    const cli_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/root.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_cli_tests = b.addRunArtifact(cli_tests);
    const test_step = b.step("test", "Run CLI framework unit tests");
    test_step.dependOn(&run_cli_tests.step);

    // Non-debug example builds strip symbols to keep binaries small.
    const strip = optimize != .Debug;

    for (examples) |ex| {
        addExample(b, cli_mod, target, optimize, strip, ex);
    }

    const release = b.step("release", "Build stripped ReleaseFast examples into zig-out/bin");
    installReleaseExamples(b, release, target, .ReleaseFast, false);

    const release_small = b.step("release-small", "Build size-optimized examples into zig-out/bin");
    installReleaseExamples(b, release_small, target, .ReleaseSmall, true);
}

fn addExample(
    b: *std.Build,
    cli_mod: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    strip: bool,
    ex: Example,
) void {
    const mod = b.createModule(.{
        .root_source_file = b.path(ex.source),
        .target = target,
        .optimize = optimize,
        .strip = strip,
        .single_threaded = true,
        .imports = &.{
            .{ .name = "cli", .module = cli_mod },
        },
    });
    const exe = b.addExecutable(.{ .name = ex.name, .root_module = mod });
    for (ex.system_libs) |lib| {
        exe.root_module.linkSystemLibrary(lib, .{});
    }
    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    if (b.args) |args| run.addArgs(args);
    const step = b.step(ex.run_step, ex.run_desc);
    step.dependOn(&run.step);
}

fn installReleaseExamples(
    b: *std.Build,
    release_step: *std.Build.Step,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    minimal: bool,
) void {
    const cli_rel = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .strip = true,
    });

    for (examples) |ex| {
        const mod = b.createModule(.{
            .root_source_file = b.path(ex.source),
            .target = target,
            .optimize = optimize,
            .strip = true,
            .single_threaded = true,
            .unwind_tables = if (minimal) .none else null,
            .omit_frame_pointer = if (minimal) true else null,
            .imports = &.{
                .{ .name = "cli", .module = cli_rel },
            },
        });
        const exe = b.addExecutable(.{ .name = ex.name, .root_module = mod });
        for (ex.system_libs) |lib| {
            exe.root_module.linkSystemLibrary(lib, .{});
        }
        const install = b.addInstallArtifact(exe, .{});
        release_step.dependOn(&install.step);
    }
}
