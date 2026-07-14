//! Fish completion script generator.

const std = @import("std");
const Allocator = std.mem.Allocator;
const CommandMeta = @import("../core/command.zig").CommandMeta;
const common = @import("common.zig");

pub fn generate(allocator: Allocator, root: *const CommandMeta) Allocator.Error![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    const Ctx = struct {
        allocator: Allocator,
        out: *std.ArrayList(u8),
        bin: []const u8,
        fn visit(self: @This(), cmd: *const CommandMeta, path: []const []const u8) !void {
            // Condition: previous tokens match path (excluding binary name at end).
            // For root: __fish_use_subcommand or no subcommand yet.
            const is_root = path.len == 1;

            for (cmd.subcommands) |child| {
                try self.out.appendSlice(self.allocator, "complete -c ");
                try self.out.appendSlice(self.allocator, self.bin);
                try self.out.appendSlice(self.allocator, " -n '");
                try appendFishCondition(self.allocator, self.out, path, is_root);
                try self.out.appendSlice(self.allocator, "' -a '");
                try self.out.appendSlice(self.allocator, child.name);
                try self.out.appendSlice(self.allocator, "'");
                if (child.description.len != 0) {
                    try self.out.appendSlice(self.allocator, " -d '");
                    try appendEscaped(self.allocator, self.out, child.description);
                    try self.out.append(self.allocator, '\'');
                }
                try self.out.append(self.allocator, '\n');
            }

            for (cmd.options) |opt| {
                try self.out.appendSlice(self.allocator, "complete -c ");
                try self.out.appendSlice(self.allocator, self.bin);
                try self.out.appendSlice(self.allocator, " -n '");
                try appendFishCondition(self.allocator, self.out, path, is_root);
                try self.out.append(self.allocator, '\'');
                if (opt.short) |s| {
                    try self.out.appendSlice(self.allocator, " -s ");
                    try self.out.append(self.allocator, s);
                }
                if (opt.long) |long| {
                    try self.out.appendSlice(self.allocator, " -l ");
                    try self.out.appendSlice(self.allocator, long);
                }
                if (opt.description.len != 0) {
                    try self.out.appendSlice(self.allocator, " -d '");
                    try appendEscaped(self.allocator, self.out, opt.description);
                    try self.out.append(self.allocator, '\'');
                }
                try self.out.append(self.allocator, '\n');
            }
        }
    };

    var path0 = [_][]const u8{root.name};
    try common.walk(root, &path0, Ctx{ .allocator = allocator, .out = &out, .bin = root.name }, Ctx.visit);

    return try out.toOwnedSlice(allocator);
}

fn appendFishCondition(
    allocator: Allocator,
    out: *std.ArrayList(u8),
    path: []const []const u8,
    is_root: bool,
) !void {
    if (is_root) {
        try out.appendSlice(allocator, "__fish_use_subcommand");
        return;
    }
    // path = [bin, sub, ...] — require seen subcommands
    try out.appendSlice(allocator, "__fish_seen_subcommand_from");
    for (path[1..]) |p| {
        try out.append(allocator, ' ');
        try out.appendSlice(allocator, p);
    }
}

fn appendEscaped(allocator: Allocator, out: *std.ArrayList(u8), text: []const u8) !void {
    for (text) |c| {
        if (c == '\'') {
            try out.appendSlice(allocator, "'\\''");
        } else {
            try out.append(allocator, c);
        }
    }
}
