//! Diagnostic package facade.

const diagnostic_mod = @import("diagnostic.zig");
const suggest_mod = @import("suggest.zig");

pub const Severity = diagnostic_mod.Severity;
pub const Code = diagnostic_mod.Code;
pub const Diagnostic = diagnostic_mod.Diagnostic;
pub const fromParseIssue = diagnostic_mod.fromParseIssue;
pub const fromValidationIssue = diagnostic_mod.fromValidationIssue;
pub const diagnose = diagnostic_mod.diagnose;
pub const collectLongNames = diagnostic_mod.collectLongNames;
pub const collectSubcommandNames = diagnostic_mod.collectSubcommandNames;

pub const editDistance = suggest_mod.editDistance;
pub const suggestClosest = suggest_mod.suggestClosest;

test {
    _ = diagnostic_mod;
    _ = suggest_mod;
}
