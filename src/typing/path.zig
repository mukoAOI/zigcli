//! Path newtype: still `[]const u8`, marked for validators / help.
//!
//! Zero-copy — borrows the original argv text.

/// Filesystem path as seen on the command line.
pub const Path = struct {
    raw: []const u8,

    /// Duck-typed hook used by `parseValue`.
    pub fn parseCli(text: []const u8) Path {
        return .{ .raw = text };
    }

    pub fn bytes(self: Path) []const u8 {
        return self.raw;
    }
};

test "Path.parseCli borrows" {
    const std = @import("std");
    const p = Path.parseCli("/tmp/a");
    try std.testing.expectEqualStrings("/tmp/a", p.bytes());
}
