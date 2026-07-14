//! Parser package facade.

const token_mod = @import("token.zig");
const tokenizer_mod = @import("tokenizer.zig");
const result_mod = @import("result.zig");
const parse_mod = @import("parse.zig");

pub const Token = token_mod.Token;
pub const ShortOption = token_mod.ShortOption;
pub const LongOption = token_mod.LongOption;

pub const Tokenizer = tokenizer_mod.Tokenizer;
pub const tokenizeAll = tokenizer_mod.tokenizeAll;
pub const classify = tokenizer_mod.classify;

pub const ParseResult = result_mod.ParseResult;
pub const ParseIssue = result_mod.ParseIssue;
pub const ParseOutput = result_mod.ParseOutput;
pub const OptionOccurrence = result_mod.OptionOccurrence;

pub const parseTokens = parse_mod.parseTokens;
pub const parseArgv = parse_mod.parseArgv;

test {
    _ = token_mod;
    _ = tokenizer_mod;
    _ = result_mod;
    _ = parse_mod;
}
