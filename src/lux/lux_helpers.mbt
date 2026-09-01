///|
/// ValidateResult — 校验结果
pub struct ValidateResult {
  valid : Bool
  errors : Array[String]
  warnings : Array[String]
}

///|
pub fn ValidateResult::ok() -> ValidateResult {
  { valid: true, errors: [], warnings: [] }
}

///|
pub fn ValidateResult::error(msg : String) -> ValidateResult {
  { valid: false, errors: [msg], warnings: [] }
}

///|
/// 校验 LucentRequest 的字段值合法性（与 ProviderCapability 无关的基本校验）
/// 例如：temperature 范围 [0, 2]，max_output_tokens >= 1，model 非空
pub fn LucentRequest::validate(self : LucentRequest) -> ValidateResult {
  let errors : Array[String] = []
  let warnings : Array[String] = []

  if self.model == "" {
    errors.push("model is required")
  }
  match self.options.temperature {
    Some(t) =>
      if t < 0.0 || t > 2.0 {
        errors.push("temperature must be in [0, 2], got " + t.to_string())
      }
    None => ()
  }
  match self.options.top_p {
    Some(p) =>
      if p < 0.0 || p > 1.0 {
        errors.push("top_p must be in [0, 1], got " + p.to_string())
      }
    None => ()
  }
  match self.options.top_k {
    Some(k) =>
      if k < 1 {
        errors.push("top_k must be >= 1, got " + k.to_string())
      }
    None => ()
  }
  match self.options.max_output_tokens {
    Some(m) =>
      if m < 1 {
        errors.push("max_output_tokens must be >= 1, got " + m.to_string())
      }
    None => ()
  }
  { valid: errors.length() == 0, errors, warnings }
}

///|
/// 校验 LucentResponse 字段合法性
pub fn LucentResponse::validate(self : LucentResponse) -> ValidateResult {
  let errors : Array[String] = []
  if self.id == "" {
    errors.push("response id is required")
  }
  if self.model == "" {
    errors.push("response model is required")
  }
  if self.choices.length() == 0 {
    errors.push("response must have at least one choice")
  }
  { valid: errors.length() == 0, errors, warnings: [] }
}

///|
/// 构建含新 conversation 的请求（子包后处理用）
pub fn LucentRequest::with_conversation(
  self : LucentRequest,
  conversation : Array[LucentConversationItem],
) -> LucentRequest {
  { ..self, conversation, }
}

///|
/// 构建含 stream 标志的请求副本（SDK 使用）
pub fn LucentRequest::with_stream(
  self : LucentRequest,
  stream : Bool,
) -> LucentRequest {
  { ..self, options: { ..self.options, stream, } }
}

///|
/// 便利构造器：用 messages 数组（旧风格）替代 conversation
pub fn LucentRequest::from_messages(
  model : String,
  instructions : Array[LucentContent]?,
  messages : Array[LucentMessage],
  tools : Array[LucentTool]?,
  tool_choice : LucentToolChoice?,
  options : LucentOptions,
  capabilities : LucentCapabilities?,
  reasoning : LucentReasoningConfig?,
  metadata : Map[String, String]?,
  extra : Map[String, Json]?,
) -> LucentRequest {
  {
    schema_version: "v1",
    model,
    instructions,
    conversation: lucent_items_from_messages(messages),
    tools,
    tool_choice,
    options,
    capabilities,
    reasoning,
    metadata,
    extra,
  }
}

///|
pub fn LucentUsage::new(
  prompt_tokens : Int,
  completion_tokens : Int,
  total_tokens : Int,
) -> LucentUsage {
  {
    prompt_tokens,
    completion_tokens,
    total_tokens,
    reasoning_tokens: None,
    cached_tokens: None,
    cache_creation_tokens: None,
  }
}

///|
/// 构造含细化用量的 LucentUsage（reasoning / cached / cache_creation）
pub fn LucentUsage::full(
  prompt_tokens : Int,
  completion_tokens : Int,
  total_tokens : Int,
  reasoning_tokens : Int?,
  cached_tokens : Int?,
  cache_creation_tokens : Int?,
) -> LucentUsage {
  {
    prompt_tokens,
    completion_tokens,
    total_tokens,
    reasoning_tokens,
    cached_tokens,
    cache_creation_tokens,
  }
}

///|
pub fn LucentUsage::with_reasoning(
  prompt_tokens : Int,
  completion_tokens : Int,
  total_tokens : Int,
  reasoning_tokens : Int,
) -> LucentUsage {
  {
    prompt_tokens,
    completion_tokens,
    total_tokens,
    reasoning_tokens: Some(reasoning_tokens),
    cached_tokens: None,
    cache_creation_tokens: None,
  }
}

///|
pub fn LucentSafetyRating::new(
  category : String,
  probability : String,
) -> LucentSafetyRating {
  { category, probability }
}

///|
pub fn LucentChoice::new(
  index : Int,
  message : LucentMessage,
  finish_reason : LucentFinishReason,
  safety_ratings : Array[LucentSafetyRating]?,
) -> LucentChoice {
  { index, message, finish_reason, safety_ratings }
}

///|
pub fn LucentResponse::new(
  id : String,
  model : String,
  created_at : Int?,
  choices : Array[LucentChoice],
  usage : LucentUsage?,
  provider_payload : Json?,
) -> LucentResponse {
  {
    schema_version: "v1",
    id,
    model,
    created_at,
    choices,
    usage,
    provider_payload,
  }
}

///|
/// 构建含 provider_payload 的新响应（外部包访问用）
pub fn LucentResponse::with_provider_payload(
  self : LucentResponse,
  payload : Json?,
) -> LucentResponse {
  { ..self, provider_payload: payload }
}

///|
/// 提取响应中的纯文本（L1 SDK 使用）
pub fn LucentResponse::get_text(self : LucentResponse) -> String {
  if self.choices.length() > 0 {
    lucent_content_to_text(self.choices[0].message.content)
  } else {
    ""
  }
}

///|
/// 便捷访问：首个 choice 的消息级 reasoning（SDK 取用入口）
pub fn LucentResponse::reasoning(self : LucentResponse) -> LucentThinking? {
  if self.choices.length() > 0 {
    self.choices[0].message.reasoning
  } else {
    None
  }
}

///|
/// LucentFinishReason 字符串映射（适配器共用）
pub fn LucentFinishReason::from_string(s : String) -> LucentFinishReason {
  match s {
    "stop" | "end_turn" | "completed" | "STOP" => Stop
    "length" | "max_tokens" | "MAX_TOKENS" | "incomplete" => Length
    "tool_calls" | "tool_use" | "function_call" => ToolCalls
    "content_filter" => ContentFilter
    "SAFETY" | "safety" => Safety
    "RECITATION" | "recitation" => Recitation
    "MALFORMED_FUNCTION_CALL" | "malformed_function_call" => MalformedToolCall
    "error" | "failed" | "ERROR" => Error
    other => Native(other)
  }
}

///|
pub fn LucentFinishReason::to_string(self : LucentFinishReason) -> String {
  match self {
    Stop => "stop"
    Length => "length"
    ToolCalls => "tool_calls"
    ContentFilter => "content_filter"
    Safety => "safety"
    Recitation => "recitation"
    MalformedToolCall => "malformed_function_call"
    Error => "error"
    Native(s) => s
  }
}

///|
/// 从 conversation items 中提取所有 Message 项（用于适配器需要 messages 视图的场景）
pub fn lucent_messages_from_items(
  items : Array[LucentConversationItem],
) -> Array[LucentMessage] {
  let result : Array[LucentMessage] = []
  for item in items {
    match item {
      Message(m) => result.push(m)
      _ => ()
    }
  }
  result
}

///|
/// 将 LucentContent 数组拼接为纯文本（Text 块拼接，其他块忽略）
pub fn lucent_content_to_text(parts : Array[LucentContent]) -> String {
  let buf : Array[String] = []
  for part in parts {
    match part {
      Text(s, _) => buf.push(s)
      _ => ()
    }
  }
  buf.join("")
}

///|
/// 检测并处理 reasoning dual_carrier 场景
///
/// 当消息级 reasoning（vLLM/DeepSeek）与 content 中的 Thinking 块并存时，
/// 优先使用消息级 reasoning，跳过 content Thinking 块，并记录 Degraded 诊断。
///
/// 用法：在适配器编码循环中，对每个 content 块调用此函数：
/// ```
/// if skip_thinking_when_dual_carrier(content[i], reasoning, diagnostics) {
///   i = i + 1
///   continue
/// }
/// ```
///
/// 返回 `true` 表示当前块应跳过（Thinking 块 + reasoning 已存在）。
pub fn skip_thinking_when_dual_carrier(
  content : LucentContent,
  reasoning : LucentThinking?,
  diagnostics : Array[ConversionDiagnostic],
) -> Bool {
  match content {
    Thinking(_) =>
      match reasoning {
        Some(_) => {
          diagnostics.push(
            ConversionDiagnostic::degraded(
              "reasoning.dual_carrier",
              Some(
                "both message.reasoning and content Thinking present; using message.reasoning",
              ),
            ),
          )
          true
        }
        None => false
      }
    _ => false
  }
}

///|
/// 构造 unsupported content 诊断并推入诊断数组
///
/// 统一 `ConversionDiagnostic::unsupported("content.xxx", Some("..."))` 模式。
/// 适配器编码循环中遇到不支持的内容类型时调用。
///
/// 用法：
/// ```
/// push_unsupported_content("audio", "openai-chat", diagnostics)
/// // 生成: unsupported("content.audio", "audio content not supported by openai-chat")
/// ```
pub fn push_unsupported_content(
  type_name : String,
  adapter : String,
  diagnostics : Array[ConversionDiagnostic],
) -> Unit {
  diagnostics.push(
    ConversionDiagnostic::unsupported(
      "content." + type_name,
      Some(type_name + " content not supported by " + adapter),
    ),
  )
}

///|
/// 构造 unsupported feature 诊断并推入诊断数组
///
/// 更通用的版本，用于非 content 类型的 unsupported 诊断（如 tools.kind, options.store 等）。
///
/// 用法：
/// ```
/// push_unsupported("tools.kind", "tool kind not supported by gemini", diagnostics)
/// ```
pub fn push_unsupported(
  field : String,
  detail : String,
  diagnostics : Array[ConversionDiagnostic],
) -> Unit {
  diagnostics.push(ConversionDiagnostic::unsupported(field, Some(detail)))
}
