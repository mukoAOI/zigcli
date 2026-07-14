你是一位资深 Zig 开发者，同时也是一个大型开源 CLI 框架的架构师。

请帮助我设计并实现一个现代化、高性能、可扩展的 Zig CLI(Command Line Interface)库。

## 项目目标

这个项目不是一个简单的命令行解析器，而是一套完整的 CLI Framework。

目标对标：

- Rust clap
- C++ CLI11
- Go cobra（命令树部分）
- Python argparse（易用性）

但是整个实现必须符合 Zig 的设计哲学，而不是照搬其他语言。

整个项目需要：

- Zig 风格
- 零成本抽象
- allocator 显式传递
- comptime 驱动
- 类型安全
- 模块化
- 易测试
- 可维护
- 可长期扩展

不要使用 OOP 思维。

不要设计继承。

不要使用虚函数。

尽量使用：

- struct
- union(enum)
- comptime
- error union
- 泛型
- interface by duck typing

## API 目标

希望最终用户可以写出类似：

const Config = struct {
    verbose: bool,
    output: ?[]const u8,
    threads: u32 = 4,
};

var app = cli.App(Config).init(allocator);

const cfg = try app.parse();

或者

var app = cli.Command("git");

try app.flag("verbose").short('v');

try app.option("output")
    .short('o')
    .required();

try app.command("commit");

API 应该自然、声明式、符合 Zig 风格。

## 整体架构

整个项目采用分层设计。

推荐分层如下：

core/
parser/
typing/
validator/
diagnostic/
help/
completion/
comptime/

所有模块之间保持低耦合。

Parser 不负责：

- 类型转换
- Validator
- Help
- Completion

Parser 只负责语法解析。

Help Generator 只依赖 Metadata。

Completion 只依赖 Metadata。

Validator 独立。

Type Parser 独立。

Metadata 是整个项目的核心。

## Command Tree

支持：

Root

Subcommand

Nested Command

Flag

Option

Argument

Positional

Multiple Values

Enum

Bool

Optional

Array

所有 Command 最终形成一棵树。

## Tokenizer

Tokenizer 独立。

argv

↓

Token

不要一边扫描一边解析。

Token 建议包括：

Argument

ShortOption

LongOption

Separator

Parser 再消费 Token。

## Metadata

整个框架维护统一 Metadata。

Metadata 描述：

Command

Option

Argument

Default Value

Description

Type

Validator

Completion

Help Generator、Parser、Completion、Validator 全部依赖 Metadata。

避免重复维护。

## Type Parser

提供统一接口：

parseValue(comptime T, text)

支持：

整数

浮点

bool

enum

optional

slice

array

path

用户自定义类型

## Validator

支持：

Required

Range

Regex

Choices

FileExists

DirectoryExists

Custom Validator

Validator 独立于 Parser。

## Diagnostic

设计统一 Diagnostic。

包括：

Error

Warning

Hint

Note

支持：

Unknown option

Missing value

Did you mean ...

以后方便国际化。

## Help Generator

Help Generator 完全根据 Metadata 自动生成。

支持：

Usage

Options

Commands

Examples

Description

Default Value

Required

自动对齐。

不要依赖 Parser。

## Completion

支持：

bash

zsh

fish

powershell

Completion 根据 Metadata 自动生成。

## Comptime

充分利用 Zig Reflection。

使用：

@typeInfo

inline for

@field

等能力。

支持：

struct 自动生成 Metadata。

类似 Rust derive(Parser)。

但不使用宏。

## Allocator

所有动态分配：

必须显式传入 allocator。

不要隐藏 allocator。

尽量 Zero Copy。

不要复制 argv。

使用 []const u8。

## Error

所有函数：

返回：

!T

不要 panic。

不要 exit。

库层不打印错误。

错误交给用户决定。

## 测试

整个项目必须高测试覆盖率。

所有模块：

使用 std.testing。

Parser

Tokenizer

Validator

Type Parser

全部拥有独立测试。

## 文档

每完成一个模块：

请提供：

模块职责

设计原因

接口说明

未来扩展方式

不要只给代码。

## Vibe Coding 要求

不要一次生成整个项目。

一次只完成一个 Milestone。

每个 Milestone 包括：

1. 功能目标
2. 架构设计
3. 数据结构
4. 接口设计
5. 实现代码
6. 单元测试
7. 下一阶段规划

不要跳步。

如果发现前面的设计存在问题，应先重构再继续。

整个项目应保持 Clean Architecture。

不要为了方便而耦合模块。

优先考虑：

可维护性

可扩展性

一致性

其次才是代码量。

整个项目最终应达到可以作为 Zig 社区优秀 CLI Framework 的质量。


编码规范：

- 一个文件只负责一个核心职责。
- 每个文件尽量不超过 300 行（特殊情况除外）。
- 每个模块都必须有 README 或模块说明。
- 所有 public API 必须有文档注释。
- 尽量避免重复代码。
- 尽量减少动态分配。
- 优先使用标准库。
- 不要过早优化，但设计要预留扩展点。
- 保持命名一致性。
- 所有新增功能必须先补充测试，再实现。
- 每完成一个 Milestone，先总结设计，再进入下一阶段。