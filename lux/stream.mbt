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
/// LucentError — 错误结构化
pub struct LucentError {
  kind : LucentErrorKind
  message : String
  provider_code : String?
} derive(Eq, Debug)

///|
/// LucentConversationMeta — 会话元信息（ConversationStart 携带）
pub struct LucentConversationMeta {
  id : String?
  model : String?
  usage_input : Int?
} derive(Eq, Debug)

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
/// LucentStreamEvent — 流事件（canonical：块生命周期）
pub(all) enum LucentStreamEvent {
  /// 会话开始（Anthropic message_start / Responses response.created）
  ConversationStart(LucentConversationMeta)
  /// 新会话项开始（Responses output_item.added）
  ItemStart(Int, LucentConversationItem) // item_index, item skeleton
  /// 内容块开始（Anthropic content_block_start）
  BlockStart(Int, LucentBlockType) // block_index, 类型化块类型
  /// 内容块增量（Anthropic content_block_delta / OpenAI delta.content / Gemini parts[].text）
  BlockDelta(Int, LucentBlockDelta) // block_index, 类型化增量
  /// 内容块结束（Anthropic content_block_stop）
  BlockEnd(Int) // block_index
  /// 会话项结束（Responses output_item.done）
  ItemEnd(Int) // item_index
  /// 块丢弃（Gemini 全量帧覆盖前一帧时用，其他厂商不触发）
  BlockDiscard(Int) // block_index
  /// 标注事件（OpenAI Responses annotations.delta / 各家 URL/file 引用）
  Annotations(Int, Array[LucentAnnotation]) // block_index, annotations
  /// 结束原因
  Finish(LucentFinishReason)
  /// Token 用量
  Usage(LucentUsage)
  /// 错误
  Error(LucentError)
  /// 流结束
  Done
} derive(Eq, Debug)

///|
/// 构造器与辅助

///|
pub fn LucentErrorKind::from_string(s : String) -> LucentErrorKind {
  match s {
    "rate_limit" | "rate_limit_exceeded" | "429" => RateLimit
    "invalid_request" | "invalid_request_error" | "400" => InvalidRequest
    "authentication" | "auth_error" | "401" | "403" => Authentication
    "server_error" | "internal_server_error" | "500" | "503" => ServerError
    "content_filter" | "content_policy" => ContentFilter
    other => Native(other)
  }
}

///|
pub fn LucentError::new(
  kind : LucentErrorKind,
  message : String,
  provider_code : String?,
) -> LucentError {
  { kind, message, provider_code }
}

///|
pub fn LucentError::simple(message : String) -> LucentError {
  { kind: Native(""), message, provider_code: None }
}

///|
pub fn LucentConversationMeta::new(
  id : String?,
  model : String?,
  usage_input : Int?,
) -> LucentConversationMeta {
  { id, model, usage_input }
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
/// 完整累加：把流事件合成为 LucentResponse，同时保留 annotations/native_events/agent_actions
/// 及对应诊断。原 lucent_stream_events_to_response 是其薄包装（取 .response）。
pub fn lucent_stream_events_to_accumulated(
  events : Array[LucentStreamEvent],
  fallback_id : String,
  fallback_model : String,
) -> AccumulatedResponse {
  // 会话元信息（ConversationStart 携带，缺则用 fallback）
  let mut resp_id = fallback_id
  let mut resp_model = fallback_model
  let mut usage : LucentUsage? = None
  let mut finish : LucentFinishReason = Stop
  let mut had_error = false

  // 累加内容：单一 assistant 消息（流式语义：一个响应对应一个 assistant 回复）
  let content : Array[LucentContent] = []
  // 块状态跟踪：block_index -> (类型, 已累加的文本)
  // 用线性数组替代 Map（MoonBit 风格），下标即 block_index
  let block_types : Array[LucentBlockType] = []
  let block_texts : Array[String] = []
  let block_signatures : Array[String] = []
  let block_tool_ids : Array[String] = []
  let block_tool_names : Array[String] = []

  // 辅助信息侧信道（不进入 response 主体）
  let annotations : Array[LucentAnnotation] = []
  let native_events : Array[LucentStreamEvent] = []
  let agent_actions : Array[LucentAgentAction] = []
  let diagnostics : Array[ConversionDiagnostic] = []

  ///| 块辅助：确保 block_index 在跟踪数组中占位
  fn ensure_block(idx : Int) -> Unit {
    while block_types.length() <= idx {
      block_types.push(Text) // 占位，真实类型由 BlockStart 覆盖
      block_texts.push("")
      block_signatures.push("")
      block_tool_ids.push("")
      block_tool_names.push("")
    }
  }

  ///| 块辅助：按类型把已累加内容刷入 content 数组
  fn flush_block(idx : Int) -> Unit {
    ensure_block(idx)
    match block_types[idx] {
      Text => {
        let s = block_texts[idx]
        if s != "" {
          content.push(LucentContent::text(s))
          block_texts[idx] = ""
        }
      }
      ToolCall(_id, _name) => {
        let id = block_tool_ids[idx]
        let name = block_tool_names[idx]
        let args = block_texts[idx]
        content.push(LucentContent::tool_use(id, name, args, None))
        block_texts[idx] = ""
      }
      Thinking => {
        let th = LucentThinking::new(
          block_texts[idx],
          match block_signatures[idx] {
            "" => None
            s => Some(s)
          },
          false,
          None,
        )
        content.push(Thinking(th))
        block_texts[idx] = ""
        block_signatures[idx] = ""
      }
      Refusal => {
        let s = block_texts[idx]
        if s != "" {
          content.push(Refusal(s))
          block_texts[idx] = ""
        }
      }
      Image | Audio | Video | Native(_) => () // 流中不累加媒体块
    }
  }

  ///| 块辅助：丢弃该块已累加内容（Gemini 全量帧覆盖语义），保留类型信息
  fn discard_block(idx : Int) -> Unit {
    ensure_block(idx)
    block_texts[idx] = ""
    block_signatures[idx] = ""
    block_tool_ids[idx] = ""
    block_tool_names[idx] = ""
  }

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
        // Responses 风格：独立 Item（非 Message 内的块）
        // 对于 ToolCall/ToolResult/Reasoning/AgentAction 直接 flush 到 content
        match item {
          Message(m) =>
            // 流中单 assistant 消息模型：把 Message 的内容并入 content
            for c in m.content {
              content.push(c)
            }
          ToolCall(tu) => content.push(ToolUse(tu))
          ToolResult(tr) => content.push(ToolResult(tr))
          Reasoning(th) => content.push(Thinking(th))
          AgentAction(aa) => {
            // v1 不展开到 response，保留到侧信道 + 诊断
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
        ensure_block(idx)
        block_types[idx] = bt
        block_texts[idx] = ""
        block_signatures[idx] = ""
        match bt {
          ToolCall(id, name) => {
            block_tool_ids[idx] = id
            block_tool_names[idx] = name
          }
          _ => ()
        }
      }
      BlockDelta(idx, delta) => {
        ensure_block(idx)
        match delta {
          TextDelta(s) => block_texts[idx] = block_texts[idx] + s
          ThinkingDelta(s) => block_texts[idx] = block_texts[idx] + s
          SignatureDelta(s) => block_signatures[idx] = block_signatures[idx] + s
          ToolArgumentsDelta(s) => block_texts[idx] = block_texts[idx] + s
          RefusalDelta(s) => {
            // Refusal 块类型若未显式 BlockStart，按 Refusal 处理
            match block_types[idx] {
              Text => block_types[idx] = Refusal
              _ => ()
            }
            block_texts[idx] = block_texts[idx] + s
          }
          NativeDelta(vendor, raw) => {
            // 厂商私有增量：保留到侧信道 + 诊断
            native_events.push(events[i])
            diagnostics.push(
              ConversionDiagnostic::new(
                "delta.native",
                Unsupported,
                Some(
                  "native delta (" +
                  vendor +
                  ") not accumulated: " +
                  raw.stringify(),
                ),
              ),
            )
          }
        }
      }
      BlockEnd(idx) => flush_block(idx)
      ItemEnd(_) => ()
      BlockDiscard(idx) => discard_block(idx)
      Annotations(_, anns) => {
        // 标注事件：保留到侧信道 + 诊断
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
      Finish(fr) => finish = fr
      Usage(u) => usage = Some(u)
      Error(_) => {
        had_error = true
        finish = Error
      }
      Done => ()
    }
    i = i + 1
  }

  // 流结束时未闭合的块：按块索引顺序 flush
  let mut j = 0
  while j < block_types.length() {
    // 仅 flush 有内容的块（避免空 Text 块污染）
    if block_texts[j] != "" || block_signatures[j] != "" {
      flush_block(j)
    }
    j = j + 1
  }

  // 构造 assistant 消息：若内容为空且发生错误，保留空消息；否则用累加内容
  let final_content : Array[LucentContent] = if had_error &&
    content.length() == 0 {
    [LucentContent::text("")]
  } else {
    content
  }
  let message = LucentMessage::new(Assistant, final_content)
  let choice = LucentChoice::new(0, message, finish, None)
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
