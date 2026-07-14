# typing — 类型解析层

## 模块职责

把 **原始字符串**（来自 Parser 的 option / positional 文本）转换成 Zig 值。

| API | 说明 |
|-----|------|
| `parseValue(T, text)` | 无分配；整数 / 浮点 / bool / enum / optional / `[N]T` / `[]const u8` / `Path` / 自定义 |
| `parseValueAlloc(T, allocator, text)` | 需要分配时用（如 `[]u32` 逗号分隔列表） |
| `Path` | 路径 newtype，零拷贝借用 |

**不做**：命令树匹配、Required 校验、打印错误。

## 设计原因

1. 与 Parser 解耦：Parser 只产出 `[]const u8`，Typing 独立可测。
2. comptime 驱动：`@typeInfo` + duck typing（`parseCli`），无虚表。
3. 自定义类型：实现 `parseCli(text)`（可选 `!T`）即可接入。

## 接口说明

```zig
const n = try cli.parseValue(u32, "42");
const flag = try cli.parseValue(bool, "yes");
const color = try cli.parseValue(Color, "red");
const path = try cli.parseValue(cli.Path, "./out");
const triple = try cli.parseValue([3]u8, "1,2,3");

const Port = struct {
    value: u16,
    pub fn parseCli(text: []const u8) cli.ParseValueError!@This() {
        return .{ .value = try cli.parseValue(u16, text) };
    }
};
```

### bool 接受

`true` / `false` / `1` / `0` / `yes` / `no` / `on` / `off`（大小写不敏感）

### optional

空字符串 → `null`，否则解析子类型。

## 未来扩展

- Validator 在解析后或解析前挂接
- 与 comptime Metadata 的字段类型自动对齐（Milestone 9）
