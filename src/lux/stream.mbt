///|
/// Lux IR 流式事件 — 块生命周期模型（v1）
///
/// 依据：docs/lux-ir-design.md §7
/// canonical 选 Anthropic 块生命周期（四家里语义最完备），补齐 Discard/Meta/Annotations

///|
/// LucentErrorKind — 错误类型化
pub(all) enum LucentErrorKind {
  RateLimit
  InvalidRequest
  Authentication
  ServerError
  ContentFilter
  Native(String)
} derive(Eq, Debug)

///|
/// explicit: Eq::equal kept as a regular method (implicit promotion is deprecated, E0079)
pub extend LucentErrorKind with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentErrorKind with Eq::{not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentErrorKind with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// LucentError — 错误结构化
pub struct LucentError {
  kind : LucentErrorKind
  message : String
  provider_code : String?
} derive(Eq, Debug)

///|
/// explicit: Eq::equal kept as a regular method (implicit promotion is deprecated, E0079)
pub extend LucentError with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentError with Eq::{not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentError with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// LucentConversationMeta — 会话元信息（ConversationStart 携带）
///
/// 通用字段（所有/多家 provider 共有）：
/// - `id`：会话/响应 ID
/// - `model`：模型名
/// - `usage_input`：输入 token 数
/// - `created_at`：创建时间戳（OpenAI 系的 created / created_at）
///
/// 非通用字段通过 `extra` 透传（如 OpenAI Responses 的 instructions、status 等）。
pub struct LucentConversationMeta {
  id : String?
  model : String?
  usage_input : Int32?
  created_at : Int32?
  extra : Json?
} derive(Eq, Debug)

///|
/// explicit: Eq::equal kept as a regular method (implicit promotion is deprecated, E0079)
pub extend LucentConversationMeta with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentConversationMeta with Eq::{not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentConversationMeta with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// LucentBlockType — 块类型（类型化，替代字符串）
pub(all) enum LucentBlockType {
  Text
  ToolCall(String, String) // id, name（块开始时若已知）
  Thinking
  Refusal
  Image
  Audio
  Video
  Native(String)
} derive(Eq, Debug)

///|
/// explicit: Eq::equal kept as a regular method (implicit promotion is deprecated, E0079)
pub extend LucentBlockType with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentBlockType with Eq::{not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentBlockType with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// LucentBlockDelta — 块增量（类型化）
pub(all) enum LucentBlockDelta {
  TextDelta(String)
  ThinkingDelta(String)
  SignatureDelta(String) // Anthropic signature_delta / Responses signature
  ToolArgumentsDelta(String) // JSON 参数片段
  RefusalDelta(String)
  NativeDelta(String, Json) // 厂商私有增量
} derive(Eq, Debug)

///|
/// explicit: Eq::equal kept as a regular method (implicit promotion is deprecated, E0079)
pub extend LucentBlockDelta with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentBlockDelta with Eq::{not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentBlockDelta with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// LucentStreamEvent — 流事件（canonical：块生命周期）
pub(all) enum LucentStreamEvent {
  /// 会话开始（Anthropic message_start / Responses response.created）
  ConversationStart(LucentConversationMeta)
  /// 新会话项开始（Responses output_item.added）
  ItemStart(Int32, LucentConversationItem) // item_index, item skeleton
  /// 内容块开始（Anthropic content_block_start）
  BlockStart(Int32, LucentBlockType) // block_index, 类型化块类型
  /// 内容块增量（Anthropic content_block_delta / OpenAI delta.content / Gemini parts[].text）
  BlockDelta(Int32, LucentBlockDelta) // block_index, 类型化增量
  /// 内容块结束（Anthropic content_block_stop）
  BlockEnd(Int32) // block_index
  /// 会话项结束（Responses output_item.done）
  ItemEnd(Int32) // item_index
  /// 块丢弃（**已废弃（deprecated），保留仅为兼容**）
  ///
  /// 决策记录：`docs/cr/CR-003-block-discard-proposal.md` 选项 B（2026-10-23
  /// 用户批准）。原设计意图是「Gemini 全量帧覆盖前一帧时用」，但 Gemini 官方
  /// chunk 的 `parts[].text` 本就是增量语义（"the new text, not the running
  /// total. Concatenate; do not replace"），该前提不成立 —— **全链路无生产者**，
  /// 四个 provider 的 stream_decode 均不产生此事件。
  ///
  /// 选 B 而非移除（A）的理由：
  /// 1. 移除是破坏性变更（治理 §5 明列「移除现有枚举变体」），需 major 版本
  ///    与全链路适配；当前无真实用例支撑这个成本。
  /// 2. 前置问题未答：「是否存在某个未支持的 provider，其流式协议真的需要
  ///    『撤销已发内容块』语义？」在回答前移除是信息不足下的破坏性决策。
  /// 3. 死代码本身不产生错误行为（危害是「文档声称已实现」，已通过修正
  ///    fidelity-matrix 与本注释消除）。
  ///
  /// **新代码不应依赖此变体**。后续若选 A，应作为独立 CR 走完整流程。
  /// 注意：MoonBit 的 `#deprecated` 不支持枚举变体级标注（会触发
  /// unused_attribute 警告），故此处用文档注释表达废弃语义。
  BlockDiscard(Int32) // block_index
  /// 标注事件（OpenAI Responses annotations.delta / 各家 URL/file 引用）
  Annotations(Int32, Array[LucentAnnotation]) // block_index, annotations
  /// 结束原因 + 命中的自定义终止序列（CR-006 批次 2，治理 §5 破坏性变更）
  ///
  /// 第二个位置参数与 `LucentChoice.stop_sequence` **完全同构**：一个事实
  /// 一种表达。仅 Anthropic Messages 有该概念（`message_delta.stop_sequence`，
  /// 与 `stop_reason: "stop_sequence"` 配对出现），其余端恒 `None`。
  ///
  /// 便利构造器 `LucentStreamEvent::finish(reason)` 供「只关心原因」的
  /// 调用点使用；JSON 序列化在 `None` 时不输出 `stop_sequence` 键
  /// （字节形态与 0.1.x 兼容）。
  Finish(LucentFinishReason, String?)
  /// Token 用量
  Usage(LucentUsage)
  /// 错误
  Error(LucentError)
  /// 流结束
  Done
} derive(Eq, Debug)

///|
/// explicit: Eq::equal kept as a regular method (implicit promotion is deprecated, E0079)
pub extend LucentStreamEvent with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentStreamEvent with Eq::{not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend LucentStreamEvent with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// 构造器与辅助

///|
pub fn LucentErrorKind::from_string(s : String) -> LucentErrorKind {
  match s {
    "rate_limit" | "rate_limit_exceeded" | "rate_limit_error" | "429" =>
      RateLimit
    "invalid_request" | "invalid_request_error" | "400" => InvalidRequest
    "authentication" | "auth_error" | "authentication_error" | "401" | "403" =>
      Authentication
    "server_error" | "internal_server_error" | "500" | "503" => ServerError
    "content_filter" | "content_policy" | "content_filter_error" =>
      ContentFilter
    other => Native(other)
  }
}

///|
pub fn LucentError::new(
  kind : LucentErrorKind,
  message : String,
  provider_code : String?,
) -> LucentError {
  { kind, message, provider_code, }
}

///|
pub fn LucentError::simple(message : String) -> LucentError {
  { kind: Native(""), message, provider_code: None, }
}

///|
/// 便利构造器：只关心结束原因的 Finish 事件（CR-006 批次 2）。
///
/// 与 `LucentError::simple` / `LucentBlockType::text` 同风格 —— 让 0.1.x
/// 形态的 `Finish(reason)` 调用点有一一对应的机械迁移目标（补 `None`
/// 即可，或换用本构造器保持可读）。
pub fn LucentStreamEvent::finish(
  reason : LucentFinishReason,
) -> LucentStreamEvent {
  Finish(reason, None)
}

///|
pub fn LucentConversationMeta::new(
  id : String?,
  model : String?,
  usage_input : Int32?,
) -> LucentConversationMeta {
  { id, model, usage_input, created_at: None, extra: None, }
}

///|
/// 创建完整的 LucentConversationMeta（含 created_at 和 extra）
pub fn LucentConversationMeta::new_full(
  id : String?,
  model : String?,
  usage_input : Int32?,
  created_at : Int32?,
  extra : Json?,
) -> LucentConversationMeta {
  { id, model, usage_input, created_at, extra, }
}

///|
pub fn LucentBlockType::text() -> LucentBlockType {
  Text
}

///|
pub fn LucentBlockType::tool_call(
  id : String,
  name : String,
) -> LucentBlockType {
  ToolCall(id, name)
}

///|
pub fn LucentBlockType::thinking() -> LucentBlockType {
  Thinking
}

///|
pub fn LucentBlockType::refusal() -> LucentBlockType {
  Refusal
}

///|
pub fn LucentBlockType::native(tag : String) -> LucentBlockType {
  Native(tag)
}

///|
pub fn LucentBlockDelta::text_delta(s : String) -> LucentBlockDelta {
  TextDelta(s)
}

///|
pub fn LucentBlockDelta::thinking_delta(s : String) -> LucentBlockDelta {
  ThinkingDelta(s)
}

///|
pub fn LucentBlockDelta::signature_delta(s : String) -> LucentBlockDelta {
  SignatureDelta(s)
}

///|
pub fn LucentBlockDelta::tool_arguments_delta(s : String) -> LucentBlockDelta {
  ToolArgumentsDelta(s)
}

///|
pub fn LucentBlockDelta::refusal_delta(s : String) -> LucentBlockDelta {
  RefusalDelta(s)
}

///|
pub fn LucentBlockDelta::native_delta(
  tag : String,
  raw : Json,
) -> LucentBlockDelta {
  NativeDelta(tag, raw)
}

///|
/// 流事件累加器 — 将 LucentStreamEvent 流累加为 LucentResponse
///
/// 用于：
/// - 宿主语言选择「流式接收但累加成完整响应」的简化场景
/// - 跨协议一致性测试的断言依据
///
/// 累加规则：
/// - 按 item_index / block_index 跟踪活跃块
/// - Text 块累加 Text 内容
/// - ToolCall 块累加 ToolArguments 片段，结束时用 BlockStart 携带的 id/name 构造 ToolUse
/// - Thinking 块累加 Thinking + Signature 增量
/// - Refusal 块累加 Refusal 增量
/// - Gemini 风格的 BlockDiscard 会清空该块的已累加内容（仅保留 block 类型信息以备后续 BlockStart）
/// - ConversationStart 提取 id/model 用于响应
/// - Usage/Finish/Attachments 最后写入响应

///|
/// AccumulatedResponse — 累加器产物：response + 未进入 response 的辅助信息
pub struct AccumulatedResponse {
  response : LucentResponse
  annotations : Array[LucentAnnotation]
  native_events : Array[LucentStreamEvent]
  agent_actions : Array[LucentAgentAction]
  diagnostics : Array[ConversionDiagnostic]
} derive(Eq, Debug)

///|
/// explicit: Eq::equal kept as a regular method (implicit promotion is deprecated, E0079)
pub extend AccumulatedResponse with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend AccumulatedResponse with Eq::{not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend AccumulatedResponse with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// BlockAccumulator — 块状态跟踪器
///
/// 管理流式解码中的块生命周期：按 block_index 跟踪类型、文本、
/// thinking、签名、工具调用信息。提供 ensure/flush/discard 操作。
pub(all) struct BlockAccumulator {
  block_types : Array[LucentBlockType]
  block_texts : Array[StringBuilder]
  block_thinking : Array[StringBuilder]
  block_signatures : Array[StringBuilder]
  block_tool_ids : Array[String]
  block_tool_names : Array[String]
}

///|
/// 创建空的 BlockAccumulator
pub fn BlockAccumulator::new() -> BlockAccumulator {
  {
    block_types: [],
    block_texts: [],
    block_thinking: [],
    block_signatures: [],
    block_tool_ids: [],
    block_tool_names: [],
  }
}

///|
/// 确保 block_index 在跟踪数组中占位
pub fn BlockAccumulator::ensure_block(
  self : BlockAccumulator,
  idx : Int32,
) -> Unit {
  while self.block_types.length() <= idx {
    self.block_types.push(Text)
    self.block_texts.push(StringBuilder())
    self.block_thinking.push(StringBuilder())
    self.block_signatures.push(StringBuilder())
    self.block_tool_ids.push("")
    self.block_tool_names.push("")
  }
}

///|
/// 按类型把已累加内容刷入 content 数组
pub fn BlockAccumulator::flush_block(
  self : BlockAccumulator,
  idx : Int32,
  content : Array[LucentContent],
  reasoning : LucentThinking?,
) -> LucentThinking? {
  self.ensure_block(idx)
  match self.block_types[idx] {
    Text => {
      let s = self.block_texts[idx].to_string()
      if s != "" {
        content.push(LucentContent::text(s))
        self.block_texts[idx].reset()
      }
      reasoning
    }
    ToolCall(_id, _name) => {
      let id = self.block_tool_ids[idx]
      let name = self.block_tool_names[idx]
      let args = self.block_texts[idx].to_string()
      content.push(LucentContent::tool_use(id, name, args, None))
      self.block_texts[idx].reset()
      reasoning
    }
    Thinking => {
      let th_text = if !self.block_thinking[idx].is_empty() {
        self.block_thinking[idx].to_string()
      } else {
        self.block_texts[idx].to_string()
      }
      let th = LucentThinking::new(
        th_text,
        match self.block_signatures[idx].to_string() {
          "" => None
          s => Some(s)
        },
        false,
        None,
      )
      let new_reasoning = merge_reasoning(reasoning, th)
      self.block_texts[idx].reset()
      self.block_thinking[idx].reset()
      self.block_signatures[idx].reset()
      new_reasoning
    }
    Refusal => {
      let s = self.block_texts[idx].to_string()
      if s != "" {
        content.push(Refusal(s))
        self.block_texts[idx].reset()
      }
      reasoning
    }
    Image | Audio | Video | Native(_) => reasoning
  }
}

///|
/// 丢弃该块已累加内容（BlockDiscard 的累加器语义），保留类型信息。
/// BlockDiscard 本身已废弃（CR-003 选项 B）：无解码器生产，此方法仅在
/// 反序列化存量 JSON 的事件流被累加时可达。
pub fn BlockAccumulator::discard_block(
  self : BlockAccumulator,
  idx : Int32,
) -> Unit {
  self.ensure_block(idx)
  self.block_texts[idx].reset()
  self.block_thinking[idx].reset()
  self.block_signatures[idx].reset()
  self.block_tool_ids[idx] = ""
  self.block_tool_names[idx] = ""
}

///|
/// 流结束时 flush 所有未闭合的块
pub fn BlockAccumulator::flush_remaining(
  self : BlockAccumulator,
  content : Array[LucentContent],
  reasoning : LucentThinking?,
) -> LucentThinking? {
  let mut r = reasoning
  let mut j = 0
  while j < self.block_types.length() {
    if !self.block_texts[j].is_empty() ||
      !self.block_signatures[j].is_empty() ||
      !self.block_thinking[j].is_empty() {
      r = self.flush_block(j, content, r)
    }
    j = j + 1
  }
  r
}

///|
/// 把一段 thinking 累加进消息级 reasoning（文本拼接，签名取最后，redacted 取 OR）
fn merge_reasoning(
  acc : LucentThinking?,
  th : LucentThinking,
) -> LucentThinking? {
  let new_text = match acc {
    Some(a) => a.text + th.text
    None => th.text
  }
  let new_sig = match th.signature {
    Some(s) => Some(s)
    None =>
      match acc {
        Some(a) => a.signature
        None => None
      }
  }
  let new_redacted = match acc {
    Some(a) => a.redacted || th.redacted
    None => th.redacted
  }
  Some(LucentThinking::new(new_text, new_sig, new_redacted, None))
}

///|
/// 处理 BlockDelta 事件
fn handle_block_delta(
  acc : BlockAccumulator,
  idx : Int32,
  delta : LucentBlockDelta,
  events : Array[LucentStreamEvent],
  event_idx : Int32,
  diagnostics : Array[ConversionDiagnostic],
  native_events : Array[LucentStreamEvent],
) -> Unit {
  acc.ensure_block(idx)
  match delta {
    TextDelta(s) => acc.block_texts[idx].write_string(s)
    ThinkingDelta(s) => {
      acc.block_thinking[idx].write_string(s)
      match acc.block_types[idx] {
        Thinking => ()
        _ =>
          diagnostics.push(
            ConversionDiagnostic::new(
              "delta.thinking",
              Degraded,
              Some("thinking delta on non-thinking block"),
            ),
          )
      }
    }
    SignatureDelta(s) => acc.block_signatures[idx].write_string(s)
    ToolArgumentsDelta(s) => acc.block_texts[idx].write_string(s)
    RefusalDelta(s) => {
      match acc.block_types[idx] {
        Text => acc.block_types[idx] = Refusal
        _ => ()
      }
      acc.block_texts[idx].write_string(s)
    }
    NativeDelta(vendor, raw) => {
      native_events.push(events[event_idx])
      diagnostics.push(
        ConversionDiagnostic::new(
          "delta.native",
          Unsupported,
          Some(
            "native delta (" + vendor + ") not accumulated: " + raw.stringify(),
          ),
        ),
      )
    }
  }
}

///|
/// 完整累加：把流事件合成为 LucentResponse，同时保留 annotations/native_events/agent_actions
/// 及对应诊断。原 lucent_stream_events_to_response 是其薄包装（取 .response）。
pub fn lucent_stream_events_to_accumulated(
  events : Array[LucentStreamEvent],
  fallback_id : String,
  fallback_model : String,
) -> AccumulatedResponse {
  let mut resp_id = fallback_id
  let mut resp_model = fallback_model
  let mut usage : LucentUsage? = None
  let mut finish : LucentFinishReason = Stop
  let stop_seq : Array[String?] = [None]
  let mut had_error = false

  let content : Array[LucentContent] = []
  let mut reasoning : LucentThinking? = None
  let acc = BlockAccumulator::new()

  let annotations : Array[LucentAnnotation] = []
  let native_events : Array[LucentStreamEvent] = []
  let agent_actions : Array[LucentAgentAction] = []
  let diagnostics : Array[ConversionDiagnostic] = []

  let mut i = 0
  while i < events.length() {
    match events[i] {
      ConversationStart(meta) => {
        match meta.id {
          Some(id) => resp_id = id
          None => ()
        }
        match meta.model {
          Some(m) => resp_model = m
          None => ()
        }
      }
      ItemStart(_, item) =>
        match item {
          Message(m) =>
            for c in m.content {
              content.push(c)
            }
          ToolCall(tu) => content.push(ToolUse(tu))
          ToolResult(tr) => content.push(ToolResult(tr))
          Reasoning(th) => reasoning = merge_reasoning(reasoning, th)
          AgentAction(aa) => {
            agent_actions.push(aa)
            diagnostics.push(
              ConversionDiagnostic::new(
                "item.agent_action",
                Unsupported,
                Some("agent action not expanded in v1 response"),
              ),
            )
          }
        }
      BlockStart(idx, bt) => {
        acc.ensure_block(idx)
        acc.block_types[idx] = bt
        acc.block_texts[idx].reset()
        acc.block_thinking[idx].reset()
        acc.block_signatures[idx].reset()
        match bt {
          ToolCall(id, name) => {
            acc.block_tool_ids[idx] = id
            acc.block_tool_names[idx] = name
          }
          _ => ()
        }
      }
      BlockDelta(idx, delta) =>
        handle_block_delta(
          acc, idx, delta, events, i, diagnostics, native_events,
        )
      BlockEnd(idx) => reasoning = acc.flush_block(idx, content, reasoning)
      ItemEnd(_) => ()
      BlockDiscard(idx) => acc.discard_block(idx)
      Annotations(_, anns) => {
        for a in anns {
          annotations.push(a)
        }
        diagnostics.push(
          ConversionDiagnostic::new(
            "item.annotations",
            Unsupported,
            Some("annotations not merged into v1 response"),
          ),
        )
      }
      Finish(fr, ss) => {
        // CR-006 批次 2：命中序列随 Finish 载体进入 LucentChoice，
        // 流式累加结果与非流式解码从此共享同一字段（不再有第二套词汇表）。
        finish = fr
        stop_seq[0] = ss
      }
      Usage(u) => usage = Some(u)
      Error(_) => {
        had_error = true
        finish = Error
      }
      Done => ()
    }
    i = i + 1
  }

  reasoning = acc.flush_remaining(content, reasoning)

  let final_content : Array[LucentContent] = if had_error &&
    content.length() == 0 {
    [LucentContent::text("")]
  } else {
    content
  }
  let message : LucentMessage = {
    role: Assistant,
    content: final_content,
    phase: None,
    reasoning,
  }
  let choice = LucentChoice::new(0, message, finish, None)
  let choice = match stop_seq[0] {
    Some(v) => choice.with_stop_sequence(v)
    None => choice
  }
  {
    response: LucentResponse::new(
      resp_id,
      resp_model,
      None,
      [choice],
      usage,
      None,
    ),
    annotations,
    native_events,
    agent_actions,
    diagnostics,
  }
}

///|
/// 薄包装：取累加结果的 response（既有调用方兼容）
pub fn lucent_stream_events_to_response(
  events : Array[LucentStreamEvent],
  fallback_id : String,
  fallback_model : String,
) -> LucentResponse {
  lucent_stream_events_to_accumulated(events, fallback_id, fallback_model).response
}

///|
/// 便利：从 LucentStreamEvent 流中提取所有 Annotations 事件（宿主语言收集标注用）
pub fn lucent_collect_annotations(
  events : Array[LucentStreamEvent],
) -> Array[LucentAnnotation] {
  let result : Array[LucentAnnotation] = []
  let mut i = 0
  while i < events.length() {
    match events[i] {
      Annotations(_, anns) =>
        for a in anns {
          result.push(a)
        }
      _ => ()
    }
    i = i + 1
  }
  result
}
