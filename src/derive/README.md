# derive — Comptime struct → Metadata

## 模块职责

用 Zig Reflection（`@typeInfo` / `inline for` / `@field`）从 `struct` **自动派生** `OptionMeta` / `CommandMeta`。

对标 clap `derive(Parser)`，但 **无宏**：类型与可选 `T.cli` 覆盖表驱动。

## 设计原因

1. 符合规范：comptime 驱动、类型安全、无 OOP。
2. 字段默认值 → `default_text` / 非 required；`?T` → optional；`bool` → flag。
3. 用 `Derived(name, T)` 生成**稳定静态存储**，避免临时数组悬垂指针。

## 接口说明

```zig
const Config = struct {
    pub const cli_name = "demo";              // optional shortcut
    pub const cli_description = "A demo tool"; // optional shortcut

    verbose: bool = false,
    output: ?[]const u8 = null,
    threads: u32 = 4,
    name: []const u8, // 无默认 → required option

    pub const cli = struct {
        // 命令级（可选）
        pub const description = "A demo tool";
        pub const examples = [_][]const u8{"demo -v"};
        // pub const aliases = [_][]const u8{"d"};

        // 字段级
        pub const verbose = .{ .short = 'v', .help = "more output" };
        pub const output = .{ .short = 'o', .value_name = "FILE" };
        pub const threads = .{ .short = 't' };
        // pub const secret = .{ .skip = true };
    };
};
```

| API | 说明 |
|-----|------|
| `optionsFromStruct(T)` | comptime `OptionMeta` 数组 |
| `Derived(name, T)` | `options` + `meta` 命名空间 |
| `commandSpec(T)` | 读取可选命令描述配置 |
| `T.cli.<field>` | `short` / `help` / `value_name` / `long` / `skip` |
| `T.cli.description` / `T.cli_description` | 命令描述（可选） |
| `T.cli.name` / `T.cli_name` | 命令名（可选） |
| `T.cli.aliases` / `examples` | 别名与示例（可选） |

## 类型映射

| Zig | CLI |
|-----|-----|
| `bool` | flag |
| int / float / enum | option |
| `[]const u8` | string option |
| `Path` | path option |
| `?T` | optional cardinality |

## 未来扩展

- Milestone 10：`App(Config)` 把 derive + parse + typing 串起来
- 嵌套 struct → 子命令
- 位置参数字段标记（`cli.positional`）
