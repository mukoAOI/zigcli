//! Positional argument metadata and builder.
//!
//! Positionals are ordered values that are not options (`FILE`, `ARGS...`).

const std = @import("std");
const kinds = @import("kinds.zig");

/// Immutable description of a positional argument.
pub const ArgumentMeta = struct {
    /// Usage name (e.g. `"FILE"`, `"PATH"`).
    name: []const u8,
    description: []const u8 = "",
    value_kind: kinds.ValueKind = .string,
    cardinality: kinds.Cardinality = .one,
    required: bool = true,
    default_text: ?[]const u8 = null,
    validator_id: ?u32 = null,
    completion_id: ?u32 = null,
    type_id: ?u32 = null,
};

/// Fluent builder over a mutable `ArgumentMeta`.
pub const ArgumentBuilder = struct {
    meta: *ArgumentMeta,

    pub fn help(self: ArgumentBuilder, text: []const u8) ArgumentBuilder {
        self.meta.description = text;
        return self;
    }

    pub fn valueKind(self: ArgumentBuilder, kind: kinds.ValueKind) ArgumentBuilder {
        self.meta.value_kind = kind;
        return self;
    }

    pub fn cardinality(self: ArgumentBuilder, card: kinds.Cardinality) ArgumentBuilder {
        self.meta.cardinality = card;
        if (card == .optional or card == .many) {
            self.meta.required = false;
        }
        return self;
    }

    pub fn optional(self: ArgumentBuilder) ArgumentBuilder {
        self.meta.required = false;
        self.meta.cardinality = .optional;
        return self;
    }

    pub fn required(self: ArgumentBuilder) ArgumentBuilder {
        self.meta.required = true;
        return self;
    }

    pub fn defaultText(self: ArgumentBuilder, text: []const u8) ArgumentBuilder {
        self.meta.default_text = text;
        return self;
    }

    pub fn finish(self: ArgumentBuilder) *ArgumentMeta {
        return self.meta;
    }
};

test "ArgumentBuilder optional positional" {
    var meta = ArgumentMeta{ .name = "FILE" };
    _ = (ArgumentBuilder{ .meta = &meta })
        .help("input file")
        .valueKind(.path)
        .optional();

    try std.testing.expect(!meta.required);
    try std.testing.expect(meta.cardinality == .optional);
    try std.testing.expect(meta.value_kind == .path);
}
