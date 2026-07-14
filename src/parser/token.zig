//! Lexical token kinds produced from argv.
//!
//! Tokens borrow slices from argv entries — never owned copies.
//! Semantics (is this a subcommand? does `-o` need a value?) belong to Parser.

const std = @import("std");

/// A short-option cluster as it appeared after a single `-`.
///
/// Example: `-abc` → `letters = "abc"`.
/// Example: `-o=file` → `letters = "o"`, `attached = "file"`.
pub const ShortOption = struct {
    /// Codepoints / bytes after `-` and before optional `=`.
    letters: []const u8,
    /// Value after `=` on the same argv entry, if any.
    attached: ?[]const u8 = null,
};

/// A long option as it appeared after `--`.
///
/// Example: `--verbose` → `name = "verbose"`, `attached = null`.
/// Example: `--output=file` → `name = "output"`, `attached = "file"`.
pub const LongOption = struct {
    name: []const u8,
    /// Value after `=` on the same argv entry, if any.
    attached: ?[]const u8 = null,
};

/// One lexical unit from argv.
pub const Token = union(enum) {
    /// Bare word: positional candidate, subcommand name, or option value (Parser decides).
    argument: []const u8,
    /// `-…` form (not `--`).
    short_option: ShortOption,
    /// `--name` / `--name=value` (not bare `--`).
    long_option: LongOption,
    /// Bare `--` — end of options; subsequent argv are pure arguments.
    separator,

    /// Tag name for diagnostics / debugging.
    pub fn tagName(self: Token) []const u8 {
        return switch (self) {
            .argument => "argument",
            .short_option => "short_option",
            .long_option => "long_option",
            .separator => "separator",
        };
    }
};

test "Token.tagName" {
    try std.testing.expectEqualStrings("separator", (Token{ .separator = {} }).tagName());
    try std.testing.expectEqualStrings("argument", (Token{ .argument = "x" }).tagName());
}
