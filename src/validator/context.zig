//! Validation inputs and structured failure payloads.
//!
//! Independent of Parser — callers pass presence + raw text values.

const std = @import("std");

/// What a validator inspects.
pub const ValidationContext = struct {
    /// Option / argument display name (borrowed).
    name: []const u8,
    /// Whether the option/argument was present on the command line.
    present: bool,
    /// Raw text values (borrowed, may be empty for presence flags).
    values: []const []const u8 = &.{},

    /// First value text, if any.
    pub fn first(self: ValidationContext) ?[]const u8 {
        if (self.values.len == 0) return null;
        return self.values[0];
    }
};

/// Domain validation failure (library does not print or exit).
pub const ValidationIssue = struct {
    pub const Kind = enum {
        required,
        out_of_range,
        not_in_choices,
        pattern_mismatch,
        file_not_found,
        directory_not_found,
        custom,
    };

    kind: Kind,
    name: []const u8,
    /// Optional borrowed detail (e.g. the rejected value).
    detail: ?[]const u8 = null,
};

test "ValidationContext.first" {
    const ctx = ValidationContext{
        .name = "x",
        .present = true,
        .values = &[_][]const u8{"a"},
    };
    try std.testing.expectEqualStrings("a", ctx.first().?);
}
