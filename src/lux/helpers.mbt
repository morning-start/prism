///|
/// ValidateResult — 校验结果
pub struct ValidateResult {
  valid : Bool
  errors : Array[String]
  warnings : Array[String]
}

///|
pub fn ValidateResult::ok() -> ValidateResult {
  { valid: true, errors: [], warnings: [], }
}

///|
pub fn ValidateResult::error(msg : String) -> ValidateResult {
  { valid: false, errors: [msg], warnings: [], }
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
  { valid: errors.length() == 0, errors, warnings, }
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
  { valid: errors.length() == 0, errors, warnings: [], }
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
  { ..self, options: { ..self.options, stream, }, }
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
  prompt_tokens : Int32,
  completion_tokens : Int32,
  total_tokens : Int32,
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
  prompt_tokens : Int32,
  completion_tokens : Int32,
  total_tokens : Int32,
  reasoning_tokens : Int32?,
  cached_tokens : Int32?,
  cache_creation_tokens : Int32?,
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
  prompt_tokens : Int32,
  completion_tokens : Int32,
  total_tokens : Int32,
  reasoning_tokens : Int32,
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
  { category, probability, }
}

///|
pub fn LucentChoice::new(
  index : Int32,
  message : LucentMessage,
  finish_reason : LucentFinishReason,
  safety_ratings : Array[LucentSafetyRating]?,
) -> LucentChoice {
  { index, message, finish_reason, safety_ratings, }
}

///|
pub fn LucentResponse::new(
  id : String,
  model : String,
  created_at : Int32?,
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
  { ..self, provider_payload: payload, }
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
    // malformed_tool_call 是 schema 法定值；malformed_function_call 为
    // 历史笔误的兼容读取（曾按此值输出，旧文档/对端可能仍在用）
    "MALFORMED_FUNCTION_CALL"
    | "malformed_function_call"
    | "malformed_tool_call" => MalformedToolCall
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
    // 与 schemas/lux-ir-v1.json 的枚举值一致（曾误输出
    // "malformed_function_call"，按 schema 校验的对端会拒绝本实现
    // 的文档；from_string 仍兼容旧拼写）
    MalformedToolCall => "malformed_tool_call"
    Error => "error"
    Native(s) => s
  }
}

///|
/// LucentReasoningEffort 字符串映射（适配器共用）
///
/// 出站侧 openai / messages / responses 三处使用完全相同的档位名
/// （"low"/"medium"/"high"/"xhigh"），集中于此避免重复 match。
/// gemini 的降级映射（XHigh → ("high", true)）语义不同，保留在 adapter。
/// Native(tag) 原样透传（未知档位不丢数据）。
pub fn LucentReasoningEffort::to_string(self : LucentReasoningEffort) -> String {
  match self {
    Low => "low"
    Medium => "medium"
    High => "high"
    XHigh => "xhigh"
    Native(tag) => tag
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

///|
/// 为扩展通道键撞名导致丢弃的条目补 Degraded 诊断（通道名由 `prefix` 指定）。
///
/// 与 `@internal.merge_extras_json_dedup` 配对使用：后者负责跳过与已编码
/// 目标字段同名的键（避免同一 JSON 对象出现重复键），本函数负责把被跳过的
/// 事实显式报出来。撞名有两种来源，都不允许静默：
///
/// 1. 目标是按 IR 重新编码出的同名字段（与源协议 wire 上那个同名字段语义
///    不同）；
/// 2. 优先级更高的扩展通道已经写过该键（`request.extra` 高于
///    `options.extras`，见 `docs/lux-ir-design.md` 的扩展通道说明）。
///
/// 用法：
/// ```
/// let dropped = @internal.merge_extras_json_dedup(parts, extras)
/// push_extras_collisions_at("extra", dropped, diagnostics)
/// ```
pub fn push_extras_collisions_at(
  prefix : String,
  dropped_keys : Array[String],
  diagnostics : Array[ConversionDiagnostic],
) -> Unit {
  for k in dropped_keys {
    diagnostics.push(
      ConversionDiagnostic::degraded(
        prefix + "." + k,
        Some(
          "extension key \"" +
          k +
          "\" collides with a field already encoded for the target (IR-mapped, or from a higher-priority extension channel); dropped to keep the JSON object free of duplicate keys",
        ),
      ),
    )
  }
}

///|
/// 为 `request.extra` 与 `options.extras` 同名的键补 Degraded 诊断。
///
/// IR 有两个扩展通道：`request.extra` 是程序作者显式给定的目标端扩展，
/// `options.extras` 是解码侧保留的源协议 wire 遗留。同名时约定 `extra` 胜出
/// （作者显式意图优先于自动保留），`extras` 侧的同名键剔除并在此报出。
/// 调用方应先用 `@internal.overlapping_extra_keys` 取交集、再剔除。
pub fn push_extras_overridden(
  keys : Array[String],
  diagnostics : Array[ConversionDiagnostic],
) -> Unit {
  for k in keys {
    diagnostics.push(
      ConversionDiagnostic::degraded(
        "options.extras." + k,
        Some(
          "request.extra also supplies \"" +
          k +
          "\"; extra wins (it is the explicit target-directed channel) and the options.extras copy is dropped",
        ),
      ),
    )
  }
}

///|
/// `options.extras` 通道的撞名诊断（字段名 `options.extras.<key>`）。
pub fn push_extras_collisions(
  dropped_keys : Array[String],
  diagnostics : Array[ConversionDiagnostic],
) -> Unit {
  push_extras_collisions_at("options.extras", dropped_keys, diagnostics)
}

///|
/// 为 extras 中「可证明属于其它协议」而被剔除的键补 Unsupported 诊断。
///
/// 判定与归属计算见 `@internal.foreign_extra_keys` /
/// `@internal.protocol_native_keys`：该键是另一个协议的原生字段，而本目标没有
/// 同名字段，下发只会让目标收到不认识的字段（常见后果是 400 拒绝）。剔除必须
/// 显式 —— 它属于 Unsupported，不是「软失败保留」的成功路径。
///
/// `owners` 为 键 → 归属协议（逗号分隔），例如 `"seed" -> "openai, gemini"`。
pub fn push_extras_foreign_at(
  prefix : String,
  owners : Map[String, String],
  diagnostics : Array[ConversionDiagnostic],
) -> Unit {
  for k, who in owners {
    diagnostics.push(
      ConversionDiagnostic::unsupported(
        prefix + "." + k,
        Some(
          "extension key \"" +
          k +
          "\" is native to " +
          who +
          ", not to this target; dropped instead of emitting a field the target does not define",
        ),
      ),
    )
  }
}

///|
/// `options.extras` 通道的外来键诊断（字段名 `options.extras.<key>`）。
pub fn push_extras_foreign(
  owners : Map[String, String],
  diagnostics : Array[ConversionDiagnostic],
) -> Unit {
  push_extras_foreign_at("options.extras", owners, diagnostics)
}
