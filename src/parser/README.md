# parser — 词法与语法层

## 模块职责

| 子模块 | 状态 | 职责 |
|--------|------|------|
| `token.zig` | M2 | Token 数据类型 |
| `tokenizer.zig` | M2 | `argv → Token` 流 |
| `result.zig` | M3 | `ParseResult` / `ParseIssue` / `ParseOutput` |
| `parse.zig` | M3 | 消费 Token + Metadata → 结构化匹配 |

## 设计原因

规范要求：**不要一边扫描一边解析**。

- Tokenizer 只做词法分类，不查 `CommandMeta`。
- Parser 只做结构匹配：子命令路径、选项绑定、位置参数收集。
- **不做**类型转换、Required 校验、Help、打印、exit。
- 领域失败用 `ParseIssue` 数据返回（非 `error` 枚举），便于 M4 映射为 `Diagnostic`。

## Tokenizer 接口

```zig
var it = cli.Tokenizer.init(argv[1..]);
while (it.next()) |tok| { ... }
```

## Parser 接口

```zig
var out = try cli.parseArgv(allocator, root_meta, argv);
defer out.deinit();

switch (out) {
    .ok => |r| {
        // r.command, r.path, r.options, r.positionals
    },
    .issue => |iss| {
        // iss.kind, iss.name, iss.short — 交给用户 / Diagnostic
    },
}
```

### 短选项簇规则

| 输入 | 行为 |
|------|------|
| `-va`（均为 flag） | 两个 presence |
| `-ofile`（`o` 取值） | `output = "file"` |
| `-o=file` / `--output=file` | attached 值 |
| `--output file` | 消费下一 argument token |

### 子命令

遇到 `argument` 且尚未锁定位置参数时，若匹配子命令则下钻；一旦开始收集 positional，不再切换子命令。

## 未来扩展

- `ParseIssue` → `Diagnostic` 见 `src/diagnostic/`（Milestone 4 已完成）
- Typing / Validator：消费 `ParseResult` 中的原始字符串
