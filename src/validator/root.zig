//! Validator package facade.

const context = @import("context.zig");
const glob_mod = @import("glob.zig");
const builtins = @import("builtins.zig");
const registry_mod = @import("registry.zig");

pub const ValidationContext = context.ValidationContext;
pub const ValidationIssue = context.ValidationIssue;

pub const Validator = builtins.Validator;
pub const validate = builtins.validate;
pub const validateAll = builtins.validateAll;

pub const globMatch = glob_mod.globMatch;

pub const Registry = registry_mod.Registry;
pub const validateParseResult = registry_mod.validateParseResult;

test {
    _ = context;
    _ = glob_mod;
    _ = builtins;
    _ = registry_mod;
}
