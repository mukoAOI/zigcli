//! Non-Windows stub for the ping example.

const std = @import("std");

pub const EchoParams = struct {
    host: []const u8,
    count: u32,
    timeout_ms: u32,
    interval_ms: u32,
    size: u32,
    verbose: bool,
};

pub fn run(params: EchoParams) !void {
    _ = params;
    std.debug.print("examples/ping is Windows-only (uses IcmpSendEcho).\n", .{});
    return error.UnsupportedPlatform;
}
