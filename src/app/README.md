# app — 高层声明式 API

## 模块职责

兑现规范目标 API：`cli.App(Config)`，把 **derive → parse → bind(typing)** 串成一条路径。

| 步骤 | 模块 |
|------|------|
| struct → Metadata | `derive` |
| argv → ParseResult | `parser` |
| raw values → Config 字段 | `typing` via `bind` |

**不做**：print、exit、自动读 `std.process.Init`（调用方传入 `argv` / 自行从 Args 收集）。

## 设计原因

1. 保持底层分层可用；App 只是薄装配层。
2. 显式 `Allocator`；结构失败用 `error.ParseFailed` + `last_issue`，便于接 Diagnostic。
3. `Config.cli_name` 可选，默认 `"app"`。

## 接口说明

```zig
const Config = struct {
    pub const cli_name = "demo";
    pub const cli_description = "A small demo"; // 或 cli.description

    verbose: bool = false,
    threads: u32 = 4,
    output: ?[]const u8 = null,

    pub const cli = struct {
        pub const description = "A small demo";
        pub const examples = [_][]const u8{"demo -v"};
        pub const verbose = .{ .short = 'v', .help = "more output" };
        pub const threads = .{ .short = 't' };
        pub const output = .{ .short = 'o', .value_name = "FILE" };
    };
};

var app = cli.App(Config).init(allocator);
const cfg = try app.parse(argv[1..]); // 不含程序名

const help = try app.help();
defer allocator.free(help);
```

失败时：

```zig
app.parse(argv) catch |err| switch (err) {
    error.ParseFailed => {
        const diag = cli.diagnose(cli.App(Config).meta_ptr, app.last_issue.?);
        // 用户决定如何展示（diagnose 自动挑选候选做 “did you mean”）
    },
    else => |e| return e,
};
```

## 进阶字段能力

```zig
const Config = struct {
    // 位置参数：从 argv 位置绑定
    host: []const u8,
    port: u16 = 80,
    // 多值选项：可重复，收集为拥有型切片（需 parseAlloc）
    tags: []const []const u8 = &.{},

    pub const cli = struct {
        pub const host = .{ .positional = 0 };
        pub const port = .{ .positional = 1 };
        pub const tags = .{ .short = 't' };
        // comptime 校验规则
        pub const threads = .{ .validate = .{ .range_int = .{ .min = 1, .max = 8 } } };
    };
};

var arena = std.heap.ArenaAllocator.init(gpa);
defer arena.deinit();

var app = cli.App(Config).init(gpa);
const cfg = try app.parseAlloc(arena.allocator(), argv);   // 多值 → arena 拥有
// 或带校验：
const checked = try app.parseChecked(io, argv);            // 失败置 last_validation
```

- `parse`：不分配（多值字段会编译报错，改用 `parseAlloc`）。
- `parseAlloc(alloc, argv)`：为 `[]E` 字段分配拥有型切片，调用方负责释放（arena 最省心）。
- `parseChecked(io, argv)`：额外运行 `required` + `cli.<field>.validate`，失败返回 `error.ValidationFailed`。

## 声明式子命令

```zig
const AddConfig = struct {
    pkg: []const u8,
    force: bool = false,
    pub const cli = struct {
        pub const pkg = .{ .positional = 0, .value_name = "NAME" };
        pub const force = .{ .short = 'f' };
    };
};
const Config = struct {
    pub const cli_name = "pkg";
    verbose: bool = false,
    pub const cli = struct { pub const verbose = .{ .short = 'v' }; };
    // 每个字段 = 一个子命令（字段名即命令名）
    pub const cli_subcommands = .{ .add = AddConfig, .remove = RemoveConfig };
};

var app = cli.App(Config).init(gpa);
const cmd = try app.parseCommand(argv);   // 返回 cli.Command(Config) tagged-union
switch (cmd) {
    .base => |c| { ... },          // 未选子命令 → 根 Config
    .add => |c| { c.pkg; c.force; },
    .remove => |c| { c.pkg; },
}
```

- 单层分发；多层嵌套用 `CommandBuilder` 或嵌套 `App`。
- 命令级 `name`/`description` 为字符串；字段 overlay 为 `.{...}` struct——二者不再冲突，字段可命名为 `name`。

## 与 CommandBuilder 的关系

- **App(Config)**：扁平选项 + 位置参数 + 多值 + 校验 + 声明式子命令，适合工具默认入口
- **CommandBuilder**：显式命令树、多层子命令、位置参数（仍完全可用）

## 未来扩展

- 多层声明式子命令
- `parse(init: process.Init)` 便利包装（0.16 Args）
