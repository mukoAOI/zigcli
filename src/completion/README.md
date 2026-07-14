# completion — Shell 补全脚本生成

## 模块职责

根据 `CommandMeta` 树自动生成补全脚本，**不依赖 Parser 运行时**。

| Shell | 生成器 |
|-------|--------|
| bash | `complete -F` + case 按命令路径分发 |
| zsh | `#compdef` + `_values` |
| fish | `complete -c` + `__fish_seen_subcommand_from` |
| powershell | `Register-ArgumentCompleter` |

补全词包含：子命令名、`--long`、`-s`。

## 设计原因

1. 与 Help 一样只读 Metadata，保持分层。
2. 各 shell 语法差异大，分文件生成，共享树遍历（`common.walk`）。
3. 库只返回脚本字符串，不写入 rc 文件、不打印。

## 接口说明

```zig
const script = try cli.generateCompletion(allocator, .bash, root_meta);
defer allocator.free(script);
// 写入 ~/.bashrc 或由 `demo completion bash` 子命令输出
```

```zig
pub const Shell = enum { bash, zsh, fish, powershell };
pub fn generate(allocator, shell: Shell, root: *const CommandMeta) ![]u8
```

## 未来扩展

- 按 `ValueKind.path` 触发文件补全
- `completion_id` 挂接自定义候选
- 动态补全（运行时查询）另开协议层
