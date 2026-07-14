//! Declarative App(Config) example.
//!
//! Run:
//!   zig build run-basic -- -v -t 8 --output out.txt
//!   zig build run-basic -- --help

const std = @import("std");
const cli = @import("cli");
const common = @import("common.zig");
const wantsHelp = common.wantsHelp;
const toArgv = common.toArgv;

const Config = struct {
    pub const cli_name = "basic";
    pub const cli_description = "Declarative App(Config) demo";

    verbose: bool = false,
    threads: u32 = 4,
    output: ?[]const u8 = null,

    pub const cli = struct {
        pub const description = "Declarative App(Config) demo";
        pub const examples = [_][]const u8{
            "basic -v -t 8 -o out.txt",
            "basic --help",
        };
        pub const verbose = .{ .short = 'v', .help = "more output" };
        pub const threads = .{ .short = 't', .help = "worker count" };
        pub const output = .{ .short = 'o', .help = "output path", .value_name = "FILE" };
    };
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
    const cfg = app.parse(args) catch |err| switch (err) {
        error.ParseFailed => {
            const diag = cli.diagnose(cli.App(Config).meta_ptr, app.last_issue.?);
            const text = try diag.formatAlloc(gpa);
            defer gpa.free(text);
            std.debug.print("{s}\n", .{text});
            return error.ParseFailed;
        },
        else => |e| return e,
    };

    std.debug.print("verbose={}\n", .{cfg.verbose});
    std.debug.print("threads={d}\n", .{cfg.threads});
    if (cfg.output) |o| {
        std.debug.print("output={s}\n", .{o});
    } else {
        std.debug.print("output=(none)\n", .{});
    }
}
