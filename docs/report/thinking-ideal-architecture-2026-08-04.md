# 如果推到重来：Thinking/Reasoning 架构理想设计

> **归档状态**：本文档是 2026-08-04 对「完全推到重来」架构的探索性设计（删除式重构，
> reasoning 与 content 平级）。**未采用**。正式采用的方案是 ADR-008 的**方案 B**（在
> `LucentResponse` 增消息级 `reasoning` 字段、保留 `LucentContent::Thinking` 作为块内
> 交错载体），落实现状见 `docs/lux-ir-design.md` §9.1。本文作为设计权衡记录保留，
> 不反映当前实现。

## 核心设计哲学

**thinking/reasoning 不是 `content` 的子类型，而是与 `content` 平级的消息组成部分。**

当前架构把 thinking 塞进 `LucentContent` 的变体，本质上是把"元信息"降级为"内容类型"。
推到重来的设计应该是：消息由「可见内容」和「推理过程」两个独立维度组成，互不包含。

---

## 1. 消息模型

### 1.1 LucentMessage

```moonbit
/// | 消息 — LLM 对话中的单一轮次
pub struct LucentMessage {
  role : LucentRole
  /// 可见内容（Text, ToolUse, ToolResult, Refusal, Image, Audio, Video）
  content : Array[LucentContent]
  /// 推理过程（可选）—— 与 content 平级，不是 content 的子类型
  reasoning : LucentReasoning?
  /// 拒绝消息（可选，与 content 互斥）
  refusal : String?
  /// 角色名称
  name : String?
  /// 工具调用（可选，与 content 中的 ToolUse 互斥或共存）
  tool_calls : Array[LucentToolCall]?
}
```

设计要点：
- `content` 只含可见内容（Text, ToolUse, ToolResult, Refusal, Image, Audio, Video）
- `reasoning` 是独立字段，与 `content` 平级
- `LucentContent` 去掉 `Thinking` 变体，thinking 不再伪装成"内容"

### 1.2 LucentReasoning

```moonbit
/// | 推理过程 — 覆盖所有厂商的 reasoning 附属信息
pub struct LucentReasoning {
  /// 推理文本（必填）
  text : String
  /// 签名（Anthropic 风格，完整性校验）
  signature : String?
  /// 加密推理内容（OpenAI Responses 风格，ZDR 场景）
  encrypted_content : String?
  /// 隐藏推理 — 是否被安全系统标记为隐藏（Anthropic redacted_thinking）
  redacted : Bool
  /// 隐藏推理的加密数据（Anthropic redacted_thinking 的数据）
  redacted_data : String?
  /// 推理摘要（Gemini Interactions / OpenAI Responses 风格，summary 数组转文本）
  summary : Array[LucentContent]?
  /// 推理级别 — 用于多轮对话中区分不同推理阶段
  level : LucentReasoningLevel?
}
```

### 1.3 LucentReasoningLevel

```moonbit
/// | 推理级别 — 跟踪多轮对话中的推理阶段
pub enum LucentReasoningLevel {
  /// 主推理（初始推理，默认）
  Primary
  /// 工具调用间的推理（interleaved thinking）
  Interleaved
  /// 最终推理后的收尾
  Final
}
```

### 1.4 LucentResponse 中的推理

```moonbit
pub struct LucentResponse {
  schema_version : String = "v1"
  id : String
  model : String
  created : Int
  choices : Array[LucentChoice]
  usage : LucentUsage?
  reasoning : String?           // 消息级推理摘要（快捷访问最后一个 choice 的 reasoning.text）
  extras : Map[String, Json]?
}

pub struct LucentChoice {
  index : Int
  message : LucentMessage
  finish_reason : LucentFinishReason?
  // message 已包含 reasoning，choice 层不需要额外字段
}
```

### 1.5 LucentContent 去掉 Thinking 变体

```moonbit
pub(all) enum LucentContent {
  Text(String, Array[LucentAnnotation]?)
  ToolUse(LucentToolUse)
  ToolResult(LucentToolResult)
  Refusal(String)
  Image(LucentMultimedia)
  Audio(LucentMultimedia)
  Video(LucentMultimedia)
  Native(String, Json)
}
// Thinking 已移除 — 移到 LucentMessage.reasoning 字段
```

---

## 2. 流式事件模型

### 2.1 新增 Reasoning 事件类型

```moonbit
pub enum StreamEvent {
  // 现有：block 生命周期（Text, ToolCall 等可见内容）
  BlockStart(Int, LucentBlockType)
  BlockDelta(Int, LucentBlockDelta)
  BlockEnd(Int)

  // 新增：推理生命周期（消息级，与 block 平级）
  ReasoningStart(String?)        // 推理开始（可选 signature）
  ReasoningDelta(String)         // 推理增量
  ReasoningSignature(String)     // 签名增量
  ReasoningEnd                   // 推理结束

  // 现有
  Finish(LucentFinishReason)
  Discard(Int)
  Meta(LucentMetaEvent)
  Error(LucentStreamError)
  Annotation(Int, LucentAnnotation)
}
```

### 2.2 各厂商流式映射

| 源协议 | → Lux IR StreamEvent |
|--------|---------------------|
| **Anthropic** `thinking_delta` | `ReasoningDelta(text)` |
| **Anthropic** `signature_delta` | `ReasoningSignature(sig)` |
| **Anthropic** `content_block_start(thinking)` | `ReasoningStart(sig?)` |
| **Anthropic** `content_block_stop(thinking)` | `ReasoningEnd` |
| **vLLM** `delta.reasoning` | `ReasoningDelta(text)` |
| **DeepSeek** `delta.reasoning_content` | `ReasoningDelta(text)` |
| **Gemini** `thought_summary` | `ReasoningDelta(text)` |
| **Gemini** `thought_signature` | `ReasoningSignature(sig)` |
| **Gemini** `step.start(thought)` | `ReasoningStart(sig?)` |
| **Gemini** `step.stop(thought)` | `ReasoningEnd` |
| **Mistral** `delta.content` 含 ThinkChunk | `ReasoningDelta(text)` |

### 2.3 流式出站规则

| 目标协议 | 映射方式 |
|---------|---------|
| **Anthropic** | `ReasoningStart` → `content_block_start(thinking)`；`ReasoningDelta` → `thinking_delta`；`ReasoningSignature` → `signature_delta`；`ReasoningEnd` → `content_block_stop` |
| **OpenAI Chat（兼容端点）** | 累积所有 `ReasoningDelta` 文本 → `delta.reasoning`（默认）或经 `reasoning_field` 切换为 `delta.reasoning_content` |
| **Gemini** | `ReasoningDelta` → `thought_summary`；`ReasoningSignature` → `thought_signature` |

---

## 3. 请求配置

### 3.1 LucentReasoningConfig

```moonbit
pub struct LucentReasoningConfig {
  enabled : Bool                          // 是否启用推理
  budget_tokens : Int?                    // 推理 token 预算
  effort : LucentReasoningEffort?         // 推理努力级别
  mode : LucentReasoningMode?             // 推理模式（standard/pro）
  summary : LucentReasoningSummary?       // 摘要类型
  continuity : LucentReasoningContinuity  // 多轮连续性规则
}

pub enum LucentReasoningEffort {
  None         // 关闭推理（OpenAI none, Mistral none）
  Minimal      // 最小推理（OpenAI minimal, Gemini minimal）
  Low          // 低推理（OpenAI low, Gemini low, DeepSeek low）
  Medium       // 中推理（OpenAI medium, Gemini medium, DeepSeek high）
  High         // 高推理（OpenAI high, Gemini high, Mistral high）
  XHigh        // 极高推理（OpenAI xhigh）
  Max          // 最大推理（OpenAI max）
}

pub enum LucentReasoningMode {
  Standard     // 标准模式
  Pro          // 专业模式（OpenAI GPT-5.6 pro）
}

pub enum LucentReasoningSummary {
  None         // 不生成摘要
  Concise      // 简洁摘要
  Detailed     // 详细摘要
  Auto         // 自动选择
}

pub enum LucentReasoningContinuity {
  /// 自动管理（Anthropic 风格：signature 自动回传）
  Automatic
  /// 必须回传（DeepSeek/Fireworks 风格：有 tool call 时必须回传）
  Mandatory
  /// 忽略（无 tool call 时 DeepSeek 忽略 reasoning_content）
  Ignored
}
```

### 3.2 各厂商配置映射

| 厂商 | `effort` 映射 | 特殊参数 |
|------|-------------|---------|
| **OpenAI Chat** | `None`/`Minimal`/`Low`/`Medium`/`High`/`XHigh`/`Max` | `reasoning.mode` → `Standard`/`Pro` |
| **Anthropic** | `Enabled`/`Disabled`（无 effort 级别） | `budget_tokens` 控制 |
| **DeepSeek** | `Low`/`Medium`/`High` | `thinking.type` = `enabled` |
| **Gemini** | `Minimal`/`Low`/`Medium`/`High` | `thinking_level` + `thinking_summaries` |
| **Mistral** | `None`/`High` | `reasoning_effort` |
| **vLLM** | 无（由 parser 控制） | `thinking_token_budget` + `--reasoning-parser` |

---

## 4. 入站归一化规则

所有协议入站时，统一归一化到 `LucentMessage.reasoning` 字段：

| 源协议 | 源字段位置 | → `LucentMessage.reasoning` |
|--------|-----------|---------------------------|
| **Anthropic** | `content[]` 中 `type: thinking` block | 提取到 `reasoning.text`；`signature` → `reasoning.signature`；`redacted` → `reasoning.redacted`；`data` → `reasoning.redacted_data` |
| **OpenAI Chat** | `usage.output_tokens_details.reasoning_tokens`（仅计数，不暴露内容） | 不产生 reasoning（内容不可见） |
| **OpenAI Responses** | `output[]` 中 `type: reasoning` Item | `summary` 文本 → `reasoning.text`；`encrypted_content` → `reasoning.encrypted_content` |
| **vLLM** | `message.reasoning` | `reasoning.text` |
| **DeepSeek** | `message.reasoning_content` | `reasoning.text` |
| **Fireworks** | `message.reasoning_content` | `reasoning.text` |
| **Gemini generateContent** | `part` 中 `thought: true` 标记 | `text` → `reasoning.text`（无 signature） |
| **Gemini Interactions** | `steps[]` 中 `type: thought` 步 | `summary` 文本 → `reasoning.text`；`signature` → `reasoning.signature` |
| **Mistral** | `content[]` 中 `type: thinking` chunk | `thinking` 文本 → `reasoning.text` |
| **Cohere** | `content[]` 中 `type: thinking` chunk | `thinking` 文本 → `reasoning.text` |

这样 `content[]` 数组在 IR 中只保留**可见内容**，thinking 不再混杂其中。

---

## 5. 出站展开规则

| 目标协议 | `LucentMessage.reasoning` → 目标格式 |
|---------|-------------------------------------|
| **Anthropic** | `text` + `signature` → `content[]` 中插入 `{type: "thinking", thinking: text, signature: sig}`；`redacted` → `{type: "redacted_thinking", signature: sig}` |
| **OpenAI Chat（标准）** | 无 reasoning 字段，忽略（或 `reasoning_tokens` 计数） |
| **OpenAI Chat（兼容端点：vLLM/DeepSeek/Fireworks）** | → `message.reasoning`（默认）或经 `reasoning_field` 切换为 `message.reasoning_content` |
| **OpenAI Responses** | → `output[]` 中 `reasoning` Item（`summary` + `encrypted_content`） |
| **Gemini generateContent** | → `part` 中插入 `{text: reasoning.text, thought: true}` |
| **Gemini Interactions** | → `steps[]` 中 `thought` 步（`summary` + `signature`） |
| **Mistral** | → `content[]` 中插入 `ThinkChunk` |
| **Cohere** | → `content[]` 中插入 `thinking` chunk |

---

## 6. 保真度契约

| 边界 | 诊断 | 条件 |
|------|------|------|
| `reasoning.signature` 丢失 | `Degraded` | 目标协议无签名概念 |
| `reasoning.redacted` 不可逆 | `Degraded` | 隐藏推理内容不可见 |
| `reasoning.encrypted_content` 不可表达 | `Degraded` | 目标协议不支持加密内容 |
| `reasoning.summary` 结构丢失 | `Degraded` | 目标协议不支持 summary 数组 |
| `reasoning.effort` 值域降级 | `Degraded` | 目标协议 effort 值域不完整 |
| 完全无 reasoning 支持 | `Unsupported` | 目标协议不支持任何形式的思考（如 gpt-3.5-turbo） |

---

## 7. 与当前架构的对比

| 维度 | 当前架构 | 推到重来的设计 |
|------|---------|--------------|
| **thinking 位置** | `LucentContent::Thinking`（content 子类型） | `LucentMessage.reasoning: LucentReasoning?`（与 content 平级） |
| **入站处理** | 各协议分别处理，openai-chat 不捕获 reasoning | 所有协议归一化到 `LucentMessage.reasoning` |
| **出站处理** | 各协议分别输出，openai-chat 忽略 Reasoning（Unsupported） | 按目标协议选择输出方式 |
| **流式事件** | 只有 block 生命周期，消息级 reasoning 需合成 block | 新增 `ReasoningStart/Delta/Signature/End` 事件 |
| **content 数组** | 含 Thinking 变体，content 和 thinking 混杂 | 只含可见内容，thinking 在独立字段 |
| **适配器代码** | 入站出站都需处理两种 thinking 位置 | 入站归一化 → 出站展开，逻辑更清晰 |
| **SDK 用户** | `c.content` 需过滤 Thinking 变体 | `c.content` 都是可见内容，`c.reasoning` 单独访问 |
| **向后兼容** | ✅ 兼容 v1 序列化 | ❌ breaking |
| **实施成本** | 低（1 个字段） | 中（新增事件类型 + 改适配器入站逻辑） |

---

## 8. 渐进式迁移路径

### 阶段一：当前方案（ADR-008 方案 B）

在 `LucentResponse` 增加 `reasoning: String?`，保留 `LucentContent::Thinking`。
- 成本低，快速解决 vLLM/DeepSeek 的 reasoning 捕获问题
- 适配器改动最小
- 是"补丁"而非"根本解决"

### 阶段二：归一化（理想架构的第一步）

在 `LucentMessage` 增加 `reasoning: LucentReasoning?`，保留 `LucentContent::Thinking`。
- 入站时：`LucentContent::Thinking` 中的内容同步到 `LucentMessage.reasoning`
- 出站时：优先使用 `LucentMessage.reasoning`，回退到 `LucentContent::Thinking`
- 兼容阶段一的序列化格式

### 阶段三：清理（理想架构完成）

`LucentContent` 去掉 `Thinking` 变体，`schema_version` 升到 v2。
- `content` 数组只含可见内容
- 所有 thinking 通过 `LucentMessage.reasoning` 访问
- 流式事件增加 `ReasoningStart/Delta/Signature/End`
- 入站适配器更新：不再合成 `LucentContent::Thinking`，直接填充 `reasoning` 字段
- 出站适配器更新：从 `reasoning` 字段展开，按目标协议选择输出方式