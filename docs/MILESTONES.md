# Zig CLI Framework — Milestone 记录

按 [`DESIGN.md`](DESIGN.md) 要求分里程碑推进；**Milestone 1–10 已全部完成**。

## 完成概览

| # | 主题 | 路径 |
|---|------|------|
| 1 | Core Metadata | `src/core/` |
| 2 | Tokenizer | `src/parser/token.zig`, `tokenizer.zig` |
| 3 | Parser | `src/parser/parse.zig`, `result.zig` |
| 4 | Diagnostic | `src/diagnostic/` |
| 5 | Type Parser | `src/typing/` |
| 6 | Validator | `src/validator/` |
| 7 | Help | `src/help/` |
| 8 | Completion | `src/completion/` |
| 9 | Comptime derive | `src/derive/` |
| 10 | App(Config) | `src/app/` |

## Milestone 10 — App(Config)（已完成）

**目标**：高层声明式 API，串起 derive + parse + typing。

**交付**：

- `src/app/bind.zig` — `ParseResult` → `Config`
- `src/app/app.zig` — `App(Config).init` / `parse` / `help`
- `src/app/README.md`

```zig
var app = cli.App(Config).init(allocator);
const cfg = try app.parse(argv[1..]);
```

## 优化增强（Milestone 10 之后）

在 1–10 基础上做的一轮打磨（不改变分层原则）：

### 二进制体积
- 示例统一 `single_threaded = true`（CLI 无需线程运行时）。
- `zig build release`：ReleaseFast + strip + 单线程（不产 `.pdb`）。
- 新增 `zig build release-small`：ReleaseSmall + strip + 去 unwind/frame-pointer，体积再降 ~26%。

### 正确性
- **未知子命令**：分组命令（有子命令、无自有位置参数）遇到未知词时给出 `unknown_subcommand` 诊断（含 “did you mean”），不再静默当位置参数。
- 版本号统一为 `0.1.0`（`build.zig.zon` ↔ `root.zig`）。

### App(Config) 打通
- **位置参数**：`cli.<field> = .{ .positional = 0 }` → 派生为 `ArgumentMeta` 并从 `positionals` 绑定。
- **多值选项**：`[]E`（E≠u8）字段视为可重复选项，`App.parseAlloc(alloc, argv)` / `bindConfigAlloc` 收集为拥有型切片。
- **comptime 校验**：`cli.<field> = .{ .validate = ... }` + `App.parseChecked(io, argv)` 运行 required 与内置 Validator，失败置 `last_validation`。
- **声明式子命令**：`pub const cli_subcommands = .{ .run = RunConfig, ... }` → comptime 命令树；`App.parseCommand(argv)` 返回 `Command(Config)` tagged-union（`.base` 或各子命令配置）。`CommandMeta.subcommands` 改为 `[]const *const CommandMeta` 以同时支持 builder 与 comptime 树。字段/命令名歧义已消除（overlay 为 struct、命令级 name/description 为字符串）。

### 诊断
- `fromValidationIssue`：`ValidationIssue → Diagnostic`（范围/必填/选项等可读消息）。
- `diagnose(command, issue)`：按 issue 类型自动挑选候选（长选项名 / 子命令名）。

### 代码质量
- 补全脚本 `appendIdent` 归一到 `completion/common.zig`。
- 示例共享 `examples/common.zig`（`wantsHelp` / `toArgv`）。
- 新增 `examples/subcommands.zig`（声明式子命令示例，`zig build run-subs`）。

### 说明
- 声明式子命令为**单层**分发；多层嵌套仍可用 `CommandBuilder` 或嵌套 `App`。

## 验证

```text
zig build test           # 全部单元测试
zig build                # 库 + 4 个示例
zig build release        # ReleaseFast + strip
zig build release-small  # 最小体积
```
