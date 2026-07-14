//! High-level `App(Config)` — derive + parse + bind in one facade.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Derived = @import("../derive/options.zig").Derived;
const parse_mod = @import("../parser/parse.zig");
const ParseIssue = @import("../parser/result.zig").ParseIssue;
const renderHelp = @import("../help/render.zig").renderHelp;
const bind_mod = @import("bind.zig");
const check_mod = @import("check.zig");

pub const BindError = bind_mod.BindError;
pub const BindAllocError = bind_mod.BindAllocError;
pub const bindConfig = bind_mod.bindConfig;
pub const bindConfigAlloc = bind_mod.bindConfigAlloc;
pub const validateConfig = check_mod.validateConfig;
pub const ValidationIssue = check_mod.ValidationIssue;

/// Errors from `App(Config).parse` (allocation + bind + structural parse).
pub const AppError = Allocator.Error || BindError || error{ParseFailed};

/// Errors from `App(Config).parseAlloc` (adds multi-value allocation).
pub const AppAllocError = Allocator.Error || BindAllocError || error{ParseFailed};

/// Errors from `App(Config).parseChecked` (adds validation).
pub const AppCheckedError = AppError || error{ValidationFailed};

fn appName(comptime Config: type) []const u8 {
    const cs = @import("../derive/spec.zig").commandSpec(Config);
    if (cs.name) |n| return n;
    return "app";
}

/// Builds the tagged-union result for `App(Config).parseCommand`.
///
/// Variant `base` carries the root `Config`; each declared subcommand
/// (`pub const cli_subcommands = .{ .run = RunConfig, ... }`) adds a variant
/// named after the field, carrying that subcommand's config.
pub fn Command(comptime Config: type) type {
    if (!@hasDecl(Config, "cli_subcommands")) {
        @compileError("Command(Config) requires `pub const cli_subcommands`");
    }
    const subs = Config.cli_subcommands;
    const sfields = @typeInfo(@TypeOf(subs)).@"struct".fields;
    const n = sfields.len + 1;

    var names: [n][]const u8 = undefined;
    var types: [n]type = undefined;
    names[0] = "base";
    types[0] = Config;
    inline for (sfields, 0..) |f, idx| {
        names[idx + 1] = f.name;
        types[idx + 1] = @field(subs, f.name);
    }

    const IntTag = std.math.IntFittingRange(0, n - 1);
    var values: [n]IntTag = undefined;
    for (0..n) |i| values[i] = @intCast(i);

    const Tag = @Enum(IntTag, .exhaustive, &names, &values);
    return @Union(.auto, Tag, &names, &types, &@splat(.{}));
}

/// Declarative CLI application parameterized by a config struct.
///
/// ```zig
/// const Config = struct {
///     pub const cli_name = "demo";
///     pub const cli_description = "A small demo"; // or cli.description
///     verbose: bool = false,
///     threads: u32 = 4,
///     pub const cli = struct {
///         pub const description = "A small demo";
///         pub const verbose = .{ .short = 'v' };
///     };
/// };
/// var app = cli.App(Config).init(allocator);
/// const cfg = try app.parse(argv); // typically argv[1..]
/// ```
pub fn App(comptime Config: type) type {
    const name = appName(Config);
    const D = Derived(name, Config);

    return struct {
        allocator: Allocator,
        /// Set when `parse` returns `error.ParseFailed`.
        last_issue: ?ParseIssue = null,
        /// Set when `parseChecked` returns `error.ValidationFailed`.
        last_validation: ?check_mod.ValidationIssue = null,

        pub const derived = D;
        pub const meta_ptr: *const @import("../core/command.zig").CommandMeta = &D.meta;

        /// Creates an app handle (no heap churn beyond caller allocator use in parse).
        pub fn init(allocator: Allocator) @This() {
            return .{ .allocator = allocator };
        }

        /// Structurally parses `argv` (without program name) and binds into `Config`.
        ///
        /// Does not print or exit. On structural failure returns `error.ParseFailed`
        /// and stores details in `last_issue`.
        pub fn parse(self: *@This(), argv: []const []const u8) AppError!Config {
            self.last_issue = null;
            var out = try parse_mod.parseArgv(self.allocator, meta_ptr, argv);
            defer out.deinit();
            switch (out) {
                .issue => |iss| {
                    self.last_issue = iss;
                    return error.ParseFailed;
                },
                .ok => |*result| {
                    return try bind_mod.bindConfig(Config, result);
                },
            }
        }

        /// Like `parse`, but allocates owned slices for multi-value (`[]E`)
        /// fields using `alloc`. The caller owns those slices (an arena is
        /// the simplest way to manage them).
        pub fn parseAlloc(self: *@This(), alloc: Allocator, argv: []const []const u8) AppAllocError!Config {
            self.last_issue = null;
            var out = try parse_mod.parseArgv(self.allocator, meta_ptr, argv);
            defer out.deinit();
            switch (out) {
                .issue => |iss| {
                    self.last_issue = iss;
                    return error.ParseFailed;
                },
                .ok => |*result| {
                    return try bind_mod.bindConfigAlloc(Config, alloc, result);
                },
            }
        }

        /// Like `parse`, but also runs comptime validation rules
        /// (`required` + `cli.<field>.validate`). On a validation failure
        /// returns `error.ValidationFailed` and stores `last_validation`.
        ///
        /// `io` is only needed by filesystem validators; pass `std.Io` from
        /// `std.process.Init` (or `std.testing.io` in tests).
        pub fn parseChecked(self: *@This(), io: std.Io, argv: []const []const u8) AppCheckedError!Config {
            self.last_issue = null;
            self.last_validation = null;
            var out = try parse_mod.parseArgv(self.allocator, meta_ptr, argv);
            defer out.deinit();
            switch (out) {
                .issue => |iss| {
                    self.last_issue = iss;
                    return error.ParseFailed;
                },
                .ok => |*result| {
                    if (check_mod.validateConfig(io, Config, result)) |issue| {
                        self.last_validation = issue;
                        return error.ValidationFailed;
                    }
                    return try bind_mod.bindConfig(Config, result);
                },
            }
        }

        /// Parses `argv` and dispatches to the selected subcommand, returning
        /// a `Command(Config)` tagged union (`.base` when no subcommand ran).
        ///
        /// Requires `Config` to declare `pub const cli_subcommands`. On a
        /// structural failure returns `error.ParseFailed` + `last_issue`.
        pub fn parseCommand(self: *@This(), argv: []const []const u8) AppError!Command(Config) {
            comptime {
                if (!@hasDecl(Config, "cli_subcommands")) {
                    @compileError("parseCommand requires `pub const cli_subcommands`; use parse otherwise");
                }
            }
            self.last_issue = null;
            var out = try parse_mod.parseArgv(self.allocator, meta_ptr, argv);
            defer out.deinit();
            switch (out) {
                .issue => |iss| {
                    self.last_issue = iss;
                    return error.ParseFailed;
                },
                .ok => |*result| {
                    const subs = Config.cli_subcommands;
                    const sfields = @typeInfo(@TypeOf(subs)).@"struct".fields;
                    inline for (sfields, 0..) |f, i| {
                        if (result.command == D.sub_metas[i]) {
                            const SubT = @field(subs, f.name);
                            return @unionInit(Command(Config), f.name, try bind_mod.bindConfig(SubT, result));
                        }
                    }
                    return @unionInit(Command(Config), "base", try bind_mod.bindConfig(Config, result));
                },
            }
        }

        /// Renders help for the derived command metadata.
        pub fn help(self: *const @This()) Allocator.Error![]u8 {
            return renderHelp(self.allocator, meta_ptr);
        }
    };
}

test "App.parse binds derived config" {
    const Config = struct {
        pub const cli_name = "demo";
        verbose: bool = false,
        threads: u32 = 4,
        output: ?[]const u8 = null,

        pub const cli = struct {
            pub const verbose = .{ .short = 'v', .help = "more" };
            pub const threads = .{ .short = 't' };
            pub const output = .{ .short = 'o' };
        };
    };

    var app = App(Config).init(std.testing.allocator);
    const argv = [_][]const u8{ "-v", "-t", "8", "--output", "x" };
    const cfg = try app.parse(&argv);
    try std.testing.expect(cfg.verbose);
    try std.testing.expectEqual(@as(u32, 8), cfg.threads);
    try std.testing.expectEqualStrings("x", cfg.output.?);
}

test "App.parseAlloc collects multi-value option" {
    const Config = struct {
        pub const cli_name = "demo";
        tags: []const []const u8 = &.{},
        ports: []u16 = &.{},

        pub const cli = struct {
            pub const tags = .{ .short = 't' };
            pub const ports = .{ .short = 'p' };
        };
    };

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    var app = App(Config).init(std.testing.allocator);
    const argv = [_][]const u8{ "-t", "a", "--tags", "b", "-p", "80", "-p", "443" };
    const cfg = try app.parseAlloc(arena.allocator(), &argv);
    try std.testing.expectEqual(@as(usize, 2), cfg.tags.len);
    try std.testing.expectEqualStrings("a", cfg.tags[0]);
    try std.testing.expectEqualStrings("b", cfg.tags[1]);
    try std.testing.expectEqual(@as(usize, 2), cfg.ports.len);
    try std.testing.expectEqual(@as(u16, 443), cfg.ports[1]);
}

test "App.parseCommand dispatches declarative subcommands" {
    const RunConfig = struct {
        script: []const u8,
        watch: bool = false,
        pub const cli = struct {
            pub const script = .{ .positional = 0 };
            pub const watch = .{ .short = 'w' };
        };
    };
    const BuildConfig = struct {
        release: bool = false,
        pub const cli = struct {
            pub const release = .{ .short = 'r' };
        };
    };
    const Config = struct {
        pub const cli_name = "tool";
        verbose: bool = false,
        pub const cli = struct {
            pub const verbose = .{ .short = 'v' };
        };
        pub const cli_subcommands = .{ .run = RunConfig, .build = BuildConfig };
    };

    var app = App(Config).init(std.testing.allocator);

    // Subcommand `run` with its own positional + flag.
    {
        const argv = [_][]const u8{ "run", "-w", "main.zig" };
        const cmd = try app.parseCommand(&argv);
        try std.testing.expect(cmd == .run);
        try std.testing.expect(cmd.run.watch);
        try std.testing.expectEqualStrings("main.zig", cmd.run.script);
    }

    // Subcommand `build`.
    {
        const argv = [_][]const u8{ "build", "-r" };
        const cmd = try app.parseCommand(&argv);
        try std.testing.expect(cmd == .build);
        try std.testing.expect(cmd.build.release);
    }

    // No subcommand → base config.
    {
        const argv = [_][]const u8{"-v"};
        const cmd = try app.parseCommand(&argv);
        try std.testing.expect(cmd == .base);
        try std.testing.expect(cmd.base.verbose);
    }

    // Unknown subcommand is rejected.
    {
        const argv = [_][]const u8{"rnu"};
        try std.testing.expectError(error.ParseFailed, app.parseCommand(&argv));
        try std.testing.expect(app.last_issue.?.kind == .unknown_subcommand);
    }
}

test "App.parseChecked enforces validation rules" {
    const thread_range = @import("../validator/builtins.zig").Validator{ .range_int = .{ .min = 1, .max = 8 } };
    const Config = struct {
        pub const cli_name = "demo";
        threads: u32 = 4,
        pub const cli = struct {
            pub const threads = .{ .short = 't', .validate = thread_range };
        };
    };

    var app = App(Config).init(std.testing.allocator);
    const bad = [_][]const u8{ "-t", "99" };
    try std.testing.expectError(error.ValidationFailed, app.parseChecked(std.testing.io, &bad));
    try std.testing.expect(app.last_validation.?.kind == .out_of_range);

    const ok = [_][]const u8{ "-t", "5" };
    const cfg = try app.parseChecked(std.testing.io, &ok);
    try std.testing.expectEqual(@as(u32, 5), cfg.threads);
}

test "App.parse unknown option sets last_issue" {
    const Config = struct {
        pub const cli_name = "demo";
        verbose: bool = false,
    };

    var app = App(Config).init(std.testing.allocator);
    const argv = [_][]const u8{"--nope"};
    try std.testing.expectError(error.ParseFailed, app.parse(&argv));
    try std.testing.expect(app.last_issue != null);
    try std.testing.expect(app.last_issue.?.kind == .unknown_long_option);
}

test "App.help contains usage" {
    const Config = struct {
        pub const cli_name = "tool";
        pub const cli_description = "example tool";
        verbose: bool = false,
        pub const cli = struct {
            pub const description = "example tool";
            pub const verbose = .{ .short = 'v', .help = "more" };
        };
    };
    var app = App(Config).init(std.testing.allocator);
    const text = try app.help();
    defer std.testing.allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "example tool") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "Usage: tool") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "--verbose") != null);
}
