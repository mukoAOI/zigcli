//! Comptime-driven validation for `App(Config)`.
//!
//! Runs required-field checks plus any `cli.<field> = .{ .validate = ... }`
//! rules against a structural `ParseResult`, returning the first
//! `ValidationIssue` (or null). The library never prints or exits.

const std = @import("std");
const Io = std.Io;
const ParseResult = @import("../parser/result.zig").ParseResult;
const fieldSpec = @import("../derive/spec.zig").fieldSpec;
const shapeOf = @import("../derive/shape.zig").shapeOf;
const builtins = @import("../validator/builtins.zig");
const context = @import("../validator/context.zig");

pub const ValidationIssue = context.ValidationIssue;
pub const ValidationContext = context.ValidationContext;

/// Validates a parsed result against `Config`'s comptime rules.
///
/// `io` is only used by filesystem validators (`file_exists`, ...).
pub fn validateConfig(io: Io, comptime Config: type, result: *const ParseResult) ?ValidationIssue {
    inline for (@typeInfo(Config).@"struct".fields) |f| {
        const s = comptime fieldSpec(Config, f.name);
        if (comptime s.skip) continue;

        var name: []const u8 = undefined;
        var present: bool = false;
        var values: []const []const u8 = &.{};

        if (comptime s.positional) |idx| {
            name = comptime s.value_name orelse f.name;
            present = idx < result.positionals.len;
            values = if (present) result.positionals[idx .. idx + 1] else &.{};
        } else {
            name = comptime s.long orelse f.name;
            if (result.findOption(name)) |occ| {
                present = true;
                values = occ.values;
            }
        }

        const ctx = ValidationContext{ .name = name, .present = present, .values = values };

        if (comptime isRequired(Config, f)) {
            if (builtins.validate(io, .required, ctx)) |issue| return issue;
        }
        if (comptime s.validate) |v| {
            if (present or v == .required) {
                if (builtins.validate(io, v, ctx)) |issue| return issue;
            }
        }
    }
    return null;
}

/// Whether a field must be supplied (no default, not optional/flag/many).
fn isRequired(comptime Config: type, comptime f: std.builtin.Type.StructField) bool {
    const s = fieldSpec(Config, f.name);
    if (s.skip) return false;
    if (f.defaultValue() != null) return false;
    const shape = shapeOf(f.type);
    if (shape.is_optional) return false;
    if (s.positional != null) return true;
    if (shape.form == .flag) return false;
    if (shape.cardinality == .many) return false;
    return true;
}

test "validateConfig runs required and range rules" {
    const thread_range = builtins.Validator{ .range_int = .{ .min = 1, .max = 8 } };
    const Config = struct {
        threads: u32 = 4,
        name: []const u8,

        pub const cli = struct {
            pub const threads = .{ .short = 't', .validate = thread_range };
        };
    };

    const parse_mod = @import("../parser/parse.zig");
    const D = @import("../derive/options.zig").Derived("demo", Config);
    const io = std.testing.io;

    // Missing required `name`.
    {
        const argv = [_][]const u8{ "-t", "4" };
        var out = try parse_mod.parseArgv(std.testing.allocator, &D.meta, &argv);
        defer out.deinit();
        const issue = validateConfig(io, Config, &out.ok);
        try std.testing.expect(issue.?.kind == .required);
        try std.testing.expectEqualStrings("name", issue.?.name);
    }

    // Out-of-range threads.
    {
        const argv = [_][]const u8{ "-t", "99", "--name", "x" };
        var out = try parse_mod.parseArgv(std.testing.allocator, &D.meta, &argv);
        defer out.deinit();
        const issue = validateConfig(io, Config, &out.ok);
        try std.testing.expect(issue.?.kind == .out_of_range);
    }

    // All good.
    {
        const argv = [_][]const u8{ "-t", "4", "--name", "x" };
        var out = try parse_mod.parseArgv(std.testing.allocator, &D.meta, &argv);
        defer out.deinit();
        try std.testing.expect(validateConfig(io, Config, &out.ok) == null);
    }
}
