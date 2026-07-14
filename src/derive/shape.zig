//! Map Zig field types → ValueKind / OptionForm / Cardinality.

const kinds = @import("../core/kinds.zig");
const Path = @import("../typing/path.zig").Path;

pub const TypeShape = struct {
    value_kind: kinds.ValueKind,
    form: kinds.OptionForm,
    cardinality: kinds.Cardinality,
    /// Underlying type after unwrapping optional (for docs / later binding).
    core_type: type,
    is_optional: bool,
};

/// Infers CLI shape from a Zig type.
pub fn shapeOf(comptime T: type) TypeShape {
    const info = @typeInfo(T);
    switch (info) {
        .optional => |opt| {
            var inner = shapeOf(opt.child);
            inner.is_optional = true;
            if (inner.form == .flag) {
                // optional bool still a flag / presence with optional semantics
                inner.cardinality = .zero;
            } else if (inner.cardinality == .many) {
                // `?[]E` keeps multi-value semantics.
            } else {
                inner.cardinality = .optional;
            }
            return inner;
        },
        .bool => return .{
            .value_kind = .bool,
            .form = .flag,
            .cardinality = .zero,
            .core_type = T,
            .is_optional = false,
        },
        .int => return .{
            .value_kind = .int,
            .form = .option,
            .cardinality = .one,
            .core_type = T,
            .is_optional = false,
        },
        .float => return .{
            .value_kind = .float,
            .form = .option,
            .cardinality = .one,
            .core_type = T,
            .is_optional = false,
        },
        .@"enum" => return .{
            .value_kind = .@"enum",
            .form = .option,
            .cardinality = .one,
            .core_type = T,
            .is_optional = false,
        },
        .pointer => |ptr| {
            if (ptr.size == .slice and ptr.child == u8) {
                return .{
                    .value_kind = .string,
                    .form = .option,
                    .cardinality = .one,
                    .core_type = T,
                    .is_optional = false,
                };
            }
            if (ptr.size == .slice) {
                // `[]E` (E != u8) is a repeatable / multi-value option.
                const elem = shapeOf(ptr.child);
                return .{
                    .value_kind = elem.value_kind,
                    .form = .option,
                    .cardinality = .many,
                    .core_type = T,
                    .is_optional = false,
                };
            }
            return .{
                .value_kind = .custom,
                .form = .option,
                .cardinality = .one,
                .core_type = T,
                .is_optional = false,
            };
        },
        .@"struct" => {
            if (T == Path) {
                return .{
                    .value_kind = .path,
                    .form = .option,
                    .cardinality = .one,
                    .core_type = T,
                    .is_optional = false,
                };
            }
            return .{
                .value_kind = .custom,
                .form = .option,
                .cardinality = .one,
                .core_type = T,
                .is_optional = false,
            };
        },
        else => return .{
            .value_kind = .custom,
            .form = .option,
            .cardinality = .one,
            .core_type = T,
            .is_optional = false,
        },
    }
}

test "shapeOf bool and optional string" {
    const std = @import("std");
    const b = shapeOf(bool);
    try std.testing.expect(b.form == .flag);
    const s = shapeOf(?[]const u8);
    try std.testing.expect(s.value_kind == .string);
    try std.testing.expect(s.cardinality == .optional);
    try std.testing.expect(s.is_optional);
}
