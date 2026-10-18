# Prism 正式文档索引

> 所有正式文档（git tracked）集中在此。研究笔记、迭代草稿在
> `.agent-workplace/`（gitignored）。

## 核心文档

| 文件 | 用途 |
|------|------|
| [`architecture.md`](architecture.md) | 架构决策源：分层、包职责、依赖方向、Current decisions |
| [`architecture-packages.md`](architecture-packages.md) | 包依赖关系 Mermaid 图 + 各包功能说明 |
| [`status.md`](status.md) | 模块完成进度、已知限制、构建/验证命令 |
| [`lux-ir-design.md`](lux-ir-design.md) | Lucent IR 正式类型规范（schema spec） |
| [`api-protocol-converter.md`](api-protocol-converter.md) | 协议转换契约（4 端点对照 + 12-case 测试矩阵 + 6 函数契约；Gemini 已纳入矩阵） |
| [`fidelity-matrix.md`](fidelity-matrix.md) | 4×4 provider 转换保真度矩阵（切流决策依据） |
| [`provider-guide.md`](provider-guide.md) | Adapter 实现指南 |

## 变更单与验收

| 文件 | 用途 |
|------|------|
| [`cr/CR-001.md`](cr/CR-001.md) | 流式 usage 保真修复（D1 丢 `input_tokens` / D2 增量重复 Finish 覆盖 usage / D3 Done 先于 Usage / D4 未注入 `stream_options.include_usage`） |
| [`cr/CR-002.md`](cr/CR-002.md) | 相邻缺口收敛（A1 Gemini 流无会话元信息 / D5 逐帧提前终止 / A4 `message_start` 缓存项 / A3 `[Usage, Finish]` 序清零 / A5 截断流未闭合块） |
| [`cr/CR-003-block-discard-proposal.md`](cr/CR-003-block-discard-proposal.md) | **待决策提案**：`BlockDiscard` 流事件的去留（全链路无生产者；建议保留 + 标记，暂缓移除） |
| [`test-report.md`](test-report.md) | CR-001 变更针对性测试 + 关联影响点 + 核心回归报告 |
| [`dod.md`](dod.md) | CR-001 迭代验收 Checklist（DoD 核销，`all_passed: true`） |

## 规则

| 文件 | 用途 |
|------|------|
| [`rules/naming-conventions.md`](rules/naming-conventions.md) | 全仓命名规则（iteration-006/007 验收清单） |
| [`rules/lucent-ir-evolution.md`](rules/lucent-ir-evolution.md) | IR 变更治理：保真度边界、提案模板、破坏性变更判定 |

## 导航

- 包内 README：`src/lux/README.md`、`src/sdk/README.md`（文件索引 + 依赖规则）
- 研究笔记（gitignored）：`.agent-workplace/research/`
- 迭代计划/任务（gitignored）：`.agent-workplace/docs/plan/`、`.agent-workplace/docs/task/`
