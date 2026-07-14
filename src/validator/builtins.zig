//! Built-in validators and the `Validator` tagged union.
//!
//! Duck typing: `custom` / `regex` are function pointers — no vtables.
//! Filesystem checks use Zig 0.16 `std.Io` (passed explicitly).

const std = @import("std");
const Io = std.Io;
const context = @import("context.zig");
const glob = @import("glob.zig");
const parse_value = @import("../typing/parse_value.zig");

pub const ValidationContext = context.ValidationContext;
pub const ValidationIssue = context.ValidationIssue;

/// A single validation rule.
pub const Validator = union(enum) {
    /// Fails when `present == false`.
    required,
    /// Inclusive integer range on the first value.
    range_int: struct { min: i64, max: i64 },
    /// Inclusive float range on the first value.
    range_float: struct { min: f64, max: f64 },
    /// First value must be one of these strings (exact).
    choices: []const []const u8,
    /// Glob pattern (`*` / `?`) against the first value.
    glob: []const u8,
    /// Arbitrary matcher (plug a real regex engine here).
    regex: *const fn (text: []const u8) bool,
    /// First value must be an existing file path.
    file_exists,
    /// First value must be an existing directory path.
    directory_exists,
    /// Custom predicate; return an issue or null.
    custom: *const fn (ctx: ValidationContext) ?ValidationIssue,
};

/// Runs one validator. Returns the first issue, or null on success.
///
/// `io` is required for filesystem rules; ignored otherwise.
pub fn validate(io: Io, v: Validator, ctx: ValidationContext) ?ValidationIssue {
    switch (v) {
        .required => {
            if (!ctx.present) {
                return .{ .kind = .required, .name = ctx.name };
            }
            return null;
        },
        .range_int => |r| {
            const text = ctx.first() orelse {
                return .{ .kind = .out_of_range, .name = ctx.name, .detail = "missing value" };
            };
            const n = parse_value.parseValue(i64, text) catch {
                return .{ .kind = .out_of_range, .name = ctx.name, .detail = text };
            };
            if (n < r.min or n > r.max) {
                return .{ .kind = .out_of_range, .name = ctx.name, .detail = text };
            }
            return null;
        },
        .range_float => |r| {
            const text = ctx.first() orelse {
                return .{ .kind = .out_of_range, .name = ctx.name, .detail = "missing value" };
            };
            const n = parse_value.parseValue(f64, text) catch {
                return .{ .kind = .out_of_range, .name = ctx.name, .detail = text };
            };
            if (n < r.min or n > r.max) {
                return .{ .kind = .out_of_range, .name = ctx.name, .detail = text };
            }
            return null;
        },
        .choices => |opts| {
            const text = ctx.first() orelse {
                return .{ .kind = .not_in_choices, .name = ctx.name };
            };
            for (opts) |c| {
                if (std.mem.eql(u8, c, text)) return null;
            }
            return .{ .kind = .not_in_choices, .name = ctx.name, .detail = text };
        },
        .glob => |pattern| {
            const text = ctx.first() orelse {
                return .{ .kind = .pattern_mismatch, .name = ctx.name };
            };
            if (!glob.globMatch(pattern, text)) {
                return .{ .kind = .pattern_mismatch, .name = ctx.name, .detail = text };
            }
            return null;
        },
        .regex => |matcher| {
            const text = ctx.first() orelse {
                return .{ .kind = .pattern_mismatch, .name = ctx.name };
            };
            if (!matcher(text)) {
                return .{ .kind = .pattern_mismatch, .name = ctx.name, .detail = text };
            }
            return null;
        },
        .file_exists => {
            const text = ctx.first() orelse {
                return .{ .kind = .file_not_found, .name = ctx.name };
            };
            var file = Io.Dir.cwd().openFile(io, text, .{}) catch {
                return .{ .kind = .file_not_found, .name = ctx.name, .detail = text };
            };
            file.close(io);
            return null;
        },
        .directory_exists => {
            const text = ctx.first() orelse {
                return .{ .kind = .directory_not_found, .name = ctx.name };
            };
            var dir = Io.Dir.cwd().openDir(io, text, .{}) catch {
                return .{ .kind = .directory_not_found, .name = ctx.name, .detail = text };
            };
            dir.close(io);
            return null;
        },
        .custom => |fn_ptr| return fn_ptr(ctx),
    }
}

/// Runs all validators; returns the first issue.
pub fn validateAll(io: Io, validators: []const Validator, ctx: ValidationContext) ?ValidationIssue {
    for (validators) |v| {
        if (validate(io, v, ctx)) |issue| return issue;
    }
    return null;
}

test "required and choices" {
    const io = std.testing.io;
    try std.testing.expect(validate(io, .required, .{
        .name = "x",
        .present = false,
    }).?.kind == .required);

    const issue = validate(io, .{ .choices = &[_][]const u8{ "a", "b" } }, .{
        .name = "mode",
        .present = true,
        .values = &[_][]const u8{"c"},
    });
    try std.testing.expect(issue.?.kind == .not_in_choices);
}

test "range_int" {
    const io = std.testing.io;
    try std.testing.expect(validate(io, .{ .range_int = .{ .min = 1, .max = 4 } }, .{
        .name = "t",
        .present = true,
        .values = &[_][]const u8{"3"},
    }) == null);

    try std.testing.expect(validate(io, .{ .range_int = .{ .min = 1, .max = 4 } }, .{
        .name = "t",
        .present = true,
        .values = &[_][]const u8{"9"},
    }).?.kind == .out_of_range);
}

test "glob and regex validators" {
    const io = std.testing.io;
    try std.testing.expect(validate(io, .{ .glob = "*.txt" }, .{
        .name = "f",
        .present = true,
        .values = &[_][]const u8{"a.zig"},
    }).?.kind == .pattern_mismatch);

    const onlyDigits = struct {
        fn m(text: []const u8) bool {
            if (text.len == 0) return false;
            for (text) |c| {
                if (c < '0' or c > '9') return false;
            }
            return true;
        }
    }.m;
    try std.testing.expect(validate(io, .{ .regex = onlyDigits }, .{
        .name = "n",
        .present = true,
        .values = &[_][]const u8{"12a"},
    }).?.kind == .pattern_mismatch);
    try std.testing.expect(validate(io, .{ .regex = onlyDigits }, .{
        .name = "n",
        .present = true,
        .values = &[_][]const u8{"12"},
    }) == null);
}

test "custom validator" {
    const io = std.testing.io;
    const pred = struct {
        fn check(ctx: ValidationContext) ?ValidationIssue {
            if (ctx.first()) |v| {
                if (v.len > 3) return .{ .kind = .custom, .name = ctx.name, .detail = v };
            }
            return null;
        }
    }.check;
    try std.testing.expect(validate(io, .{ .custom = pred }, .{
        .name = "s",
        .present = true,
        .values = &[_][]const u8{"abcd"},
    }).?.kind == .custom);
}

test "file_exists and directory_exists" {
    const io = std.testing.io;
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    try tmp.dir.writeFile(io, .{ .sub_path = "f.txt", .data = "x" });
    try tmp.dir.createDir(io, "sub", .default_dir);

    var abs_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    const abs_file_len = try tmp.dir.realPathFile(io, "f.txt", &abs_buf);
    const abs_file = abs_buf[0..abs_file_len];
    try std.testing.expect(validate(io, .file_exists, .{
        .name = "f",
        .present = true,
        .values = &[_][]const u8{abs_file},
    }) == null);

    var abs_dir_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
    var sub = try tmp.dir.openDir(io, "sub", .{});
    defer sub.close(io);
    const abs_dir_len = try sub.realPath(io, &abs_dir_buf);
    const abs_dir = abs_dir_buf[0..abs_dir_len];
    try std.testing.expect(validate(io, .directory_exists, .{
        .name = "d",
        .present = true,
        .values = &[_][]const u8{abs_dir},
    }) == null);

    try std.testing.expect(validate(io, .file_exists, .{
        .name = "f",
        .present = true,
        .values = &[_][]const u8{"__no_such_file_cli__"},
    }).?.kind == .file_not_found);
}
