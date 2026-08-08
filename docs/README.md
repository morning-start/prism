# Prism 文档索引

> 定稿文档（提交 git）在本目录 `docs/`。
> 过程文档（Agent 私有）在 `.agent-workplace/`。

## 快速导航

| 你需要找什么 | 前往 |
|------------|------|
| **Lux IR 正式规范** | [`lux-ir-design.md`](./lux-ir-design.md) |
| **架构设计（双场景）** | [`architecture.md`](./architecture.md) |
| **当前状态追踪** | [`status.md`](./status.md) |
| **SDK 用法** | [`sdk-usage.md`](./sdk-usage.md) |
| **架构决策记录** | [`adr/`](./adr/) |
| **厂商协议对比** | [`protocols/`](./protocols/) |
| **审计与调研报告** | [`report/`](./report/) |
| **治理规则** | [`rules/`](./rules/) |
| **任务分解（过程态）** | `.agent-workplace/docs/task/` |

## 核心规范

| 文档 | 说明 |
|------|------|
| [`lux-ir-design.md`](./lux-ir-design.md) | Lux IR 形式规范（v1），含 §9.1 reasoning 映射表 |
| [`architecture.md`](./architecture.md) | 双场景架构、6-Function 适配器契约 |
| [`status.md`](./status.md) | 各模块完成度与当前边界 |
| [`sdk-usage.md`](./sdk-usage.md) | 三层 SDK 使用指南 |

## 决策记录（docs/adr/）

| 文档 | 主题 |
|------|------|
| [`ADR-008-thinking-reasoning-unification.md`](./adr/ADR-008-thinking-reasoning-unification.md) | Thinking/Reasoning 统一（方案 B） |

## 厂商协议（docs/protocols/）

| 文档 | 说明 |
|------|------|
| [`README.md`](./protocols/README.md) | 协议分组总览与差异矩阵 |
| [`01-openai-completions.md`](./protocols/01-openai-completions.md) | OpenAI Chat Completions |
| [`02-openai-responses.md`](./protocols/02-openai-responses.md) | OpenAI Responses |
| [`03-anthropic-messages.md`](./protocols/03-anthropic-messages.md) | Anthropic Messages |
| [`04-google-gemini.md`](./protocols/04-google-gemini.md) | Google Gemini |
| [`field-comparison.md`](./protocols/field-comparison.md) | 字段级对比与审计 |

## 审计与报告（docs/report/）

| 文档 | 类型 |
|------|------|
| [`architecture-audit-2026-07-28.md`](./report/architecture-audit-2026-07-28.md) | 架构审计 |
| [`cross-language-service-strategies.md`](./report/cross-language-service-strategies.md) | 跨语言服务策略 |

## 规则（docs/rules/）

| 文档 | 说明 |
|------|------|
| [`lucent-ir-evolution.md`](./rules/lucent-ir-evolution.md) | IR 演进与字段归类（五道门） |
| [`sdk-three-layer.md`](./rules/sdk-three-layer.md) | SDK 三层架构 |
| [`audit-gaps.md`](./rules/audit-gaps.md) | 代码与规格缺口审计 |
