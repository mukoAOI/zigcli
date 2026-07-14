//! Typing package facade — convert argv text to Zig values.

const path_mod = @import("path.zig");
const parse_mod = @import("parse_value.zig");

pub const Path = path_mod.Path;
pub const ParseValueError = parse_mod.ParseValueError;
pub const ParseValueAllocError = parse_mod.ParseValueAllocError;
pub const parseValue = parse_mod.parseValue;
pub const parseValueAlloc = parse_mod.parseValueAlloc;

test {
    _ = path_mod;
    _ = parse_mod;
}
