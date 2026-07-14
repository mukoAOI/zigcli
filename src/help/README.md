# help — 帮助文本生成

## 模块职责

完全根据 `CommandMeta` 生成帮助文本，**不依赖 Parser**。

| 章节 | 内容 |
|------|------|
| Description | 命令描述 |
| Usage | 祖先路径 + `[COMMAND]` / `[OPTIONS]` / 位置参数 |
| Arguments | 对齐列表 + required / default |
| Options | `-s, --long <VAL>` 对齐 + required / default |
| Commands | 子命令名 + 描述（对齐） |
| Examples | Metadata 中的示例行 |

## 设计原因

1. Help / Completion 只读 Metadata，与词法语法解耦。
2. 先算左列最大宽度再填充空格，保证对齐。
3. 返回分配的 `[]u8`，库本身不打印。

## 接口说明

```zig
const text = try cli.renderHelp(allocator, command_meta);
defer allocator.free(text);
// 用户决定写到 stdout / 日志
```

可选样式：

```zig
const text = try cli.renderHelpStyled(allocator, meta, .{ .indent = 4, .column_gap = 4 });
```

## 未来扩展

- 终端宽度自动折行
- 颜色 / ANSI（可选）
- 与 `--help` 旗标自动绑定（高层 App API）
