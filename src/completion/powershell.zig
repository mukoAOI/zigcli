//! PowerShell completion script generator.

const std = @import("std");
const Allocator = std.mem.Allocator;
const CommandMeta = @import("../core/command.zig").CommandMeta;
const common = @import("common.zig");

pub fn generate(allocator: Allocator, root: *const CommandMeta) Allocator.Error![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    const bin = root.name;
    try out.appendSlice(allocator,
        \\Register-ArgumentCompleter -CommandName '
    );
    try out.appendSlice(allocator, bin);
    try out.appendSlice(allocator,
        \\' -ScriptBlock {
        \\  param($wordToComplete, $commandAst, $cursorPosition)
        \\  $tokens = $commandAst.CommandElements | ForEach-Object { $_.ToString() }
        \\  $cmd = '
    );
    try common.appendIdent(allocator, &out, bin);
    try out.appendSlice(allocator,
        \\'
        \\  for ($i = 1; $i -lt $tokens.Count; $i++) {
        \\    $t = $tokens[$i]
        \\    if ($t.StartsWith('-')) { continue }
        \\    if ($i -eq $tokens.Count - 1 -and $wordToComplete) { break }
        \\    $cmd = $cmd + '_' + ($t -replace '-', '_')
        \\  }
        \\  $words = switch ($cmd) {
        \\
    );

    const Ctx = struct {
        allocator: Allocator,
        out: *std.ArrayList(u8),
        fn visit(self: @This(), cmd: *const CommandMeta, path: []const []const u8) !void {
            try self.out.appendSlice(self.allocator, "    '");
            try common.appendSanitizedPath(self.allocator, self.out, path);
            try self.out.appendSlice(self.allocator, "' { @(");
            try appendPsArray(self.allocator, self.out, cmd);
            try self.out.appendSlice(self.allocator, ") }\n");
        }
    };
    var path0 = [_][]const u8{bin};
    try common.walk(root, &path0, Ctx{ .allocator = allocator, .out = &out }, Ctx.visit);

    try out.appendSlice(allocator,
        \\    Default { @() }
        \\  }
        \\  $words | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
        \\    [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        \\  }
        \\}
        \\
    );

    return try out.toOwnedSlice(allocator);
}

fn appendPsArray(allocator: Allocator, list: *std.ArrayList(u8), cmd: *const CommandMeta) !void {
    var first = true;
    for (cmd.options) |opt| {
        if (opt.long) |long| {
            if (!first) try list.appendSlice(allocator, ", ");
            try list.append(allocator, '\'');
            try list.appendSlice(allocator, "--");
            try list.appendSlice(allocator, long);
            try list.append(allocator, '\'');
            first = false;
        }
        if (opt.short) |s| {
            if (!first) try list.appendSlice(allocator, ", ");
            try list.append(allocator, '\'');
            try list.append(allocator, '-');
            try list.append(allocator, s);
            try list.append(allocator, '\'');
            first = false;
        }
    }
    for (cmd.subcommands) |child| {
        if (!first) try list.appendSlice(allocator, ", ");
        try list.append(allocator, '\'');
        try list.appendSlice(allocator, child.name);
        try list.append(allocator, '\'');
        first = false;
    }
}
