# Lucent IR 字段覆盖审计

> 按 docs/rules/lucent-ir-evolution.md 的五道门逐字段判定。
> 版本：v1 (2026-07-26)

---

## 结论摘要

| 结论 | 字段数 | 说明 |
|------|--------|------|
| ✅ **已在 IR 中** | — | Text, ToolUse, ToolResult, Thinking, Refusal, Image, Audio, Video, Role, ToolKind, FinishReason, ReasoningConfig, StructuredOutput 等 |
| ⚠️ **应按标准入 IR 但未加** | **1** | `store: Bool` |
| 🔶 **争议中，建议暂缓** | 1 | `parallel_tool_calls: Bool` |
| ⛔ **正确归属 extras** | 10+ | seed, logprobs, top_logprobs, background, truncation, include, context_management, system_fingerprint, mediaResolution, allowedFunctionNames 等 |
| ⛔ **正确归属 Transport** | 2 | previous_response_id, conversation (HTTP 状态管理) |
| ⛔ **正确归属 provider_payload** | 2 | moderation, content_filters |

---

## 逐字段判定详情

### ✅ 已有字段（形状改变 → 核心类型）

| 字段 | 协议 | IR 位置 | 判定过程 |
|------|------|---------|---------|
| `content[].type: text/tool_use/thinking/refusal/image` | 所有 | `LucentContent` 枚举 | 门1: 形状改变 — 消费方 match 分支处理 |
| `role: system/user/assistant/tool/model/developer` | 所有 | `LucentRole` 枚举 | 门1: 形状改变 — 角色不同处理不同 |
| `tool_calls[]` / `function_call` | 所有 | `LucentConversationItem::ToolCall` | 门1: 形状改变 — 工具执行路径不同 |
| `tool_result` / `function_call_output` | 所有 | `LucentConversationItem::ToolResult` | 门1: 形状改变 |
| `thinking` / `reasoning` | 所有 | `LucentConversationItem::Reasoning` | 门1: 形状改变 |
| `phase: commentary\|final_answer` | Codex | `LucentMessage.phase` | 门1: 形状改变 ✅ 已加 |
| `reasoning.effort: xhigh` | Codex | `LucentReasoningEffort::XHigh` | 门1: 形状改变 ✅ 已加 |
| `stop_reason` / `finishReason` / `status` | 所有 | `LucentFinishReason` | 门1: 形状改变 — 消费方判断是否继续 |
| `tools[].type: function/file_search/web_search/...` | 所有 | `LucentToolKind` | 门1: 形状改变 ✅ 已加 |
| `finish_reason: SAFETY/RECITATION` | Gemini | `LucentFinishReason::Safety/Recitation` | 门1: 形状改变 ✅ 已有 |
| `temperature` / `top_p` / `max_tokens` | 所有 | `LucentOptions` | 门2: 跨厂商控制参数 ✅ 已有 |
| `top_k` | Anthropic/Gemini | `LucentOptions.top_k` | 门2 ✅ 已有 |
| `stop_sequences` | 所有 | `LucentOptions.stop` | 门2 ✅ 已有 |
| `candidate_count` | Gemini | `LucentOptions.candidate_count` | 门2 ✅ 已有 |
| `response_format` / `text.format` | 所有 | `LucentStructuredOutput` | 门2 ✅ 已有 |
| `reasoning_tokens` / `thinking_tokens` | 所有 | `LucentUsage.reasoning_tokens` | 门2 ✅ 已有 |
| `cached_tokens` | OpenAI/Anthropic | `LucentUsage.cached_tokens` | 门2 ✅ 已有 |

---

### ⚠️ 应按标准入 IR 但未加

| 字段 | 协议 | 判定 | 建议位置 |
|------|------|------|---------|
| `store: Bool` | OpenAI Chat + Responses | 门1: ❌ 形状不改变。门2: ✅ 跨厂商（存储控制语义多家支持）。门3: ✅ 语义稳定。→ **可移植控制候选** | `LucentOptions.store: Bool?` |

**判定理由：** `store` 出现在 OpenAI Chat 和 OpenAI Responses 中，Anthropic 和 Gemini 也有类似的存储控制机制（虽然字段名不同）。这是一个跨厂商的生成行为控制参数，不改变对话形状，符合门2的"可移植控制候选"标准。

---

### 🔶 争议中，建议暂缓

| 字段 | 协议 | 判定 | 建议 |
|------|------|------|------|
| `parallel_tool_calls: Bool` | OpenAI Responses + Anthropic | 门1: ❌ 消费方应始终准备好处理多个tool result，无论模型是批还是顺序。门2: ✅ "并行调用"语义跨厂商存在。门3: ⚠️ 语义尚在演进中，部分模型不支持或行为不一致。→ **争议** | 暂 `extra`，待语义稳定后再入 `LucentOptions` |

---

### ⛔ 正确归属 extras / Transport

| 字段 | 协议 | 判定 | 归宿 |
|------|------|------|------|
| `seed: Int` | OpenAI Chat | 门4: 仅OpenAI ❌（Responses不支持） | `LucentOptions.extras`（当前已在 `Luc entOptions.seed`，标记 `@deprecated`） |
| `logprobs: Bool` | OpenAI Chat | 门4: 仅OpenAI | `LucentOptions.extras` |
| `top_logprobs: Int` | OpenAI Chat | 门4: 仅OpenAI | `LucentOptions.extras` |
| `moderation` | OpenAI Chat | 门4: 仅OpenAI | `provider_payload` |
| `system_fingerprint` | OpenAI Chat | 门4: 仅OpenAI | `provider_payload` |
| `previous_response_id` | OpenAI Responses | 门5: HTTP状态管理 | **Transport 层** |
| `conversation` | OpenAI Responses | 门5: HTTP状态管理 | **Transport 层** |
| `background: Bool` | OpenAI Responses | 门5: 改变调用模式 | **Transport 层** |
| `context_management` | OpenAI Responses | 门4: 仅OpenAI | `LucentRequest.extras` |
| `truncation` | OpenAI Responses | 门4: 仅OpenAI | `LucentRequest.extras` |
| `include` | OpenAI Responses | 门4: 仅OpenAI | `LucentRequest.extras` |
| `prompt_cache_options` | OpenAI Responses / Anthropic | 门3: ⚠️ 语义尚在演进（每家实现方式不同），暂孵化 | `LucentRequest.extras` |
| `metadata.user_id` | Anthropic | 门4: 仅Anthropic | `LucentRequest.metadata`（已有） |
| `thinking.type: enabled\|adaptive` | Anthropic | 门1: ❌ 消费方看到都是Thinking block。门4: 仅Anthropic的语义细分。 | `LucentReasoningConfig.extras` |
| `thinking.display: omitted` | Anthropic | 门4: 仅Anthropic | `LucentReasoningConfig.extras` |
| `thinking_level: minimal\|low\|medium\|high` | Gemini | 门2: ⚠️ 跨厂商概念（Anthropic有effort），但取值不同，语义未统一。 | `LucentReasoningConfig.extras` |
| `safetySettings` | Gemini | 门4: 仅Gemini | `LucentRequest.extras` |
| `allowedFunctionNames` | Gemini | 门4: 仅Gemini | `LucentToolChoice?` 或 `LucentRequest.extras` |
| `mediaResolution` | Gemini | 门4: 仅Gemini | `LucentOptions.extras` |

---

## 最终结论

**IR 在"对话形状"层面已经完整覆盖当前 4 家协议的所有语义单位。** 缺少的唯一一个字段是：

```moonbit
// LucentOptions 加一行
struct LucentOptions {
  ...
  store: Bool?            // 默认为 provider 行为（OpenAI: true, ZDR: false）
}
```

所有其他字段（logprobs, seed, background, moderation, truncation, include, thinking_level, parallel_tool_calls, 等）都已经**正确归类**到 `extras`、`provider_payload` 或 Transport 层。

**不需要大规模改动 IR。** 加一个 `store`，补一个 `LucentOptions.extras` 逃生舱，就完整了。
