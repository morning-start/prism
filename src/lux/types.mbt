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
/// 显式声明 Eq::equal 保留为常规方法（隐式提升已弃用，见 E0079）
pub extend LucentRole with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentRole with Eq::{not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentRole with @moonbitlang/core/debug.Debug::{to_repr}

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
/// explicit: Eq::equal kept as a regular method (implicit promotion is deprecated, E0079)
pub extend LucentModality with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentModality with Eq::{not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentModality with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// LucentMediaSource — 多模态来源三选一
pub(all) enum LucentMediaSource {
  Inline(String)
  Url(String)
  FileUri(String)
} derive(Eq, Debug)

///|
/// explicit: Eq::equal kept as a regular method (implicit promotion is deprecated, E0079)
pub extend LucentMediaSource with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentMediaSource with Eq::{not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentMediaSource with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// LucentMultimedia — 多模态媒体块
pub struct LucentMultimedia {
  media_type : String
  source : LucentMediaSource
} derive(Eq, Debug)

///|
/// explicit: Eq::equal kept as a regular method (implicit promotion is deprecated, E0079)
pub extend LucentMultimedia with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentMultimedia with Eq::{not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentMultimedia with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// LucentAnnotationKind — 标注类型
pub(all) enum LucentAnnotationKind {
  Url
  FileCitation
  WebSearchCitation
  Native(String)
} derive(Eq, Debug)

///|
/// explicit: Eq::equal kept as a regular method (implicit promotion is deprecated, E0079)
pub extend LucentAnnotationKind with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentAnnotationKind with Eq::{not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentAnnotationKind with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// LucentAnnotation — 标注侧信道
pub struct LucentAnnotation {
  kind : LucentAnnotationKind
  text : String?
  reference : String?
  start : Int32?
  end : Int32?
} derive(Eq, Debug)

///|
/// explicit: Eq::equal kept as a regular method (implicit promotion is deprecated, E0079)
pub extend LucentAnnotation with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentAnnotation with Eq::{not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentAnnotation with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// LucentThinking — 推理内容
pub struct LucentThinking {
  text : String
  signature : String?
  redacted : Bool
  summary : Array[LucentContent]?
} derive(Eq, Debug)

///|
/// explicit: Eq::equal kept as a regular method (implicit promotion is deprecated, E0079)
pub extend LucentThinking with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentThinking with Eq::{not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentThinking with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// LucentToolUse — 工具调用（结构化）
pub struct LucentToolUse {
  id : String
  name : String
  arguments_json : String
  arguments_value : Json?
} derive(Eq, Debug)

///|
/// explicit: Eq::equal kept as a regular method (implicit promotion is deprecated, E0079)
pub extend LucentToolUse with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentToolUse with Eq::{not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentToolUse with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// LucentToolResult — 工具结果（多块内容）
pub struct LucentToolResult {
  tool_use_id : String
  content : Array[LucentContent]
  is_error : Bool
} derive(Eq, Debug)

///|
/// explicit: Eq::equal kept as a regular method (implicit promotion is deprecated, E0079)
pub extend LucentToolResult with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentToolResult with Eq::{not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentToolResult with @moonbitlang/core/debug.Debug::{to_repr}

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
/// explicit: Eq::equal kept as a regular method (implicit promotion is deprecated, E0079)
pub extend LucentAgentAction with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentAgentAction with Eq::{not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentAgentAction with @moonbitlang/core/debug.Debug::{to_repr}

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
/// explicit: Eq::equal kept as a regular method (implicit promotion is deprecated, E0079)
pub extend LucentContent with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentContent with Eq::{not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentContent with @moonbitlang/core/debug.Debug::{to_repr}

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
/// explicit: Eq::equal kept as a regular method (implicit promotion is deprecated, E0079)
pub extend LucentMessage with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentMessage with Eq::{not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentMessage with @moonbitlang/core/debug.Debug::{to_repr}

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
/// explicit: Eq::equal kept as a regular method (implicit promotion is deprecated, E0079)
pub extend LucentConversationItem with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentConversationItem with Eq::{not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentConversationItem with @moonbitlang/core/debug.Debug::{to_repr}

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
/// explicit: Eq::equal kept as a regular method (implicit promotion is deprecated, E0079)
pub extend LucentToolKind with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentToolKind with Eq::{not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentToolKind with @moonbitlang/core/debug.Debug::{to_repr}

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
/// explicit: Eq::equal kept as a regular method (implicit promotion is deprecated, E0079)
pub extend LucentTool with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentTool with Eq::{not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentTool with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// LucentToolChoice — 工具选择（类型化）
/// Native(String)：未知 tool_choice 值原样保留（与 Role/ToolKind 等一致）
pub(all) enum LucentToolChoice {
  Auto
  None
  Required
  SpecificTool(String)
  Native(String)
} derive(Eq, Debug)

///|
/// explicit: Eq::equal kept as a regular method (implicit promotion is deprecated, E0079)
pub extend LucentToolChoice with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentToolChoice with Eq::{not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentToolChoice with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// LucentStructuredOutput — 结构化输出
/// Native(String)：未知 structured_output 值原样保留
pub(all) enum LucentStructuredOutput {
  JsonObject
  Text
  JsonSchema(String)
  Native(String)
} derive(Eq, Debug)

///|
/// explicit: Eq::equal kept as a regular method (implicit promotion is deprecated, E0079)
pub extend LucentStructuredOutput with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentStructuredOutput with Eq::{not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentStructuredOutput with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// LucentOptions — 生成参数
pub struct LucentOptions {
  temperature : Double?
  top_p : Double?
  top_k : Int32?
  max_output_tokens : Int32?
  stop : Array[String]?
  stream : Bool
  candidate_count : Int32?
  structured_output : LucentStructuredOutput?
  store : Bool?
  /// Responses 有状态续接载体（T8 标准可选字段）：上一轮 response id。
  /// 无状态端点（chat/messages/gemini）出站时由目标端拒绝或降级。
  previous_response_id : String?
  extras : Map[String, Json]?
} derive(Eq, Debug)

///|
/// explicit: Eq::equal kept as a regular method (implicit promotion is deprecated, E0079)
pub extend LucentOptions with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentOptions with Eq::{not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentOptions with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// LucentReasoningEffort — 推理力度
/// Native(String)：未知档位原样保留（跨 provider 档位漂移不丢数据）
pub(all) enum LucentReasoningEffort {
  Low
  Medium
  High
  XHigh
  Native(String)
} derive(Eq, Debug)

///|
/// explicit: Eq::equal kept as a regular method (implicit promotion is deprecated, E0079)
pub extend LucentReasoningEffort with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentReasoningEffort with Eq::{not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentReasoningEffort with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// LucentReasoningSummary — 推理摘要详细度
/// Native(String)：未知详细度值原样保留
pub(all) enum LucentReasoningSummary {
  Auto
  Concise
  Detailed
  Native(String)
} derive(Eq, Debug)

///|
/// explicit: Eq::equal kept as a regular method (implicit promotion is deprecated, E0079)
pub extend LucentReasoningSummary with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentReasoningSummary with Eq::{not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentReasoningSummary with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// ConversationSnapshot — 中间件本地会话存储单元（T8）
///
/// 背景：Responses 的 previous_response_id 是有状态续接——客户端第二轮
/// 只带新 input + 上一轮 response id，历史在服务端。跨端转到无状态
/// 端点（chat/messages/gemini）时必须由中间件本地保存并还原历史。
/// 本类型是存储单元：某次 response_id 对应的请求上下文（还原所需）
/// 与可选响应文本（审计/调试用）。不参与 wire 编解码；
/// to_json/from_json 供宿主持久化（IR 提案见
/// .agent-workplace/docs/report/ir-proposal-previous-response-id.md）。
pub struct ConversationSnapshot {
  response_id : String
  request : LucentRequest
  response_text : String?
} derive(Eq, Debug)

///|
/// explicit: Eq::equal kept as a regular method (implicit promotion is deprecated, E0079)
pub extend ConversationSnapshot with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend ConversationSnapshot with Eq::{not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend ConversationSnapshot with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// LucentReasoningConfig — 推理配置
pub struct LucentReasoningConfig {
  enabled : Bool
  budget_tokens : Int32?
  effort : LucentReasoningEffort?
  summary : LucentReasoningSummary?
} derive(Eq, Debug)

///|
/// explicit: Eq::equal kept as a regular method (implicit promotion is deprecated, E0079)
pub extend LucentReasoningConfig with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentReasoningConfig with Eq::{not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentReasoningConfig with @moonbitlang/core/debug.Debug::{to_repr}

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
/// explicit: Eq::equal kept as a regular method (implicit promotion is deprecated, E0079)
pub extend SupportLevel with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend SupportLevel with Eq::{not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend SupportLevel with @moonbitlang/core/debug.Debug::{to_repr}

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
/// explicit: Eq::equal kept as a regular method (implicit promotion is deprecated, E0079)
pub extend LucentCapabilities with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentCapabilities with Eq::{not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentCapabilities with @moonbitlang/core/debug.Debug::{to_repr}

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
/// explicit: Eq::equal kept as a regular method (implicit promotion is deprecated, E0079)
pub extend LucentRequest with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentRequest with Eq::{not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentRequest with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// LucentUsage — Token 用量（面向 reasoning 时代）
pub(all) struct LucentUsage {
  prompt_tokens : Int32
  completion_tokens : Int32
  total_tokens : Int32
  reasoning_tokens : Int32?
  cached_tokens : Int32?
  cache_creation_tokens : Int32?
} derive(Eq, Debug)

///|
/// explicit: Eq::equal kept as a regular method (implicit promotion is deprecated, E0079)
pub extend LucentUsage with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentUsage with Eq::{not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentUsage with @moonbitlang/core/debug.Debug::{to_repr}

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
/// explicit: Eq::equal kept as a regular method (implicit promotion is deprecated, E0079)
pub extend LucentFinishReason with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentFinishReason with Eq::{not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentFinishReason with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// LucentSafetyRating — 安全评级
pub struct LucentSafetyRating {
  category : String
  probability : String
} derive(Eq, Debug)

///|
/// explicit: Eq::equal kept as a regular method (implicit promotion is deprecated, E0079)
pub extend LucentSafetyRating with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentSafetyRating with Eq::{not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentSafetyRating with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// LucentChoice — 候选回复
pub struct LucentChoice {
  index : Int32
  message : LucentMessage
  finish_reason : LucentFinishReason
  safety_ratings : Array[LucentSafetyRating]?
  /// 实际命中的自定义终止序列（CR-005）。
  ///
  /// 与 `LucentOptions.stop`（请求侧的**候选**列表）是不同的事实：这里是
  /// 响应侧「最终命中了哪一个」。Anthropic Messages 的 `stop_sequence` 字段
  /// 即此语义，且与 `stop_reason: "stop_sequence"` 配对出现。
  ///
  /// 标准可选字段（治理 §6「新增可选标准字段」）：`None` 表示未命中任何
  /// 自定义序列。只有 messages 有该概念，其余目标编码时若不支持须显式诊断。
  stop_sequence : String?
} derive(Eq, Debug)

///|
/// explicit: Eq::equal kept as a regular method (implicit promotion is deprecated, E0079)
pub extend LucentChoice with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentChoice with Eq::{not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentChoice with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// LucentResponse — 非流式 LLM 响应
pub struct LucentResponse {
  schema_version : String
  id : String
  model : String
  created_at : Int32?
  choices : Array[LucentChoice]
  usage : LucentUsage?
  provider_payload : Json?
} derive(Eq, Debug)

///|
/// explicit: Eq::equal kept as a regular method (implicit promotion is deprecated, E0079)
pub extend LucentResponse with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentResponse with Eq::{not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentResponse with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// ProviderCapability — 适配器能力声明（SDK 自省用）
pub struct ProviderCapability {
  model_pattern : String
  provider : String
  capabilities : LucentCapabilities
  extra_params : Map[String, Json]?
} derive(Eq, Debug)

///|
/// explicit: Eq::equal kept as a regular method (implicit promotion is deprecated, E0079)
pub extend ProviderCapability with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend ProviderCapability with Eq::{not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend ProviderCapability with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub fn ProviderCapability::new(
  model_pattern : String,
  provider : String,
  capabilities : LucentCapabilities,
  extra_params : Map[String, Json]?,
) -> ProviderCapability {
  { model_pattern, provider, capabilities, extra_params, }
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
/// explicit: Eq::equal kept as a regular method (implicit promotion is deprecated, E0079)
pub extend ConversionStatus with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend ConversionStatus with Eq::{not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend ConversionStatus with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// ConversionDiagnostic — 单个字段的转换结果诊断
pub struct ConversionDiagnostic {
  field : String
  status : ConversionStatus
  detail : String?
} derive(Eq, Debug)

///|
/// explicit: Eq::equal kept as a regular method (implicit promotion is deprecated, E0079)
pub extend ConversionDiagnostic with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend ConversionDiagnostic with Eq::{not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend ConversionDiagnostic with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub fn ConversionDiagnostic::new(
  field : String,
  status : ConversionStatus,
  detail : String?,
) -> ConversionDiagnostic {
  { field, status, detail, }
}

///|
/// ConversionResult — 带诊断的转换结果
/// 成功时不等于 Exact：value 可用但部分字段已丢失
pub struct ConversionResult[T] {
  value : T
  diagnostics : Array[ConversionDiagnostic]
} derive(Eq, Debug)

///|
/// explicit: Eq::equal kept as a regular method (implicit promotion is deprecated, E0079)
pub extend ConversionResult with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend ConversionResult with Eq::{not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend ConversionResult with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub fn[T] ConversionResult::new(value : T) -> ConversionResult[T] {
  { value, diagnostics: [], }
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
  { ..self, diagnostics: all, }
}

///|
/// 构造 Unsupported 诊断（provider 适配器共用样板）。
pub fn ConversionDiagnostic::unsupported(
  field : String,
  detail : String?,
) -> ConversionDiagnostic {
  { field, status: Unsupported, detail, }
}

///|
/// 构造 Degraded 诊断（provider 适配器共用样板）。
pub fn ConversionDiagnostic::degraded(
  field : String,
  detail : String?,
) -> ConversionDiagnostic {
  { field, status: Degraded, detail, }
}

///|
/// 构造 Exact 诊断（场景说明用：字段确实无损，但承载位置非直觉 —— 例如
/// 目标协议的流式开关由端点路径而非请求体决定）。不表示降级。
pub fn ConversionDiagnostic::exact(
  field : String,
  detail : String?,
) -> ConversionDiagnostic {
  { field, status: Exact, detail, }
}

///|
/// 构造 Invalid 诊断（provider 适配器共用样板：入站载荷格式非法、无法编码为
/// 合法的目标请求体时使用，调用方通常同时回退到安全默认值）。
pub fn ConversionDiagnostic::invalid(
  field : String,
  detail : String?,
) -> ConversionDiagnostic {
  { field, status: Invalid, detail, }
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
/// explicit: Eq::equal kept as a regular method (implicit promotion is deprecated, E0079)
pub extend LucentDiscovery with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentDiscovery with Eq::{not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentDiscovery with @moonbitlang/core/debug.Debug::{to_repr}

///|
pub fn LucentDiscovery::new(
  protocol_version : String,
  schema_url : String,
  providers : Array[ProviderCapability],
) -> LucentDiscovery {
  { schema_version: "v1", protocol_version, schema_url, providers, }
}
