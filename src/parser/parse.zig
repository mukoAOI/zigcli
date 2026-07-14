//! Structural parser: consume Tokens + CommandMeta → ParseOutput.
//!
//! Does: subcommand walk, option binding, short-cluster expansion, positionals.
//! Does not: type conversion, validators, help, printing, exit.

const std = @import("std");
const Allocator = std.mem.Allocator;
const CommandMeta = @import("../core/command.zig").CommandMeta;
const OptionMeta = @import("../core/option.zig").OptionMeta;
const token_mod = @import("token.zig");
const result_mod = @import("result.zig");
const tokenizer_mod = @import("tokenizer.zig");

pub const Token = token_mod.Token;
pub const ParseResult = result_mod.ParseResult;
pub const ParseIssue = result_mod.ParseIssue;
pub const ParseOutput = result_mod.ParseOutput;
pub const OptionOccurrence = result_mod.OptionOccurrence;

const State = struct {
    allocator: Allocator,
    tokens: []const Token,
    index: usize = 0,
    command: *const CommandMeta,
    path: std.ArrayList(*const CommandMeta) = .empty,
    options: std.ArrayList(OptionOccurrence) = .empty,
    positionals: std.ArrayList([]const u8) = .empty,
    locked_positionals: bool = false,

    fn discard(self: *State) void {
        for (self.options.items) |occ| self.allocator.free(occ.values);
        self.options.deinit(self.allocator);
        self.path.deinit(self.allocator);
        self.positionals.deinit(self.allocator);
        self.options = .empty;
        self.path = .empty;
        self.positionals = .empty;
    }

    fn takeOk(self: *State) Allocator.Error!ParseOutput {
        const path = try self.path.toOwnedSlice(self.allocator);
        errdefer self.allocator.free(path);
        const options = try self.options.toOwnedSlice(self.allocator);
        errdefer {
            for (options) |occ| self.allocator.free(occ.values);
            self.allocator.free(options);
        }
        const positionals = try self.positionals.toOwnedSlice(self.allocator);
        self.path = .empty;
        self.options = .empty;
        self.positionals = .empty;
        return .{ .ok = .{
            .allocator = self.allocator,
            .command = self.command,
            .path = path,
            .options = options,
            .positionals = positionals,
        } };
    }

    fn peek(self: *const State) ?Token {
        if (self.index >= self.tokens.len) return null;
        return self.tokens[self.index];
    }

    fn advance(self: *State) ?Token {
        const t = self.peek() orelse return null;
        self.index += 1;
        return t;
    }

    fn record(self: *State, meta: *const OptionMeta, values: []const []const u8) !void {
        const owned = try self.allocator.dupe([]const u8, values);
        errdefer self.allocator.free(owned);
        try self.options.append(self.allocator, .{ .meta = meta, .values = owned });
    }

    fn takesValue(meta: *const OptionMeta) bool {
        return meta.cardinality != .zero;
    }

    fn requiresValue(meta: *const OptionMeta) bool {
        return meta.cardinality.requiresValue();
    }
};

/// Parse a pre-tokenized argv against the command tree rooted at `root`.
pub fn parseTokens(
    allocator: Allocator,
    root: *const CommandMeta,
    tokens: []const Token,
) Allocator.Error!ParseOutput {
    var st: State = .{
        .allocator = allocator,
        .tokens = tokens,
        .command = root,
    };
    defer st.discard();

    try st.path.append(allocator, root);

    while (st.peek()) |_| {
        const tok = st.advance().?;
        switch (tok) {
            .separator => {
                // Tokenizer already turns following argv into `.argument`.
                while (st.advance()) |rest| {
                    switch (rest) {
                        .argument => |a| {
                            st.locked_positionals = true;
                            try st.positionals.append(allocator, a);
                        },
                        else => {
                            return .{ .issue = .{
                                .kind = .unexpected_attached_value,
                                .name = "--",
                            } };
                        },
                    }
                }
            },
            .long_option => |long| {
                if (try bindLong(&st, long)) |iss| return .{ .issue = iss };
            },
            .short_option => |short| {
                if (try bindShort(&st, short)) |iss| return .{ .issue = iss };
            },
            .argument => |word| {
                if (!st.locked_positionals) {
                    if (st.command.findSubcommand(word)) |child| {
                        st.command = child;
                        try st.path.append(allocator, child);
                        continue;
                    }
                    // A command that groups subcommands but declares no
                    // positionals of its own must reject unknown words instead
                    // of silently swallowing them as positionals.
                    if (st.command.subcommands.len > 0 and st.command.arguments.len == 0) {
                        return .{ .issue = .{ .kind = .unknown_subcommand, .name = word } };
                    }
                }
                st.locked_positionals = true;
                try st.positionals.append(allocator, word);
            },
        }
    }

    return try st.takeOk();
}

/// Tokenize then parse. Frees the temporary token buffer before returning.
pub fn parseArgv(
    allocator: Allocator,
    root: *const CommandMeta,
    argv: []const []const u8,
) Allocator.Error!ParseOutput {
    const tokens = try tokenizer_mod.tokenizeAll(allocator, argv);
    defer allocator.free(tokens);
    return parseTokens(allocator, root, tokens);
}

fn bindLong(st: *State, long: token_mod.LongOption) !?ParseIssue {
    const meta = st.command.findOptionLong(long.name) orelse {
        return ParseIssue{ .kind = .unknown_long_option, .name = long.name };
    };

    if (!State.takesValue(meta)) {
        if (long.attached) |v| {
            try st.record(meta, &.{v});
        } else {
            try st.record(meta, &.{});
        }
        return null;
    }

    if (long.attached) |v| {
        try st.record(meta, &.{v});
        return null;
    }

    if (st.peek()) |n| {
        if (n == .argument) {
            try st.record(meta, &.{st.advance().?.argument});
            return null;
        }
    }

    if (State.requiresValue(meta)) {
        return ParseIssue{ .kind = .missing_option_value, .name = long.name };
    }
    try st.record(meta, &.{});
    return null;
}

fn bindShort(st: *State, short: token_mod.ShortOption) !?ParseIssue {
    if (short.letters.len == 0) {
        return ParseIssue{ .kind = .empty_short_cluster };
    }

    var i: usize = 0;
    while (i < short.letters.len) {
        const code = short.letters[i];
        i += 1;

        const meta = st.command.findOptionShort(code) orelse {
            return ParseIssue{ .kind = .unknown_short_option, .short = code };
        };

        if (!State.takesValue(meta)) {
            const at_end = i == short.letters.len;
            if (short.attached != null and at_end) {
                try st.record(meta, &.{short.attached.?});
            } else if (short.attached != null and !at_end) {
                return ParseIssue{ .kind = .unexpected_attached_value, .short = code };
            } else {
                try st.record(meta, &.{});
            }
            continue;
        }

        // Value-taking: rest of cluster is the value (`-ofile`).
        if (i < short.letters.len) {
            const rest = short.letters[i..];
            i = short.letters.len;
            if (short.attached != null) {
                return ParseIssue{ .kind = .unexpected_attached_value, .short = code };
            }
            try st.record(meta, &.{rest});
            break;
        }

        if (short.attached) |v| {
            try st.record(meta, &.{v});
            break;
        }

        if (st.peek()) |n| {
            if (n == .argument) {
                try st.record(meta, &.{st.advance().?.argument});
                break;
            }
        }

        if (State.requiresValue(meta)) {
            return ParseIssue{ .kind = .missing_option_value, .short = code };
        }
        try st.record(meta, &.{});
        break;
    }
    return null;
}

fn buildDemo(allocator: Allocator) !@import("../core/command.zig").CommandBuilder {
    const CommandBuilder = @import("../core/command.zig").CommandBuilder;
    var root = CommandBuilder.init(allocator, "demo");
    errdefer root.deinit();
    _ = (try root.flag("verbose")).short('v');
    _ = (try root.opt("output", .path)).short('o');
    _ = (try root.flag("all")).short('a');

    const run = try root.subcommand("run");
    _ = (try run.flag("dry-run")).short('n');
    _ = try run.arg("SCRIPT");

    _ = root.seal();
    return root;
}

test "parse subcommand path and flags" {
    var root = try buildDemo(std.testing.allocator);
    defer root.deinit();

    const argv = [_][]const u8{ "-v", "run", "-n", "main.zig" };
    var out = try parseArgv(std.testing.allocator, &root.meta, &argv);
    defer out.deinit();

    try std.testing.expect(out == .ok);
    try std.testing.expectEqualStrings("run", out.ok.command.name);
    try std.testing.expectEqual(@as(usize, 2), out.ok.path.len);
    try std.testing.expect(out.ok.hasOption("verbose"));
    try std.testing.expect(out.ok.hasOption("dry-run"));
    try std.testing.expectEqual(@as(usize, 1), out.ok.positionals.len);
    try std.testing.expectEqualStrings("main.zig", out.ok.positionals[0]);
}

test "parse short cluster flags and attached value" {
    var root = try buildDemo(std.testing.allocator);
    defer root.deinit();

    const argv = [_][]const u8{ "-va", "-o=out.txt" };
    var out = try parseArgv(std.testing.allocator, &root.meta, &argv);
    defer out.deinit();

    try std.testing.expect(out == .ok);
    try std.testing.expect(out.ok.hasOption("verbose"));
    try std.testing.expect(out.ok.hasOption("all"));
    try std.testing.expectEqualStrings("out.txt", out.ok.findOption("output").?.values[0]);
}

test "parse -ofile style cluster value" {
    var root = try buildDemo(std.testing.allocator);
    defer root.deinit();

    const argv = [_][]const u8{"-ofile.txt"};
    var out = try parseArgv(std.testing.allocator, &root.meta, &argv);
    defer out.deinit();

    try std.testing.expect(out == .ok);
    try std.testing.expectEqualStrings("file.txt", out.ok.findOption("output").?.values[0]);
}

test "parse unknown long option" {
    var root = try buildDemo(std.testing.allocator);
    defer root.deinit();

    const argv = [_][]const u8{"--nope"};
    var out = try parseArgv(std.testing.allocator, &root.meta, &argv);
    defer out.deinit();

    try std.testing.expect(out == .issue);
    try std.testing.expect(out.issue.kind == .unknown_long_option);
    try std.testing.expectEqualStrings("nope", out.issue.name.?);
}

test "parse missing option value" {
    var root = try buildDemo(std.testing.allocator);
    defer root.deinit();

    const argv = [_][]const u8{"--output"};
    var out = try parseArgv(std.testing.allocator, &root.meta, &argv);
    defer out.deinit();

    try std.testing.expect(out == .issue);
    try std.testing.expect(out.issue.kind == .missing_option_value);
}

test "parse separator keeps dashed args" {
    var root = try buildDemo(std.testing.allocator);
    defer root.deinit();

    const argv = [_][]const u8{ "--", "-v", "run" };
    var out = try parseArgv(std.testing.allocator, &root.meta, &argv);
    defer out.deinit();

    try std.testing.expect(out == .ok);
    try std.testing.expectEqualStrings("demo", out.ok.command.name);
    try std.testing.expectEqual(@as(usize, 2), out.ok.positionals.len);
    try std.testing.expectEqualStrings("-v", out.ok.positionals[0]);
    try std.testing.expectEqualStrings("run", out.ok.positionals[1]);
}

test "parse unknown subcommand is rejected" {
    const CommandBuilder = @import("../core/command.zig").CommandBuilder;
    var root = CommandBuilder.init(std.testing.allocator, "git");
    defer root.deinit();
    _ = try root.subcommand("commit");
    _ = try root.subcommand("push");
    _ = root.seal();

    const argv = [_][]const u8{"commmit"};
    var out = try parseArgv(std.testing.allocator, &root.meta, &argv);
    defer out.deinit();

    try std.testing.expect(out == .issue);
    try std.testing.expect(out.issue.kind == .unknown_subcommand);
    try std.testing.expectEqualStrings("commmit", out.issue.name.?);
}

test "parse unknown word stays positional when command owns args" {
    const CommandBuilder = @import("../core/command.zig").CommandBuilder;
    var root = CommandBuilder.init(std.testing.allocator, "tool");
    defer root.deinit();
    _ = try root.subcommand("run");
    _ = try root.arg("FILE");
    _ = root.seal();

    const argv = [_][]const u8{"whatever"};
    var out = try parseArgv(std.testing.allocator, &root.meta, &argv);
    defer out.deinit();

    try std.testing.expect(out == .ok);
    try std.testing.expectEqual(@as(usize, 1), out.ok.positionals.len);
}
