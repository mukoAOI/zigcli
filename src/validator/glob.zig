//! Glob-style pattern matching (`*` / `?`) for CLI “regex” without a regex crate.
//!
//! Full regex engines can be plugged via `Validator.regex` function pointers.

const std = @import("std");

/// Returns true if `text` matches glob `pattern`.
///
/// - `*` — any sequence (including empty)
/// - `?` — any single byte
/// - other bytes match literally
pub fn globMatch(pattern: []const u8, text: []const u8) bool {
    return match(pattern, 0, text, 0);
}

fn match(pattern: []const u8, pi: usize, text: []const u8, ti: usize) bool {
    var i = pi;
    var j = ti;
    while (i < pattern.len) {
        const pc = pattern[i];
        if (pc == '*') {
            // Collapse consecutive stars.
            while (i < pattern.len and pattern[i] == '*') i += 1;
            if (i == pattern.len) return true;
            var k = j;
            while (k <= text.len) : (k += 1) {
                if (match(pattern, i, text, k)) return true;
            }
            return false;
        }
        if (j >= text.len) return false;
        if (pc != '?' and pc != text[j]) return false;
        i += 1;
        j += 1;
    }
    return j == text.len;
}

test "globMatch" {
    try std.testing.expect(globMatch("*.zig", "main.zig"));
    try std.testing.expect(globMatch("file.?", "file.c"));
    try std.testing.expect(!globMatch("a*b", "ac"));
    try std.testing.expect(globMatch("a*b", "ab"));
    try std.testing.expect(globMatch("a*b", "axxb"));
}
