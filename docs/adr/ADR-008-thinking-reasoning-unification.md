# ADR-008: Thinking/Reasoning 架构统一方案

## 状态

**已实施**（2026-08-05）— 方案 B 已落地，但最终实现与本提案有差异。

> **实现差异说明**：本提案建议在 `LucentResponse` 增加 `reasoning: String?` 字段。
> 最终实现将 `reasoning` 放在 `LucentMessage` 上（`reasoning : LucentThinking? = None`），
> 因为消息级 reasoning 是 message 的属性（vLLM/DeepSeek 在 message 字段内），
> 且 `LucentResponse` 是多 choice 容器。`LucentResponse` 仅提供便捷访问方法
> `reasoning() : LucentThinking?`（取 `choices[0].message.reasoning`），不新增字段。
> 详见 `lux-ir-design.md` §1.2 和 §9.1。

## 背景

当前 Lux IR 将 thinking 设计为 `LucentContent::Thinking(LucentThinking)` content block 变体
（Anthropic 风格）。但行业调研（2026-08-04）发现 11 个厂商/API 形态存在 **4 种结构类型**，
包括消息级额外字段（vLLM/DeepSeek/Fireworks）、独立 Item/步类型（OpenAI Responses/Gemini
Interactions）、布尔标记（Gemini generateContent）。现有架构无法表达消息级 reasoning，
导致跨协议转换时信息丢失。

## 设计原则（引用 lucent-ir-evolution.md）

1. **转换正确性优先**：精确、有损、不支持必须可区分；不得静默丢弃。
2. **内容类型用代数和 + 元数据侧信道**：不一致字段用类型化侧信道，不强行统一。
3. **流式选 Anthropic 块生命周期作 canonical**：补齐差异事件，不做降级。
4. **SDK 面向任务而非字段表**：不改 `LucentContent` 的公共构造函数签名。

## 方案选项

### 方案 A：不修改 IR，只在适配器层处理

| 优点 | 缺点 |
|------|------|
| IR 零改动 | 消息级 reasoning 在 IR 中无表达，跨协议转换时被迫合成 content block，丢失消息级语义 |
| 适配器改动最小 | 多轮对话中 reasoning 的回传规则无法在 IR 层表达，适配器需自行追踪 |

**结论**：否决。违背"转换正确性优先"原则——消息级 reasoning 被静默降级为 content block。

### 方案 B（推荐）：在 LucentResponse 增加消息级 reasoning 字段

在 `LucentResponse` 中增加 `reasoning: String?` 消息级字段，保留 `LucentContent::Thinking`
作为 content block 变体。两种风格并存，适配器按协议选择填充/输出途径。

| 优点 | 缺点 |
|------|------|
| 改动最小（仅增一个字段） | 两种表达方式共存，适配器需判断 |
| 兼容现有 content block 的 thinking | 流式事件模型需要额外处理 |
| 消息级 reasoning 完整表达 | |
| 现有序列化向后兼容 | |

**结论**：推荐。符合"用代数和 + 侧信道"原则。

### 方案 C：完全重构 thinking 为独立模型

把 thinking 从 `LucentContent` 中分离为独立类型，支持消息级和 content block 级两种表达。

| 优点 | 缺点 |
|------|------|
| 最完整、最灵活 | 改动最大，breaking change 影响现有适配器 |
| 语义清晰 | 违背"SDK 面向任务而非字段表"原则 |
| 便于未来扩展 | 需要 version bump（v2），增加治理成本 |

**结论**：否决。过度工程，且当前阶段不宜引入 breaking change。

## 方案 B 详细设计

### 1. IR 结构体修改

#### 1.1 LucentResponse 增加 `reasoning` 字段

```moonbit
pub struct LucentResponse {
  schema_version : String = "v1"
  id : String
  model : String
  created : Int
  choices : Array[LucentChoice]
  usage : LucentUsage?
  reasoning : String?  // ← 新增：消息级推理文本（vLLM/DeepSeek 风格）
  extras : Map[String, Json]?
}
```

- `reasoning: String?` — 消息级推理文本，纯字符串，无签名
- 仅当源协议是消息级 reasoning 时填充（vLLM/DeepSeek/Fireworks）
- 当源协议是 content block 风格时，`reasoning` 为 `None`，thinking 内容在 `LucentContent::Thinking` 中

#### 1.2 LucentThinking 保留不变

```
LucentThinking {
  text : String           // 推理文本
  signature : String?      // 签名（Anthropic 风格）
  redacted : Bool          // 是否隐藏
  summary : Array[LucentContent]?  // 推理摘要（Gemini/OpenAI Responses 风格）
}
```

- 保留当前结构，`text` 和 `signature` 语义不变
- `summary` 字段已兼容 Gemini Interactions 和 OpenAI Responses 的 summary 数组

#### 1.3 LucentReasoningConfig 不变

```
LucentReasoningConfig {
  enabled : Bool
  budget_tokens : Int?
  effort : LucentReasoningEffort?
  summary : LucentReasoningSummary?
}
```

- 保留当前结构
- `effort` 值域（`LucentReasoningEffort`）当前为枚举，未来可扩展

### 2. 适配器入站规则

| 源协议 | 消息级 reasoning | content block thinking | 双存在 |
|--------|-----------------|----------------------|--------|
| **Anthropic** | — | `content[]` → `LucentContent::Thinking` | 只有 block |
| **OpenAI Chat** | 无（token 隐藏） | `content[]` 无 thinking | 无 |
| **OpenAI Responses** | `output[]` reasoning Item → `LucentResponse.reasoning`（summary 文本） | 无 | 独立 Item |
| **Gemini generateContent** | — | `thought:true` part → `LucentContent::Thinking` | 只有 block |
| **Gemini Interactions** | — | `thought` step → `LucentContent::Thinking`（summary 文本） | 只有 block |
| **vLLM** | `message.reasoning` → `LucentResponse.reasoning` | 无 | 只有消息级 |
| **DeepSeek** | `message.reasoning_content` → `LucentResponse.reasoning` | 无 | 只有消息级 |
| **Fireworks** | `message.reasoning_content` → `LucentResponse.reasoning` | 无 | 只有消息级 |
| **Mistral** | — | `ThinkChunk` → `LucentContent::Thinking` | 只有 block |
| **Cohere** | — | `thinking` chunk → `LucentContent::Thinking` | 只有 block |

**双存在规则**：Anthropic 等协议可能同时包含 `thinking` block 和最终文本。这属于正常情况。
`LucentResponse.reasoning` 和 `LucentContent::Thinking` 可以同时存在，语义为：
- `reasoning`：消息级推理（对 vLLM/DeepSeek 等协议）
- `Thinking(content)`：在 content 数组中的推理块（对 Anthropic 等协议）

### 3. 适配器出站规则

> 目标协议 = 标准形态：Anthropic / OpenAI Chat（含兼容端点）/ OpenAI Responses / Gemini。
> vLLM、DeepSeek、Fireworks 不是独立目标协议——它们是 **OpenAI Chat 兼容端点**（上游推理引擎），
> 其 `message.reasoning` / `reasoning_content` 是 OpenAI Chat 形态上的**字段名变体**，
> 出站时经 `reasoning_field` 声明切换（Batch E 已落地）。

| 目标协议 | 输出方式 |
|---------|---------|
| **Anthropic** | `LucentContent::Thinking` → `content[]` block；`LucentResponse.reasoning` 忽略（或合成 thinking block） |
| **OpenAI Chat（标准）** | `LucentResponse.reasoning` 忽略（标准 Chat API 无 reasoning 字段）；`LucentContent::Thinking` 忽略 + `Unsupported` 诊断 |
| **OpenAI Chat（兼容端点：vLLM/DeepSeek/Fireworks）** | `LucentResponse.reasoning` → `message.reasoning`（默认 vLLM 字段名）或 `message.reasoning_content`（经 `reasoning_field` 声明切换）；签名/redacted/summary 丢失 → `Degraded` |
| **OpenAI Responses** | `LucentResponse.reasoning` → `reasoning` Item（encrypted 或 summary）；`LucentContent::Thinking` + `reasoning` → 两个 Item |
| **Gemini generateContent** | `LucentContent::Thinking` → `thought:true` part；`LucentResponse.reasoning` → 合成 `thought:true` part |
| **Gemini Interactions** | `LucentContent::Thinking` → `thought` step；`LucentResponse.reasoning` → `thought` step（无签名 → `Degraded`） |
| **Mistral** | `LucentContent::Thinking` → `ThinkChunk`；`LucentResponse.reasoning` → 合成 `ThinkChunk` |

### 4. 流式事件模型

当前 Lux IR 的 `StreamEvent`（BlockStart/BlockDelta/BlockEnd）保持为 canonical 流式事件模型
（lucent-ir-evolution.md 原则 5）。各协议流式 thinking 的映射规则：

| 源协议流式 | → Lux IR StreamEvent | 说明 |
|-----------|----------------------|------|
| **Anthropic** `thinking_delta` | `BlockDelta(ThinkingDelta(text))` | 直接映射 |
| **Anthropic** `signature_delta` | `BlockDelta(SignatureDelta(sig))` | 直接映射 |
| **vLLM** `delta.reasoning` | `BlockStart(Thinking)` + `BlockDelta(ThinkingDelta(text))` | 合成 block 生命周期 |
| **DeepSeek** `delta.reasoning_content` | `BlockStart(Thinking)` + `BlockDelta(ThinkingDelta(text))` | 合成 block 生命周期 |
| **Gemini Interactions** `thought_summary` | `BlockStart(Thinking)` + `BlockDelta(ThinkingDelta(text))` | 合成 block 生命周期 |
| **Gemini Interactions** `thought_signature` | `BlockDelta(SignatureDelta(sig))` | 映射签名 |

**反向（出站流式）**：

| 目标协议流式 | 映射方式 |
|-------------|---------|
| **Anthropic** | `BlockDelta(ThinkingDelta)` → `thinking_delta`；`BlockDelta(SignatureDelta)` → `signature_delta` |
| **OpenAI Chat（兼容端点）** | `BlockDelta(ThinkingDelta)` → 累积后 `delta.reasoning`（或经 `reasoning_field` 切换为 `delta.reasoning_content`） |

### 5. 保真度契约

新增以下保真度边界：

| 边界 | 诊断级别 | 条件 |
|------|---------|------|
| `reasoning.signature` | `Degraded` | 目标协议无签名概念（OpenAI Chat 兼容端点/DeepSeek/Mistral/Cohere/Gemini generateContent） |
| `reasoning.redacted` | `Degraded` | `redacted_thinking` 内容不可见，只能保留 signature |
| `reasoning.encrypted` | `Degraded` | OpenAI Responses 的 `encrypted_content` 在目标协议中不可表达 |
| `reasoning.effort.none` | `Degraded` | 目标协议 `reasoning_effort` 值域不包含 `none` |
| `reasoning.effort.max` | `Degraded` | 目标协议 `reasoning_effort` 最大值为 `high` |
| `reasoning.summary` | `Degraded` | 目标协议不支持 summary 数组（如 Anthropic） |

### 6. 多轮对话规则

定义 `LucentReasoningContinuity` 枚举控制多轮对话中的 thinking 回传行为：

```moonbit
pub enum LucentReasoningContinuity {
  /// 自动管理（Anthropic 风格：signature 自动回传）
  Automatic
  /// 必须回传（DeepSeek/Fireworks 风格：有 tool call 时 reasoning_content 必须回传）
  Mandatory
  /// 忽略（无 tool call 时 DeepSeek 忽略 reasoning_content）
  Ignored
}
```

- 入站时适配器根据协议设置 `LucentResponse.reasoning` 的连续性
- 出站时适配器根据规则决定是否/如何回传

## 影响范围

### IR 层改动

- `LucentResponse` 增加 `reasoning: String?`（1 个字段，非 breaking）
- 所有其他结构体不变

### 适配器层改动

- **openai-chat**（入站）：解析 `message.reasoning` / `message.reasoning_content` → `LucentResponse.reasoning`
- **openai-chat**（流式入站）：解析 `delta.reasoning` / `delta.reasoning_content` → `BlockStart(Thinking)` + `ThinkingDelta`
- **openai-chat**（出站）：`LucentResponse.reasoning` → `message.reasoning`（OpenAI Chat 兼容端点默认字段名）或 `message.reasoning_content`（经 `reasoning_field` 切换）
- **openai-chat**（出站流式）：`ThinkingDelta` → `delta.reasoning` / `delta.reasoning_content`
- **openai-responses**（入站）：`reasoning` Item → `LucentResponse.reasoning`（summary 文本）
- **openai-responses**（出站）：`LucentResponse.reasoning` → `reasoning` Item
- **Gemini**（入站）：`thought:true` part → `LucentContent::Thinking`（已有，不变）
- **Gemini Interactions**（出站）：`LucentResponse.reasoning` → `thought` step（无签名产生 `Degraded`）

### 测试层

- 新增契约测试：跨协议 thinking round-trip（Anthropic thinking block ↔ vLLM reasoning 字段）
- 新增保真度测试：签名丢失产生 `Degraded` 诊断
- 新增流式测试：vLLM `delta.reasoning` → Lux IR StreamEvent → Anthropic `thinking_delta`

## 实施顺序

1. `LucentResponse` 增加 `reasoning: String?` 字段 + 序列化/反序列化（IR 层）
2. openai-chat 入站：解析 `message.reasoning` / `message.reasoning_content`（适配器层）
3. openai-chat 流式入站：解析 `delta.reasoning` / `delta.reasoning_content`
4. openai-chat 出站：`LucentResponse.reasoning` → `message.reasoning` / `reasoning_content`
5. 保真度诊断：签名丢失产生 `Degraded`
6. 跨协议契约测试

## 未解决问题

- 流式出站时，`reasoning` 字段的累积/拆分策略（vLLM 的 `delta.reasoning` 是增量，需要累积到 block 完整再发送）
- `LucentResponse.reasoning` 与 `LucentContent::Thinking` 同时存在时的优先级规则（出站时优先使用哪个？）
- Gemini Interactions 的 `thought_summary` 与 `LucentThinking.summary` 的融合策略