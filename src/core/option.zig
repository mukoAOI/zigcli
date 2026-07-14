//! Option / flag metadata and a small builder for declarative registration.
//!
//! Ownership: all string slices are borrowed (caller- or static-owned).
//! The builder never copies argv text.

const std = @import("std");
const kinds = @import("kinds.zig");

/// Immutable description of a single flag or option.
///
/// Extension points (`validator_id`, `completion_id`, `type_id`) are opaque
/// indices into later registries so `core` never depends on those modules.
pub const OptionMeta = struct {
    /// Long name without leading `--` (e.g. `"verbose"`).
    long: ?[]const u8 = null,
    /// Short name as a single ASCII codepoint (e.g. `'v'`).
    short: ?u8 = null,
    /// Human-readable help text.
    description: []const u8 = "",
    /// Placeholder shown in usage (e.g. `"FILE"`).
    value_name: ?[]const u8 = null,
    form: kinds.OptionForm = .flag,
    value_kind: kinds.ValueKind = .bool,
    cardinality: kinds.Cardinality = .zero,
    required: bool = false,
    /// Default rendered in help only; not parsed here.
    default_text: ?[]const u8 = null,
    /// Opaque id for a registered Validator (null = none).
    validator_id: ?u32 = null,
    /// Opaque id for a registered Completer (null = none).
    completion_id: ?u32 = null,
    /// Opaque id for a custom TypeParser (null = use `value_kind`).
    type_id: ?u32 = null,

    /// Display name preferred for diagnostics and help.
    ///
    /// Prefers the long name. Short-only options should use `writeLabel`.
    pub fn displayName(self: OptionMeta) []const u8 {
        if (self.long) |long| return long;
        return "<short>";
    }

    /// Writes a help/diagnostic label into `buf` (needs at least 2 bytes for `-x`).
    pub fn writeLabel(self: OptionMeta, buf: []u8) []const u8 {
        if (self.long) |long| return long;
        if (self.short) |code| {
            std.debug.assert(buf.len >= 2);
            buf[0] = '-';
            buf[1] = code;
            return buf[0..2];
        }
        return "<unnamed>";
    }

    /// Returns true if this option can be matched by a long name.
    pub fn matchesLong(self: OptionMeta, name: []const u8) bool {
        const long = self.long orelse return false;
        return std.mem.eql(u8, long, name);
    }

    /// Returns true if this option can be matched by a short codepoint.
    pub fn matchesShort(self: OptionMeta, code: u8) bool {
        return self.short == code;
    }
};

/// Fluent builder that configures an `OptionMeta` in place.
///
/// Not an OOP hierarchy — just a thin mutable view over `OptionMeta`.
pub const OptionBuilder = struct {
    meta: *OptionMeta,

    pub fn short(self: OptionBuilder, code: u8) OptionBuilder {
        self.meta.short = code;
        return self;
    }

    pub fn long(self: OptionBuilder, name: []const u8) OptionBuilder {
        self.meta.long = name;
        return self;
    }

    pub fn help(self: OptionBuilder, text: []const u8) OptionBuilder {
        self.meta.description = text;
        return self;
    }

    pub fn valueName(self: OptionBuilder, name: []const u8) OptionBuilder {
        self.meta.value_name = name;
        return self;
    }

    pub fn required(self: OptionBuilder) OptionBuilder {
        self.meta.required = true;
        return self;
    }

    pub fn defaultText(self: OptionBuilder, text: []const u8) OptionBuilder {
        self.meta.default_text = text;
        return self;
    }

    pub fn asFlag(self: OptionBuilder) OptionBuilder {
        self.meta.form = .flag;
        self.meta.value_kind = .bool;
        self.meta.cardinality = .zero;
        return self;
    }

    pub fn asOption(self: OptionBuilder, value_kind: kinds.ValueKind) OptionBuilder {
        self.meta.form = .option;
        self.meta.value_kind = value_kind;
        self.meta.cardinality = .one;
        return self;
    }

    pub fn cardinality(self: OptionBuilder, card: kinds.Cardinality) OptionBuilder {
        self.meta.cardinality = card;
        return self;
    }

    pub fn valueKind(self: OptionBuilder, kind: kinds.ValueKind) OptionBuilder {
        self.meta.value_kind = kind;
        return self;
    }

    pub fn finish(self: OptionBuilder) *OptionMeta {
        return self.meta;
    }
};

test "OptionMeta matching" {
    const opt = OptionMeta{
        .long = "output",
        .short = 'o',
        .form = .option,
        .value_kind = .path,
        .cardinality = .one,
    };
    try std.testing.expect(opt.matchesLong("output"));
    try std.testing.expect(!opt.matchesLong("out"));
    try std.testing.expect(opt.matchesShort('o'));
    try std.testing.expect(!opt.matchesShort('v'));
    try std.testing.expectEqualStrings("output", opt.displayName());
}

test "OptionBuilder fluent configuration" {
    var meta = OptionMeta{};
    _ = (OptionBuilder{ .meta = &meta })
        .long("threads")
        .short('t')
        .asOption(.int)
        .help("worker count")
        .defaultText("4")
        .valueName("N");

    try std.testing.expectEqualStrings("threads", meta.long.?);
    try std.testing.expect(meta.short == 't');
    try std.testing.expect(meta.form == .option);
    try std.testing.expect(meta.value_kind == .int);
    try std.testing.expect(meta.cardinality == .one);
    try std.testing.expectEqualStrings("worker count", meta.description);
}
