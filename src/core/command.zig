//! Command-tree metadata: one node plus owned child lists.
//!
//! A command owns its options, positionals, and subcommand pointers.
//! Child builders are heap-allocated so parent/child links stay stable.
//! All name/description slices remain borrowed (zero-copy).

const std = @import("std");
const Allocator = std.mem.Allocator;
const kinds = @import("kinds.zig");
const option = @import("option.zig");
const argument = @import("argument.zig");

pub const OptionMeta = option.OptionMeta;
pub const OptionBuilder = option.OptionBuilder;
pub const ArgumentMeta = argument.ArgumentMeta;
pub const ArgumentBuilder = argument.ArgumentBuilder;

/// One node in the command tree.
pub const CommandMeta = struct {
    name: []const u8,
    description: []const u8 = "",
    aliases: []const []const u8 = &.{},
    examples: []const []const u8 = &.{},
    parent: ?*CommandMeta = null,
    options: []const OptionMeta = &.{},
    arguments: []const ArgumentMeta = &.{},
    /// Child nodes (borrowed). Builder path heap-allocates them; the comptime
    /// derive path points at `pub const` metadata.
    subcommands: []const *const CommandMeta = &.{},

    /// Depth from the root (root = 0).
    pub fn depth(self: *const CommandMeta) usize {
        var d: usize = 0;
        var cur: ?*const CommandMeta = self.parent;
        while (cur) |p| : (cur = p.parent) d += 1;
        return d;
    }

    /// Whether `name` matches this command's primary name or an alias.
    pub fn matchesName(self: *const CommandMeta, name: []const u8) bool {
        if (std.mem.eql(u8, self.name, name)) return true;
        for (self.aliases) |alias| {
            if (std.mem.eql(u8, alias, name)) return true;
        }
        return false;
    }

    /// Finds a direct child subcommand by name or alias.
    pub fn findSubcommand(self: *const CommandMeta, name: []const u8) ?*const CommandMeta {
        for (self.subcommands) |child| {
            if (child.matchesName(name)) return child;
        }
        return null;
    }

    /// Finds an option by long name among this command's options.
    pub fn findOptionLong(self: *const CommandMeta, long: []const u8) ?*const OptionMeta {
        for (self.options) |*opt| {
            if (opt.matchesLong(long)) return opt;
        }
        return null;
    }

    /// Finds an option by short codepoint among this command's options.
    pub fn findOptionShort(self: *const CommandMeta, code: u8) ?*const OptionMeta {
        for (self.options) |*opt| {
            if (opt.matchesShort(code)) return opt;
        }
        return null;
    }
};

/// Mutable builder that grows option / argument / subcommand lists.
///
/// Call `deinit` to free owned memory. Borrowed string slices are not freed.
pub const CommandBuilder = struct {
    allocator: Allocator,
    meta: CommandMeta,
    options_list: std.ArrayList(OptionMeta) = .empty,
    arguments_list: std.ArrayList(ArgumentMeta) = .empty,
    subcommands_list: std.ArrayList(*const CommandMeta) = .empty,
    aliases_list: std.ArrayList([]const u8) = .empty,
    examples_list: std.ArrayList([]const u8) = .empty,
    child_builders: std.ArrayList(*CommandBuilder) = .empty,
    sealed: bool = false,

    pub fn init(allocator: Allocator, name: []const u8) CommandBuilder {
        return .{
            .allocator = allocator,
            .meta = .{ .name = name },
        };
    }

    /// Frees this builder and all recursively owned child builders.
    pub fn deinit(self: *CommandBuilder) void {
        for (self.child_builders.items) |child| {
            child.deinit();
            self.allocator.destroy(child);
        }
        self.options_list.deinit(self.allocator);
        self.arguments_list.deinit(self.allocator);
        self.subcommands_list.deinit(self.allocator);
        self.aliases_list.deinit(self.allocator);
        self.examples_list.deinit(self.allocator);
        self.child_builders.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn help(self: *CommandBuilder, text: []const u8) *CommandBuilder {
        self.meta.description = text;
        return self;
    }

    pub fn alias(self: *CommandBuilder, name: []const u8) Allocator.Error!*CommandBuilder {
        try self.aliases_list.append(self.allocator, name);
        self.meta.aliases = self.aliases_list.items;
        return self;
    }

    pub fn example(self: *CommandBuilder, text: []const u8) Allocator.Error!*CommandBuilder {
        try self.examples_list.append(self.allocator, text);
        self.meta.examples = self.examples_list.items;
        return self;
    }

    /// Registers a presence flag (`--long`).
    pub fn flag(self: *CommandBuilder, long: []const u8) Allocator.Error!OptionBuilder {
        try self.options_list.append(self.allocator, .{
            .long = long,
            .form = .flag,
            .value_kind = .bool,
            .cardinality = .zero,
        });
        self.meta.options = self.options_list.items;
        return .{ .meta = &self.options_list.items[self.options_list.items.len - 1] };
    }

    /// Registers a valued option (`--long <value>`).
    pub fn opt(
        self: *CommandBuilder,
        long: []const u8,
        value_kind: kinds.ValueKind,
    ) Allocator.Error!OptionBuilder {
        try self.options_list.append(self.allocator, .{
            .long = long,
            .form = .option,
            .value_kind = value_kind,
            .cardinality = .one,
        });
        self.meta.options = self.options_list.items;
        return .{ .meta = &self.options_list.items[self.options_list.items.len - 1] };
    }

    /// Registers a positional argument.
    pub fn arg(self: *CommandBuilder, name: []const u8) Allocator.Error!ArgumentBuilder {
        try self.arguments_list.append(self.allocator, .{ .name = name });
        self.meta.arguments = self.arguments_list.items;
        return .{ .meta = &self.arguments_list.items[self.arguments_list.items.len - 1] };
    }

    /// Allocates a child command, links it into the tree, and returns its builder.
    pub fn subcommand(self: *CommandBuilder, name: []const u8) Allocator.Error!*CommandBuilder {
        const child = try self.allocator.create(CommandBuilder);
        errdefer self.allocator.destroy(child);
        child.* = CommandBuilder.init(self.allocator, name);
        child.meta.parent = &self.meta;
        try self.subcommands_list.append(self.allocator, &child.meta);
        errdefer _ = self.subcommands_list.pop();
        try self.child_builders.append(self.allocator, child);
        self.meta.subcommands = self.subcommands_list.items;
        return child;
    }

    /// Syncs slice fields (recursively) and returns this node's metadata.
    pub fn seal(self: *CommandBuilder) *CommandMeta {
        self.meta.options = self.options_list.items;
        self.meta.arguments = self.arguments_list.items;
        self.meta.subcommands = self.subcommands_list.items;
        self.meta.aliases = self.aliases_list.items;
        self.meta.examples = self.examples_list.items;
        self.sealed = true;
        for (self.child_builders.items) |child| {
            _ = child.seal();
        }
        return &self.meta;
    }
};

test "command tree lookup" {
    var root = CommandBuilder.init(std.testing.allocator, "git");
    defer root.deinit();
    _ = root.help("git cli");

    const commit = try root.subcommand("commit");
    _ = commit.help("record changes");
    _ = (try commit.flag("all")).short('a').help("stage all");

    const meta = root.seal();
    try std.testing.expect(meta.findSubcommand("commit") != null);
    try std.testing.expect(meta.findSubcommand("push") == null);

    const commit_meta = meta.findSubcommand("commit").?;
    try std.testing.expectEqual(@as(usize, 1), commit_meta.depth());
    try std.testing.expect(commit_meta.findOptionLong("all") != null);
    try std.testing.expect(commit_meta.findOptionShort('a') != null);
}

test "aliases and positionals" {
    var root = CommandBuilder.init(std.testing.allocator, "tool");
    defer root.deinit();
    _ = try root.alias("t");
    _ = (try root.arg("FILE")).valueKind(.path).help("input");
    _ = (try root.opt("output", .path)).short('o').required();

    const meta = root.seal();
    try std.testing.expect(meta.matchesName("t"));
    try std.testing.expectEqual(@as(usize, 1), meta.arguments.len);
    try std.testing.expect(meta.findOptionLong("output").?.required);
}
