//! Completion package facade — Metadata → shell scripts.

const generate_mod = @import("generate.zig");
const common_mod = @import("common.zig");

pub const Shell = generate_mod.Shell;
pub const generate = generate_mod.generate;

pub const appendWords = common_mod.appendWords;
pub const walk = common_mod.walk;

test {
    _ = common_mod;
    _ = generate_mod;
    _ = @import("bash.zig");
    _ = @import("zsh.zig");
    _ = @import("fish.zig");
    _ = @import("powershell.zig");
}
