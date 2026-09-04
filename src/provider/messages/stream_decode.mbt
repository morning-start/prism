///|
/// Anthropic Messages — 流解码（SSE → LucentStreamEvent）
///
/// SSE 格式：
///   event: X
///   data: {...}
///
/// 用 \n\n 分隔 SSE 消息，再逐条解析 event/data 行
pub fn messages_sse_to_events(
  sse_str : String,
) -> Result[@lux.ConversionResult[Array[@lux.LucentStreamEvent]], String] {
  let events : Array[@lux.LucentStreamEvent] = []
  let messages = @internal.parse_sse_messages(sse_str)
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
            let usage_input = match @internal.obj_get(msg_jv, "usage") {
              Some(u) => @internal.field_int(u, "input_tokens")
              None => None
            }
            events.push(
              ConversationStart(
                @lux.LucentConversationMeta::new(id, model, usage_input),
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
              Some(reason) =>
                events.push(
                  Finish(@lux.LucentFinishReason::from_string(reason)),
                )
              None => ()
            }
          None => ()
        }
        match @internal.obj_get(jv, "usage") {
          Some(u) => {
            let (_, ot, _) = @internal.parse_usage_json(
              u,
              "input_tokens",
              "output_tokens",
              None,
            )
            events.push(Usage(@lux.LucentUsage::new(0, ot, ot)))
          }
          None => ()
        }
      }
      "message_stop" => {
        // 如果没有 Finish 事件，补一个默认的 Finish(Stop)
        let has_finish = events.any(fn(e) {
          match e {
            Finish(_) => true
            _ => false
          }
        })
        if !has_finish {
          events.push(Finish(Stop))
        }
        events.push(Done)
      }
      "error" =>
        // Anthropic error 事件：{"type":"error","error":{"type":"...","message":"..."}}
        // error 是对象而非字符串；兼容字符串形态的容错写法
        match @internal.obj_get(jv, "error") {
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
          None =>
            match @internal.field_str(jv, "error") {
              Some(e_msg) => events.push(Error(@lux.LucentError::simple(e_msg)))
              None => ()
            }
        }
      _ => ()
    }
    i = i + 1
  }
  Ok(@lux.ConversionResult::new(events))
}
