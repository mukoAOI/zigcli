//! Bash completion script generator.

const std = @import("std");
const Allocator = std.mem.Allocator;
const CommandMeta = @import("../core/command.zig").CommandMeta;
const common = @import("common.zig");

pub fn generate(allocator: Allocator, root: *const CommandMeta) Allocator.Error![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    const bin = root.name;
    try out.appendSlice(allocator, "_");
    try common.appendIdent(allocator, &out, bin);
    try out.appendSlice(allocator,
        \\() {
        \\  local cur cmd i
        \\  cur="${COMP_WORDS[COMP_CWORD]}"
        \\  cmd="
    );
    try common.appendIdent(allocator, &out, bin);
    try out.appendSlice(allocator,
        \\"
        \\  i=1
        \\  while [[ $i -lt $COMP_CWORD ]]; do
        \\    case "${COMP_WORDS[i]}" in
        \\      -*) ;;
        \\      *) cmd="${cmd}_${COMP_WORDS[i]//-/_}" ;;
        \\    esac
        \\    ((i++))
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
            try self.out.appendSlice(self.allocator, ") COMPREPLY=($(compgen -W \"");
            try common.appendWords(self.allocator, self.out, cmd);
            try self.out.appendSlice(self.allocator, "\" -- \"$cur\")) ;;\n");
        }
    };
    var path0 = [_][]const u8{bin};
    try common.walk(root, &path0, Ctx{ .allocator = allocator, .out = &out }, Ctx.visit);

    try out.appendSlice(allocator,
        \\  esac
        \\}
        \\complete -F _
    );
    try common.appendIdent(allocator, &out, bin);
    try out.append(allocator, ' ');
    try out.appendSlice(allocator, bin);
    try out.append(allocator, '\n');

    return try out.toOwnedSlice(allocator);
}
