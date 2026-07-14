//! ICMP ping example using this CLI framework.
//!
//! Run (Windows; needs network):
//!   zig build run-ping -- 8.8.8.8
//!   zig build run-ping -- -c 4 -W 1000 example.com
//!   zig build run-ping -- --help
//!
//! On non-Windows targets the example compiles but prints an unsupported notice.

const std = @import("std");
const builtin = @import("builtin");
const cli = @import("cli");
const common = @import("common.zig");
const wantsHelp = common.wantsHelp;
const toArgv = common.toArgv;

const platform = if (builtin.os.tag == .windows)
    @import("ping_windows.zig")
else
    @import("ping_stub.zig");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const arena = init.arena.allocator();

    var root = cli.CommandBuilder.init(gpa, "ping");
    defer root.deinit();
    _ = root.help("Send ICMP echo requests (Windows)");
    _ = try root.example("ping 8.8.8.8");
    _ = try root.example("ping -c 4 -W 1000 example.com");
    _ = (try root.opt("count", .int)).short('c').defaultText("4").help("stop after N replies").valueName("N");
    _ = (try root.opt("timeout", .int)).short('W').defaultText("1000").help("per-probe timeout in ms").valueName("MS");
    _ = (try root.opt("interval", .int)).short('i').defaultText("1000").help("wait between probes in ms").valueName("MS");
    _ = (try root.opt("size", .int)).short('s').defaultText("32").help("payload bytes").valueName("BYTES");
    _ = (try root.flag("verbose")).short('v').help("print extra diagnostics");
    _ = (try root.arg("HOST")).help("IPv4 address or host name");

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

    const parsed = switch (out) {
        .issue => |issue| {
            const diag = cli.diagnose(meta, issue);
            const text = try diag.formatAlloc(gpa);
            defer gpa.free(text);
            std.debug.print("{s}\n", .{text});
            return error.ParseFailed;
        },
        .ok => |r| r,
    };

    if (parsed.positionals.len != 1) {
        std.debug.print("error: HOST is required\n\n", .{});
        const text = try cli.renderHelp(gpa, meta);
        defer gpa.free(text);
        std.debug.print("{s}", .{text});
        return error.ParseFailed;
    }

    const host = parsed.positionals[0];
    const count = try optU32(parsed, "count", 4);
    const timeout_ms = try optU32(parsed, "timeout", 1000);
    const interval_ms = try optU32(parsed, "interval", 1000);
    const size = try optU32(parsed, "size", 32);
    const verbose = parsed.hasOption("verbose");

    if (count == 0 or count > 1000) return error.InvalidCount;
    if (size == 0 or size > 65500) return error.InvalidSize;

    try platform.run(.{
        .host = host,
        .count = count,
        .timeout_ms = timeout_ms,
        .interval_ms = interval_ms,
        .size = size,
        .verbose = verbose,
    });
}

fn optU32(parsed: cli.ParseResult, long: []const u8, default_value: u32) !u32 {
    const occ = parsed.findOption(long) orelse return default_value;
    if (occ.values.len == 0) return default_value;
    return try cli.parseValue(u32, occ.values[0]);
}
