//! Structured parse outcomes: success payload and domain issues.
//!
//! Domain failures are **not** Zig `error` codes — they stay data so
//! Milestone 4 can map them to full `Diagnostic`s. Allocation failures
//! still surface as `Allocator.Error`.

const std = @import("std");
const Allocator = std.mem.Allocator;
const CommandMeta = @import("../core/command.zig").CommandMeta;
const OptionMeta = @import("../core/option.zig").OptionMeta;

/// One recorded option/flag occurrence (raw text only).
pub const OptionOccurrence = struct {
    meta: *const OptionMeta,
    /// Borrowed argv slices; empty for a pure presence flag.
    values: []const []const u8,
};

/// Domain-level parse problem (library does not print or exit).
pub const ParseIssue = struct {
    pub const Kind = enum {
        unknown_long_option,
        unknown_short_option,
        missing_option_value,
        unexpected_attached_value,
        empty_short_cluster,
        unknown_subcommand,
    };

    kind: Kind,
    /// Long name, subcommand name, or other borrowed label, when applicable.
    name: ?[]const u8 = null,
    /// Short option codepoint, when applicable.
    short: ?u8 = null,
};

/// Successful structural match against a command tree.
pub const ParseResult = struct {
    allocator: Allocator,
    /// Leaf command selected after subcommand walks.
    command: *const CommandMeta,
    /// Root → leaf path (includes `command`).
    path: []*const CommandMeta,
    options: []OptionOccurrence,
    /// Raw positional texts in order (not yet typed / validated).
    positionals: []const []const u8,

    pub fn deinit(self: *ParseResult) void {
        for (self.options) |occ| {
            self.allocator.free(occ.values);
        }
        self.allocator.free(self.options);
        self.allocator.free(self.path);
        self.allocator.free(self.positionals);
        self.* = undefined;
    }

    /// First occurrence of an option by long name, if any.
    pub fn findOption(self: *const ParseResult, long: []const u8) ?OptionOccurrence {
        for (self.options) |occ| {
            if (occ.meta.matchesLong(long)) return occ;
        }
        return null;
    }

    /// Whether a flag/option with this long name was present.
    pub fn hasOption(self: *const ParseResult, long: []const u8) bool {
        return self.findOption(long) != null;
    }
};

/// Result of structural parsing.
pub const ParseOutput = union(enum) {
    ok: ParseResult,
    issue: ParseIssue,

    pub fn deinit(self: *ParseOutput) void {
        switch (self.*) {
            .ok => |*r| r.deinit(),
            .issue => {},
        }
        self.* = undefined;
    }
};

test "ParseIssue kind names exist" {
    try std.testing.expect(@intFromEnum(ParseIssue.Kind.unknown_long_option) >= 0);
}
