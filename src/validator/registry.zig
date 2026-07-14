//! Validator registry keyed by opaque `validator_id` from Metadata.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const builtins = @import("builtins.zig");
const context = @import("context.zig");
const ParseResult = @import("../parser/result.zig").ParseResult;

pub const Validator = builtins.Validator;
pub const ValidationIssue = context.ValidationIssue;
pub const ValidationContext = context.ValidationContext;

/// Maps `validator_id` → `Validator` (id is the append index).
pub const Registry = struct {
    allocator: Allocator,
    entries: std.ArrayList(Validator) = .empty,

    pub fn init(allocator: Allocator) Registry {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Registry) void {
        self.entries.deinit(self.allocator);
        self.* = undefined;
    }

    /// Registers a validator; returns the id to store on Metadata.
    pub fn add(self: *Registry, v: Validator) Allocator.Error!u32 {
        const id: u32 = @intCast(self.entries.items.len);
        try self.entries.append(self.allocator, v);
        return id;
    }

    pub fn get(self: *const Registry, id: u32) ?Validator {
        if (id >= self.entries.items.len) return null;
        return self.entries.items[id];
    }
};

/// Validates options/arguments on a successful parse using Metadata + Registry.
pub fn validateParseResult(
    io: Io,
    result: *const ParseResult,
    registry: *const Registry,
) ?ValidationIssue {
    const cmd = result.command;

    for (cmd.options) |*opt| {
        const occ = findOccurrence(result, opt);
        const present = occ != null;
        const values: []const []const u8 = if (occ) |o| o.values else &.{};
        const ctx = ValidationContext{
            .name = opt.displayName(),
            .present = present,
            .values = values,
        };

        if (opt.required) {
            if (builtins.validate(io, .required, ctx)) |issue| return issue;
        }
        if (opt.validator_id) |vid| {
            if (registry.get(vid)) |v| {
                if (!present and v != .required) continue;
                if (builtins.validate(io, v, ctx)) |issue| return issue;
            }
        }
    }

    for (cmd.arguments, 0..) |*arg, i| {
        const present = i < result.positionals.len;
        const values: []const []const u8 = if (present)
            result.positionals[i .. i + 1]
        else
            &.{};
        const ctx = ValidationContext{
            .name = arg.name,
            .present = present,
            .values = values,
        };
        if (arg.required) {
            if (builtins.validate(io, .required, ctx)) |issue| return issue;
        }
        if (arg.validator_id) |vid| {
            if (registry.get(vid)) |v| {
                if (!present and v != .required) continue;
                if (builtins.validate(io, v, ctx)) |issue| return issue;
            }
        }
    }

    return null;
}

fn findOccurrence(result: *const ParseResult, opt: *const @import("../core/option.zig").OptionMeta) ?@import("../parser/result.zig").OptionOccurrence {
    for (result.options) |occ| {
        if (occ.meta == opt) return occ;
        if (opt.long) |long| {
            if (occ.meta.matchesLong(long)) return occ;
        } else if (opt.short) |s| {
            if (occ.meta.matchesShort(s)) return occ;
        }
    }
    return null;
}

test "registry add/get" {
    var reg = Registry.init(std.testing.allocator);
    defer reg.deinit();
    const id = try reg.add(.{ .range_int = .{ .min = 0, .max = 10 } });
    try std.testing.expect(reg.get(id) != null);
    try std.testing.expect(reg.get(99) == null);
}
