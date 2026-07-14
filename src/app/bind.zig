//! Bind a structural `ParseResult` into a typed config struct.

const std = @import("std");
const Allocator = std.mem.Allocator;
const ParseResult = @import("../parser/result.zig").ParseResult;
const parse_value = @import("../typing/parse_value.zig");
const fieldSpec = @import("../derive/spec.zig").fieldSpec;
const shapeOf = @import("../derive/shape.zig").shapeOf;

pub const BindError = parse_value.ParseValueError || error{MissingRequired};

/// `bindConfig` plus allocation for multi-value (`[]E`) fields.
pub const BindAllocError = BindError || Allocator.Error;

/// Fills `Config` from parsed option occurrences (field name / cli.long → option).
///
/// This path never allocates. A `Config` with a multi-value (`[]E`, E != u8)
/// field is a compile error — use `bindConfigAlloc` instead.
pub fn bindConfig(comptime Config: type, result: *const ParseResult) BindError!Config {
    if (@typeInfo(Config) != .@"struct") {
        @compileError("bindConfig expects a struct type");
    }

    var cfg: Config = undefined;
    inline for (@typeInfo(Config).@"struct".fields) |f| {
        const s = comptime fieldSpec(Config, f.name);
        if (comptime s.skip) {
            if (comptime f.defaultValue()) |d| {
                @field(cfg, f.name) = d;
            } else {
                @compileError("skipped field '" ++ f.name ++ "' needs a default value");
            }
            continue;
        }

        if (comptime s.positional) |idx| {
            if (idx < result.positionals.len) {
                @field(cfg, f.name) = try bindPositional(f.type, result.positionals[idx]);
            } else if (comptime f.defaultValue()) |d| {
                @field(cfg, f.name) = d;
            } else if (comptime @typeInfo(f.type) == .optional) {
                @field(cfg, f.name) = null;
            } else {
                return error.MissingRequired;
            }
            continue;
        }

        const long_name: []const u8 = comptime s.long orelse f.name;
        const shape = comptime shapeOf(f.type);
        if (comptime shape.cardinality == .many) {
            @compileError("field '" ++ f.name ++ "' is multi-value; use bindConfigAlloc / App.parseAlloc");
        }

        if (result.findOption(long_name)) |occ| {
            @field(cfg, f.name) = try bindOccurrence(f.type, shape.form == .flag, occ.values);
        } else if (comptime f.defaultValue()) |d| {
            @field(cfg, f.name) = d;
        } else if (comptime @typeInfo(f.type) == .optional) {
            @field(cfg, f.name) = null;
        } else if (comptime f.type == bool) {
            @field(cfg, f.name) = false;
        } else {
            return error.MissingRequired;
        }
    }
    return cfg;
}

/// Like `bindConfig`, but allocates owned slices for multi-value (`[]E`) fields.
///
/// The caller owns any allocated slices and must free them (an arena is the
/// easiest option). Scalar / string / optional fields still borrow argv.
pub fn bindConfigAlloc(
    comptime Config: type,
    allocator: Allocator,
    result: *const ParseResult,
) BindAllocError!Config {
    if (@typeInfo(Config) != .@"struct") {
        @compileError("bindConfigAlloc expects a struct type");
    }

    var cfg: Config = undefined;
    inline for (@typeInfo(Config).@"struct".fields) |f| {
        const s = comptime fieldSpec(Config, f.name);
        if (comptime s.skip) {
            if (comptime f.defaultValue()) |d| {
                @field(cfg, f.name) = d;
            } else {
                @compileError("skipped field '" ++ f.name ++ "' needs a default value");
            }
            continue;
        }

        if (comptime s.positional) |idx| {
            if (idx < result.positionals.len) {
                @field(cfg, f.name) = try bindPositional(f.type, result.positionals[idx]);
            } else if (comptime f.defaultValue()) |d| {
                @field(cfg, f.name) = d;
            } else if (comptime @typeInfo(f.type) == .optional) {
                @field(cfg, f.name) = null;
            } else {
                return error.MissingRequired;
            }
            continue;
        }

        const long_name: []const u8 = comptime s.long orelse f.name;
        const shape = comptime shapeOf(f.type);

        if (comptime shape.cardinality == .many) {
            @field(cfg, f.name) = try bindMany(f.type, allocator, result, long_name);
            continue;
        }

        if (result.findOption(long_name)) |occ| {
            @field(cfg, f.name) = try bindOccurrence(f.type, shape.form == .flag, occ.values);
        } else if (comptime f.defaultValue()) |d| {
            @field(cfg, f.name) = d;
        } else if (comptime @typeInfo(f.type) == .optional) {
            @field(cfg, f.name) = null;
        } else if (comptime f.type == bool) {
            @field(cfg, f.name) = false;
        } else {
            return error.MissingRequired;
        }
    }
    return cfg;
}

/// Collects every value for `long` across all occurrences into an owned `[]E`.
fn bindMany(
    comptime T: type,
    allocator: Allocator,
    result: *const ParseResult,
    long: []const u8,
) BindAllocError!T {
    const info = @typeInfo(T);
    const SliceT = if (info == .optional) info.optional.child else T;
    const Elem = @typeInfo(SliceT).pointer.child;

    var count: usize = 0;
    for (result.options) |occ| {
        if (occ.meta.matchesLong(long)) count += occ.values.len;
    }

    if (info == .optional and count == 0) return null;

    const out = try allocator.alloc(Elem, count);
    errdefer allocator.free(out);
    var i: usize = 0;
    for (result.options) |occ| {
        if (!occ.meta.matchesLong(long)) continue;
        for (occ.values) |v| {
            out[i] = try parse_value.parseValue(Elem, v);
            i += 1;
        }
    }
    return out;
}

fn bindPositional(comptime T: type, raw: []const u8) BindError!T {
    const info = @typeInfo(T);
    if (info == .optional) {
        return try parse_value.parseValue(info.optional.child, raw);
    }
    return try parse_value.parseValue(T, raw);
}

fn bindOccurrence(comptime T: type, comptime is_flag: bool, values: []const []const u8) BindError!T {
    if (comptime is_flag or T == bool) {
        if (values.len == 0) return true;
        return try parse_value.parseValue(bool, values[0]);
    }

    const info = @typeInfo(T);
    if (info == .optional) {
        if (values.len == 0) return null;
        const inner = try parse_value.parseValue(info.optional.child, values[0]);
        return inner;
    }

    if (values.len == 0) return error.EmptyInput;
    return try parse_value.parseValue(T, values[0]);
}

test "bindConfig maps flags and values" {
    const Config = struct {
        verbose: bool = false,
        threads: u32 = 4,
        output: ?[]const u8 = null,

        pub const cli = struct {
            pub const verbose = .{ .short = 'v' };
            pub const threads = .{ .short = 't' };
            pub const output = .{ .short = 'o' };
        };
    };

    const D = @import("../derive/options.zig").Derived("demo", Config);
    const verbose_meta = D.meta.findOptionLong("verbose").?;
    const threads_meta = D.meta.findOptionLong("threads").?;
    const output_meta = D.meta.findOptionLong("output").?;

    var path_buf = [_]*const @import("../core/command.zig").CommandMeta{&D.meta};
    var occs = [_]@import("../parser/result.zig").OptionOccurrence{
        .{ .meta = verbose_meta, .values = &.{} },
        .{ .meta = threads_meta, .values = &[_][]const u8{"8"} },
        .{ .meta = output_meta, .values = &[_][]const u8{"out.txt"} },
    };
    const result = ParseResult{
        .allocator = std.testing.allocator,
        .command = &D.meta,
        .path = &path_buf,
        .options = &occs,
        .positionals = &.{},
    };

    const cfg = try bindConfig(Config, &result);
    try std.testing.expect(cfg.verbose);
    try std.testing.expectEqual(@as(u32, 8), cfg.threads);
    try std.testing.expectEqualStrings("out.txt", cfg.output.?);
}

test "bindConfig binds positionals" {
    const parse_mod = @import("../parser/parse.zig");
    const Config = struct {
        verbose: bool = false,
        host: []const u8,
        port: u16 = 80,

        pub const cli = struct {
            pub const verbose = .{ .short = 'v' };
            pub const host = .{ .positional = 0 };
            pub const port = .{ .positional = 1 };
        };
    };

    const D = @import("../derive/options.zig").Derived("net", Config);
    // Two positionals derived, one option.
    try std.testing.expectEqual(@as(usize, 1), D.meta.options.len);
    try std.testing.expectEqual(@as(usize, 2), D.meta.arguments.len);
    try std.testing.expectEqualStrings("host", D.meta.arguments[0].name);

    const argv = [_][]const u8{ "-v", "example.com", "8080" };
    var out = try parse_mod.parseArgv(std.testing.allocator, &D.meta, &argv);
    defer out.deinit();
    try std.testing.expect(out == .ok);

    const cfg = try bindConfig(Config, &out.ok);
    try std.testing.expect(cfg.verbose);
    try std.testing.expectEqualStrings("example.com", cfg.host);
    try std.testing.expectEqual(@as(u16, 8080), cfg.port);
}

test "bindConfig missing required positional" {
    const parse_mod = @import("../parser/parse.zig");
    const Config = struct {
        host: []const u8,
        pub const cli = struct {
            pub const host = .{ .positional = 0 };
        };
    };

    const D = @import("../derive/options.zig").Derived("net", Config);
    const argv = [_][]const u8{};
    var out = try parse_mod.parseArgv(std.testing.allocator, &D.meta, &argv);
    defer out.deinit();
    try std.testing.expectError(error.MissingRequired, bindConfig(Config, &out.ok));
}
