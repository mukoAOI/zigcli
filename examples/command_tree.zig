//! Command-tree example using CommandBuilder (subcommands + options).
//!
//! Run:
//!   zig build run-tree -- -v run -n main.zig
//!   zig build run-tree -- --help

const std = @import("std");
const cli = @import("cli");
const common = @import("common.zig");
const wantsHelp = common.wantsHelp;
const toArgv = common.toArgv;

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const arena = init.arena.allocator();

    var root = cli.CommandBuilder.init(gpa, "tree");
    defer root.deinit();
    _ = root.help("command-tree demo");
    _ = (try root.flag("verbose")).short('v').help("more output");
    _ = try root.example("tree -v run -n main.zig");

    const run = try root.subcommand("run");
    _ = run.help("run a script");
    _ = (try run.flag("dry-run")).short('n').help("do not write");
    _ = (try run.arg("SCRIPT")).help("script path");

    const meta = root.seal();

    const raw = try init.minimal.args.toSlice(arena);
    const argv = try toArgv(arena, raw);
    const args = if (argv.len > 0) argv[1..] else argv;

    if (wantsHelp(args)) {
        const text = try cli.renderHelp(gpa, meta);
        defer gpa.free(text);
        std.debug.print("{s}", .{text});
        return;
    }

    var out = try cli.parseArgv(gpa, meta, args);
    defer out.deinit();

    switch (out) {
        .issue => |issue| {
            const diag = cli.diagnose(meta, issue);
            const text = try diag.formatAlloc(gpa);
            defer gpa.free(text);
            std.debug.print("{s}\n", .{text});
            return error.ParseFailed;
        },
        .ok => |r| {
            std.debug.print("command={s}\n", .{r.command.name});
            std.debug.print("verbose={}\n", .{r.hasOption("verbose")});
            std.debug.print("dry-run={}\n", .{r.hasOption("dry-run")});
            for (r.positionals, 0..) |p, i| {
                std.debug.print("positional[{d}]={s}\n", .{ i, p });
            }
        },
    }
}
