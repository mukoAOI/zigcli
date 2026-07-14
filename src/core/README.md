# core — Metadata 层

## 模块职责

`core` 是整个 CLI Framework 的**单一事实来源（Metadata）**。

它描述命令树、选项、位置参数及其语义标签，供后续模块只读消费：

| 消费者 | 依赖方式 |
|--------|----------|
| Parser | 按 Metadata 匹配 Token → 结构化结果 |
| Help | 仅根据 Metadata 生成 Usage / Options |
| Completion | 仅根据 Metadata 生成 shell 脚本 |
| Validator | 通过 `validator_id` 间接挂接 |
| Type Parser | 通过 `value_kind` / `type_id` 挂接 |

`core` **不**做：词法分析、类型转换、校验、打印、exit。

## 设计原因

1. **低耦合**：Parser / Help / Completion 互不依赖，只依赖 Metadata。
2. **Zero-copy**：名称与描述均为 `[]const u8` 借用，不复制 argv。
3. **显式分配**：`CommandBuilder` 接受 `Allocator`；字符串归属调用方。
4. **扩展点**：`validator_id` / `completion_id` / `type_id` 为不透明索引，避免 `core` 反向依赖上层。
5. **非 OOP**：只有 `struct` + builder 视图，无继承、无虚表。

## 主要接口

```zig
var root = cli.CommandBuilder.init(allocator, "git");
defer root.deinit();

_ = (try root.flag("verbose")).short('v').help("more output");
_ = (try root.opt("output", .path)).short('o').required();

const commit = try root.subcommand("commit");
_ = (try commit.arg("PATH")).optional();

const meta: *cli.CommandMeta = root.seal();
```

| 类型 | 说明 |
|------|------|
| `ValueKind` / `Cardinality` / `OptionForm` | 语义枚举 |
| `OptionMeta` / `ArgumentMeta` / `CommandMeta` | 不可变描述（seal 后稳定） |
| `CommandBuilder` | 显式 allocator 的命令树构建器 |

## 未来扩展

- Milestone 2：`parser/tokenizer` 产出 Token，由 Parser 对照 `CommandMeta` 消费
- Milestone：`comptime/` 从 `struct` 反射生成等价 Metadata（类 clap derive）
- 枚举 choices、默认值解析仍留在 typing / validator，不塞进 `core`
