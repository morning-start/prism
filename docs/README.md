# Prism 文档索引

> Prism 项目全部文档的导航入口。按「核心规范 → 决策记录 → 计划 → 任务 → 调研报告 → 规则」分层组织。
> 文档结构遵循 `AGENTS.md` 约定：`docs/plans/` 只放 roadmap 式规划，`docs/tasks/` 放任务分解。

## 快速导航

| 你需要找什么 | 前往 |
|------------|------|
| **Lux IR 正式规范**（API 与字段的唯一依据） | [`lux-ir-design.md`](./lux-ir-design.md) |
| **双场景需求**（SDK + 中转站 source of truth） | [`requirements.md`](./requirements.md) |
| **SDK 用法** | [`sdk-usage.md`](./sdk-usage.md) |
| **架构决策记录** | [`adr/`](./adr/) |
| **项目路线图与阶段计划** | [`plans/`](./plans/) |
| **任务分解与实施** | [`tasks/`](./tasks/) |
| **厂商协议对比与适配** | [`protocols/`](./protocols/) |
| **审计与调研报告** | [`report/`](./report/) |
| **接口字段归类与治理规则** | [`rules/`](./rules/) |

## 核心规范（docs/ 根）

| 文档 | 说明 | 状态 |
|------|------|------|
| [`lux-ir-design.md`](./lux-ir-design.md) | Lux IR 形式规范（v1），含 §9.1 消息级 reasoning 承载与跨协议映射表 | 现行 |
| [`requirements.md`](./requirements.md) | 双场景架构需求与时序 | 现行 |
| [`sdk-usage.md`](./sdk-usage.md) | 三层 SDK 使用指南 | 现行 |

## 决策记录（docs/adr/）

| 文档 | 主题 | 状态 |
|------|------|------|
| [`ADR-008-thinking-reasoning-unification.md`](./adr/ADR-008-thinking-reasoning-unification.md) | Thinking/Reasoning 架构统一（方案 B：`LucentMessage.reasoning` + 保留 content Thinking） | 已实施 |

## 计划与任务

### 路线图（docs/plans/）

| 文档 | 说明 |
|------|------|
| [`2026-08-01-project-roadmap.md`](./plans/2026-08-01-project-roadmap.md) | 项目总路线图（Phase 1-4） |
| [`2026-08-05-thinking-reasoning-unification.md`](./plans/2026-08-05-thinking-reasoning-unification.md) | Thinking/Reasoning 统一实施计划（双场景） |

### 任务分解（docs/tasks/）

| 文档 | 说明 |
|------|------|
| [`2026-08-05-thinking-reasoning-tasks.md`](./tasks/2026-08-05-thinking-reasoning-tasks.md) | Thinking/Reasoning 统一 Batch 编排（A-D，已全部完成） |

> 早期的 phase1-phase4 历史任务分解已随对应阶段交付归档，见 `docs/report/architecture-audit-2026-07-28.md` 与 git 历史。

## 厂商协议（docs/protocols/）

| 文档 | 说明 |
|------|------|
| [`README.md`](./protocols/README.md) | 协议分组总览与差异矩阵 |
| [`01-openai-completions.md`](./protocols/01-openai-completions.md) | OpenAI Chat Completions |
| [`02-openai-responses.md`](./protocols/02-openai-responses.md) | OpenAI Responses（含 Codex/Azure） |
| [`03-anthropic-messages.md`](./protocols/03-anthropic-messages.md) | Anthropic Messages |
| [`04-google-gemini.md`](./protocols/04-google-gemini.md) | Google Gemini（含 Vertex） |
| [`field-audit.md`](./protocols/field-audit.md) | 字段级审计 |

## 审计与调研报告（docs/report/）

| 文档 | 类型 | 状态 |
|------|------|------|
| [`architecture-audit-2026-07-28.md`](./report/architecture-audit-2026-07-28.md) | 架构与代码质量审计 | 历史 |
| [`cross-language-service-strategies.md`](./report/cross-language-service-strategies.md) | 跨语言服务策略调查 | 历史 |
| [`thinking-inconsistency-2026-08-04.md`](./report/thinking-inconsistency-2026-08-04.md) | Thinking/Reasoning 全厂商不一致调研 | **归档**（结论见 §9.1） |
| [`thinking-ideal-architecture-2026-08-04.md`](./report/thinking-ideal-architecture-2026-08-04.md) | Thinking/Reasoning 理想架构（未采用） | **归档**（ADR-008 方案 B） |

## 规则（docs/rules/）

| 文档 | 说明 |
|------|------|
| [`lucent-ir-evolution.md`](./rules/lucent-ir-evolution.md) | Lucent IR 演进与字段归类规则（五道门） |
| [`sdk-three-layer.md`](./rules/sdk-three-layer.md) | Prism SDK 三层架构设计 |
| [`audit-gaps.md`](./rules/audit-gaps.md) | 当前代码与实际缺口审计 |
