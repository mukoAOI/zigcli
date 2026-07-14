# zigcli

**Zig 0.16 命令行框架** — comptime 驱动、显式 allocator、零 OOP。

对标 Rust [clap](https://github.com/clap-rs/clap) / C++ [CLI11](https://github.com/CLIUtils/CLI11) 的能力，但实现遵循 Zig 风格：分层模块、编译期元数据派生、结构化错误（不直接 `exit`）。

## 特性

- **`App(Config)`** — 声明式配置 struct → 自动派生选项/位置参数/子命令
- **`CommandBuilder`** — 命令树、多层子命令、运行时构建
- **解析** — POSIX/GNU 风格短/长选项、`=value`、`--`、位置参数
- **类型绑定** — `bool`、`i32`/`u32`、`f64`、`[]const u8`、`enum`、`?T`、`[]E`（多值）
- **校验** — comptime 嵌入 `Validator`（required、range、file_exists 等）
- **诊断** — `ParseIssue` / `ValidationIssue` → 可读 `Diagnostic`，含 “did you mean”
- **帮助** — 从 `CommandMeta` 渲染 Usage / Options / Commands
- **补全** — bash / zsh / fish / PowerShell 脚本生成
- **体积友好** — 示例可 `release-small` 构建（单线程 + strip + 无 unwind）

## 要求

- [Zig](https://ziglang.org/) **0.16.0** 或更高

## 作为依赖使用

### 1. 添加包

将本仓库 URL 写入你的 `build.zig.zon`：

```zig
.dependencies = .{
    .zigcli = .{
        .url = "https://github.com/mukoAOI/zigcli/archive/refs/tags/v0.1.0.tar.gz",
        .hash = "<运行 zig build 后填入>",
    },
},
```

或使用本地 path 开发：

```zig
.dependencies = .{
    .zigcli = .{ .path = "../zigcli" },
},
```

### 2. 在 `build.zig` 中引入模块

```zig
const zigcli = b.dependency("zigcli", .{
    .target = target,
    .optimize = optimize,
});

exe.root_module.addImport("cli", zigcli.module("cli"));
```

### 3. 代码

```zig
const cli = @import("cli");

const Config = struct {
    pub const cli_name = "mytool";
    verbose: bool = false,
    pub const cli = struct {
        pub const verbose = .{ .short = 'v', .help = "more output" };
    };
};

pub fn main(init: std.process.Init) !void {
    var app = cli.App(Config).init(init.gpa);
    const cfg = try app.parse(argv_without_program_name);
    _ = cfg;
}
```

## 克隆本仓库

```bash
git clone https://github.com/mukoAOI/zigcli.git
cd zigcli
zig build test      # 单元测试
zig build           # 编译库 + 示例
```

### 运行示例

| 命令 | 说明 |
|------|------|
| `zig build run-basic -- -v -t 8 -o out.txt` | `App(Config)` 声明式 |
| `zig build run-tree -- run main.zig` | `CommandBuilder` 命令树 |
| `zig build run-subs -- add pkg -f` | 声明式子命令 |
| `zig build run-ping -- 8.8.8.8` | ICMP ping（Windows） |

各示例均支持 `--help`。

### 发布体积构建

```bash
zig build release          # ReleaseFast + strip
zig build release-small    # 最小体积（约 −26%）
```

## 项目结构

```
zigcli/
├── build.zig              # 构建脚本（导出 cli 模块）
├── build.zig.zon          # 包清单
├── src/
│   ├── root.zig           # 公共 API 入口
│   ├── core/              # CommandMeta / OptionMeta / CommandBuilder
│   ├── parser/            # Tokenizer + Parser
│   ├── diagnostic/        # 错误诊断与建议
│   ├── typing/            # 字符串 → 类型
│   ├── validator/         # 校验规则
│   ├── help/              # 帮助文本渲染
│   ├── completion/        # Shell 补全生成
│   ├── derive/            # comptime 元数据派生
│   └── app/               # App(Config) 高层 API
├── examples/              # 可运行示例（非库的一部分）
└── docs/                  # 设计与里程碑文档
```

各子目录下有 `README.md` 说明模块职责。

## API 概览

### 声明式 `App(Config)`

```zig
// 位置参数
host: []const u8,
pub const cli = struct { pub const host = .{ .positional = 0 }; };

// 多值选项（需 parseAlloc）
tags: []const []const u8,
pub const cli = struct { pub const tags = .{ .long = "tag" }; };

// comptime 校验
threads: u32 = 4,
pub const cli = struct {
    pub const threads = .{ .short = 't', .validate = .{ .range_int = .{ .min = 1, .max = 64 } } };
};
const cfg = try app.parseChecked(std.io.getStdOut(), argv);

// 声明式子命令
pub const cli_subcommands = .{ .run = RunConfig, .build = BuildConfig };
const cmd = try app.parseCommand(argv);
switch (cmd) { .base => |c| ..., .run => |c| ..., .build => |c| ... }
```

详见 [`src/app/README.md`](src/app/README.md)。

### 底层 `CommandBuilder`

```zig
var root = cli.CommandBuilder.init(allocator, "demo");
defer root.deinit();
const run = try root.subcommand("run");
_ = try run.arg("SCRIPT");
_ = root.seal();
var out = try cli.parseArgv(allocator, &root.meta, argv);
defer out.deinit();
```

## 设计原则

- **显式 allocator** — 所有堆分配经 `Allocator` 传入，有对应 `deinit`
- **结构化失败** — 解析/校验失败返回 issue，由调用方决定如何展示或退出
- **comptime 优先** — 元数据在编译期生成，运行时无反射开销
- **库不 exit** — 框架只返回错误与诊断，不调用 `std.process.exit`

## 版本

当前版本：**0.1.0**（`build.zig.zon` / `src/root.zig`）

## 文档

- [App(Config) 指南](src/app/README.md)
- [里程碑与变更记录](docs/MILESTONES.md)
- [原始设计规范](docs/DESIGN.md)

## 许可证

[MIT](LICENSE)
