//! Left-column labels for options / arguments used by the help renderer.

const std = @import("std");
const Allocator = std.mem.Allocator;
const OptionMeta = @import("../core/option.zig").OptionMeta;
const ArgumentMeta = @import("../core/argument.zig").ArgumentMeta;
const kinds = @import("../core/kinds.zig");

/// Formats `-v, --verbose <FILE>` style label into `buf` (or allocates).
pub fn optionLabelAlloc(allocator: Allocator, opt: *const OptionMeta) Allocator.Error![]u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);

    var wrote_name = false;
    if (opt.short) |s| {
        try list.append(allocator, '-');
        try list.append(allocator, s);
        wrote_name = true;
    }
    if (opt.long) |long| {
        if (wrote_name) try list.appendSlice(allocator, ", ");
        try list.appendSlice(allocator, "--");
        try list.appendSlice(allocator, long);
        wrote_name = true;
    }
    if (!wrote_name) {
        try list.appendSlice(allocator, "<option>");
    }

    if (opt.cardinality != .zero) {
        try list.append(allocator, ' ');
        const vname = opt.value_name orelse defaultValueName(opt.value_kind);
        switch (opt.cardinality) {
            .optional => {
                try list.append(allocator, '[');
                try list.appendSlice(allocator, vname);
                try list.append(allocator, ']');
            },
            .many => {
                try list.append(allocator, '[');
                try list.appendSlice(allocator, vname);
                try list.appendSlice(allocator, "]...");
            },
            .at_least_one => {
                try list.append(allocator, '<');
                try list.appendSlice(allocator, vname);
                try list.appendSlice(allocator, ">...");
            },
            .one => {
                try list.append(allocator, '<');
                try list.appendSlice(allocator, vname);
                try list.append(allocator, '>');
            },
            .zero => {},
        }
    }

    return try list.toOwnedSlice(allocator);
}

fn defaultValueName(kind: kinds.ValueKind) []const u8 {
    return switch (kind) {
        .bool => "BOOL",
        .int => "INT",
        .float => "FLOAT",
        .string => "STRING",
        .path => "PATH",
        .@"enum" => "ENUM",
        .custom => "VALUE",
    };
}

/// Formats `<NAME>` / `[NAME]` / `<NAME>...` for a positional.
pub fn argumentLabelAlloc(allocator: Allocator, arg: *const ArgumentMeta) Allocator.Error![]u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);

    switch (arg.cardinality) {
        .optional => {
            try list.append(allocator, '[');
            try list.appendSlice(allocator, arg.name);
            try list.append(allocator, ']');
        },
        .many => {
            try list.append(allocator, '[');
            try list.appendSlice(allocator, arg.name);
            try list.appendSlice(allocator, "]...");
        },
        .at_least_one => {
            try list.append(allocator, '<');
            try list.appendSlice(allocator, arg.name);
            try list.appendSlice(allocator, ">...");
        },
        .zero, .one => {
            if (arg.required) {
                try list.append(allocator, '<');
                try list.appendSlice(allocator, arg.name);
                try list.append(allocator, '>');
            } else {
                try list.append(allocator, '[');
                try list.appendSlice(allocator, arg.name);
                try list.append(allocator, ']');
            }
        },
    }
    return try list.toOwnedSlice(allocator);
}

test "optionLabelAlloc" {
    const opt = OptionMeta{
        .long = "output",
        .short = 'o',
        .form = .option,
        .value_kind = .path,
        .cardinality = .one,
        .value_name = "FILE",
    };
    const label = try optionLabelAlloc(std.testing.allocator, &opt);
    defer std.testing.allocator.free(label);
    try std.testing.expectEqualStrings("-o, --output <FILE>", label);
}

test "argumentLabelAlloc" {
    const arg = ArgumentMeta{ .name = "SCRIPT", .required = true };
    const label = try argumentLabelAlloc(std.testing.allocator, &arg);
    defer std.testing.allocator.free(label);
    try std.testing.expectEqualStrings("<SCRIPT>", label);
}
