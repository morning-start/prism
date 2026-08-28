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
  for msg in msgs {
    result.push(LucentConversationItem::message(msg))
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
