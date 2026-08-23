# 兼容字段清单（Compatibility Fields）

> 目标：回答「要实现一个协议适配器（Provider），需要支持哪些字段」。
> 视角：从协议侧（而非 IR 侧）列出每个协议的最小兼容集 + 完整字段集。
>
> 配套文档：
> - 字段在 Lucent IR 的归属判定 → [`field-comparison.md`](./field-comparison.md)
> - 字段归类五道门规则 → [`../rules/lucent-ir-evolution.md`](../rules/lucent-ir-evolution.md)
> - 各协议字段语义详述 → [`01`](./01-openai-completions.md) / [`02`](./02-openai-responses.md) / [`03`](./03-anthropic-messages.md) / [`04`](./04-google-gemini.md)
>
> 版本：v1 (2026-08-23)

---

## 0. 术语

| 术语 | 含义 |
|------|------|
| **最小兼容集（必填）** | 协议硬性要求、缺失即请求失败或无意义的字段，适配器必须读写。 |
| **完整字段集** | 协议文档公开的全部请求/响应/流式字段，适配器应尽量支持，不支持需显式 `Unsupported` 诊断。 |
| **可选字段** | 缺失时协议走默认行为，适配器可忽略或透传到 `extras`。 |

---

## 1. 最小兼容集（四协议必填字段）

| 协议 | 必填字段 | 备注 |
|------|---------|------|
| OpenAI Chat Completions | `model`、`messages` | `messages` 至少一条 |
| OpenAI Responses | `model`、`input` | `input` 可为字符串或 item 数组 |
| Anthropic Messages | `model`、`max_tokens`、`messages` | `max_tokens` 为 Anthropic 特有必填 |
| Google Gemini (generateContent) | `contents` | `model` 在 URL path（`models/{model}:generateContent`） |

> 关键差异：只有 Anthropic 把 `max_tokens` 列为必填；Gemini 的最小集不含 `model`（在路径而非 body）。

---

## 2. 完整字段清单（按协议，2026-08 最新）

### 2.1 OpenAI Chat Completions

| 字段 | 类型 | 必填 | 状态 | 新增于 |
|------|------|:---:|------|--------|
| `model` | string | ✅ | 已支持 | — |
| `messages` | array | ✅ | 已支持 | — |
| `modalities` | array<string> | — | ⚠️ 待评估 | 2026（音频输出） |
| `audio` | object `{format, voice}` | — | ⚠️ 待评估 | 2026（音频输出） |
| `max_completion_tokens` | int | — | 已支持（新名） | 替代弃用的 `max_tokens` |
| `reasoning_effort` | enum | — | 已支持 | — |
| `verbosity` | enum `low/medium/high` | — | ⚠️ 待评估 | GPT-5 专用 |
| `response_format` | object | — | 已支持 | — |
| `tools` / `tool_choice` | — | — | 已支持 | — |
| `parallel_tool_calls` | bool | — | 争议（extra） | — |
| `seed` | int | — | 已支持（@deprecated） | — |
| `store` | bool | — | 已支持 | — |
| `temperature` / `top_p` / `stop` / `n` / `stream` | — | — | 已支持 | — |
| `stream_options` | object | — | 未入 IR（流式细节） | — |
| `frequency_penalty` / `presence_penalty` | number | — | 归 extras | — |
| `logit_bias` | map | — | 归 extras | — |
| `logprobs` / `top_logprobs` | — | — | 归 extras | — |
| `prediction` | object | — | 未入 IR（推测解码） | — |
| `service_tier` | enum | — | 归 extras | — |
| `user` | string | — | 归 extras | — |

### 2.2 OpenAI Responses

| 字段 | 类型 | 必填 | 状态 | 新增于 |
|------|------|:---:|------|--------|
| `model` | string | ✅ | 已支持 | — |
| `input` | string/array | ✅ | 已支持 | — |
| `instructions` | string | — | 已支持 | — |
| `tools` / `tool_choice` | — | — | 已支持 | — |
| `parallel_tool_calls` | bool | — | 争议（extra） | — |
| `max_output_tokens` | int | — | 已支持 | — |
| `reasoning` | object `{effort, ...}` | — | 已支持 | — |
| `store` | bool | — | 已支持 | — |
| `metadata` | map | — | 已支持 | — |
| `top_p` / `temperature` | — | — | 已支持 | — |
| `stop` | string/array | — | 已支持 | — |
| `truncation` | enum `auto/disabled` | — | 归 extras | — |
| `background` | bool | — | Transport 层 | — |
| `context_management` | array | — | 归 extras（compaction） | — |
| `conversation` | string/object | — | Transport 层（HTTP 状态） | — |
| `include` | array | — | 归 extras | — |
| `previous_response_id` | string | — | Transport 层 | — |
| `prompt_cache_key` | string | — | 归 extras | — |
| `prompt_cache_retention` | enum | — | 归 extras | — |
| `max_tool_calls` | int | — | 未入 IR | — |
| `safety_identifier` | string | — | 归 extras | — |
| `prompt` | object | — | 未入 IR（prompt 模板引用） | — |

### 2.3 Anthropic Messages

| 字段 | 类型 | 必填 | 状态 | 新增于 |
|------|------|:---:|------|--------|
| `model` | string | ✅ | 已支持 | — |
| `max_tokens` | int | ✅ | 已支持 | — |
| `messages` | array | ✅ | 已支持 | — |
| `system` | string/array | — | 已支持 | — |
| `tools` | array | — | 已支持（`input_schema`） | — |
| `tool_choice` | object | — | 已支持 | — |
| `strict` | bool | — | ⚠️ 待评估 | 结构化输出严格校验 |
| `temperature` / `top_p` / `top_k` / `stop_sequences` | — | — | 已支持 | — |
| `stream` | bool | — | 已支持 | — |
| `thinking` | object `{type, budget_tokens, display}` | — | 已支持 | — |
| `output_config` | object `{effort, format}` | — | ⚠️ 待评估 | 2026（`output_format` → `output_config.format` 迁移） |
| `metadata` | object | — | 已支持 | — |

### 2.4 Google Gemini — generateContent

| 字段 | 类型 | 必填 | 状态 | 新增于 |
|------|------|:---:|------|--------|
| `contents` | array | ✅ | 已支持 | — |
| `systemInstruction` | object | — | 已支持 | — |
| `tools` | array | — | 已支持（`functionDeclarations`） | — |
| `toolConfig` | object | — | 已支持 | — |
| `generationConfig.temperature` / `topP` / `topK` / `maxOutputTokens` / `stopSequences` | — | — | 已支持 | — |
| `generationConfig.candidateCount` | int | — | 已支持 | — |
| `generationConfig.responseMimeType` / `responseSchema` | — | — | 已支持（结构化输出） | — |
| `generationConfig.thinking_config` | object `{thinkingBudget, includeThoughts}` | — | 已支持（旧） | — |
| `generationConfig.thinkingConfig.thinking_level` | enum `minimal/low/medium/high` | — | ⚠️ 待评估 | 2026（Gemini 3，替代 thinkingBudget） |
| `safetySettings` | array | — | 归 extras | — |
| `mediaResolution` | enum | — | 归 extras | — |
| `allowedFunctionNames` | array | — | 归 extras | — |

### 2.5 Google Gemini — Interactions API（Gemini 3 新范式）

> 2026-06 起 GA，Google 官方推荐新项目使用；generateContent 降级为 legacy 但仍支持。
> 当前 Prism 的 `gemini` 适配器实现的是 generateContent，Interactions API 为**独立新端点**。

| 维度 | generateContent（legacy） | Interactions API（新） |
|------|--------------------------|----------------------|
| 端点 | `POST /v1beta/models/{model}:generateContent` | `POST /v1beta2/interactions` |
| 输入 | `contents[].parts[]` | `input`（string/block） |
| 输出 | `candidates[0].content.parts[]` | `steps[]` timeline（`thought`/`function_call`/`model_output`） |
| 多轮 | 客户端重发全历史 | `previous_interaction_id` 服务端续接 |
| 思考 | `thoughtsTokenCount` 计数 | `steps[type:thought]` 显式步骤 |
| 后台 | 不支持 | `background: true` |
| 存储 | 默认不存 | `store: true` 默认（可 `store:false`） |

**决策：** 是否新增 `gemini-interactions` 适配器属于「新协议范式」决策，见 [§4 gap](#4-缺口与待评估字段)。

---

## 3. 跨协议字段映射（Lucent IR 视角）

下表是「四协议 → Lucent IR」的一张精简映射，完整判定见 [`field-comparison.md`](./field-comparison.md)。

| 语义 | OpenAIChat | OpenAI Responses | Anthropic | Gemini | Lucent IR |
|------|-----------|------------------|-----------|--------|-----------|
| 模型 | `model` | `model` | `model` | `model`（path） | `LucentRequest.model` |
| 系统指令 | 首条 system/developer 消息 | `instructions` | `system` | `systemInstruction` | `LucentRequest.instructions` |
| 对话 | `messages[]` | `input[]` | `messages[]` | `contents[]` | `LucentRequest.conversation` |
| 工具 | `tools[].function` | `tools[]` | `tools[].input_schema` | `tools[].functionDeclarations` | `LucentRequest.tools` |
| 采样温度 | `temperature` | `temperature` | `temperature` | `generationConfig.temperature` | `LucentOptions.temperature` |
| 核采样 | `top_p` | `top_p` | `top_p` | `topP` | `LucentOptions.top_p` |
| Top-K | — | — | `top_k` | `topK` | `LucentOptions.top_k` |
| 最大输出 | `max_completion_tokens` | `max_output_tokens` | `max_tokens` | `maxOutputTokens` | `LucentOptions.max_output_tokens` |
| 停止序列 | `stop` | `stop` | `stop_sequences` | `stopSequences` | `LucentOptions.stop` |
| 候选数 | `n` | — | — | `candidateCount` | `LucentOptions.candidate_count` |
| 结构化输出 | `response_format` | `text.format` | `output_config.format` | `responseSchema` | `LucentStructuredOutput` |
| 推理力度 | `reasoning_effort` | `reasoning.effort` | `output_config.effort` | `thinking_level` | `LucentReasoningConfig.effort` |
| 思考预算 | — | — | `thinking.budget_tokens` | `thinkingBudget` | `LucentReasoningConfig.budget_tokens` |
| 存储控制 | `store` | `store` | —（ZDR） | `store`（Interactions） | `LucentOptions.store` |
| 并行调用 | `parallel_tool_calls` | `parallel_tool_calls` | —（自动交错） | —（自动） | 争议 → `extras` |

---

## 4. 缺口与待评估字段

> 以下字段是本次网络搜索新确认、但 IR 尚未覆盖或归属待定的字段。改动任何 Lucent IR 字段前须走 [`../rules/lucent-ir-evolution.md`](../rules/lucent-ir-evolution.md) 五道门。

| # | 字段 | 协议 | 缺口 | 建议处置 |
|---|------|------|------|---------|
| 1 | `audio` + `modalities` | OpenAI Chat | 音频输出配置无 IR 承载位 | 门2 评估：音频输出跨厂商（Gemini 也支持），候选 `LucentOptions.audio` 或归 `extras` |
| 2 | `output_config.format` | Anthropic | 结构化输出从 `output_format` 迁移到了 `output_config.format`，适配器需对齐新形状 | 确认适配器编码/解码新路径，`LucentStructuredOutput` 本身不变 |
| 3 | `thinking_level` | Gemini 3 | 替代 `thinkingBudget`，取值 `minimal/low/medium/high` | 映射到 `LucentReasoningConfig.effort`，替换旧的 budget 映射 |
| 4 | Interactions API | Gemini 3 | 全新端点/请求/响应范式 | 架构决策：新增 `gemini-interactions` 适配器（对齐 OpenAI Responses vs Chat 的双接口模式） |
| 5 | `verbosity` | OpenAI Chat（GPT-5） | 输出详尽度，无 IR 承载位 | 门4：仅 OpenAI → `extras` |
| 6 | `strict` | Anthropic | 工具严格 schema 校验开关 | 门4：仅 Anthropic → `extras` |
| 7 | `max_tool_calls` | OpenAI Responses | 内置工具总调用上限 | 门4：仅 OpenAI → `extras` |
| 8 | `seed` 一等字段 | OpenAI Chat | 已 `@deprecated` 但仍是一等字段，未移入 extras | 收尾迁移到 `LucentOptions.extras` |
| 9 | `store` 归属歧义 | OpenAI ×2 | 已实现为 `LucentOptions.store`（一等字段），但治理规则示例表仍归 `extra` | 同步治理规则示例表，确认 `store` 为可移植控制候选 |

---

## 5. 变更记录

| 日期 | 更新内容 |
|------|---------|
| 2026-08-23 | 首次汇总：四协议最小兼容集 + 完整字段清单 + 跨协议映射 + 9 项 gap |
| 2026-08-23 | gap 收尾：#8 seed 迁移至 extras；#9 store 归类可移植控制；#5/#6/#7 确认 verbosity/strict/max_tool_calls 经 catch-all 自动归 extras |