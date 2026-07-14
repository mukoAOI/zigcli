//! Closest-string suggestion (Did you mean …).
//!
//! Pure utility: no I/O. Used by Diagnostic when mapping unknown names.

const std = @import("std");

/// Classic Levenshtein edit distance.
pub fn editDistance(a: []const u8, b: []const u8) usize {
    if (a.len == 0) return b.len;
    if (b.len == 0) return a.len;

    // Two-row DP to keep stack small for typical CLI name lengths.
    var prev_buf: [64]usize = undefined;
    var curr_buf: [64]usize = undefined;
    if (b.len >= prev_buf.len) {
        // Fallback for unusually long names: allocate-free clamp via simple walk.
        return editDistanceUnbounded(a, b);
    }

    const prev = prev_buf[0 .. b.len + 1];
    const curr = curr_buf[0 .. b.len + 1];
    for (prev, 0..) |*c, i| c.* = i;

    for (a, 0..) |ca, i| {
        curr[0] = i + 1;
        for (b, 0..) |cb, j| {
            const cost: usize = if (ca == cb) 0 else 1;
            curr[j + 1] = @min(
                @min(curr[j] + 1, prev[j + 1] + 1),
                prev[j] + cost,
            );
        }
        @memcpy(prev, curr);
    }
    return prev[b.len];
}

fn editDistanceUnbounded(a: []const u8, b: []const u8) usize {
    // Intentionally simple O(n*m) with fixed max comparison budget via
    // early exit when lengths differ a lot — allocator-free.
    if (a.len > b.len + 8 or b.len > a.len + 8) {
        return @max(a.len, b.len);
    }
    var dist: usize = 0;
    const n = @min(a.len, b.len);
    for (0..n) |i| {
        if (a[i] != b[i]) dist += 1;
    }
    return dist + (a.len - n) + (b.len - n);
}

/// Returns the closest candidate within `max_distance`, or null.
pub fn suggestClosest(
    needle: []const u8,
    candidates: []const []const u8,
    max_distance: usize,
) ?[]const u8 {
    var best: ?[]const u8 = null;
    var best_dist: usize = std.math.maxInt(usize);
    for (candidates) |c| {
        const d = editDistance(needle, c);
        if (d < best_dist and d <= max_distance) {
            best_dist = d;
            best = c;
        }
    }
    return best;
}

test "editDistance basic" {
    try std.testing.expectEqual(@as(usize, 0), editDistance("verbose", "verbose"));
    try std.testing.expectEqual(@as(usize, 1), editDistance("verbos", "verbose"));
    try std.testing.expectEqual(@as(usize, 1), editDistance("outpt", "output"));
    try std.testing.expectEqual(@as(usize, 2), editDistance("oupt", "output"));
}

test "suggestClosest picks nearest" {
    const cands = [_][]const u8{ "verbose", "output", "version" };
    try std.testing.expectEqualStrings(
        "verbose",
        suggestClosest("verbos", &cands, 2).?,
    );
    try std.testing.expect(suggestClosest("zzzz", &cands, 1) == null);
}
