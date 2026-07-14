//! Derive `OptionMeta` / `CommandMeta` from a Zig struct via `@typeInfo`.

const std = @import("std");
const OptionMeta = @import("../core/option.zig").OptionMeta;
const ArgumentMeta = @import("../core/argument.zig").ArgumentMeta;
const CommandMeta = @import("../core/command.zig").CommandMeta;
const spec_mod = @import("spec.zig");
const shape_mod = @import("shape.zig");

pub const FieldSpec = spec_mod.FieldSpec;
pub const fieldSpec = spec_mod.fieldSpec;
pub const CommandSpec = spec_mod.CommandSpec;
pub const commandSpec = spec_mod.commandSpec;
pub const shapeOf = shape_mod.shapeOf;

fn countOptionFields(comptime T: type) usize {
    const fields = @typeInfo(T).@"struct".fields;
    var n: usize = 0;
    inline for (fields) |f| {
        const s = fieldSpec(T, f.name);
        if (!s.skip and s.positional == null) n += 1;
    }
    return n;
}

fn countPositionalFields(comptime T: type) usize {
    const fields = @typeInfo(T).@"struct".fields;
    var n: usize = 0;
    inline for (fields) |f| {
        const s = fieldSpec(T, f.name);
        if (!s.skip and s.positional != null) n += 1;
    }
    return n;
}

/// Comptime array type holding derived options for `T`.
pub fn OptionsArray(comptime T: type) type {
    return [countOptionFields(T)]OptionMeta;
}

/// Comptime array type holding derived positional arguments for `T`.
pub fn ArgumentsArray(comptime T: type) type {
    return [countPositionalFields(T)]ArgumentMeta;
}

/// Builds option metadata for every (non-skipped) field of `T`.
pub fn optionsFromStruct(comptime T: type) OptionsArray(T) {
    if (@typeInfo(T) != .@"struct") {
        @compileError("optionsFromStruct expects a struct type");
    }
    var out: OptionsArray(T) = undefined;
    const fields = @typeInfo(T).@"struct".fields;
    var i: usize = 0;
    inline for (fields) |f| {
        const s = comptime fieldSpec(T, f.name);
        if (comptime s.skip or s.positional != null) continue;

        const shape = comptime shapeOf(f.type);
        const long_name: []const u8 = comptime s.long orelse f.name;

        var required = false;
        var default_text: ?[]const u8 = null;

        if (comptime f.defaultValue()) |def| {
            default_text = comptime comptimeDefaultText(f.type, def);
            required = false;
        } else if (shape.is_optional) {
            required = false;
        } else if (shape.form == .flag) {
            required = false;
        } else if (shape.cardinality == .many) {
            // Multi-value options default to an empty collection.
            required = false;
        } else {
            required = true;
        }

        out[i] = .{
            .long = long_name,
            .short = s.short,
            .description = s.help,
            .value_name = s.value_name,
            .form = shape.form,
            .value_kind = shape.value_kind,
            .cardinality = shape.cardinality,
            .required = required,
            .default_text = default_text,
        };
        i += 1;
    }
    return out;
}

/// Builds positional argument metadata for every positional field of `T`,
/// ordered by the field's declared `positional` index.
pub fn argumentsFromStruct(comptime T: type) ArgumentsArray(T) {
    var out: ArgumentsArray(T) = undefined;
    const n = out.len;
    const fields = @typeInfo(T).@"struct".fields;

    comptime var seen = [_]bool{false} ** (if (n == 0) 1 else n);
    inline for (fields) |f| {
        const s = comptime fieldSpec(T, f.name);
        if (comptime s.skip or s.positional == null) continue;
        const idx = comptime s.positional.?;
        if (comptime idx >= n) {
            @compileError("positional index for '" ++ f.name ++ "' is out of range (indices must be 0..N-1 and contiguous)");
        }
        if (comptime seen[idx]) {
            @compileError("duplicate positional index for '" ++ f.name ++ "'");
        }
        seen[idx] = true;

        const shape = comptime shapeOf(f.type);
        var required = true;
        if (comptime f.defaultValue() != null) {
            required = false;
        } else if (comptime shape.is_optional) {
            required = false;
        }

        out[idx] = .{
            .name = comptime s.value_name orelse f.name,
            .description = s.help,
            .value_kind = shape.value_kind,
            .cardinality = shape.cardinality,
            .required = required,
        };
    }
    return out;
}

fn comptimeDefaultText(comptime T: type, comptime value: T) ?[]const u8 {
    const info = @typeInfo(T);
    switch (info) {
        .bool => return if (value) "true" else "false",
        .int, .float => {
            return std.fmt.comptimePrint("{d}", .{value});
        },
        .optional => {
            if (value) |v| {
                return comptimeDefaultText(@TypeOf(v), v);
            }
            return null;
        },
        .@"enum" => return @tagName(value),
        .pointer => |ptr| {
            if (ptr.size == .slice and ptr.child == u8) {
                return value;
            }
            return null;
        },
        else => return null,
    }
}

/// Namespace holding a stable `options` array and `meta`.
///
/// `fallback_name` is used when `T` does not declare `cli.name` / `cli_name`.
/// Optional `description` / `aliases` / `examples` come from `commandSpec(T)`.
///
/// ```zig
/// const D = cli.Derived("demo", Config);
/// const meta = &D.meta;
/// ```
pub fn Derived(comptime fallback_name: []const u8, comptime T: type) type {
    const cs = commandSpec(T);
    const resolved_name = cs.name orelse fallback_name;
    return struct {
        pub const options: OptionsArray(T) = optionsFromStruct(T);
        pub const arguments: ArgumentsArray(T) = argumentsFromStruct(T);
        pub const sub_metas: [subcommandCount(T)]*const CommandMeta = subMetasFromStruct(T);
        pub const meta: CommandMeta = .{
            .name = resolved_name,
            .description = cs.description,
            .aliases = cs.aliases,
            .examples = cs.examples,
            .options = &options,
            .arguments = &arguments,
            .subcommands = &sub_metas,
        };
    };
}

/// Number of subcommands declared via `pub const cli_subcommands`.
pub fn subcommandCount(comptime T: type) usize {
    if (!@hasDecl(T, "cli_subcommands")) return 0;
    return @typeInfo(@TypeOf(T.cli_subcommands)).@"struct".fields.len;
}

/// Builds child `CommandMeta` pointers from `T.cli_subcommands`
/// (`.{ .name = SubConfig, ... }`), each derived recursively.
fn subMetasFromStruct(comptime T: type) [subcommandCount(T)]*const CommandMeta {
    var out: [subcommandCount(T)]*const CommandMeta = undefined;
    if (comptime subcommandCount(T) == 0) return out;
    const subs = T.cli_subcommands;
    const sfields = @typeInfo(@TypeOf(subs)).@"struct".fields;
    inline for (sfields, 0..) |f, i| {
        const SubT = @field(subs, f.name);
        out[i] = &Derived(f.name, SubT).meta;
    }
    return out;
}

test "optionsFromStruct derives flags and options" {
    const Config = struct {
        verbose: bool = false,
        output: ?[]const u8 = null,
        threads: u32 = 4,
        name: []const u8,

        pub const cli = struct {
            pub const verbose = .{ .short = 'v', .help = "more output" };
            pub const output = .{ .short = 'o', .value_name = "FILE" };
            pub const threads = .{ .short = 't', .help = "workers" };
        };
    };

    const opts = optionsFromStruct(Config);
    try std.testing.expectEqual(@as(usize, 4), opts.len);

    try std.testing.expectEqualStrings("verbose", opts[0].long.?);
    try std.testing.expect(opts[0].short == 'v');
    try std.testing.expect(opts[0].form == .flag);
    try std.testing.expect(opts[0].cardinality == .zero);
    try std.testing.expectEqualStrings("more output", opts[0].description);

    try std.testing.expectEqualStrings("output", opts[1].long.?);
    try std.testing.expect(opts[1].cardinality == .optional);

    try std.testing.expectEqualStrings("threads", opts[2].long.?);
    try std.testing.expectEqualStrings("4", opts[2].default_text.?);

    try std.testing.expectEqualStrings("name", opts[3].long.?);
    try std.testing.expect(opts[3].required);
}

test "Derived exposes stable CommandMeta" {
    const Config = struct {
        verbose: bool = false,
        pub const cli = struct {
            pub const description = "handy tool";
            pub const examples = [_][]const u8{"tool -v"};
            pub const verbose = .{ .short = 'v' };
        };
    };
    const D = Derived("tool", Config);
    try std.testing.expectEqualStrings("tool", D.meta.name);
    try std.testing.expectEqualStrings("handy tool", D.meta.description);
    try std.testing.expectEqual(@as(usize, 1), D.meta.examples.len);
    try std.testing.expectEqual(@as(usize, 1), D.meta.options.len);
    try std.testing.expect(D.meta.findOptionLong("verbose") != null);
    try std.testing.expect(D.meta.findOptionShort('v') != null);
}

test "Derived prefers cli.name over fallback" {
    const Config = struct {
        pub const cli = struct {
            pub const name = "renamed";
            pub const description = "desc";
        };
        verbose: bool = false,
    };
    const D = Derived("fallback", Config);
    try std.testing.expectEqualStrings("renamed", D.meta.name);
    try std.testing.expectEqualStrings("desc", D.meta.description);
}

test "skip field" {
    const Config = struct {
        verbose: bool = false,
        internal: u32 = 0,
        pub const cli = struct {
            pub const internal = .{ .skip = true };
        };
    };
    const opts = optionsFromStruct(Config);
    try std.testing.expectEqual(@as(usize, 1), opts.len);
    try std.testing.expectEqualStrings("verbose", opts[0].long.?);
}
