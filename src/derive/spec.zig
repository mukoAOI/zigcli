//! Optional CLI overrides: per-field (`T.cli.<field>`) and command-level
//! (`T.cli.description` / `T.cli_name` / …).
//!
//! ```zig
//! const Config = struct {
//!     pub const cli_name = "demo"; // optional shortcut
//!     pub const cli_description = "A demo tool"; // optional shortcut
//!
//!     verbose: bool = false,
//!
//!     pub const cli = struct {
//!         pub const description = "A demo tool"; // preferred
//!         pub const examples = [_][]const u8{"demo -v"};
//!         pub const verbose = .{ .short = 'v', .help = "more output" };
//!     };
//! };
//! ```

/// Comptime overrides for a derived option field.
pub const FieldSpec = struct {
    short: ?u8 = null,
    help: []const u8 = "",
    value_name: ?[]const u8 = null,
    /// Force long name (defaults to struct field name).
    long: ?[]const u8 = null,
    /// Skip deriving this field as a CLI option.
    skip: bool = false,
    /// Bind this field to a positional argument at the given index
    /// (`0`-based) instead of an option.
    positional: ?usize = null,
    /// Optional validation rule run by `validateConfig` / `App.parseChecked`.
    validate: ?Validator = null,
};

/// Optional command-level metadata taken from `T` / `T.cli`.
pub const CommandSpec = struct {
    /// Overrides the Derived / App binary name when set.
    name: ?[]const u8 = null,
    description: []const u8 = "",
    aliases: []const []const u8 = &.{},
    examples: []const []const u8 = &.{},
};

/// Looks up `T.cli.<field>` if present, otherwise empty spec.
///
/// A field overlay is always a struct literal (`.{ .short = 'v', ... }`), so
/// command-level string/array decls (`name`, `description`, ...) are ignored
/// here — this lets a config field even be named `name`.
pub fn fieldSpec(comptime T: type, comptime field_name: []const u8) FieldSpec {
    if (!@hasDecl(T, "cli")) return .{};
    const Cli = T.cli;
    if (!@hasDecl(Cli, field_name)) return .{};

    const raw = @field(Cli, field_name);
    const R = @TypeOf(raw);
    if (@typeInfo(R) != .@"struct") return .{};

    var spec: FieldSpec = .{};
    if (@hasField(R, "short")) spec.short = @field(raw, "short");
    if (@hasField(R, "help")) spec.help = @field(raw, "help");
    if (@hasField(R, "value_name")) spec.value_name = @field(raw, "value_name");
    if (@hasField(R, "long")) spec.long = @field(raw, "long");
    if (@hasField(R, "skip")) spec.skip = @field(raw, "skip");
    if (@hasField(R, "positional")) spec.positional = @field(raw, "positional");
    if (@hasField(R, "validate")) spec.validate = @field(raw, "validate");
    return spec;
}

/// A `cli` decl is command-level metadata (not a field overlay) when its value
/// is not a struct literal — overlays are always `.{ ... }` structs.
fn isFieldOverlay(comptime value: anytype) bool {
    return @typeInfo(@TypeOf(value)) == .@"struct";
}

const std = @import("std");
const Validator = @import("../validator/builtins.zig").Validator;

/// Collects optional command metadata from `T.cli_*` and/or `T.cli`.
///
/// Precedence for name: `T.cli.name` > `T.cli_name`.
/// Precedence for description: `T.cli.description` > `T.cli_description`.
pub fn commandSpec(comptime T: type) CommandSpec {
    var s: CommandSpec = .{};

    if (@hasDecl(T, "cli_name")) {
        s.name = T.cli_name;
    }
    if (@hasDecl(T, "cli_description")) {
        s.description = T.cli_description;
    }
    if (@hasDecl(T, "cli_aliases")) {
        s.aliases = sliceFromDecl(T.cli_aliases);
    }
    if (@hasDecl(T, "cli_examples")) {
        s.examples = sliceFromDecl(T.cli_examples);
    }

    if (@hasDecl(T, "cli")) {
        const Cli = T.cli;
        // Only treat these as command-level metadata when they are not field
        // overlays (a field may legitimately be named `name`, `aliases`, ...).
        if (@hasDecl(Cli, "name") and !isFieldOverlay(Cli.name)) s.name = Cli.name;
        if (@hasDecl(Cli, "description") and !isFieldOverlay(Cli.description)) s.description = Cli.description;
        if (@hasDecl(Cli, "aliases") and !isFieldOverlay(Cli.aliases)) s.aliases = sliceFromDecl(Cli.aliases);
        if (@hasDecl(Cli, "examples") and !isFieldOverlay(Cli.examples)) s.examples = sliceFromDecl(Cli.examples);
    }

    return s;
}

fn sliceFromDecl(comptime value: anytype) []const []const u8 {
    const V = @TypeOf(value);
    const info = @typeInfo(V);
    return switch (info) {
        .pointer => |ptr| blk: {
            if (ptr.size == .slice) break :blk value;
            if (ptr.size == .one) {
                const child = @typeInfo(ptr.child);
                if (child == .array) break :blk value[0..];
            }
            @compileError("cli aliases/examples must be a slice or array of []const u8");
        },
        .array => value[0..],
        else => @compileError("cli aliases/examples must be a slice or array of []const u8"),
    };
}

test "fieldSpec reads cli overlay" {
    const C = struct {
        verbose: bool = false,
        pub const cli = struct {
            pub const description = "ignored for fieldSpec";
            pub const verbose = .{ .short = 'v', .help = "more" };
        };
    };
    const s = fieldSpec(C, "verbose");
    try std.testing.expect(s.short == 'v');
    try std.testing.expectEqualStrings("more", s.help);
    // command decl must not be treated as a field overlay
    const fake = fieldSpec(C, "description");
    try std.testing.expect(fake.short == null);
    try std.testing.expectEqualStrings("", fake.help);
}

test "commandSpec reads optional description and name" {
    const C = struct {
        pub const cli_name = "from_top";
        pub const cli_description = "top desc";
        verbose: bool = false,
        pub const cli = struct {
            pub const name = "from_cli";
            pub const description = "cli desc";
            pub const examples = [_][]const u8{"from_cli -v"};
            pub const verbose = .{ .short = 'v' };
        };
    };
    const s = commandSpec(C);
    try std.testing.expectEqualStrings("from_cli", s.name.?);
    try std.testing.expectEqualStrings("cli desc", s.description);
    try std.testing.expectEqual(@as(usize, 1), s.examples.len);
}
