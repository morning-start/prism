# Prism 正式文档索引

> 所有正式文档（git tracked）集中在此。研究笔记、迭代草稿在
> `.agent-workplace/`（gitignored）。

## 核心文档

| 文件 | 用途 |
|------|------|
| [`architecture.md`](architecture.md) | 架构决策源：分层、包职责、依赖方向、Current decisions |
| [`status.md`](status.md) | 模块完成进度、已知限制、构建/验证命令 |
| [`lux-ir-design.md`](lux-ir-design.md) | Lucent IR 正式类型规范（schema spec） |
| [`api-protocol-converter.md`](api-protocol-converter.md) | 3 端点协议转换契约（12-case 测试矩阵 + 6 函数契约） |
| [`provider-guide.md`](provider-guide.md) | Adapter 实现指南 |

## 规则

| 文件 | 用途 |
|------|------|
| [`rules/naming-conventions.md`](rules/naming-conventions.md) | 全仓命名规则（iteration-006/007 验收清单） |
| [`rules/lucent-ir-evolution.md`](rules/lucent-ir-evolution.md) | IR 变更治理：保真度边界、提案模板、破坏性变更判定 |

## 导航

- 包内 README：`src/lux/README.md`、`src/sdk/README.md`（文件索引 + 依赖规则）
- 研究笔记（gitignored）：`.agent-workplace/research/`
- 迭代计划/任务（gitignored）：`.agent-workplace/docs/plan/`、`.agent-workplace/docs/task/`
