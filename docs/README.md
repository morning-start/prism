# Prism 正式文档索引

> 所有正式文档（git tracked）集中在此。过程态工作区 `.agent-workplace/` 已于
> 2026-10-24 退役；跨 Agent 共享的需求池/任务板/风险/变更记录在 DSH 侧
> `team-workspace/docs/`（仓库外）。

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
| [`design/finish-reason-contract.md`](design/finish-reason-contract.md) | **设计说明**：finish_reason / status 的封闭枚举裁决模型（目标白名单裁决、诊断判据是「信息损失」而非「值被改动」、四目标映射依据、既有约定的逐条审视） |

## 变更单与验收

| 文件 | 用途 |
|------|------|
| [`cr/CR-001.md`](cr/CR-001.md) | 流式 usage 保真修复（D1 丢 `input_tokens` / D2 增量重复 Finish 覆盖 usage / D3 Done 先于 Usage / D4 未注入 `stream_options.include_usage`） |
| [`cr/CR-002.md`](cr/CR-002.md) | 相邻缺口收敛（A1 Gemini 流无会话元信息 / D5 逐帧提前终止 / A4 `message_start` 缓存项 / A3 `[Usage, Finish]` 序清零 / A5 截断流未闭合块） |
| [`cr/CR-003-block-discard-proposal.md`](cr/CR-003-block-discard-proposal.md) | **已决策（B，2026-10-23）**：`BlockDiscard` 保留 + 标记 deprecated（全链路无生产者；移除为破坏性变更暂缓；无生产者事实由 `stream_event_coverage_test` 锁定） |
| [`cr/CR-004.md`](cr/CR-004.md) | IR 字段级保真度修复（P0-2 / P0-3）：`malformed_tool_call` wire 值对齐 schema（旧拼写兼容读取）；`LucentMediaSource` schema 漂移修复（schema 与实现对齐为对象形状） |
| [`cr/CR-005-stop-sequence-carrier.md`](cr/CR-005-stop-sequence-carrier.md) | **已决策并实施（B）**：`LucentChoice.stop_sequence`（实际命中的终止序列）。缺陷 A（非流式无载体）/ B（流式与非流式解出不同 IR 值）/ C（**流式溢出非法枚举**）全部修复。跨端与流式均为显式诊断而非静默丢弃 |
| [`cr/CR-006-stream-termination.md`](cr/CR-006-stream-termination.md) | **已全部落地（0.1.5 + 0.2.0）**：`Finish(reason, stop_sequence?)` 载荷（破坏性，方案 A 获批）+ 5 类流式终止信息静默丢弃修复（responses incomplete/failed/error 事件、gemini blockReason 拦截不再伪装正常结束） |
| [`test-report.md`](test-report.md) | CR-001 变更针对性测试 + 关联影响点 + 核心回归报告 |
| [`dod.md`](dod.md) | CR-001 迭代验收 Checklist（DoD 核销，`all_passed: true`） |

## 规则

| 文件 | 用途 |
|------|------|
| [`rules/naming-conventions.md`](rules/naming-conventions.md) | 全仓命名规则（iteration-006/007 验收清单） |
| [`rules/lucent-ir-evolution.md`](rules/lucent-ir-evolution.md) | IR 变更治理：保真度边界、提案模板、破坏性变更判定 |
| [`rules/conformance-oracle.md`](rules/conformance-oracle.md) | 官方 schema 校验（Node oracle）：五组检查、豁免治理、CI 与 `scripts/verify.sh` 接入 |

## 计划与报告

| 文件 | 用途 |
|------|------|
| [`reports/iteration-003-acceptance.md`](reports/iteration-003-acceptance.md) | iteration-003 验收报告 |
| [`superpowers/plans/2026-09-10-provider-metadata-single-source-plan.md`](superpowers/plans/2026-09-10-provider-metadata-single-source-plan.md) | provider 元数据单一来源：实施计划 |
| [`superpowers/specs/2026-09-10-provider-metadata-single-source-design.md`](superpowers/specs/2026-09-10-provider-metadata-single-source-design.md) | provider 元数据单一来源：设计稿 |

## 导航

- 包内 README：`src/lux/README.md`、`src/sdk/README.md`（文件索引 + 依赖规则）
- 使用指南：根目录 [`USAGE.md`](../USAGE.md)（MoonBit / Go / TS wrapper + 4 场景）
- 跨 Agent 共享文档（需求池/任务板/风险/变更记录）：DSH 侧 `team-workspace/docs/`（仓库外）
