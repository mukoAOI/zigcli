//! Shared helpers for shell completion script generation.

const std = @import("std");
const Allocator = std.mem.Allocator;
const CommandMeta = @import("../core/command.zig").CommandMeta;

/// Appends space-separated completion words for one command (options + subcommands).
pub fn appendWords(allocator: Allocator, list: *std.ArrayList(u8), cmd: *const CommandMeta) !void {
    var first = true;
    for (cmd.options) |opt| {
        if (opt.long) |long| {
            if (!first) try list.append(allocator, ' ');
            try list.appendSlice(allocator, "--");
            try list.appendSlice(allocator, long);
            first = false;
        }
        if (opt.short) |s| {
            if (!first) try list.append(allocator, ' ');
            try list.append(allocator, '-');
            try list.append(allocator, s);
            first = false;
        }
    }
    for (cmd.subcommands) |child| {
        if (!first) try list.append(allocator, ' ');
        try list.appendSlice(allocator, child.name);
        first = false;
    }
}

/// Appends `name` with every non-alphanumeric byte replaced by `_`.
pub fn appendIdent(allocator: Allocator, out: *std.ArrayList(u8), name: []const u8) !void {
    for (name) |c| {
        const outc: u8 = if ((c >= 'a' and c <= 'z') or
            (c >= 'A' and c <= 'Z') or
            (c >= '0' and c <= '9'))
            c
        else
            '_';
        try out.append(allocator, outc);
    }
}

/// Sanitizes a command path into a shell-safe id (`demo_run`).
pub fn appendSanitizedPath(
    allocator: Allocator,
    list: *std.ArrayList(u8),
    path: []const []const u8,
) !void {
    for (path, 0..) |part, i| {
        if (i != 0) try list.append(allocator, '_');
        try appendIdent(allocator, list, part);
    }
}

/// Depth-first visit of the command tree.
pub fn walk(
    cmd: *const CommandMeta,
    path: []const []const u8,
    ctx: anytype,
    comptime visitor: fn (@TypeOf(ctx), *const CommandMeta, []const []const u8) Allocator.Error!void,
) Allocator.Error!void {
    try visitor(ctx, cmd, path);
    for (cmd.subcommands) |child| {
        var child_path_buf: [32][]const u8 = undefined;
        const n = @min(path.len, child_path_buf.len - 1);
        @memcpy(child_path_buf[0..n], path[0..n]);
        child_path_buf[n] = child.name;
        try walk(child, child_path_buf[0 .. n + 1], ctx, visitor);
    }
}

test "appendWords lists flags and subs" {
    var opts = [_]@import("../core/option.zig").OptionMeta{
        .{ .long = "verbose", .short = 'v' },
    };
    var child = CommandMeta{ .name = "run" };
    var children = [_]*CommandMeta{&child};
    var cmd = CommandMeta{
        .name = "demo",
        .options = &opts,
        .subcommands = &children,
    };

    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(std.testing.allocator);
    try appendWords(std.testing.allocator, &list, &cmd);
    try std.testing.expect(std.mem.indexOf(u8, list.items, "--verbose") != null);
    try std.testing.expect(std.mem.indexOf(u8, list.items, "-v") != null);
    try std.testing.expect(std.mem.indexOf(u8, list.items, "run") != null);
}
