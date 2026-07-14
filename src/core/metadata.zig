//! Core metadata facade for the CLI framework.
//!
//! Re-exports kinds and command-tree types. Later milestones (parser, help,
//! completion, validator) depend on these types — never the reverse.

const command = @import("command.zig");
const kinds = @import("kinds.zig");
const option = @import("option.zig");
const argument = @import("argument.zig");

pub const ValueKind = kinds.ValueKind;
pub const Cardinality = kinds.Cardinality;
pub const OptionForm = kinds.OptionForm;

pub const OptionMeta = option.OptionMeta;
pub const OptionBuilder = option.OptionBuilder;
pub const ArgumentMeta = argument.ArgumentMeta;
pub const ArgumentBuilder = argument.ArgumentBuilder;
pub const CommandMeta = command.CommandMeta;
pub const CommandBuilder = command.CommandBuilder;

/// Convenience: create a root command builder.
pub fn commandRoot(allocator: std.mem.Allocator, name: []const u8) CommandBuilder {
    return CommandBuilder.init(allocator, name);
}

const std = @import("std");

test "metadata facade builds a small app" {
    var app = commandRoot(std.testing.allocator, "demo");
    defer app.deinit();

    _ = app.help("demo application");
    _ = (try app.flag("verbose")).short('v');
    _ = (try app.opt("threads", .int)).short('t').defaultText("4");

    const run = try app.subcommand("run");
    _ = (try run.arg("SCRIPT")).valueKind(.path);

    const meta = app.seal();
    try std.testing.expectEqualStrings("demo", meta.name);
    try std.testing.expectEqual(@as(usize, 2), meta.options.len);
    try std.testing.expect(meta.findSubcommand("run") != null);
}

test {
    _ = kinds;
    _ = option;
    _ = argument;
    _ = command;
}
