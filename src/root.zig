//! zigcli — Zig CLI framework (public package root).
//!
//! Requires Zig 0.16.0+. Import as `@import("cli")`.

const core_metadata = @import("core/metadata.zig");
const parser_root = @import("parser/root.zig");
const diagnostic_root = @import("diagnostic/root.zig");
const typing_root = @import("typing/root.zig");
const validator_root = @import("validator/root.zig");
const help_root = @import("help/root.zig");
const completion_root = @import("completion/root.zig");
const derive_root = @import("derive/root.zig");
const app_root = @import("app/root.zig");

pub const ValueKind = core_metadata.ValueKind;
pub const Cardinality = core_metadata.Cardinality;
pub const OptionForm = core_metadata.OptionForm;

pub const OptionMeta = core_metadata.OptionMeta;
pub const OptionBuilder = core_metadata.OptionBuilder;
pub const ArgumentMeta = core_metadata.ArgumentMeta;
pub const ArgumentBuilder = core_metadata.ArgumentBuilder;
pub const CommandMeta = core_metadata.CommandMeta;
pub const CommandBuilder = core_metadata.CommandBuilder;

pub const commandRoot = core_metadata.commandRoot;

pub const Token = parser_root.Token;
pub const ShortOption = parser_root.ShortOption;
pub const LongOption = parser_root.LongOption;
pub const Tokenizer = parser_root.Tokenizer;
pub const tokenizeAll = parser_root.tokenizeAll;
pub const classify = parser_root.classify;

pub const ParseResult = parser_root.ParseResult;
pub const ParseIssue = parser_root.ParseIssue;
pub const ParseOutput = parser_root.ParseOutput;
pub const OptionOccurrence = parser_root.OptionOccurrence;
pub const parseTokens = parser_root.parseTokens;
pub const parseArgv = parser_root.parseArgv;

pub const Severity = diagnostic_root.Severity;
pub const DiagnosticCode = diagnostic_root.Code;
pub const Diagnostic = diagnostic_root.Diagnostic;
pub const fromParseIssue = diagnostic_root.fromParseIssue;
pub const fromValidationIssue = diagnostic_root.fromValidationIssue;
pub const diagnose = diagnostic_root.diagnose;
pub const collectLongNames = diagnostic_root.collectLongNames;
pub const collectSubcommandNames = diagnostic_root.collectSubcommandNames;
pub const editDistance = diagnostic_root.editDistance;
pub const suggestClosest = diagnostic_root.suggestClosest;

pub const Path = typing_root.Path;
pub const ParseValueError = typing_root.ParseValueError;
pub const ParseValueAllocError = typing_root.ParseValueAllocError;
pub const parseValue = typing_root.parseValue;
pub const parseValueAlloc = typing_root.parseValueAlloc;

pub const ValidationContext = validator_root.ValidationContext;
pub const ValidationIssue = validator_root.ValidationIssue;
pub const Validator = validator_root.Validator;
pub const validate = validator_root.validate;
pub const validateAll = validator_root.validateAll;
pub const globMatch = validator_root.globMatch;
pub const Registry = validator_root.Registry;
pub const validateParseResult = validator_root.validateParseResult;

pub const HelpStyle = help_root.HelpStyle;
pub const renderHelp = help_root.renderHelp;
pub const renderHelpStyled = help_root.renderHelpStyled;
pub const optionLabelAlloc = help_root.optionLabelAlloc;
pub const argumentLabelAlloc = help_root.argumentLabelAlloc;

pub const Shell = completion_root.Shell;
pub const generateCompletion = completion_root.generate;

pub const FieldSpec = derive_root.FieldSpec;
pub const fieldSpec = derive_root.fieldSpec;
pub const CommandSpec = derive_root.CommandSpec;
pub const commandSpec = derive_root.commandSpec;
pub const TypeShape = derive_root.TypeShape;
pub const shapeOf = derive_root.shapeOf;
pub const OptionsArray = derive_root.OptionsArray;
pub const optionsFromStruct = derive_root.optionsFromStruct;
pub const ArgumentsArray = derive_root.ArgumentsArray;
pub const argumentsFromStruct = derive_root.argumentsFromStruct;
pub const subcommandCount = derive_root.subcommandCount;
pub const Derived = derive_root.Derived;

pub const App = app_root.App;
pub const Command = app_root.Command;
pub const AppError = app_root.AppError;
pub const AppAllocError = app_root.AppAllocError;
pub const AppCheckedError = app_root.AppCheckedError;
pub const BindError = app_root.BindError;
pub const BindAllocError = app_root.BindAllocError;
pub const bindConfig = app_root.bindConfig;
pub const bindConfigAlloc = app_root.bindConfigAlloc;
pub const validateConfig = app_root.validateConfig;

/// Library semantic version.
pub const version = "0.1.0";

test {
    _ = core_metadata;
    _ = parser_root;
    _ = diagnostic_root;
    _ = typing_root;
    _ = validator_root;
    _ = help_root;
    _ = completion_root;
    _ = derive_root;
    _ = app_root;
}
