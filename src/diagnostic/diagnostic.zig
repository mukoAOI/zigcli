//! Structured diagnostics for the CLI framework.
//!
//! Library code never prints or exits — callers render via `formatAlloc`
//! or translate using stable `Code` values (i18n-friendly).

const std = @import("std");
const Allocator = std.mem.Allocator;
const ParseIssue = @import("../parser/result.zig").ParseIssue;
const ValidationIssue = @import("../validator/context.zig").ValidationIssue;
const CommandMeta = @import("../core/command.zig").CommandMeta;
const suggest = @import("suggest.zig");

/// Diagnostic severity levels.
pub const Severity = enum {
    @"error",
    warning,
    hint,
    note,

    pub fn asText(self: Severity) []const u8 {
        return switch (self) {
            .@"error" => "error",
            .warning => "warning",
            .hint => "hint",
            .note => "note",
        };
    }
};

/// Stable machine-readable codes (prefer these for i18n over English prose).
pub const Code = enum {
    unknown_long_option,
    unknown_short_option,
    missing_option_value,
    unexpected_attached_value,
    empty_short_cluster,
    unknown_subcommand,
    // Validation codes.
    missing_required,
    value_out_of_range,
    value_not_in_choices,
    pattern_mismatch,
    file_not_found,
    directory_not_found,
    validation_failed,

    pub fn defaultSeverity(self: Code) Severity {
        _ = self;
        return .@"error";
    }
};

/// One structured diagnostic. All string slices are borrowed.
pub const Diagnostic = struct {
    code: Code,
    severity: Severity,
    /// Long option / label involved, if any.
    name: ?[]const u8 = null,
    /// Short option codepoint, if any.
    short: ?u8 = null,
    /// “Did you mean …” suggestion (borrowed from caller candidates).
    suggestion: ?[]const u8 = null,
    /// Offending value or extra context (borrowed), when applicable.
    detail: ?[]const u8 = null,
    /// Extra note lines (borrowed).
    notes: []const []const u8 = &.{},

    /// Allocates a default English rendering. Caller owns the returned slice.
    pub fn formatAlloc(self: Diagnostic, allocator: Allocator) Allocator.Error![]u8 {
        var list: std.ArrayList(u8) = .empty;
        errdefer list.deinit(allocator);
        try appendEnglish(self, &list, allocator);
        return try list.toOwnedSlice(allocator);
    }
};

fn appendEnglish(d: Diagnostic, list: *std.ArrayList(u8), allocator: Allocator) !void {
    try list.appendSlice(allocator, d.severity.asText());
    try list.appendSlice(allocator, ": ");
    switch (d.code) {
        .unknown_long_option => {
            try list.appendSlice(allocator, "unknown option '--");
            try list.appendSlice(allocator, d.name orelse "?");
            try list.append(allocator, '\'');
        },
        .unknown_short_option => {
            try list.appendSlice(allocator, "unknown option '-");
            try list.append(allocator, d.short orelse '?');
            try list.append(allocator, '\'');
        },
        .missing_option_value => {
            if (d.name) |n| {
                try list.appendSlice(allocator, "missing value for option '--");
                try list.appendSlice(allocator, n);
                try list.append(allocator, '\'');
            } else if (d.short) |c| {
                try list.appendSlice(allocator, "missing value for option '-");
                try list.append(allocator, c);
                try list.append(allocator, '\'');
            } else {
                try list.appendSlice(allocator, "missing value for option");
            }
        },
        .unexpected_attached_value => {
            try list.appendSlice(allocator, "unexpected attached value");
            if (d.name) |n| {
                try list.appendSlice(allocator, " near '");
                try list.appendSlice(allocator, n);
                try list.append(allocator, '\'');
            } else if (d.short) |c| {
                try list.appendSlice(allocator, " near '-");
                try list.append(allocator, c);
                try list.append(allocator, '\'');
            }
        },
        .empty_short_cluster => {
            try list.appendSlice(allocator, "empty short-option cluster");
        },
        .unknown_subcommand => {
            try list.appendSlice(allocator, "unknown subcommand '");
            try list.appendSlice(allocator, d.name orelse "?");
            try list.append(allocator, '\'');
        },
        .missing_required => {
            try list.appendSlice(allocator, "missing required '");
            try list.appendSlice(allocator, d.name orelse "?");
            try list.append(allocator, '\'');
        },
        .value_out_of_range => {
            try appendValueProblem(list, allocator, "value out of range for '", d);
        },
        .value_not_in_choices => {
            try appendValueProblem(list, allocator, "invalid choice for '", d);
        },
        .pattern_mismatch => {
            try appendValueProblem(list, allocator, "value does not match pattern for '", d);
        },
        .file_not_found => {
            try appendValueProblem(list, allocator, "file not found for '", d);
        },
        .directory_not_found => {
            try appendValueProblem(list, allocator, "directory not found for '", d);
        },
        .validation_failed => {
            try appendValueProblem(list, allocator, "invalid value for '", d);
        },
    }
    if (d.suggestion) |s| {
        try list.appendSlice(allocator, "\nhint: did you mean '");
        try list.appendSlice(allocator, s);
        try list.appendSlice(allocator, "'?");
    }
    for (d.notes) |n| {
        try list.appendSlice(allocator, "\nnote: ");
        try list.appendSlice(allocator, n);
    }
}

/// Renders `<prefix><name>'` plus an optional `(got '<detail>')` suffix.
fn appendValueProblem(list: *std.ArrayList(u8), allocator: Allocator, prefix: []const u8, d: Diagnostic) !void {
    try list.appendSlice(allocator, prefix);
    try list.appendSlice(allocator, d.name orelse "?");
    try list.append(allocator, '\'');
    if (d.detail) |v| {
        try list.appendSlice(allocator, " (got '");
        try list.appendSlice(allocator, v);
        try list.appendSlice(allocator, "')");
    }
}

/// Maps a `ParseIssue` into a `Diagnostic`.
///
/// `candidates` are long option names used for “did you mean” on unknown longs.
pub fn fromParseIssue(issue: ParseIssue, candidates: []const []const u8) Diagnostic {
    const code: Code = switch (issue.kind) {
        .unknown_long_option => .unknown_long_option,
        .unknown_short_option => .unknown_short_option,
        .missing_option_value => .missing_option_value,
        .unexpected_attached_value => .unexpected_attached_value,
        .empty_short_cluster => .empty_short_cluster,
        .unknown_subcommand => .unknown_subcommand,
    };

    var diag = Diagnostic{
        .code = code,
        .severity = code.defaultSeverity(),
        .name = issue.name,
        .short = issue.short,
    };

    if (code == .unknown_long_option or code == .unknown_subcommand) {
        if (issue.name) |n| {
            diag.suggestion = suggest.suggestClosest(n, candidates, 2);
        }
    }

    return diag;
}

/// Maps a `ValidationIssue` into a `Diagnostic` (borrows its slices).
pub fn fromValidationIssue(issue: ValidationIssue) Diagnostic {
    const code: Code = switch (issue.kind) {
        .required => .missing_required,
        .out_of_range => .value_out_of_range,
        .not_in_choices => .value_not_in_choices,
        .pattern_mismatch => .pattern_mismatch,
        .file_not_found => .file_not_found,
        .directory_not_found => .directory_not_found,
        .custom => .validation_failed,
    };
    return .{
        .code = code,
        .severity = code.defaultSeverity(),
        .name = issue.name,
        .detail = issue.detail,
    };
}

/// Ergonomic wrapper: builds a `Diagnostic` for `issue`, automatically
/// choosing "did you mean" candidates from `command` based on the issue kind
/// (long option names, or subcommand names for `unknown_subcommand`).
///
/// All slices borrow from `command`, which must outlive the returned value.
pub fn diagnose(command: *const CommandMeta, issue: ParseIssue) Diagnostic {
    var buffer: [64][]const u8 = undefined;
    const candidates: []const []const u8 = switch (issue.kind) {
        .unknown_subcommand => collectSubcommandNames(command, &buffer),
        else => collectLongNames(command, &buffer),
    };
    return fromParseIssue(issue, candidates);
}

/// Fills `buffer` with long option names from `command` (no allocation).
pub fn collectLongNames(command: *const CommandMeta, buffer: [][]const u8) []const []const u8 {
    var n: usize = 0;
    for (command.options) |opt| {
        if (opt.long) |long| {
            if (n >= buffer.len) break;
            buffer[n] = long;
            n += 1;
        }
    }
    return buffer[0..n];
}

/// Fills `buffer` with direct subcommand names from `command` (no allocation).
pub fn collectSubcommandNames(command: *const CommandMeta, buffer: [][]const u8) []const []const u8 {
    var n: usize = 0;
    for (command.subcommands) |child| {
        if (n >= buffer.len) break;
        buffer[n] = child.name;
        n += 1;
    }
    return buffer[0..n];
}

test "fromParseIssue unknown long with suggestion" {
    const issue = ParseIssue{
        .kind = .unknown_long_option,
        .name = "verbos",
    };
    const cands = [_][]const u8{ "verbose", "output" };
    const diag = fromParseIssue(issue, &cands);
    try std.testing.expect(diag.code == .unknown_long_option);
    try std.testing.expect(diag.severity == .@"error");
    try std.testing.expectEqualStrings("verbose", diag.suggestion.?);

    const text = try diag.formatAlloc(std.testing.allocator);
    defer std.testing.allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "unknown option '--verbos'") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "did you mean 'verbose'") != null);
}

test "fromParseIssue missing value" {
    const issue = ParseIssue{
        .kind = .missing_option_value,
        .name = "output",
    };
    const diag = fromParseIssue(issue, &.{});
    const text = try diag.formatAlloc(std.testing.allocator);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("error: missing value for option '--output'", text);
}

test "fromParseIssue unknown short" {
    const issue = ParseIssue{ .kind = .unknown_short_option, .short = 'z' };
    const diag = fromParseIssue(issue, &.{});
    const text = try diag.formatAlloc(std.testing.allocator);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("error: unknown option '-z'", text);
}

test "collectLongNames" {
    const opt = @import("../core/option.zig").OptionMeta{
        .long = "verbose",
        .short = 'v',
    };
    var cmd = CommandMeta{ .name = "demo", .options = undefined };
    // Use a one-element slice over a local binding.
    var opts = [_]@import("../core/option.zig").OptionMeta{opt};
    cmd.options = &opts;
    var buf: [8][]const u8 = undefined;
    const names = collectLongNames(&cmd, &buf);
    try std.testing.expectEqual(@as(usize, 1), names.len);
    try std.testing.expectEqualStrings("verbose", names[0]);
}

test "fromValidationIssue renders range and required" {
    const oor = fromValidationIssue(.{ .kind = .out_of_range, .name = "threads", .detail = "99" });
    const t1 = try oor.formatAlloc(std.testing.allocator);
    defer std.testing.allocator.free(t1);
    try std.testing.expectEqualStrings("error: value out of range for 'threads' (got '99')", t1);

    const req = fromValidationIssue(.{ .kind = .required, .name = "output" });
    const t2 = try req.formatAlloc(std.testing.allocator);
    defer std.testing.allocator.free(t2);
    try std.testing.expectEqualStrings("error: missing required 'output'", t2);
}

test "diagnose unknown subcommand suggests closest child" {
    var commit = CommandMeta{ .name = "commit" };
    var push = CommandMeta{ .name = "push" };
    var children = [_]*CommandMeta{ &commit, &push };
    var root = CommandMeta{ .name = "git", .subcommands = &children };

    const issue = ParseIssue{ .kind = .unknown_subcommand, .name = "commmit" };
    const diag = diagnose(&root, issue);
    try std.testing.expect(diag.code == .unknown_subcommand);
    try std.testing.expectEqualStrings("commit", diag.suggestion.?);

    const text = try diag.formatAlloc(std.testing.allocator);
    defer std.testing.allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "unknown subcommand 'commmit'") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "did you mean 'commit'") != null);
}
