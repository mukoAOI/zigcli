//! Shared classification enums for CLI metadata.
//!
//! These kinds describe *what* a value is and *how many* values are expected.
//! They do not perform parsing or validation — that belongs to later modules.

/// Semantic category of a CLI value.
///
/// Used by Help / Completion / Type Parser as a stable tag.
/// Actual Zig types are resolved later via `typing` + comptime reflection.
pub const ValueKind = enum {
    /// Presence-only or explicit true/false (`--verbose`, `--flag=true`).
    bool,
    /// Signed or unsigned integer text.
    int,
    /// Floating-point text.
    float,
    /// Free-form UTF-8 slice (zero-copy from argv when possible).
    string,
    /// Filesystem path (still `[]const u8`; validators may check existence).
    path,
    /// Named enum member text.
    @"enum",
    /// User-supplied type registered with the typing layer.
    custom,
};

/// How many values an option or positional argument accepts.
pub const Cardinality = enum {
    /// Flag: no value token is consumed.
    zero,
    /// Zero or one value.
    optional,
    /// Exactly one value.
    one,
    /// Zero or more values.
    many,
    /// One or more values.
    at_least_one,

    /// Returns true if at least one value token is mandatory.
    pub fn requiresValue(self: Cardinality) bool {
        return switch (self) {
            .zero, .optional, .many => false,
            .one, .at_least_one => true,
        };
    }

    /// Returns true if more than one value may be attached.
    pub fn allowsMultiple(self: Cardinality) bool {
        return switch (self) {
            .many, .at_least_one => true,
            .zero, .optional, .one => false,
        };
    }
};

/// Surface form of an option in the command line.
pub const OptionForm = enum {
    /// Boolean / presence flag (`-v`, `--verbose`).
    flag,
    /// Key/value option (`-o file`, `--output=file`).
    option,
};

test "Cardinality.requiresValue" {
    const std = @import("std");
    try std.testing.expect(!Cardinality.zero.requiresValue());
    try std.testing.expect(!Cardinality.optional.requiresValue());
    try std.testing.expect(Cardinality.one.requiresValue());
    try std.testing.expect(Cardinality.at_least_one.requiresValue());
}

test "Cardinality.allowsMultiple" {
    const std = @import("std");
    try std.testing.expect(Cardinality.many.allowsMultiple());
    try std.testing.expect(Cardinality.at_least_one.allowsMultiple());
    try std.testing.expect(!Cardinality.one.allowsMultiple());
}
