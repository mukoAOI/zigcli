//! Shared helpers for the example programs (not part of the `cli` library).

const std = @import("std");

/// True if `--help` / `-h` appears anywhere in `args`.
pub fn wantsHelp(args: []const []const u8) bool {
    for (args) |a| {
        if (std.mem.eql(u8, a, "--help") or std.mem.eql(u8, a, "-h")) return true;
    }
    return false;
}

/// Copies Zig 0.16 sentinel-terminated argv into plain `[]const u8` slices.
pub fn toArgv(arena: std.mem.Allocator, raw: []const [:0]const u8) ![]const []const u8 {
    const out = try arena.alloc([]const u8, raw.len);
    for (raw, 0..) |a, i| out[i] = a;
    return out;
}
