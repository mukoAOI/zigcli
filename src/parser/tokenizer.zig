//! Argv tokenizer: pure lexical scan, no Metadata, no type conversion.
//!
//! ```
//! argv  →  []Token
//! ```
//!
//! After a `separator` (`--`), every remaining entry is an `argument`.
//! All slices are borrowed from the caller's argv.

const std = @import("std");
const Allocator = std.mem.Allocator;
const token_mod = @import("token.zig");

pub const Token = token_mod.Token;
pub const ShortOption = token_mod.ShortOption;
pub const LongOption = token_mod.LongOption;

/// Streaming tokenizer over an argv slice (typically without argv[0]).
pub const Tokenizer = struct {
    argv: []const []const u8,
    index: usize = 0,
    force_arguments: bool = false,

    pub fn init(argv: []const []const u8) Tokenizer {
        return .{ .argv = argv };
    }

    /// Returns the next token, or `null` at end of argv.
    pub fn next(self: *Tokenizer) ?Token {
        if (self.index >= self.argv.len) return null;
        const raw = self.argv[self.index];
        self.index += 1;

        if (self.force_arguments) {
            return .{ .argument = raw };
        }

        return classify(raw, &self.force_arguments);
    }

    /// Remaining unconsumed argv entries (borrowed).
    pub fn rest(self: *const Tokenizer) []const []const u8 {
        return self.argv[self.index..];
    }
};

/// Classifies a single argv entry. Sets `force_arguments` when `raw` is `--`.
pub fn classify(raw: []const u8, force_arguments: *bool) Token {
    if (raw.len == 0) return .{ .argument = raw };

    if (raw[0] != '-') {
        return .{ .argument = raw };
    }

    // Lone "-" — conventionally stdin / literal argument, not an option.
    if (raw.len == 1) {
        return .{ .argument = raw };
    }

    if (raw[1] == '-') {
        // "--" separator
        if (raw.len == 2) {
            force_arguments.* = true;
            return .separator;
        }
        // "--name" or "--name=value"
        const body = raw[2..];
        if (std.mem.indexOfScalar(u8, body, '=')) |eq| {
            return .{ .long_option = .{
                .name = body[0..eq],
                .attached = body[eq + 1 ..],
            } };
        }
        return .{ .long_option = .{ .name = body, .attached = null } };
    }

    // Short form: "-x", "-abc", "-o=file", "-abc=val"
    const body = raw[1..];
    if (std.mem.indexOfScalar(u8, body, '=')) |eq| {
        return .{ .short_option = .{
            .letters = body[0..eq],
            .attached = body[eq + 1 ..],
        } };
    }
    return .{ .short_option = .{ .letters = body, .attached = null } };
}

/// Tokenizes the full argv into an owned slice of tokens (slices still borrow argv).
pub fn tokenizeAll(allocator: Allocator, argv: []const []const u8) Allocator.Error![]Token {
    var list: std.ArrayList(Token) = .empty;
    errdefer list.deinit(allocator);

    var it = Tokenizer.init(argv);
    while (it.next()) |tok| {
        try list.append(allocator, tok);
    }
    return try list.toOwnedSlice(allocator);
}

test "tokenize plain arguments" {
    const argv = [_][]const u8{ "commit", "file.txt" };
    var it = Tokenizer.init(&argv);
    try expectArg(it.next().?, "commit");
    try expectArg(it.next().?, "file.txt");
    try std.testing.expect(it.next() == null);
}

test "tokenize short and long options" {
    const argv = [_][]const u8{ "-v", "-abc", "--verbose", "--output=out.txt", "-o=x" };
    const tokens = try tokenizeAll(std.testing.allocator, &argv);
    defer std.testing.allocator.free(tokens);

    try std.testing.expectEqual(@as(usize, 5), tokens.len);
    try expectShort(tokens[0], "v", null);
    try expectShort(tokens[1], "abc", null);
    try expectLong(tokens[2], "verbose", null);
    try expectLong(tokens[3], "output", "out.txt");
    try expectShort(tokens[4], "o", "x");
}

test "tokenize separator forces arguments" {
    const argv = [_][]const u8{ "-v", "--", "-f", "--looks-like-long" };
    const tokens = try tokenizeAll(std.testing.allocator, &argv);
    defer std.testing.allocator.free(tokens);

    try std.testing.expectEqual(@as(usize, 4), tokens.len);
    try expectShort(tokens[0], "v", null);
    try std.testing.expect(tokens[1] == .separator);
    try expectArg(tokens[2], "-f");
    try expectArg(tokens[3], "--looks-like-long");
}

test "tokenize lone dash is argument" {
    const argv = [_][]const u8{"-"};
    var it = Tokenizer.init(&argv);
    try expectArg(it.next().?, "-");
    try std.testing.expect(it.next() == null);
}

test "tokenize empty and equals edge cases" {
    const argv = [_][]const u8{ "", "--=value", "--name=", "-=" };
    const tokens = try tokenizeAll(std.testing.allocator, &argv);
    defer std.testing.allocator.free(tokens);

    try expectArg(tokens[0], "");
    try expectLong(tokens[1], "", "value");
    try expectLong(tokens[2], "name", "");
    try expectShort(tokens[3], "", "");
}

test "streaming rest()" {
    const argv = [_][]const u8{ "a", "b", "c" };
    var it = Tokenizer.init(&argv);
    _ = it.next();
    try std.testing.expectEqual(@as(usize, 2), it.rest().len);
    try std.testing.expectEqualStrings("b", it.rest()[0]);
}

fn expectArg(tok: Token, text: []const u8) !void {
    try std.testing.expect(tok == .argument);
    try std.testing.expectEqualStrings(text, tok.argument);
}

fn expectShort(tok: Token, letters: []const u8, attached: ?[]const u8) !void {
    try std.testing.expect(tok == .short_option);
    try std.testing.expectEqualStrings(letters, tok.short_option.letters);
    if (attached) |v| {
        try std.testing.expectEqualStrings(v, tok.short_option.attached.?);
    } else {
        try std.testing.expect(tok.short_option.attached == null);
    }
}

fn expectLong(tok: Token, name: []const u8, attached: ?[]const u8) !void {
    try std.testing.expect(tok == .long_option);
    try std.testing.expectEqualStrings(name, tok.long_option.name);
    if (attached) |v| {
        try std.testing.expectEqualStrings(v, tok.long_option.attached.?);
    } else {
        try std.testing.expect(tok.long_option.attached == null);
    }
}
