//! Help package facade — Metadata → aligned help text.

const format_mod = @import("format.zig");
const render_mod = @import("render.zig");

pub const optionLabelAlloc = format_mod.optionLabelAlloc;
pub const argumentLabelAlloc = format_mod.argumentLabelAlloc;

pub const HelpStyle = render_mod.HelpStyle;
pub const renderHelp = render_mod.renderHelp;
pub const renderHelpStyled = render_mod.renderHelpStyled;

test {
    _ = format_mod;
    _ = render_mod;
}
