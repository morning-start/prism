///|
/// 5. responses_sse_to_events — 流解码
///
/// 使用逐行状态机解析 SSE 流，正确处理：
/// - 多行 data: 字段（SSE 规范：用换行符合并）
/// - 心跳注释行（: keep-alive 等）
/// - data: 值内含换行符的 JSON（pretty-printed）
/// - CRLF 行尾
pub fn responses_sse_to_events(
  sse_str : String,
) -> Result[@lux.ConversionResult[Array[@lux.LucentStreamEvent]], String] {
  let events : Array[@lux.LucentStreamEvent] = []
  let diagnostics : Array[@lux.ConversionDiagnostic] = []
  // 统一换行符：CRLF → LF，再用统一 SSE 解析
  let normalized = sse_str
    .replace(old="\r\n", new="\n")
    .replace(old="\r", new="\n")
  let messages = @internal.parse_sse_messages(normalized)
  let mut i = 0
  while i < messages.length() {
    let event_type_raw = messages[i].event_type.unwrap_or("")
    let data_raw = messages[i].data.trim().to_owned()
    // 统一帧预处理（iteration-008 方向 B）：与 messages/openai/gemini
    // 共用 internal 管线，保留"失败必诊断"语义
    let (jv_opt, fail_reason) = @internal.parse_sse_frame_with_reason(data_raw)
    match jv_opt {
      None =>
        match fail_reason {
          Some(reason) =>
            diagnostics.push(
              @lux.ConversionDiagnostic::new("sse.data", Invalid, Some(reason)),
            )
          None => ()
        }
      Some(jv) => {
        // event: 行缺失时，从 JSON 的 type 字段回退推断事件类型
        let event_type = if event_type_raw == "" {
          @internal.field_str(jv, "type").unwrap_or(event_type_raw)
        } else {
          event_type_raw
        }
        match event_type {
          "response.created" =>
            match @internal.obj_get(jv, "response") {
              Some(r) => {
                let rid = @internal.field_str(r, "id")
                let rmodel = @internal.field_str(r, "model")
                let created_at = @internal.field_int(r, "created_at")
                let extra = build_extra(r, ["id", "model", "created_at"])
                events.push(
                  ConversationStart(
                    @lux.LucentConversationMeta::new_full(
                      rid,
                      rmodel,
                      None,
                      created_at,
                      extra,
                    ),
                  ),
                )
              }
              None => ()
            }
          "response.output_item.added" => {
            let idx = @internal.field_int(jv, "output_index").unwrap_or(0)
            match @internal.obj_get(jv, "item") {
              Some(item) =>
                match parse_input_item(item, diagnostics) {
                  Some(ci) => {
                    events.push(ItemStart(idx, ci))
                    // reasoning item 需要额外发出 BlockStart，让编码器生成 thinking content block
                    match @internal.field_str(item, "type") {
                      Some("reasoning") =>
                        events.push(BlockStart(idx, Thinking))
                      _ => ()
                    }
                  }
                  None => ()
                }
              None => ()
            }
          }
          "response.content_part.added" => {
            let idx = @internal.field_int(jv, "content_index").unwrap_or(0)
            match @internal.obj_get(jv, "part") {
              Some(part) =>
                match @internal.field_str(part, "type") {
                  Some("output_text") => events.push(BlockStart(idx, Text))
                  Some("refusal") => events.push(BlockStart(idx, Refusal))
                  _ => ()
                }
              None => ()
            }
          }
          "response.output_text.delta" => {
            let idx = @internal.field_int(jv, "content_index").unwrap_or(0)
            match @internal.field_str(jv, "delta") {
              Some(t) =>
                events.push(
                  BlockDelta(idx, @lux.LucentBlockDelta::text_delta(t)),
                )
              None => ()
            }
          }
          "response.output_text.done" => {
            let idx = @internal.field_int(jv, "content_index").unwrap_or(0)
            events.push(BlockEnd(idx))
          }
          "response.refusal.delta" => {
            let idx = @internal.field_int(jv, "content_index").unwrap_or(0)
            match @internal.field_str(jv, "delta") {
              Some(t) =>
                events.push(
                  BlockDelta(idx, @lux.LucentBlockDelta::refusal_delta(t)),
                )
              None => ()
            }
          }
          "response.refusal.done" => {
            let idx = @internal.field_int(jv, "content_index").unwrap_or(0)
            events.push(BlockEnd(idx))
          }
          "response.reasoning_summary_text.delta"
          | "response.reasoning_text.delta" => {
            let idx = @internal.field_int(jv, "content_index").unwrap_or(0)
            match @internal.field_str(jv, "delta") {
              Some(t) =>
                events.push(
                  BlockDelta(idx, @lux.LucentBlockDelta::thinking_delta(t)),
                )
              None => ()
            }
          }
          "response.reasoning_summary_text.done"
          | "response.reasoning_text.done" => {
            let idx = @internal.field_int(jv, "content_index").unwrap_or(0)
            events.push(BlockEnd(idx))
          }
          "response.function_call_arguments.delta" => {
            let idx = @internal.field_int(jv, "output_index").unwrap_or(0)
            match @internal.field_str(jv, "delta") {
              Some(a) =>
                events.push(
                  BlockDelta(
                    idx,
                    @lux.LucentBlockDelta::tool_arguments_delta(a),
                  ),
                )
              None => ()
            }
          }
          "response.function_call_arguments.done" => {
            let idx = @internal.field_int(jv, "output_index").unwrap_or(0)
            events.push(BlockEnd(idx))
          }
          "response.completed" => {
            match @internal.obj_get(jv, "response") {
              Some(r) => {
                match @internal.field_str(r, "status") {
                  Some(s) =>
                    events.push(Finish(@lux.LucentFinishReason::from_string(s)))
                  None => ()
                }
                match @internal.obj_get(r, "usage") {
                  Some(u) => {
                    let pt = @internal.field_int(u, "input_tokens").unwrap_or(0)
                    let ct = @internal.field_int(u, "output_tokens").unwrap_or(
                      0,
                    )
                    let tt = @internal.field_int(u, "total_tokens").unwrap_or(
                      pt + ct,
                    )
                    let reasoning = @internal.parse_reasoning_tokens(u, [
                      "output_tokens_details",
                    ])
                    let cached = @internal.parse_cached_tokens(u, [
                      "input_tokens_details",
                    ])
                    events.push(
                      Usage(
                        @lux.LucentUsage::full(
                          pt,
                          ct,
                          tt,
                          reasoning,
                          cached,
                          None,
                        ),
                      ),
                    )
                  }
                  None => ()
                }
              }
              None => ()
            }
            events.push(Done)
          }
          "error" =>
            match @internal.field_str(jv, "error") {
              Some(err_msg) =>
                events.push(Error(@lux.LucentError::simple(err_msg)))
              None => ()
            }
          _ => ()
        }
      }
    }
    i = i + 1
  }
  let result = @lux.ConversionResult::new(events)
  Ok(result.with_diagnostics(diagnostics))
}
