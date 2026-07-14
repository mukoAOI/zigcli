//! Zsh completion script generator.

const std = @import("std");
const Allocator = std.mem.Allocator;
const CommandMeta = @import("../core/command.zig").CommandMeta;
const common = @import("common.zig");

pub fn generate(allocator: Allocator, root: *const CommandMeta) Allocator.Error![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    const bin = root.name;
    try out.appendSlice(allocator, "#compdef ");
    try out.appendSlice(allocator, bin);
    try out.appendSlice(allocator, "\n\n_");
    try common.appendIdent(allocator, &out, bin);
    try out.appendSlice(allocator,
        \\() {
        \\  local cur context state state_descr line
        \\  typeset -A opt_args
        \\  local -a words
        \\  words=("${words[@]}")
        \\  local cmd="
    );
    try common.appendIdent(allocator, &out, bin);
    try out.appendSlice(allocator,
        \\"
        \\  local i=2
        \\  while (( i < CURRENT )); do
        \\    case "${words[i]}" in
        \\      -*) ;;
        \\      *) cmd="${cmd}_${words[i]//-/_}" ;;
        \\    esac
        \\    (( i++ ))
        \\  done
        \\  case "$cmd" in
        \\
    );

    const Ctx = struct {
        allocator: Allocator,
        out: *std.ArrayList(u8),
        fn visit(self: @This(), cmd: *const CommandMeta, path: []const []const u8) !void {
            try self.out.appendSlice(self.allocator, "    ");
            try common.appendSanitizedPath(self.allocator, self.out, path);
            try self.out.appendSlice(self.allocator, ") _values '' ");
            // zsh _values wants quoted words
            try appendQuotedWords(self.allocator, self.out, cmd);
            try self.out.appendSlice(self.allocator, " ;;\n");
        }
    };
    var path0 = [_][]const u8{bin};
    try common.walk(root, &path0, Ctx{ .allocator = allocator, .out = &out }, Ctx.visit);

    try out.appendSlice(allocator,
        \\  esac
        \\}
        \\
        \\compdef _
    );
    try common.appendIdent(allocator, &out, bin);
    try out.append(allocator, ' ');
    try out.appendSlice(allocator, bin);
    try out.append(allocator, '\n');

    return try out.toOwnedSlice(allocator);
}

fn appendQuotedWords(allocator: Allocator, list: *std.ArrayList(u8), cmd: *const CommandMeta) !void {
    var first = true;
    for (cmd.options) |opt| {
        if (opt.long) |long| {
            if (!first) try list.append(allocator, ' ');
            try list.append(allocator, '\'');
            try list.appendSlice(allocator, "--");
            try list.appendSlice(allocator, long);
            try list.append(allocator, '\'');
            first = false;
        }
        if (opt.short) |s| {
            if (!first) try list.append(allocator, ' ');
            try list.append(allocator, '\'');
            try list.append(allocator, '-');
            try list.append(allocator, s);
            try list.append(allocator, '\'');
            first = false;
        }
    }
    for (cmd.subcommands) |child| {
        if (!first) try list.append(allocator, ' ');
        try list.append(allocator, '\'');
        try list.appendSlice(allocator, child.name);
        try list.append(allocator, '\'');
        first = false;
    }
}
