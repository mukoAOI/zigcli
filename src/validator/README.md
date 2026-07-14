# validator — 校验层

## 模块职责

在 **Parser 之后**、面向原始字符串值做约束检查。独立于词法 / 语法解析。

| 能力 | 说明 |
|------|------|
| Required | `present == false` 失败 |
| Range | 整数 / 浮点闭区间 |
| Choices | 精确枚举字符串 |
| Glob / Regex | 内置 `*`/`?` glob；`regex` 为函数指针可挂真引擎 |
| FileExists / DirectoryExists | 文件系统探测（失败变为 Issue，非 panic） |
| Custom | `fn(ValidationContext) ?ValidationIssue` |
| Registry | `validator_id` → `Validator` |
| `validateParseResult` | 对照 `ParseResult` + Metadata 批量校验 |

**不做**：类型转换（见 typing）、打印、exit。

## 设计原因

1. Parser 只保证结构匹配；Required 等语义属于 Validator。
2. Zig 标准库无正则：内置 glob；真 regex 用 `Validator.regex` 注入。
3. Metadata 只存 `validator_id`，避免 `core` 依赖本模块。

## 接口说明

```zig
var reg = cli.Registry.init(allocator);
defer reg.deinit();
const id = try reg.add(.{ .range_int = .{ .min = 1, .max = 8 } });
// 构建 Metadata 时写入 option.validator_id = id

const io = init.io; // from std.process.Init in main

if (cli.validate(io, .{ .choices = &.{ "debug", "release" } }, ctx)) |issue| {
    // 交给用户 / Diagnostic
}

if (cli.validateParseResult(io, &parse_ok, &reg)) |issue| { ... }
```

Zig 0.16 文件系统依赖显式 `std.Io`；非文件类校验会忽略该参数。

## 未来扩展

- `ValidationIssue` → `Diagnostic` 桥接
- Regex 编译缓存
- 跨字段联合约束
