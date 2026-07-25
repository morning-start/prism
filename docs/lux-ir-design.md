# Lux IR 设计规范

> Prism 自研中立中间协议（Lucent IR）的形式规范。
> 本文件是 `protocol/lux/` 包实现的**唯一依据**，所有适配器以此为准。
> 版本：`schema_version = "v1"`

---

## 0. 设计目标

1. **有效适配所有已知接口** — OpenAI Chat / Anthropic Messages / OpenAI Responses / Google Gemini 四家接口在同一 IR 下无扭曲适配。
2. **未来新接口可接入** — 新增厂商按「能力归类 → 消息映射 → 内容映射 → 扩展归类 → 实现 6 函数」流程接入，不动 IR 骨干。
3. **覆盖全使用场景并预判未来** — Agent 动作、结构化输出、多模态、多候选、reasoning token 统计、版本化治理已预留。

## 0.1 设计原则

1. **以「会话事件流」为骨干**，不以「消息数组」为骨干 —— `LucentConversationItem` 异质平级，自然承载 Responses 的 Item 模型。
2. **内容类型用代数和 + 元数据侧信道** —— 不强行统一各家不一致字段，给「不一致部分」留类型化侧信道。
3. **流式选 Anthropic 块生命周期作 canonical**，补齐四类缺失事件（Discard / Meta / Annotations / 错误结构化）。
4. **用量统计面向 reasoning 时代** —— 思考 token、缓存 token 一等公民。
5. **能力分级：标准化能力 / 厂商标识 / 不透明透传** —— 三层清晰，新增厂商按层归类。
6. **版本化治理** —— `schema_version: "v1"` 顶层声明，未来 breaking change 走 v2，不破坏已部署 WASM 调用方。

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
  ref_ : String?            // 引用目标 URL / file_id
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

### 3.1 `LucentTool`

```moonbit
pub struct LucentTool {
  name : String
  description : String?
  parameters_json : String           // JSON Schema
  strict : Bool?                     // 严格模式（OpenAI strict:true）
}
```

**适配规则**：
- OpenAI Chat `tools[].function` → 直接映射
- Anthropic `tools[].input_schema` → 映射为 `parameters_json`（字段名不同，语义同构）
- Gemini `tools[].functionDeclarations[]` → 展平为 `Array[LucentTool]`

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

**适配器包命名**：`protocol/<vendor>/<api>/`，导出函数前缀 `<vendor>_<api>_`，例如 `openai_chat_to_lux_request` / `anthropic_to_lux_request`。

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
4. **WASM 导出**：6 函数 × 4 适配器 = 24 个导出点，纯函数，宿主语言零摩擦。
