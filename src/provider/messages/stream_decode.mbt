///|
/// Anthropic Messages — 流解码（SSE → LucentStreamEvent）
///
/// SSE 格式：
///   event: X
///   data: {...}
///
/// 用 \n\n 分隔 SSE 消息，再逐条解析 event/data 行

///|
/// Anthropic Messages 流解码的跨帧状态（P1 修复）。
///
/// `message_delta.usage` 只保证 `output_tokens`；`input_tokens` 与缓存计费项
/// 挂在更早的 `message_start.usage` —— 逐帧解码时后续帧看不到首帧，必须靠
/// 会话把输入侧用量带到 `message_delta`（此前是函数局部变量，逐帧即丢失，
/// 导致 `prompt_tokens` 恒 0）。会话化后两条路径共享同一份状态机。
pub struct MessagesStreamState {
  mut usage_input : Int32?
  mut usage_cached : Int32?
  mut usage_cache_creation : Int32?
  /// 本会话是否已发出 message_stop 的 Done（逐帧路径由会话层统一补终止符）
  mut finish_seen : Bool
}

///|
pub fn MessagesStreamState::new() -> MessagesStreamState {
  {
    usage_input: None,
    usage_cached: None,
    usage_cache_creation: None,
    finish_seen: false,
  }
}

///|
pub fn messages_sse_to_events(
  sse_str : String,
) -> Result[@lux.ConversionResult[Array[@lux.LucentStreamEvent]], String] {
  messages_decode_frames(sse_str, MessagesStreamState::new())
}

///|
/// 解码一帧 SSE（复用会话内跨帧状态）
fn messages_decode_frames(
  sse_str : String,
  st : MessagesStreamState,
) -> Result[@lux.ConversionResult[Array[@lux.LucentStreamEvent]], String] {
  let events : Array[@lux.LucentStreamEvent] = []
  let messages = @internal.parse_sse_messages(sse_str)
  // CR-001 D1：跨帧累积输入侧用量。Anthropic 的 message_delta.usage 只保证
  // output_tokens；input_tokens / 缓存计费项既可能挂在 message_start.usage，
  // 也可能重复挂在 message_delta.usage —— 两处都读，缺失时回落到已记录值，
  // 避免"输入侧恒 0"。
  let mut usage_input : Int32? = st.usage_input
  let mut usage_cached : Int32? = st.usage_cached
  let mut usage_cache_creation : Int32? = st.usage_cache_creation
  let mut i = 0
  while i < messages.length() {
    let event_type = messages[i].event_type.unwrap_or("")
    let jv = match @internal.parse_sse_frame(messages[i].data) {
      Some(v) => v
      None => {
        i = i + 1
        continue
      }
    }
    match event_type {
      "message_start" =>
        match @internal.obj_get(jv, "message") {
          Some(msg_jv) => {
            let id = @internal.field_str(msg_jv, "id")
            let model = @internal.field_str(msg_jv, "model")
            match @internal.obj_get(msg_jv, "usage") {
              Some(u) => {
                usage_input = @internal.field_int(u, "input_tokens")
                usage_cached = @internal.parse_cached_tokens(u, [])
                usage_cache_creation = @internal.parse_cache_creation_tokens(
                  u,
                  [],
                )
              }
              None => ()
            }
            // CR-001：缓存计费项随会话元信息透传（extension 载体 extra，缺失即 None）。
            // 逐帧路径下 message_delta 帧看不到 message_start，StreamConverter 依赖
            // 该载体回填输入侧用量，从而与整缓冲输出保持一致。
            let cache_fields : Map[String, Json] = Map([])
            match usage_cached {
              Some(n) => cache_fields["usage_cached"] = Json(n)
              None => ()
            }
            match usage_cache_creation {
              Some(n) => cache_fields["usage_cache_creation"] = Json(n)
              None => ()
            }
            let meta_extra : Json? = if cache_fields.length() > 0 {
              Some(Json::object(cache_fields))
            } else {
              None
            }
            events.push(
              ConversationStart(
                @lux.LucentConversationMeta::new_full(
                  id,
                  model,
                  usage_input,
                  None,
                  meta_extra,
                ),
              ),
            )
          }
          None => ()
        }
      "content_block_start" => {
        let idx = @internal.field_int(jv, "index").unwrap_or(0)
        match @internal.obj_get(jv, "content_block") {
          Some(block) =>
            match @internal.field_str(block, "type") {
              Some("text") => events.push(BlockStart(idx, Text))
              Some("thinking") => events.push(BlockStart(idx, Thinking))
              Some("tool_use") => {
                let tc_id = @internal.field_str(block, "id").unwrap_or("")
                let tc_name = @internal.field_str(block, "name").unwrap_or("")
                events.push(
                  BlockStart(
                    idx,
                    @lux.LucentBlockType::tool_call(tc_id, tc_name),
                  ),
                )
              }
              _ => ()
            }
          None => ()
        }
      }
      "content_block_delta" => {
        let idx = @internal.field_int(jv, "index").unwrap_or(0)
        match @internal.obj_get(jv, "delta") {
          Some(delta) =>
            match @internal.field_str(delta, "type") {
              Some("text_delta") =>
                match @internal.field_str(delta, "text") {
                  Some(t) =>
                    events.push(
                      BlockDelta(idx, @lux.LucentBlockDelta::text_delta(t)),
                    )
                  None => ()
                }
              Some("thinking_delta") =>
                match @internal.field_str(delta, "thinking") {
                  Some(t) =>
                    events.push(
                      BlockDelta(idx, @lux.LucentBlockDelta::thinking_delta(t)),
                    )
                  None => ()
                }
              Some("signature_delta") =>
                match @internal.field_str(delta, "signature") {
                  Some(s) =>
                    events.push(
                      BlockDelta(idx, @lux.LucentBlockDelta::signature_delta(s)),
                    )
                  None => ()
                }
              Some("input_json_delta") =>
                match @internal.field_str(delta, "partial_json") {
                  Some(j_str) =>
                    events.push(
                      BlockDelta(
                        idx,
                        @lux.LucentBlockDelta::tool_arguments_delta(j_str),
                      ),
                    )
                  None => ()
                }
              _ => ()
            }
          None => ()
        }
      }
      "content_block_stop" => {
        let idx = @internal.field_int(jv, "index").unwrap_or(0)
        events.push(BlockEnd(idx))
      }
      "message_delta" => {
        match @internal.obj_get(jv, "delta") {
          Some(delta) =>
            match @internal.field_str(delta, "stop_reason") {
              Some(reason) => {
                events.push(
                  Finish(@lux.LucentFinishReason::from_string(reason)),
                )
                st.finish_seen = true
              }
              None => ()
            }
          None => ()
        }
        match @internal.obj_get(jv, "usage") {
          Some(u) => {
            let pt = match @internal.field_int(u, "input_tokens") {
              Some(n) => n
              None => usage_input.unwrap_or(0)
            }
            let ot = @internal.field_int(u, "output_tokens").unwrap_or(0)
            let cached = match @internal.parse_cached_tokens(u, []) {
              Some(n) => Some(n)
              None => usage_cached
            }
            let cache_creation = match
              @internal.parse_cache_creation_tokens(u, []) {
              Some(n) => Some(n)
              None => usage_cache_creation
            }
            events.push(
              Usage(
                @lux.LucentUsage::full(
                  pt,
                  ot,
                  pt + ot,
                  None,
                  cached,
                  cache_creation,
                ),
              ),
            )
          }
          None => ()
        }
      }
      "message_stop" => {
        // 如果没有 Finish 事件，补一个默认的 Finish(Stop)。
        // 跨帧：Finish 可能落在更早的 message_delta 帧，用会话标记而非本帧
        // 事件判断，否则逐帧路径会重复补 Finish（规整器虽会去重，但语义应
        // 在解码侧就正确）。
        if !st.finish_seen {
          events.push(Finish(Stop))
          st.finish_seen = true
        }
        events.push(Done)
      }
      "error" =>
        // Anthropic error 事件：{"type":"error","error":{"type":"...","message":"..."}}
        // error 是对象而非字符串；兼容字符串形态的容错写法。
        // 顺序 String → 对象：obj_get 返回 error 键的值本身，字符串值若先进
        // 对象分支会退化成 "unknown error" 并丢掉真正的错误文本。
        match @internal.obj_get(jv, "error") {
          Some(String(err_str)) =>
            events.push(Error(@lux.LucentError::simple(err_str)))
          Some(err_obj) => {
            let err_type = @internal.field_str(err_obj, "type")
            let err_msg = @internal.field_str(err_obj, "message")
            let msg = match err_msg {
              Some(m) => m
              None =>
                match err_type {
                  Some(t) => t
                  None => "unknown error"
                }
            }
            let kind = @lux.LucentErrorKind::from_string(err_type.unwrap_or(""))
            events.push(Error(@lux.LucentError::new(kind, msg, err_type)))
          }
          None => ()
        }
      _ => ()
    }
    i = i + 1
  }
  // 跨帧状态写回会话
  st.usage_input = usage_input
  st.usage_cached = usage_cached
  st.usage_cache_creation = usage_cache_creation
  Ok(@lux.ConversionResult::new(events))
}

///|
/// 创建 messages 流解码会话（T5 增量转换入口，跨帧状态由会话持有）
///
/// `decode` 逐帧调用复用同一状态：`message_delta` 帧仍能读到 `message_start`
/// 记录的输入侧用量（否则 `prompt_tokens` 恒 0）。
pub fn messages_stream_decoder() -> @lux.LucentStreamDecoder {
  let st = MessagesStreamState::new()
  @lux.LucentStreamDecoder::new(
    fn(frame) { messages_decode_frames(frame, st) },
    fn() { [] },
  )
}
