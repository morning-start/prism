# Lux IR 设计规范

> Prism 自研中立中间协议（Lucent IR）的形式规范。
> 本文件是 `protocol/lux/` 包实现的**唯一依据**，所有适配器以此为准。
> 版本：`schema_version = "v1"`

---

## 0. 设计目标与使用场景

Lucent IR 同时服务两个场景，优先级不可倒置：

1. **协议转换基础设施**：供中间站、网关、代理和兼容层通过 `Source -> Lucent -> Target` 转换请求、响应与流事件。硬门槛是转换保真、显式能力边界和不静默丢失。
2. **工作流与 Agent SDK**：供应用直接构造上下文、注册工具、消费生成、提交工具结果并判断下一步。目标是稳定、任务导向、可组合、可发现且容易写对。

场景一的正确性是场景二的前置条件。不得为了 SDK 表面简洁牺牲转换语义，也不得为了保留 Provider 原始形状把 SDK 核心退化为不透明 JSON。

设计原则、字段归类标准、向后兼容策略和演进流程已独立到 [`docs/rules/lucent-ir-evolution.md`](rules/lucent-ir-evolution.md)，本文档不再重复。

在此前提下，本规范还必须：

1. **有效适配所有已知接口** — OpenAI Chat / Anthropic Messages / OpenAI Responses / Google Gemini 四家接口在同一 IR 下无扭曲适配。
2. **允许未来接口接入** — 新增厂商按「能力归类 → 消息映射 → 内容映射 → 扩展归类 → 实现 6 函数」流程接入，不随意改动 IR 骨干。
3. **支持 Agent/工作流的稳定状态机** — 对话、工具、推理、结束、错误、用量和流式生命周期具有统一消费语义。

---

## 1. 核心类型

### 1.1 会话骨干：`LucentConversationItem`

把「消息数组」升级为「会话项数组」—— 异质，平级承载消息/工具调用/工具结果/推理/Agent 动作。传统 messages 模型当作 `Item::Message` 的特例。

```moonbit
pub enum LucentConversationItem {
  Message(LucentMessage)             // OpenAI Chat / Anthropic / Gemini 的 messages/contents
  ToolCall(LucentToolUse)            // OpenAI Responses 的 function_call Item
  ToolResult(LucentToolResult)       // OpenAI Responses 的 function_call_output Item
  Reasoning(LucentThinking)          // OpenAI Responses 的 reasoning Item
  AgentAction(LucentAgentAction)     // OpenAI Responses 的 computer_call / 未来 agent 步骤
}
```

**适配收益**：
- OpenAI Chat 适配器把 `messages[]` 每条映射为 `Item::Message` —— 一行包装。
- Responses 适配器直接把 `input[]` 的 message / function_call / function_call_output / reasoning 一一映射为对应 `Item` 变体 —— 无需扭曲。
- 未来加 computer_call / browser_action / code_execution，只需在 `LucentAgentAction` 加变体，不动骨干。

### 1.2 `LucentMessage`（消息特例）

```moonbit
pub struct LucentMessage {
  role : LucentRole
  content : Array[LucentContent]
  phase : String?                // Codex 的 phase（commentary/final_answer）
  reasoning : LucentThinking?    // 消息级 reasoning（vLLM/DeepSeek/Fireworks）
}

pub enum LucentRole {
  System
  User
  Assistant
  Tool       // OpenAI Chat / Gemini 有；Anthropic 用 user+tool_result 承载
  Model      // 新增：Gemini 的 "model" 角色
  Developer  // 新增：OpenAI Chat 的 "developer" 角色
  Native(String)
}
```

> Anthropic 把工具结果塞在 `user` 角色的 `tool_result` content block 中 —— 适配层把 Anthropic user+tool_result 解码为 `Item::ToolResult`（而非 `Item::Message`），骨干统一。
> Gemini 的 `model` 角色在适配层映射为 `LucentRole::Assistant`（语义等价）；若需保留原生角色名，走 `LucentRole::Native("model")`。

### 1.3 `LucentRequest`

```moonbit
pub struct LucentRequest {
  schema_version : String                          // 固定 "v1"
  model : String
  instructions : Array[LucentContent]?             // 顶层系统指令
  conversation : Array[LucentConversationItem]     // 替代 messages，平级承载所有项
  tools : Array[LucentTool]?
  tool_choice : LucentToolChoice?
  options : LucentOptions
  capabilities : LucentCapabilities?
  reasoning : LucentReasoningConfig?               // 推理配置
  metadata : Map[String, String]?
  extra : Map[String, Json]?                       // 厂商不透明透传
}
```

**系统指令位置**：
- OpenAI Chat：`role: system` 的消息 → 适配层抽出存 `instructions`
- Anthropic：顶层 `system` 字段 → 直接映射 `instructions`
- OpenAI Responses：顶层 `instructions` 字段 → 直接映射
- Gemini：`systemInstruction.parts[].text` → 映射为 `Array[LucentContent::Text]`

---

## 2. 内容类型：`LucentContent`

### 2.1 主枚举

```moonbit
pub enum LucentContent {
  Text(String, Array[LucentAnnotation]?)      // annotations 侧信道
  ToolUse(LucentToolUse)
  ToolResult(LucentToolResult)
  Thinking(LucentThinking)                     // 升级为结构体
  Refusal(String)
  Image(LucentMultimedia)
  Audio(LucentMultimedia)
  Video(LucentMultimedia)                      // 新增：Gemini 已支持，未来通用
  Native(String, Json)                         // (type_tag, raw_json) 厂商私有内容类型
}
```

### 2.2 推理内容：`LucentThinking`

```moonbit
pub struct LucentThinking {
  text : String
  signature : String?
  /// 推理是否被厂商脱敏（Anthropic redacted_thinking / Gemini 部分 thought）
  redacted : Bool
  /// 推理摘要（OpenAI Responses reasoning.summary）
  summary : Array[LucentContent]?
}
```

**适配规则**：
- Anthropic `redacted_thinking` → `Thinking { redacted=true, signature=Some(...), text="" }`
- Gemini `thought: true`（打在 part 上的布尔标记）→ 该 part 解码为 `Text`，**同时**把 `Thinking` 也发一份（`redacted=false`），不丢失「这段同时是思考」的语义。
- OpenAI Responses `reasoning.summary[].text` → `summary: Array[LucentContent::Text]`

### 2.3 工具调用 / 结果：结构化

```moonbit
pub struct LucentToolUse {
  id : String
  name : String
  arguments_json : String            // canonical 为字符串（OpenAI/Responses 原生格式）
  arguments_value : Json?            // 已解析对象，可选（Anthropic/Gemini 原生是对象，适配层 stringify）
}

pub struct LucentToolResult {
  tool_use_id : String
  content : Array[LucentContent]     // Anthropic 块数组 / OpenAI 字符串 → 统一为数组
  is_error : Bool                    // Anthropic is_error / 未来通用
}
```

> 工具参数 canonical 选 **字符串**（OpenAI/Responses 原生即字符串）。Anthropic/Gemini 原生是 JSON 对象，适配层做 `JSON.stringify(input)` 入 IR，反方向做 `JSON.parse(arguments_json)` 入外部 —— 在适配层解决，不污染 IR。

### 2.4 多模态：`LucentMultimedia`

```moonbit
pub struct LucentMultimedia {
  media_type : String                // MIME type
  source : LucentMediaSource
}

pub enum LucentMediaSource {
  Inline(String)        // base64 data
  Url(String)           // 远程 URL
  FileUri(String)       // 厂商文件 URI（OpenAI file_id / Gemini fileUri）
}
```

**JSON 序列化**（`to_json` / `from_json`）：

```json
{ "type": "url",      "data": "https://example.com/photo.jpg" }
{ "type": "inline",   "data": "iVBORw0KGgo..." }
{ "type": "file_uri", "data": "file-abc" }
```

**适配规则**：
- OpenAI Chat `image_url.url` 若为 `data:` URI → `Inline`；否则 → `Url`
- Anthropic `image.source.type=base64` → `Inline`；`type=url` → `Url`
- Gemini `inlineData` → `Inline`；`fileData.fileUri` → `FileUri`

### 2.5 标注：`LucentAnnotation`（侧信道）

```moonbit
pub struct LucentAnnotation {
  kind : LucentAnnotationKind
  text : String?           // 被标注的原文片段
  reference : String?            // 引用目标 URL / file_id
  start : Int?             // 原文起始 offset
  end : Int?
}

pub enum LucentAnnotationKind {
  Url
  FileCitation
  WebSearchCitation
  Native(String)
}
```

承载 OpenAI Responses 的 `output_text.annotations[]`、各家 URL/file 引用、citation。

---

## 3. 工具：定义与选择

### 3.0 设计原则：入 IR 的判断标准

“是否改变对话形状”是判断 SDK 是否需要类型化分支的强证据，但不是唯一标准。字段归属必须同时通过 [`Lucent IR 演进与字段归类规则`](rules/lucent-ir-evolution.md) 的五道判定门，并分别满足转换契约与 SDK 契约。

```text
改变对话/事件形状，且语义稳定、Provider 无关
  -> 核心类型候选（例：tool_use vs text）

不形成新节点，但跨 Provider 具有稳定同构控制语义
  -> 可移植控制候选

转换不能丢失，但语义尚未成熟
  -> 类型化孵化区或有序 Native

仅控制特定 Provider 行为
  -> 命名空间化请求扩展

改变 HTTP、后台任务或轮询生命周期
  -> Transport
```

无论归属何处，适配器都必须明确给出 `Exact`、`Degraded`、`Unsupported` 或 `Invalid` 结果，不得通过忽略字段伪装成功。

### 3.1 `LucentTool` 与 `LucentToolKind`

```moonbit
pub enum LucentToolKind {
  Function                // 标准函数调用（用户需注册 handler）
  FileSearch              // OpenAI 内置：文件搜索（provider 自托管）
  WebSearch               // OpenAI 内置：网络搜索（provider 自托管）
  CodeInterpreter         // OpenAI 内置：代码解释器（provider 自托管）
  ComputerUse             // OpenAI 内置：计算机使用（provider 自托管）
  CodeExecution           // Anthropic：代码执行沙箱（provider 自托管）
  Shell                   // Codex / Anthropic：shell 命令
  ApplyPatch              // Codex：应用代码 diff
  MCP                     // OpenAI：MCP 远程工具
  Native(String)          // 逃生口：未知工具类型
}

pub struct LucentTool {
  name : String
  description : String?
  parameters_json : String           // JSON Schema
  strict : Bool?                     // 严格模式（OpenAI strict:true）
  kind : LucentToolKind              // 默认 Function
}
```

**适配规则**：
- OpenAI Chat `tools[].function` → `kind: Function`
- OpenAI Responses `tools[].type`（function / file_search / web_search / ...）→ 对应 `LucentToolKind`
- Anthropic `tools[].type`（custom / code_execution_20250522 / bash_20250124）→ 对应 `LucentToolKind`
- Gemini `tools[].functionDeclarations[]` → `kind: Function`

### 3.2 `LucentToolChoice`（类型化）

```moonbit
pub enum LucentToolChoice {
  Auto                    // OpenAI "auto" / Anthropic {"type":"auto"} / Gemini AUTO
  None                    // OpenAI "none" / Gemini NONE
  Required                // OpenAI "required" / Anthropic {"type":"any"} / Gemini ANY
  SpecificTool(String)    // OpenAI {"type":"function","function":{"name":"x"}} / Anthropic {"type":"tool","name":"x"}
}
```

替代 `String?`，编译期防拼写错误。

---

## 4. 生成参数：`LucentOptions`

```moonbit
pub struct LucentOptions {
  temperature : Double?
  top_p : Double?
  top_k : Int?                    // 新增：Anthropic / Gemini
  max_output_tokens : Int?
  stop : Array[String]?
  stream : Bool
  candidate_count : Int?          // 新增：Gemini candidateCount
  seed : Int?                     // 新增：OpenAI seed
  structured_output : LucentStructuredOutput?   // 新增
}

pub enum LucentStructuredOutput {
  JsonObject                       // {"type":"json_object"}
  Text                             // {"type":"text"}
  JsonSchema(String)               // {"type":"json_schema","schema":{...}} → schema as raw JSON string
}
```

---

## 5. 推理配置：`LucentReasoningConfig`

```moonbit
pub struct LucentReasoningConfig {
  enabled : Bool
  budget_tokens : Int?             // Anthropic budget_tokens / Gemini thinkingBudget
  effort : LucentReasoningEffort?  // OpenAI Responses effort
  summary : LucentReasoningSummary? // OpenAI Responses summary
}

pub enum LucentReasoningEffort { Low; Medium; High }
pub enum LucentReasoningSummary { Auto; Concise; Detailed }
```

---

## 6. 能力分级：`LucentCapabilities`

```moonbit
pub struct LucentCapabilities {
  tool_calling : Bool
  parallel_tool_calls : Bool
  reasoning : Bool
  multimodal_input : Bool
  structured_output : Bool
  input_modalities : Array[LucentModality]
  output_modalities : Array[LucentModality]
}

pub enum LucentModality {
  Text
  Image
  Audio
  Video
  Pdf
  Native(String)
}
```

**能力分级规则**（新增厂商时按此三层归类）：

| 层级 | 归宿 | 举例 |
|------|------|------|
| **标准化能力**（多家厂商共有） | 提升为 IR 一等字段 | `tool_calling` / `parallel_tool_calls` / `reasoning` / `structured_output` / `multimodal_input` |
| **厂商独有但语义清晰** | 类型化占位 | `LucentReasoningConfig`（Anthropic/OpenAI/Gemini 都有推理配置，字段不同语义同构） |
| **完全私有**（无跨厂商语义） | `extra: Map[String, Json]` | `truncation` / `include` / `safetySettings` / `cache_control` |

---

## 7. 流式：`LucentStreamEvent`

canonical 选 **Anthropic 块生命周期**（四家里语义最完备），补齐四类缺失事件。

### 7.1 事件枚举

```moonbit
pub enum LucentStreamEvent {
  ConversationStart(LucentConversationMeta)    // Anthropic message_start / Responses response.created
  ItemStart(Int, LucentConversationItem)        // Responses output_item.added
  BlockStart(Int, LucentBlockType)              // Anthropic content_block_start
  BlockDelta(Int, LucentBlockDelta)             // Anthropic content_block_delta / OpenAI delta.content / Gemini parts[].text
  BlockEnd(Int)                                 // Anthropic content_block_stop
  ItemEnd(Int)                                  // Responses output_item.done
  BlockDiscard(Int)                             // 新增：Gemini 全量帧覆盖前一帧
  Annotations(Int, Array[LucentAnnotation])     // 新增：Responses annotations.delta
  Finish(LucentFinishReason)
  Usage(LucentUsage)
  Error(LucentError)
  Done
}
```

### 7.2 块类型 / 增量（类型化）

```moonbit
pub enum LucentBlockType {
  Text
  ToolCall(String, String)    // id, name（块开始时若已知）
  Thinking
  Refusal
  Image
  Audio
  Video
  Native(String)
}

pub enum LucentBlockDelta {
  TextDelta(String)
  ThinkingDelta(String)
  SignatureDelta(String)             // Anthropic signature_delta / Responses signature
  ToolArgumentsDelta(String)         // JSON 参数片段
  RefusalDelta(String)
  NativeDelta(String, Json)          // 厂商私有增量
}
```

### 7.3 会话元信息 / 错误

```moonbit
pub struct LucentConversationMeta {
  id : String?
  model : String?
  usage_input : Int?                 // Anthropic message_start 携带 input_tokens
}

pub struct LucentError {
  kind : LucentErrorKind
  message : String
  provider_code : String?            // 厂商原始错误码
}

pub enum LucentErrorKind {
  RateLimit
  InvalidRequest
  Authentication
  ServerError
  ContentFilter
  Native(String)
}
```

### 7.4 流式适配规则（各家 → IR）

| 协议 | 适配层合成策略 |
|------|--------------|
| **OpenAI Chat** | delta 流无显式块边界 → 适配层凭空造 `BlockStart/End`（按 `tool_calls[].index` 切换），`delta.content` → `BlockDelta(TextDelta)` |
| **Anthropic** | 直接映射：`content_block_start` → `BlockStart`，`delta.type=text_delta` → `BlockDelta(TextDelta)`，`input_json_delta` → `BlockDelta(ToolArgumentsDelta)`，`signature_delta` → `BlockDelta(SignatureDelta)` |
| **OpenAI Responses** | 事件命名一一映射：`output_item.added` → `ItemStart`，`output_text.delta` → `BlockDelta(TextDelta)`，`function_call_arguments.delta` → `BlockDelta(ToolArgumentsDelta)`，`response.completed` → `Finish + Done` |
| **Gemini** | 全量帧 → 适配层做 diff：上一帧已有内容发 `BlockDiscard`，新内容发 `BlockDelta`；`thought: true` 同时发 `BlockDelta(TextDelta)` 和 `BlockStart(Thinking) + BlockDelta(ThinkingDelta)` |

### 7.5 流式累加器

`lucent_stream_events_to_response(events, id, model) → LucentResponse` —— 把事件流累加为非流式响应，用于：
- 宿主语言选择「流式接收但累加成完整响应」的简化场景
- 跨协议一致性测试的断言依据

---

## 8. 用量统计：`LucentUsage`

```moonbit
pub struct LucentUsage {
  prompt_tokens : Int
  completion_tokens : Int
  total_tokens : Int
  reasoning_tokens : Int?           // 新增：Responses reasoning_tokens / Gemini thoughtsTokenCount
  cached_tokens : Int?              // 新增：Responses cached_tokens / Anthropic cache_read
  cache_creation_tokens : Int?      // 新增：Anthropic cache_creation
}
```

面向 reasoning 时代 —— 思考 token、缓存 token 一等公民。

---

## 9. 响应：`LucentResponse`

```moonbit
pub struct LucentResponse {
  schema_version : String                    // 固定 "v1"
  id : String
  model : String
  created_at : Int?                          // 新增：OpenAI created / Responses created_at
  choices : Array[LucentChoice]              // 多候选，Gemini candidates / OpenAI choices
  usage : LucentUsage?
  provider_payload : Json?                  // 厂商原生 payload 透传
}

pub struct LucentChoice {
  index : Int                                // 候选序号
  message : LucentMessage
  finish_reason : LucentFinishReason
  safety_ratings : Array[LucentSafetyRating]?   // 新增：Gemini safetyRatings
}

pub struct LucentSafetyRating {
  category : String
  probability : String
}

pub enum LucentFinishReason {
  Stop
  Length
  ToolCalls
  ContentFilter
  Safety                                  // 新增：Gemini SAFETY
  Recitation                              // 新增：Gemini RECITATION
  MalformedToolCall                       // 新增：Gemini MALFORMED_FUNCTION_CALL
  Error
  Native(String)                          // 厂商独有
}
```

**适配规则**：
- Anthropic `stop_reason: end_turn/max_tokens/tool_use` → `Stop/Length/ToolCalls`
- Gemini `finishReason: STOP/MAX_TOKENS/SAFETY/RECITATION` → 对应变体（`"safety"` → `Safety`，`"content_filter"` → `ContentFilter`，二者不同义）
- OpenAI Responses `status: completed/incomplete/failed` → `Stop/Length/Error`
- `provider_payload` 承载 `previous_response_id` / `system_fingerprint` / `safetyRatings` 等

---

## 9.1 消息级 reasoning 承载与跨协议映射

### 三载体职责分工（不互相取代）

消息/会话级推理过程在 IR 中有三类载体，语义不同，必须按职责使用：

| 载体 | 表达 | 主要服务 | 示例 |
|------|------|---------|------|
| `LucentContent::Thinking`（块内） | thinking 在正文中的**交错位置** | 中转站结构保真 | Anthropic `thinking` block 夹在 text 中；Mistral/Cohere thinking chunk |
| `LucentConversationItem::Reasoning`（平级项） | 独立 Item 级思考 | 中转站（Requests / 历史回传） | OpenAI Responses `input[]`/`output[]` 的 `reasoning` item |
| `LucentMessage.reasoning`（消息级，**v1 新增**） | 消息级 reasoning 字段 | SDK + 中转站 | vLLM `message.reasoning` / DeepSeek/Fireworks `message.reasoning_content` |

- `content` 数组只含**可见内容**（Text/ToolUse/ToolResult/Refusal/Image/Audio/Video）；`Thinking` 仅是 Anthropic 风格交错位置的保真载体。
- `LucentMessage.reasoning` 是消息级 reasoning 的**首选读取入口**（SDK `c.message.reasoning`）。
- `LucentConversationItem::Reasoning` 用于请求/历史侧回传。

### 各厂商推理映射表

| 厂商 / API | 入站承载 | 出站展开 | 流式事件 | 保真度诊断 |
|-----------|---------|---------|---------|-----------|
| Anthropic Messages | `content[]` `Thinking` block（含 signature / redacted_thinking） | 展开为 `thinking` + `redacted_thinking` block | `block_start(thinking)` / `thinking_delta` / `signature_delta` | `signature` 保留 |
| OpenAI Chat（o-series） | `message.reasoning`（vLLM）/ `reasoning_content`（DeepSeek/Fireworks）→ `LucentMessage.reasoning` | `message.reasoning`（默认 vLLM 字段名） | `delta.reasoning` / `delta.reasoning_content` → `Thinking` 块 | 出站签名/redacted/summary 丢失 → `Degraded`；字段名按 `reasoning_field` 扩展切换 |
| OpenAI Responses | `output[]` `reasoning` item（summary/signature）→ `Item::Reasoning` / 非流式折叠为 content Thinking | `Item::Reasoning` → `{"type":"reasoning", summary, signature}` | `reasoning` item + `response.reasoning_summary_text.delta/done` | `summary`/`signature` 保留 |
| Gemini generateContent / Vertex | `part.thought:true` → 同时发 Text + `Thinking`（redacted=false） | `thought: true` 打在 part 上 | `BlockStart(Thinking) + BlockDelta(ThinkingDelta)`（与 Text 平行） | `thought` 布尔标记保留 |
| Gemini Interactions | `steps[]` `thought` 步 | 展开为 `thought` 步 | 逐步 `thought` 增量 | `thought_summary` ↔ `LucentThinking.summary`（融合待定 → `Degraded`） |
| Mistral | `content[]` thinking chunk | thinking chunk | `thinking` chunk delta | — |
| Cohere | `content[]` thinking chunk | thinking chunk | `thinking` chunk delta | — |
| Azure / Codex（responses 薄封装） | 随 openai_responses（Item 级） | 随 openai_responses（Item 级） | 随 openai_responses | 随 openai_responses；codex 请求侧 `effort` 支持 xhigh |

> 注意：`openai_azure`、`openai_codex` 的 `moon.pkg` import **`openai_responses`**（非 openai-chat），
> reasoning 经 `LucentConversationItem::Reasoning` / `LucentThinking` Item 模型流动，不由消息级字段承载。

### 未决问题收敛

(a) **出站字段名分歧**：默认 `reasoning`（vLLM 形态）；经 `extra`/`ProviderCapability` 显式声明
`reasoning_field: "reasoning_content"` 时切换；无声明且确需 DeepSeek 形态时产生 `Unsupported` 诊断，不静默。

(b) **双载体出站优先级**：`LucentMessage.reasoning` 优先；回退 `content` 的 Thinking block；
两者同时存在时视为 `Degraded`（不静默，提示消费者处理重复表达）。

(c) **流式/非流式归位**：流式 `Thinking` 块在累加器（`lucent_stream_events_to_accumulated`）中
归位到 `LucentMessage.reasoning`，`content[]` 不含 Thinking；非流式入站直接填 `message.reasoning`。
两条路径最终一致，SDK 统一从 `c.message.reasoning` 读取。

---

## 10. 6-Function 适配器契约

每个适配器实现 6 个纯函数，方向正交：

| # | 方向 | 解码（外部 → Lux） | 编码（Lux → 外部） |
|---|------|------------------|------------------|
| 1 | 请求 | `ext_to_lux_request(String) → Result[LucentRequest, String]` | `lux_request_to_ext(LucentRequest) → Result[String, String]` |
| 2 | 响应 | `ext_to_lux_response(String) → Result[LucentResponse, String]` | `lux_response_to_ext(LucentResponse) → Result[String, String]` |
| 3 | 流式 | `ext_sse_to_events(String) → Result[Array[LucentStreamEvent], String]` | `lux_events_to_ext_sse(Array[LucentStreamEvent]) → Result[String, String]` |

**契约不变性**：
- 纯函数，无 IO、无状态、无网络（WASM 安全边界）。
- String 进出，WASM 导出零摩擦。
- 6 个函数覆盖双层转换的全路径（业务调用模式 + 协议转发模式）。

**适配器包命名**：`provider/<vendor>/`，导出函数前缀 `<vendor>_<api>_`，例如 `openai_chat_to_lux_request` / `anthropic_to_lux_request`（实际实现注册于 `sdk/provider_capability.mbt` 的 `ProviderRegistration` 注册表）。

---

## 11. Agent 动作占位：`LucentAgentAction`

```moonbit
/// v1 仅作为类型化占位，参数走 provider_payload
/// 未来扩展：browser_action / code_execution / file_operation 等
pub struct LucentAgentAction {
  kind : String                // "computer_call" / 未来其他
  id : String
  call_id : String?
  name : String?
  arguments_json : String?
  result : String?
  provider_payload : Json?
}
```

承载 OpenAI Responses 的 `computer_call` / `computer_call_output`。v1 不展开为独立字段，避免 IR 膨胀；v2 按需升格。

---

## 12. 未来接口接入流程

新增一个厂商接口（例如文心 / 讯飞 / Cohere）的步骤：

1. **归类能力**：对照 `LucentCapabilities`，把该厂商支持的能力标 true。
2. **映射消息**：该厂商的 messages/contents/input → `LucentConversationItem`，选择最贴近的变体。
3. **映射内容**：该厂商的 content types → `LucentContent`，无对应的走 `Native(String, Json)`。
4. **归类扩展**：
   - 标准化能力 → IR 一等字段
   - 厂商私有但语义清晰 → 类型化占位（如推理配置走 `LucentReasoningConfig`）
   - 完全私有 → `extra`
5. **实现 6 函数**：按契约实现，纯函数，String 进出。
6. **跨协议一致性测试**：同一 canonical conversation，所有适配器 decode → IR 应语义等价。

整个流程不动 IR 骨干 —— 这是「有效适配所有接口 + 未来新接口可接入」的核心保证。

---

## 13. 与现有 lux IR 的 breaking changes

| 现有 | 重设计 | 影响 |
|------|-------|------|
| `LucentRequest.messages` | `LucentRequest.conversation: Array[LucentConversationItem]` | breaking，适配层一行包装 |
| `LucentContent::Thinking(String, String?)` | `LucentContent::Thinking(LucentThinking)` | breaking，redacted 语义补齐 |
| `LucentContent::Text(String)` | `LucentContent::Text(String, Array[LucentAnnotation]?)` | breaking，annotations 补齐 |
| `LucentContent::Image(String, String)` | `LucentContent::Image(LucentMultimedia)` | breaking，三种 source 补齐 |
| `LucentContent::ToolUse(...)` 平铺参数 | `LucentContent::ToolUse(LucentToolUse)` | breaking，结构化 |
| `LucentContent::ToolResult(...)` 平铺参数 | `LucentContent::ToolResult(LucentToolResult)` | breaking，is_error 补齐 |
| `LucentStreamEvent::ContentStart/Delta/End` | `BlockStart/BlockDelta/BlockEnd` + 类型化 | breaking，但语义一致 |
| `LucentUsage` 三字段 | 六字段 | 非 breaking（新字段 Optional） |
| `LucentFinishReason` 五变体 | 九变体 + Native | 非 breaking（新增变体） |
| `LucentToolChoice` String | `LucentToolChoice` enum | breaking，类型化 |
| 无 `LucentReasoningConfig` | 新增 | 非 breaking |
| 无 `LucentStructuredOutput` | 新增 | 非 breaking |
| 无 `schema_version` | 新增 | 非 breaking |

breaking changes 集中在「类型化」和「补齐缺失语义」，都是一次性改动。现有 `openai_chat` 适配器代码量小（~290 行），重写成本可控。

---

## 14. 落地顺序

1. **Phase 0 重做**：按此规范重写 `protocol/lux/lux.mbt` + `stream.mbt`，更新白盒测试。foundation，所有适配器依赖。
2. **适配器重写**：OpenAI Chat → Anthropic → OpenAI Responses → Gemini（按接口复杂度递增，Responses 最扭曲所以放后面验证骨干设计）。
3. **跨协议一致性测试**：canonical conversation 在四家适配器间 round-trip，验证「同一语义 → 四家 JSON → 同一 IR」。
4. **WASM 导出**：6 个通用转换函数（经 `sdk/` 注册表按 provider 分发）+ 5 个高层 SDK API，共 11 个导出点，纯函数，宿主语言零摩擦。中转站场景的协议→协议转发通过 `convert_*`（source 解码 + target 编码）组合实现。
