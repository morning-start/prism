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
pub(all) struct LucentUsage {
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
