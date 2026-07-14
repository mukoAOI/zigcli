# diagnostic — 诊断信息层

## 模块职责

统一表达 CLI 运行时问题，供用户或上层 UI 渲染。

| 类型 | 说明 |
|------|------|
| `Severity` | `error` / `warning` / `hint` / `note` |
| `Code` | 稳定机器码，便于国际化 |
| `Diagnostic` | 结构化诊断（含可选 suggestion / notes） |
| `fromParseIssue` | `ParseIssue` → `Diagnostic` |
| `suggestClosest` | “Did you mean …” 编辑距离建议 |

**不做**：写 stderr、调用 `exit`、绑定具体终端配色。

## 设计原因

1. Parser 只返回轻量 `ParseIssue`；Diagnostic 负责人类可读信息与扩展字段。
2. 用 `Code` + 结构化字段，而不是唯一英文字符串，方便日后 i18n。
3. 默认英文 `formatAlloc` 仅作开箱即用渲染；调用方可忽略文案、按 `Code` 自行翻译。

## 接口说明

```zig
var out = try cli.parseArgv(allocator, root, argv);
defer out.deinit();

if (out == .issue) {
    var buf: [32][]const u8 = undefined;
    const cands = cli.collectLongNames(root, &buf);
    const diag = cli.fromParseIssue(out.issue, cands);
    const text = try diag.formatAlloc(allocator);
    defer allocator.free(text);
    // 用户决定如何展示 text / diag.code
}
```

## 未来扩展

- Warning / Hint 可由 Validator、过时选项标志产生
- 短选项未知也可对 short→long 字典做建议
- 消息目录（gettext 风格）挂在 `Code` 上
