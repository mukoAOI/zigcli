//! Unified completion script generation API.

const std = @import("std");
const Allocator = std.mem.Allocator;
const CommandMeta = @import("../core/command.zig").CommandMeta;
const bash = @import("bash.zig");
const zsh = @import("zsh.zig");
const fish = @import("fish.zig");
const powershell = @import("powershell.zig");

/// Target shell for completion scripts.
pub const Shell = enum {
    bash,
    zsh,
    fish,
    powershell,
};

/// Generates a completion script for `root` targeting `shell`.
///
/// The returned slice is owned by the caller. Library does not install or print it.
pub fn generate(
    allocator: Allocator,
    shell: Shell,
    root: *const CommandMeta,
) Allocator.Error![]u8 {
    return switch (shell) {
        .bash => bash.generate(allocator, root),
        .zsh => zsh.generate(allocator, root),
        .fish => fish.generate(allocator, root),
        .powershell => powershell.generate(allocator, root),
    };
}

fn buildDemo(allocator: Allocator) !@import("../core/command.zig").CommandBuilder {
    const CommandBuilder = @import("../core/command.zig").CommandBuilder;
    var root = CommandBuilder.init(allocator, "demo");
    errdefer root.deinit();
    _ = (try root.flag("verbose")).short('v').help("more output");
    const run = try root.subcommand("run");
    _ = run.help("run a script");
    _ = (try run.flag("dry-run")).short('n');
    _ = root.seal();
    return root;
}

test "generate bash contains complete and options" {
    var root = try buildDemo(std.testing.allocator);
    defer root.deinit();
    const script = try generate(std.testing.allocator, .bash, &root.meta);
    defer std.testing.allocator.free(script);
    try std.testing.expect(std.mem.indexOf(u8, script, "complete -F") != null);
    try std.testing.expect(std.mem.indexOf(u8, script, "--verbose") != null);
    try std.testing.expect(std.mem.indexOf(u8, script, "demo_run") != null);
}

test "generate zsh fish powershell" {
    var root = try buildDemo(std.testing.allocator);
    defer root.deinit();

    const z = try generate(std.testing.allocator, .zsh, &root.meta);
    defer std.testing.allocator.free(z);
    try std.testing.expect(std.mem.indexOf(u8, z, "#compdef demo") != null);

    const f = try generate(std.testing.allocator, .fish, &root.meta);
    defer std.testing.allocator.free(f);
    try std.testing.expect(std.mem.indexOf(u8, f, "complete -c demo") != null);
    try std.testing.expect(std.mem.indexOf(u8, f, "-l verbose") != null);

    const p = try generate(std.testing.allocator, .powershell, &root.meta);
    defer std.testing.allocator.free(p);
    try std.testing.expect(std.mem.indexOf(u8, p, "Register-ArgumentCompleter") != null);
    try std.testing.expect(std.mem.indexOf(u8, p, "--verbose") != null);
}
