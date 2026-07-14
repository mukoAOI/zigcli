//! Help text renderer driven purely by `CommandMeta` (no Parser dependency).

const std = @import("std");
const Allocator = std.mem.Allocator;
const CommandMeta = @import("../core/command.zig").CommandMeta;
const format = @import("format.zig");

/// Tunables for help layout.
pub const HelpStyle = struct {
    indent: usize = 2,
    column_gap: usize = 2,
};

/// Renders full help for a single command node.
pub fn renderHelp(allocator: Allocator, command: *const CommandMeta) Allocator.Error![]u8 {
    return renderHelpStyled(allocator, command, .{});
}

/// Renders help with custom layout style.
pub fn renderHelpStyled(
    allocator: Allocator,
    command: *const CommandMeta,
    style: HelpStyle,
) Allocator.Error![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    if (command.description.len != 0) {
        try out.appendSlice(allocator, command.description);
        try out.appendSlice(allocator, "\n\n");
    }

    try appendUsage(allocator, &out, command);
    try out.append(allocator, '\n');

    if (command.arguments.len != 0) {
        try out.append(allocator, '\n');
        try appendAlignedSection(allocator, &out, "Arguments:", style, command.arguments.len, struct {
            fn label(a: Allocator, i: usize, cmd: *const CommandMeta) Allocator.Error![]u8 {
                return format.argumentLabelAlloc(a, &cmd.arguments[i]);
            }
            fn desc(i: usize, cmd: *const CommandMeta) []const u8 {
                return cmd.arguments[i].description;
            }
            fn suffix(a: Allocator, i: usize, cmd: *const CommandMeta) Allocator.Error![]u8 {
                return argumentSuffixAlloc(a, &cmd.arguments[i]);
            }
        }, command);
    }

    if (command.options.len != 0) {
        try out.append(allocator, '\n');
        try appendAlignedSection(allocator, &out, "Options:", style, command.options.len, struct {
            fn label(a: Allocator, i: usize, cmd: *const CommandMeta) Allocator.Error![]u8 {
                return format.optionLabelAlloc(a, &cmd.options[i]);
            }
            fn desc(i: usize, cmd: *const CommandMeta) []const u8 {
                return cmd.options[i].description;
            }
            fn suffix(a: Allocator, i: usize, cmd: *const CommandMeta) Allocator.Error![]u8 {
                return optionSuffixAlloc(a, &cmd.options[i]);
            }
        }, command);
    }

    if (command.subcommands.len != 0) {
        try out.append(allocator, '\n');
        try appendCommands(allocator, &out, command, style);
    }

    if (command.examples.len != 0) {
        try out.append(allocator, '\n');
        try out.appendSlice(allocator, "Examples:\n");
        for (command.examples) |ex| {
            try appendIndent(allocator, &out, style.indent);
            try out.appendSlice(allocator, ex);
            try out.append(allocator, '\n');
        }
    }

    return try out.toOwnedSlice(allocator);
}

fn appendUsage(allocator: Allocator, out: *std.ArrayList(u8), command: *const CommandMeta) !void {
    try out.appendSlice(allocator, "Usage: ");

    // Walk ancestors leaf → root, then reverse to root → leaf.
    var chain_buf: [32]*const CommandMeta = undefined;
    var n: usize = 0;
    var cur: ?*const CommandMeta = command;
    while (cur) |c| {
        if (n >= chain_buf.len) break;
        chain_buf[n] = c;
        n += 1;
        cur = c.parent;
    }
    var i: usize = 0;
    while (i < n / 2) : (i += 1) {
        const tmp = chain_buf[i];
        chain_buf[i] = chain_buf[n - 1 - i];
        chain_buf[n - 1 - i] = tmp;
    }
    for (chain_buf[0..n], 0..) |c, idx| {
        if (idx != 0) try out.append(allocator, ' ');
        try out.appendSlice(allocator, c.name);
    }

    if (command.subcommands.len != 0) {
        try out.appendSlice(allocator, " [COMMAND]");
    }
    if (command.options.len != 0) {
        try out.appendSlice(allocator, " [OPTIONS]");
    }
    for (command.arguments) |*arg| {
        try out.append(allocator, ' ');
        const label = try format.argumentLabelAlloc(allocator, arg);
        defer allocator.free(label);
        try out.appendSlice(allocator, label);
    }
    try out.append(allocator, '\n');
}

fn appendIndent(allocator: Allocator, out: *std.ArrayList(u8), n: usize) !void {
    var i: usize = 0;
    while (i < n) : (i += 1) try out.append(allocator, ' ');
}

fn optionSuffixAlloc(allocator: Allocator, opt: *const @import("../core/option.zig").OptionMeta) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);
    if (opt.required) try list.appendSlice(allocator, " [required]");
    if (opt.default_text) |d| {
        try list.appendSlice(allocator, " [default: ");
        try list.appendSlice(allocator, d);
        try list.append(allocator, ']');
    }
    return try list.toOwnedSlice(allocator);
}

fn argumentSuffixAlloc(allocator: Allocator, arg: *const @import("../core/argument.zig").ArgumentMeta) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    errdefer list.deinit(allocator);
    if (arg.required) try list.appendSlice(allocator, " [required]");
    if (arg.default_text) |d| {
        try list.appendSlice(allocator, " [default: ");
        try list.appendSlice(allocator, d);
        try list.append(allocator, ']');
    }
    return try list.toOwnedSlice(allocator);
}

fn appendAlignedSection(
    allocator: Allocator,
    out: *std.ArrayList(u8),
    title: []const u8,
    style: HelpStyle,
    count: usize,
    comptime Hooks: type,
    command: *const CommandMeta,
) !void {
    try out.appendSlice(allocator, title);
    try out.append(allocator, '\n');

    var labels = try allocator.alloc([]u8, count);
    defer {
        for (labels) |l| allocator.free(l);
        allocator.free(labels);
    }
    var suffixes = try allocator.alloc([]u8, count);
    defer {
        for (suffixes) |s| allocator.free(s);
        allocator.free(suffixes);
    }

    var max_w: usize = 0;
    for (0..count) |i| {
        labels[i] = try Hooks.label(allocator, i, command);
        suffixes[i] = try Hooks.suffix(allocator, i, command);
        max_w = @max(max_w, labels[i].len);
    }

    for (0..count) |i| {
        try appendIndent(allocator, out, style.indent);
        try out.appendSlice(allocator, labels[i]);
        const pad = max_w - labels[i].len + style.column_gap;
        var p: usize = 0;
        while (p < pad) : (p += 1) try out.append(allocator, ' ');
        const d = Hooks.desc(i, command);
        if (d.len != 0) try out.appendSlice(allocator, d);
        if (suffixes[i].len != 0) try out.appendSlice(allocator, suffixes[i]);
        try out.append(allocator, '\n');
    }
}

fn appendCommands(
    allocator: Allocator,
    out: *std.ArrayList(u8),
    command: *const CommandMeta,
    style: HelpStyle,
) !void {
    try out.appendSlice(allocator, "Commands:\n");
    var max_w: usize = 0;
    for (command.subcommands) |child| {
        max_w = @max(max_w, child.name.len);
    }
    for (command.subcommands) |child| {
        try appendIndent(allocator, out, style.indent);
        try out.appendSlice(allocator, child.name);
        const pad = max_w - child.name.len + style.column_gap;
        var p: usize = 0;
        while (p < pad) : (p += 1) try out.append(allocator, ' ');
        try out.appendSlice(allocator, child.description);
        try out.append(allocator, '\n');
    }
}

test "renderHelp includes usage options commands examples" {
    const CommandBuilder = @import("../core/command.zig").CommandBuilder;
    var root = CommandBuilder.init(std.testing.allocator, "demo");
    defer root.deinit();
    _ = root.help("Demo application");
    _ = (try root.flag("verbose")).short('v').help("more output");
    _ = (try root.opt("threads", .int)).short('t').defaultText("4").help("workers");
    _ = try root.example("demo run main.zig");

    const run = try root.subcommand("run");
    _ = run.help("run a script");
    _ = (try run.arg("SCRIPT")).help("script path");

    _ = root.seal();

    const text = try renderHelp(std.testing.allocator, &root.meta);
    defer std.testing.allocator.free(text);

    try std.testing.expect(std.mem.indexOf(u8, text, "Demo application") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "Usage: demo") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "Options:") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "--verbose") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "[default: 4]") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "Commands:") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "run") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "Examples:") != null);

    const run_help = try renderHelp(std.testing.allocator, root.meta.findSubcommand("run").?);
    defer std.testing.allocator.free(run_help);
    try std.testing.expect(std.mem.indexOf(u8, run_help, "Usage: demo run") != null);
    try std.testing.expect(std.mem.indexOf(u8, run_help, "<SCRIPT>") != null);
}
