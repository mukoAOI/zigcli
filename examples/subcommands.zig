//! Declarative subcommands via `App(Config).parseCommand`.
//!
//! Run:
//!   zig build run-subs -- add mypkg -f
//!   zig build run-subs -- remove mypkg
//!   zig build run-subs -- -v
//!   zig build run-subs -- --help

const std = @import("std");
const cli = @import("cli");
const common = @import("common.zig");
const wantsHelp = common.wantsHelp;
const toArgv = common.toArgv;

const AddConfig = struct {
    pkg: []const u8,
    force: bool = false,

    pub const cli = struct {
        pub const description = "Add a package";
        pub const pkg = .{ .positional = 0, .value_name = "NAME" };
        pub const force = .{ .short = 'f', .help = "overwrite if present" };
    };
};

const RemoveConfig = struct {
    pkg: []const u8,

    pub const cli = struct {
        pub const description = "Remove a package";
        pub const pkg = .{ .positional = 0, .value_name = "NAME" };
    };
};

const Config = struct {
    pub const cli_name = "pkg";
    pub const cli_description = "Declarative subcommand demo";

    verbose: bool = false,

    pub const cli = struct {
        pub const verbose = .{ .short = 'v', .help = "more output" };
    };

    // Each field maps to a subcommand named after the field.
    pub const cli_subcommands = .{ .add = AddConfig, .remove = RemoveConfig };
};

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const arena = init.arena.allocator();

    const raw = try init.minimal.args.toSlice(arena);
    const argv = try toArgv(arena, raw);
    const args = if (argv.len > 0) argv[1..] else argv;

    if (wantsHelp(args)) {
        var app = cli.App(Config).init(gpa);
        const text = try app.help();
        defer gpa.free(text);
        std.debug.print("{s}", .{text});
        return;
    }

    var app = cli.App(Config).init(gpa);
    const cmd = app.parseCommand(args) catch |err| switch (err) {
        error.ParseFailed => {
            const diag = cli.diagnose(cli.App(Config).meta_ptr, app.last_issue.?);
            const text = try diag.formatAlloc(gpa);
            defer gpa.free(text);
            std.debug.print("{s}\n", .{text});
            return error.ParseFailed;
        },
        else => |e| return e,
    };

    switch (cmd) {
        .base => |c| std.debug.print("no subcommand (verbose={})\n", .{c.verbose}),
        .add => |c| std.debug.print("add pkg={s} force={}\n", .{ c.pkg, c.force }),
        .remove => |c| std.debug.print("remove pkg={s}\n", .{c.pkg}),
    }
}
