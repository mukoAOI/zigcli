//! Unified comptime type parser: `parseValue(T, text)`.
//!
//! Independent of Parser / Validator / Help — only converts text → T.
//! Allocator is required only for owned slices (`[]T` where T ≠ u8).

const std = @import("std");
const Allocator = std.mem.Allocator;
const Path = @import("path.zig").Path;

/// Domain errors for type conversion (library does not print).
pub const ParseValueError = error{
    InvalidBool,
    InvalidInt,
    InvalidFloat,
    InvalidEnum,
    InvalidArray,
    InvalidSlice,
    InvalidValue,
    EmptyInput,
    UnsupportedType,
};

pub const ParseValueAllocError = ParseValueError || Allocator.Error;

/// Parse a single argv fragment into `T` without allocating.
///
/// Supported:
/// - integers / floats
/// - `bool` (`true`/`false`/`1`/`0`/`yes`/`no`/`on`/`off`, case-insensitive)
/// - enums (match field / tag names)
/// - `?T` (empty → null)
/// - `[]const u8` (zero-copy borrow)
/// - `[N]T` (comma-separated)
/// - `Path`
/// - custom types with `pub fn parseCli(text: []const u8) !T` (or returning `T`)
pub fn parseValue(comptime T: type, text: []const u8) ParseValueError!T {
    if (comptime hasParseCli(T)) {
        return invokeParseCli(T, text);
    }

    if (T == []const u8) {
        return text;
    }

    if (T == Path) {
        return Path.parseCli(text);
    }

    const info = @typeInfo(T);
    switch (info) {
        .bool => return parseBool(text),
        .int => return std.fmt.parseInt(T, text, 0) catch return error.InvalidInt,
        .float => return std.fmt.parseFloat(T, text) catch return error.InvalidFloat,
        .@"enum" => return parseEnum(T, text),
        .optional => |opt| {
            if (text.len == 0) return null;
            return try parseValue(opt.child, text);
        },
        .array => |arr| return parseArray(arr.child, arr.len, text),
        .pointer => |ptr| {
            if (ptr.size == .slice and ptr.child == u8) {
                return text;
            }
            return error.UnsupportedType;
        },
        else => return error.UnsupportedType,
    }
}

/// Parse types that need an allocator (currently owned `[]E` element slices).
///
/// `[]const u8` / `[]u8` still borrow and ignore the allocator.
pub fn parseValueAlloc(comptime T: type, allocator: Allocator, text: []const u8) ParseValueAllocError!T {
    if (comptime hasParseCliAlloc(T)) {
        return T.parseCli(allocator, text);
    }

    const info = @typeInfo(T);
    switch (info) {
        .pointer => |ptr| {
            if (ptr.size == .slice) {
                if (ptr.child == u8) return text;
                return try parseOwnedSlice(ptr.child, allocator, text);
            }
        },
        else => {},
    }
    return parseValue(T, text);
}

fn hasParseCli(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .@"struct", .@"enum", .@"union", .@"opaque" => @hasDecl(T, "parseCli") and !hasParseCliAlloc(T),
        else => false,
    };
}

fn hasParseCliAlloc(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .@"struct", .@"enum", .@"union", .@"opaque" => blk: {
            if (!@hasDecl(T, "parseCli")) break :blk false;
            // Heuristic: two-parameter parseCli means (allocator, text).
            const info = @typeInfo(@TypeOf(T.parseCli));
            break :blk info == .@"fn" and info.@"fn".params.len == 2;
        },
        else => false,
    };
}

fn invokeParseCli(comptime T: type, text: []const u8) ParseValueError!T {
    const result = T.parseCli(text);
    const R = @TypeOf(result);
    if (@typeInfo(R) == .error_union) {
        return result catch return error.InvalidValue;
    }
    return result;
}

fn parseBool(text: []const u8) ParseValueError!bool {
    if (eqlIgnoreCase(text, "true") or eqlIgnoreCase(text, "1") or
        eqlIgnoreCase(text, "yes") or eqlIgnoreCase(text, "on"))
        return true;
    if (eqlIgnoreCase(text, "false") or eqlIgnoreCase(text, "0") or
        eqlIgnoreCase(text, "no") or eqlIgnoreCase(text, "off"))
        return false;
    return error.InvalidBool;
}

fn parseEnum(comptime E: type, text: []const u8) ParseValueError!E {
    inline for (std.meta.fields(E)) |field| {
        if (std.mem.eql(u8, field.name, text)) {
            return @field(E, field.name);
        }
    }
    // Case-insensitive fallback for UX.
    inline for (std.meta.fields(E)) |field| {
        if (eqlIgnoreCase(field.name, text)) {
            return @field(E, field.name);
        }
    }
    return error.InvalidEnum;
}

fn parseArray(comptime E: type, comptime N: usize, text: []const u8) ParseValueError![N]E {
    if (N == 0) {
        if (text.len == 0) return .{};
        return error.InvalidArray;
    }
    var out: [N]E = undefined;
    var it = std.mem.splitScalar(u8, text, ',');
    var i: usize = 0;
    while (it.next()) |part_raw| {
        const part = std.mem.trim(u8, part_raw, " \t");
        if (part.len == 0 and i == 0 and text.len == 0) break;
        if (i >= N) return error.InvalidArray;
        out[i] = try parseValue(E, part);
        i += 1;
    }
    if (i != N) return error.InvalidArray;
    return out;
}

fn parseOwnedSlice(comptime E: type, allocator: Allocator, text: []const u8) ParseValueAllocError![]E {
    if (text.len == 0) {
        return try allocator.alloc(E, 0);
    }
    var count: usize = 1;
    for (text) |c| {
        if (c == ',') count += 1;
    }
    const out = try allocator.alloc(E, count);
    errdefer allocator.free(out);

    var it = std.mem.splitScalar(u8, text, ',');
    var i: usize = 0;
    while (it.next()) |part_raw| : (i += 1) {
        const part = std.mem.trim(u8, part_raw, " \t");
        out[i] = try parseValue(E, part);
    }
    if (i != count) return error.InvalidSlice;
    return out;
}

fn eqlIgnoreCase(a: []const u8, b: []const u8) bool {
    return std.ascii.eqlIgnoreCase(a, b);
}

test "parseValue integers and floats" {
    try std.testing.expectEqual(@as(u32, 42), try parseValue(u32, "42"));
    try std.testing.expectEqual(@as(i32, -7), try parseValue(i32, "-7"));
    try std.testing.expectEqual(@as(f32, 3.5), try parseValue(f32, "3.5"));
    try std.testing.expectError(error.InvalidInt, parseValue(u8, "x"));
}

test "parseValue bool" {
    try std.testing.expectEqual(true, try parseValue(bool, "true"));
    try std.testing.expectEqual(true, try parseValue(bool, "YES"));
    try std.testing.expectEqual(false, try parseValue(bool, "off"));
    try std.testing.expectError(error.InvalidBool, parseValue(bool, "maybe"));
}

test "parseValue enum and optional" {
    const Color = enum { red, green, blue };
    try std.testing.expectEqual(Color.green, try parseValue(Color, "green"));
    try std.testing.expectEqual(Color.red, try parseValue(Color, "RED"));

    try std.testing.expect((try parseValue(?u32, "")) == null);
    try std.testing.expectEqual(@as(u32, 9), (try parseValue(?u32, "9")).?);
}

test "parseValue slice borrow and array" {
    const s = try parseValue([]const u8, "hello");
    try std.testing.expectEqualStrings("hello", s);

    const arr = try parseValue([3]u8, "1,2,3");
    try std.testing.expectEqual(@as(u8, 1), arr[0]);
    try std.testing.expectEqual(@as(u8, 3), arr[2]);
    try std.testing.expectError(error.InvalidArray, parseValue([2]u8, "1"));
}

test "parseValue Path and custom type" {
    const p = try parseValue(Path, "C:\\tmp\\a");
    try std.testing.expectEqualStrings("C:\\tmp\\a", p.raw);

    const Port = struct {
        value: u16,
        pub fn parseCli(text: []const u8) ParseValueError!@This() {
            return .{ .value = try parseValue(u16, text) };
        }
    };
    const port = try parseValue(Port, "8080");
    try std.testing.expectEqual(@as(u16, 8080), port.value);
}

test "parseValueAlloc owned slice" {
    const nums = try parseValueAlloc([]u32, std.testing.allocator, "1, 2, 3");
    defer std.testing.allocator.free(nums);
    try std.testing.expectEqual(@as(usize, 3), nums.len);
    try std.testing.expectEqual(@as(u32, 2), nums[1]);
}
