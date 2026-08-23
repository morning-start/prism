///|
/// Lux IR — Prism 中立中间协议（v1）
///
/// 依据：docs/lux-ir-design.md
/// 骨干：LucentConversationItem 异质平级，承载消息/工具调用/工具结果/推理/Agent 动作
/// 版本：schema_version = "v1"

///|
/// LucentRole — 对话角色
pub(all) enum LucentRole {
  System
  User
  Assistant
  Tool
  Model
  Developer
  Native(String)
} derive(Eq, Debug)

///|
/// LucentModality — 模态声明
pub(all) enum LucentModality {
  Text
  Image
  Audio
  Video
  Pdf
  Native(String)
} derive(Eq, Debug)

///|
/// LucentMediaSource — 多模态来源三选一
pub(all) enum LucentMediaSource {
  Inline(String)
  Url(String)
  FileUri(String)
} derive(Eq, Debug)

///|
/// LucentMultimedia — 多模态媒体块
pub struct LucentMultimedia {
  media_type : String
  source : LucentMediaSource
} derive(Eq, Debug)

///|
/// LucentAnnotationKind — 标注类型
pub(all) enum LucentAnnotationKind {
  Url
  FileCitation
  WebSearchCitation
  Native(String)
} derive(Eq, Debug)

///|
/// LucentAnnotation — 标注侧信道
pub struct LucentAnnotation {
  kind : LucentAnnotationKind
  text : String?
  reference : String?
  start : Int?
  end : Int?
} derive(Eq, Debug)

///|
/// LucentThinking — 推理内容
pub struct LucentThinking {
  text : String
  signature : String?
  redacted : Bool
  summary : Array[LucentContent]?
} derive(Eq, Debug)

///|
/// LucentToolUse — 工具调用（结构化）
pub struct LucentToolUse {
  id : String
  name : String
  arguments_json : String
  arguments_value : Json?
} derive(Eq, Debug)

///|
/// LucentToolResult — 工具结果（多块内容）
pub struct LucentToolResult {
  tool_use_id : String
  content : Array[LucentContent]
  is_error : Bool
} derive(Eq, Debug)

///|
/// LucentAgentAction — Agent 动作占位（v1 仅类型化，参数走 provider_payload）
pub struct LucentAgentAction {
  kind : String
  id : String
  call_id : String?
  name : String?
  arguments_json : String?
  result : String?
  provider_payload : Json?
} derive(Eq, Debug)

///|
/// LucentContent — 内容块主枚举
pub(all) enum LucentContent {
  Text(String, Array[LucentAnnotation]?)
  ToolUse(LucentToolUse)
  ToolResult(LucentToolResult)
  Thinking(LucentThinking)
  Refusal(String)
  Image(LucentMultimedia)
  Audio(LucentMultimedia)
  Video(LucentMultimedia)
  File(LucentMultimedia)
  Native(String, Json)
} derive(Eq, Debug)

///|
/// LucentMessage — 消息特例（role + content 块数组）
pub struct LucentMessage {
  role : LucentRole
  content : Array[LucentContent]
  phase : String?
  /// 消息级 reasoning（vLLM/DeepSeek/Fireworks 的 message.reasoning / reasoning_content）
  reasoning : LucentThinking?
} derive(Eq, Debug)

///|
/// LucentConversationItem — 会话项异质平级
pub(all) enum LucentConversationItem {
  Message(LucentMessage)
  ToolCall(LucentToolUse)
  ToolResult(LucentToolResult)
  Reasoning(LucentThinking)
  AgentAction(LucentAgentAction)
} derive(Eq, Debug)

///|
/// LucentToolKind — 工具类型（消费方处理逻辑不同）
pub(all) enum LucentToolKind {
  Function
  FileSearch
  WebSearch
  CodeInterpreter
  ComputerUse
  CodeExecution
  Shell
  ApplyPatch
  MCP
  Native(String)
} derive(Eq, Debug)

///|
/// LucentTool — 工具定义
pub struct LucentTool {
  name : String
  description : String?
  parameters_json : String
  strict : Bool?
  kind : LucentToolKind
} derive(Eq, Debug)

///|
/// LucentToolChoice — 工具选择（类型化）
pub(all) enum LucentToolChoice {
  Auto
  None
  Required
  SpecificTool(String)
} derive(Eq, Debug)

///|
/// LucentStructuredOutput — 结构化输出
pub(all) enum LucentStructuredOutput {
  JsonObject
  Text
  JsonSchema(String)
} derive(Eq, Debug)

///|
/// LucentOptions — 生成参数
pub struct LucentOptions {
  temperature : Double?
  top_p : Double?
  top_k : Int?
  max_output_tokens : Int?
  stop : Array[String]?
  stream : Bool
  candidate_count : Int?
  /// @deprecated 仅 OpenAI Chat 使用，非通用生成参数，后续移入 extras
  seed : Int?
  structured_output : LucentStructuredOutput?
  store : Bool?
  extras : Map[String, Json]?
} derive(Eq, Debug)

///|
/// LucentReasoningEffort — 推理力度
pub(all) enum LucentReasoningEffort {
  Low
  Medium
  High
  XHigh
} derive(Eq, Debug)

///|
/// LucentReasoningSummary — 推理摘要详细度
pub(all) enum LucentReasoningSummary {
  Auto
  Concise
  Detailed
} derive(Eq, Debug)

///|
/// LucentReasoningConfig — 推理配置
pub struct LucentReasoningConfig {
  enabled : Bool
  budget_tokens : Int?
  effort : LucentReasoningEffort?
  summary : LucentReasoningSummary?
} derive(Eq, Debug)

///|
/// SupportLevel — 能力支持级别
/// 替代原有 Bool 能力声明，区分「完全支持 / 部分支持 / 不支持」三档。
/// 线格式：`"full"` / `"partial"` / `"none"`（`Absent` 命名避开 Option::None 冲突）。
pub(all) enum SupportLevel {
  Full
  Partial
  Absent
} derive(Eq, Debug)

///|
pub fn SupportLevel::from_string(s : String) -> SupportLevel? {
  match s {
    "full" => Some(Full)
    "partial" => Some(Partial)
    "none" => Some(Absent)
    _ => None
  }
}

///|
pub fn SupportLevel::to_string(self : SupportLevel) -> String {
  match self {
    Full => "full"
    Partial => "partial"
    Absent => "none"
  }
}

///|
/// LucentCapabilities — 标准化能力声明
pub struct LucentCapabilities {
  tool_calling : SupportLevel
  parallel_tool_calls : SupportLevel
  reasoning : SupportLevel
  multimodal_input : SupportLevel
  structured_output : SupportLevel
  input_modalities : Array[LucentModality]
  output_modalities : Array[LucentModality]
} derive(Eq, Debug)

///|
/// LucentRequest — 完整 LLM 请求
pub struct LucentRequest {
  schema_version : String
  model : String
  instructions : Array[LucentContent]?
  conversation : Array[LucentConversationItem]
  tools : Array[LucentTool]?
  tool_choice : LucentToolChoice?
  options : LucentOptions
  capabilities : LucentCapabilities?
  reasoning : LucentReasoningConfig?
  metadata : Map[String, String]?
  extra : Map[String, Json]?
} derive(Eq, Debug)

///|
/// LucentUsage — Token 用量（面向 reasoning 时代）
pub struct LucentUsage {
  prompt_tokens : Int
  completion_tokens : Int
  total_tokens : Int
  reasoning_tokens : Int?
  cached_tokens : Int?
  cache_creation_tokens : Int?
} derive(Eq, Debug)

///|
/// LucentFinishReason — 结束原因
pub(all) enum LucentFinishReason {
  Stop
  Length
  ToolCalls
  ContentFilter
  Safety
  Recitation
  MalformedToolCall
  Error
  Native(String)
} derive(Eq, Debug)

///|
/// LucentSafetyRating — 安全评级
pub struct LucentSafetyRating {
  category : String
  probability : String
} derive(Eq, Debug)

///|
/// LucentChoice — 候选回复
pub struct LucentChoice {
  index : Int
  message : LucentMessage
  finish_reason : LucentFinishReason
  safety_ratings : Array[LucentSafetyRating]?
} derive(Eq, Debug)

///|
/// LucentResponse — 非流式 LLM 响应
pub struct LucentResponse {
  schema_version : String
  id : String
  model : String
  created_at : Int?
  choices : Array[LucentChoice]
  usage : LucentUsage?
  provider_payload : Json?
} derive(Eq, Debug)

///|
/// ProviderCapability — 适配器能力声明（SDK 自省用）
pub struct ProviderCapability {
  model_pattern : String
  provider : String
  capabilities : LucentCapabilities
  extra_params : Map[String, Json]?
} derive(Eq, Debug)

///|
pub fn ProviderCapability::new(
  model_pattern : String,
  provider : String,
  capabilities : LucentCapabilities,
  extra_params : Map[String, Json]?,
) -> ProviderCapability {
  { model_pattern, provider, capabilities, extra_params }
}

///|
/// ConversionStatus — 字段转换状态（五道门治理要求）
pub(all) enum ConversionStatus {
  Exact // 字段完全对等映射，无信息丢失
  Degraded // 字段被近似映射，部分语义丢失
  Unsupported // 字段不被目标协议支持，已舍弃
  Invalid // 字段格式错误或值非法
} derive(Eq, Debug)

///|
/// ConversionDiagnostic — 单个字段的转换结果诊断
pub struct ConversionDiagnostic {
  field : String
  status : ConversionStatus
  detail : String?
} derive(Eq, Debug)

///|
pub fn ConversionDiagnostic::new(
  field : String,
  status : ConversionStatus,
  detail : String?,
) -> ConversionDiagnostic {
  { field, status, detail }
}

///|
/// ConversionResult — 带诊断的转换结果
/// 成功时不等于 Exact：value 可用但部分字段已丢失
pub struct ConversionResult[T] {
  value : T
  diagnostics : Array[ConversionDiagnostic]
} derive(Eq, Debug)

///|
pub fn[T] ConversionResult::new(value : T) -> ConversionResult[T] {
  { value, diagnostics: [] }
}

///|
/// 获取转换结果值。
pub fn[T] ConversionResult::value(self : ConversionResult[T]) -> T {
  self.value
}

///|
/// 获取转换诊断列表。
pub fn[T] ConversionResult::diagnostics(
  self : ConversionResult[T],
) -> Array[ConversionDiagnostic] {
  self.diagnostics
}

///|
/// 追加一条转换诊断（返回新结果，不修改原结果的诊断数组）。
pub fn[T] ConversionResult::with_diagnostic(
  self : ConversionResult[T],
  diagnostic : ConversionDiagnostic,
) -> ConversionResult[T] {
  let diagnostics = self.diagnostics.copy()
  diagnostics.push(diagnostic)
  { ..self, diagnostics, }
}

///|
/// 批量附加诊断（返回新结果，等价于逐条 with_diagnostic）。
pub fn[T] ConversionResult::with_diagnostics(
  self : ConversionResult[T],
  diagnostics : Array[ConversionDiagnostic],
) -> ConversionResult[T] {
  if diagnostics.length() == 0 {
    return self
  }
  let all = self.diagnostics.copy()
  for d in diagnostics {
    all.push(d)
  }
  { ..self, diagnostics: all }
}

///|
/// 构造 Unsupported 诊断（provider 适配器共用样板）。
pub fn ConversionDiagnostic::unsupported(
  field : String,
  detail : String?,
) -> ConversionDiagnostic {
  { field, status: Unsupported, detail }
}

///|
/// 构造 Degraded 诊断（provider 适配器共用样板）。
pub fn ConversionDiagnostic::degraded(
  field : String,
  detail : String?,
) -> ConversionDiagnostic {
  { field, status: Degraded, detail }
}

///|
/// 获取诊断状态。
pub fn ConversionDiagnostic::status(
  self : ConversionDiagnostic,
) -> ConversionStatus {
  self.status
}

///|
/// LucentDiscovery — 能力发现响应
/// SDK 接入时第一步调用，获取 Prism 实例的能力清单
pub struct LucentDiscovery {
  schema_version : String
  protocol_version : String
  schema_url : String
  providers : Array[ProviderCapability]
} derive(Eq, Debug)

///|
pub fn LucentDiscovery::new(
  protocol_version : String,
  schema_url : String,
  providers : Array[ProviderCapability],
) -> LucentDiscovery {
  { schema_version: "v1", protocol_version, schema_url, providers }
}

///|
/// 构造器与辅助函数

///|
pub fn LucentRole::from_string(s : String) -> LucentRole? {
  match s {
    "system" => Some(System)
    "user" => Some(User)
    "assistant" => Some(Assistant)
    "tool" => Some(Tool)
    "model" => Some(Model)
    "developer" => Some(Developer)
    _ => None
  }
}

///|
pub fn LucentRole::to_string(self : LucentRole) -> String {
  match self {
    System => "system"
    User => "user"
    Assistant => "assistant"
    Tool => "tool"
    Model => "model"
    Developer => "developer"
    Native(s) => s
  }
}

///|
pub fn LucentModality::from_string(s : String) -> LucentModality? {
  match s {
    "text" => Some(Text)
    "image" => Some(Image)
    "audio" => Some(Audio)
    "video" => Some(Video)
    "pdf" => Some(Pdf)
    _ => None
  }
}

///|
pub fn LucentMediaSource::inline(data : String) -> LucentMediaSource {
  Inline(data)
}

///|
pub fn LucentMediaSource::url(u : String) -> LucentMediaSource {
  Url(u)
}

///|
pub fn LucentMediaSource::file_uri(uri : String) -> LucentMediaSource {
  FileUri(uri)
}

///|
pub fn LucentMultimedia::new(
  media_type : String,
  source : LucentMediaSource,
) -> LucentMultimedia {
  { media_type, source }
}

///|
pub fn LucentAnnotation::new(
  kind : LucentAnnotationKind,
  text : String?,
  reference : String?,
  start : Int?,
  end : Int?,
) -> LucentAnnotation {
  { kind, text, reference, start, end }
}

///|
pub fn LucentThinking::new(
  text : String,
  signature : String?,
  redacted : Bool,
  summary : Array[LucentContent]?,
) -> LucentThinking {
  { text, signature, redacted, summary }
}

///|
pub fn LucentThinking::visible(
  text : String,
  signature : String?,
) -> LucentThinking {
  { text, signature, redacted: false, summary: None }
}

///|
pub fn LucentThinking::redacted(signature : String?) -> LucentThinking {
  { text: "", signature, redacted: true, summary: None }
}

///|
pub fn LucentToolUse::new(
  id : String,
  name : String,
  arguments_json : String,
  arguments_value : Json?,
) -> LucentToolUse {
  { id, name, arguments_json, arguments_value }
}

///|
pub fn LucentToolResult::new(
  tool_use_id : String,
  content : Array[LucentContent],
  is_error : Bool,
) -> LucentToolResult {
  { tool_use_id, content, is_error }
}

///|
pub fn LucentToolResult::ok(
  tool_use_id : String,
  content : Array[LucentContent],
) -> LucentToolResult {
  { tool_use_id, content, is_error: false }
}

///|
pub fn LucentToolResult::error(
  tool_use_id : String,
  content : Array[LucentContent],
) -> LucentToolResult {
  { tool_use_id, content, is_error: true }
}

///|
pub fn LucentAgentAction::new(
  kind : String,
  id : String,
  call_id : String?,
  name : String?,
  arguments_json : String?,
  result : String?,
  provider_payload : Json?,
) -> LucentAgentAction {
  { kind, id, call_id, name, arguments_json, result, provider_payload }
}

///|
pub fn LucentContent::text(s : String) -> LucentContent {
  Text(s, None)
}

///|
pub fn LucentContent::text_with_annotations(
  s : String,
  annotations : Array[LucentAnnotation],
) -> LucentContent {
  Text(s, Some(annotations))
}

///|
pub fn LucentContent::tool_use(
  id : String,
  name : String,
  arguments_json : String,
  arguments_value : Json?,
) -> LucentContent {
  ToolUse({ id, name, arguments_json, arguments_value })
}

///|
pub fn LucentContent::tool_result(
  tool_use_id : String,
  content : Array[LucentContent],
) -> LucentContent {
  ToolResult({ tool_use_id, content, is_error: false })
}

///|
pub fn LucentContent::tool_result_error(
  tool_use_id : String,
  content : Array[LucentContent],
) -> LucentContent {
  ToolResult({ tool_use_id, content, is_error: true })
}

///|
pub fn LucentContent::thinking(
  text : String,
  signature : String?,
) -> LucentContent {
  Thinking({ text, signature, redacted: false, summary: None })
}

///|
pub fn LucentContent::redacted_thinking(signature : String?) -> LucentContent {
  Thinking({ text: "", signature, redacted: true, summary: None })
}

///|
pub fn LucentContent::refusal(text : String) -> LucentContent {
  Refusal(text)
}

///|
pub fn LucentContent::image(
  media_type : String,
  source : LucentMediaSource,
) -> LucentContent {
  Image({ media_type, source })
}

///|
/// 构造文件 content（PDF 等非媒体文件），来源三选一：url / inline / file_uri
pub fn LucentContent::file(
  media_type : String,
  source : LucentMediaSource,
) -> LucentContent {
  File({ media_type, source })
}

///|
pub fn LucentContent::audio(
  media_type : String,
  source : LucentMediaSource,
) -> LucentContent {
  Audio({ media_type, source })
}

///|
pub fn LucentContent::video(
  media_type : String,
  source : LucentMediaSource,
) -> LucentContent {
  Video({ media_type, source })
}

///|
pub fn LucentContent::native(type_tag : String, raw : Json) -> LucentContent {
  Native(type_tag, raw)
}

///|
pub fn LucentMessage::new(
  role : LucentRole,
  content : Array[LucentContent],
) -> LucentMessage {
  { role, content, phase: None, reasoning: None }
}

///|
pub fn LucentMessage::with_phase(
  role : LucentRole,
  content : Array[LucentContent],
  phase : String?,
) -> LucentMessage {
  { role, content, phase, reasoning: None }
}

///|
/// 构造带消息级 reasoning 的 message（openai-chat 等适配器入站使用）
pub fn LucentMessage::with_reasoning(
  role : LucentRole,
  content : Array[LucentContent],
  reasoning : LucentThinking?,
) -> LucentMessage {
  { role, content, phase: None, reasoning }
}

///|
pub fn LucentConversationItem::message(
  msg : LucentMessage,
) -> LucentConversationItem {
  Message(msg)
}

///|
pub fn LucentConversationItem::tool_call(
  tu : LucentToolUse,
) -> LucentConversationItem {
  ToolCall(tu)
}

///|
pub fn LucentConversationItem::tool_result(
  tr : LucentToolResult,
) -> LucentConversationItem {
  ToolResult(tr)
}

///|
pub fn LucentConversationItem::reasoning(
  th : LucentThinking,
) -> LucentConversationItem {
  Reasoning(th)
}

///|
pub fn LucentConversationItem::agent_action(
  aa : LucentAgentAction,
) -> LucentConversationItem {
  AgentAction(aa)
}

///|
/// 便利：将 Array[LucentMessage] 包装为 Array[LucentConversationItem]
pub fn lucent_items_from_messages(
  msgs : Array[LucentMessage],
) -> Array[LucentConversationItem] {
  let result : Array[LucentConversationItem] = []
  let mut i = 0
  while i < msgs.length() {
    result.push(LucentConversationItem::message(msgs[i]))
    i = i + 1
  }
  result
}

///|
pub fn LucentTool::new(
  name : String,
  description : String?,
  parameters_json : String,
  strict : Bool?,
  kind : LucentToolKind,
) -> LucentTool {
  { name, description, parameters_json, strict, kind }
}

///|
pub fn LucentTool::simple(
  name : String,
  description : String,
  parameters_json : String,
) -> LucentTool {
  {
    name,
    description: Some(description),
    parameters_json,
    strict: None,
    kind: Function,
  }
}

///|
pub fn LucentOptions::default() -> LucentOptions {
  {
    temperature: None,
    top_p: None,
    top_k: None,
    max_output_tokens: None,
    stop: None,
    stream: false,
    candidate_count: None,
    seed: None,
    structured_output: None,
    store: None,
    extras: None,
  }
}

///|
pub fn LucentOptions::new(
  temperature : Double?,
  top_p : Double?,
  top_k : Int?,
  max_output_tokens : Int?,
  stop : Array[String]?,
  stream : Bool,
  candidate_count : Int?,
  seed : Int?,
  structured_output : LucentStructuredOutput?,
  store : Bool?,
  extras : Map[String, Json]?,
) -> LucentOptions {
  {
    temperature,
    top_p,
    top_k,
    max_output_tokens,
    stop,
    stream,
    candidate_count,
    seed,
    structured_output,
    store,
    extras,
  }
}

///|

///|
pub fn LucentCapabilities::default() -> LucentCapabilities {
  {
    tool_calling: Absent,
    parallel_tool_calls: Absent,
    reasoning: Absent,
    multimodal_input: Absent,
    structured_output: Absent,
    input_modalities: [],
    output_modalities: [],
  }
}

///|
pub fn LucentCapabilities::create(
  tool_calling : SupportLevel,
  parallel_tool_calls : SupportLevel,
  reasoning : SupportLevel,
  multimodal_input : SupportLevel,
  structured_output : SupportLevel,
  input_modalities : Array[LucentModality],
  output_modalities : Array[LucentModality],
) -> LucentCapabilities {
  {
    tool_calling,
    parallel_tool_calls,
    reasoning,
    multimodal_input,
    structured_output,
    input_modalities,
    output_modalities,
  }
}

///|
pub fn LucentReasoningConfig::enabled(budget : Int?) -> LucentReasoningConfig {
  { enabled: true, budget_tokens: budget, effort: None, summary: None }
}

///|
pub fn LucentReasoningConfig::new(
  effort : LucentReasoningEffort?,
  summary : LucentReasoningSummary?,
) -> LucentReasoningConfig {
  { enabled: true, budget_tokens: None, effort, summary }
}

///|
pub fn LucentReasoningConfig::disabled() -> LucentReasoningConfig {
  { enabled: false, budget_tokens: None, effort: None, summary: None }
}

///|
pub fn LucentRequest::new(
  model : String,
  instructions : Array[LucentContent]?,
  conversation : Array[LucentConversationItem],
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
    conversation,
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
/// 构建含 store 值的选项副本
pub fn LucentOptions::with_store(
  self : LucentOptions,
  store : Bool?,
) -> LucentOptions {
  { ..self, store, }
}

///|
/// 构建含 extras 的选项副本
pub fn LucentOptions::with_extras(
  self : LucentOptions,
  extras : Map[String, Json]?,
) -> LucentOptions {
  { ..self, extras, }
}

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
  let mut i = 0
  while i < items.length() {
    match items[i] {
      Message(m) => result.push(m)
      _ => ()
    }
    i = i + 1
  }
  result
}

///|
/// 将 LucentContent 数组拼接为纯文本（Text 块拼接，其他块忽略）
pub fn lucent_content_to_text(parts : Array[LucentContent]) -> String {
  let buf : Array[String] = []
  let mut i = 0
  while i < parts.length() {
    match parts[i] {
      Text(s, _) => buf.push(s)
      _ => ()
    }
    i = i + 1
  }
  buf.join("")
}
