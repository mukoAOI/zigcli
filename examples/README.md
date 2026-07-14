# examples

本目录示例展示库的两种主要用法，**不属于库公共 API**（`examples/common.zig` 仅为示例共享工具）。

| 示例 | 说明 | 命令 |
|------|------|------|
| `basic_app.zig` | `App(Config)` 声明式解析 | `zig build run-basic -- -v -t 8 -o out.txt` |
| `command_tree.zig` | `CommandBuilder` 子命令树 | `zig build run-tree -- run main.zig` |
| `subcommands.zig` | 声明式子命令 `parseCommand` | `zig build run-subs -- add pkg -f` |
| `ping.zig` | ICMP ping（Windows 完整功能；其他平台编译为 stub） | `zig build run-ping -- 8.8.8.8` |

```bash
zig build run-basic -- --help
zig build run-tree -- --help
zig build run-subs -- --help
zig build run-ping -- -c 4 -W 1000 example.com
```
