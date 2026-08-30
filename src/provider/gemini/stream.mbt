///|
/// 5. gemini_sse_to_events — 流解码
///
/// Gemini 流式格式：每行一个 data: {...} 完整帧
/// 适配层做 diff，发 BlockDiscard 旧帧 + BlockDelta 新内容
pub fn gemini_sse_to_events(
  sse_str : String,
) -> Result[@lux.ConversionResult[Array[@lux.LucentStreamEvent]], String] {
  let events : Array[@lux.LucentStreamEvent] = []
  // Gemini 流式用单 \n 分隔消息（非标准 SSE），归一化为 \n\n
  // 先将 \n\n 压为 \n，再将 \n 展开为 \n\n，保证每个 data: 行独占一个消息块
  let normalized = sse_str
    .replace(old="\r\n", new="\n")
    .replace(old="\n\n", new="\n")
    .replace(old="\n", new="\n\n")
  let messages = @internal.parse_sse_messages(normalized)
  let mut has_text_block = false
  let mut current_text = ""
  let mut text_block_index = 0
  let mut i = 0
  while i < messages.length() {
    let jv = match @internal.parse_sse_frame(messages[i].data) {
      Some(v) => v
      None => {
        i = i + 1
        continue
      }
    }
    // 每一帧都是完整 candidates 数组
    // 对 text 部分做简单 diff：检测新文本增量
    match @internal.field_arr(jv, "candidates") {
      Some(cands) =>
        if cands.length() > 0 {
          match @internal.obj_get(cands[0], "content") {
            Some(content) =>
              match @internal.field_arr(content, "parts") {
                Some(parts) => {
                  let mut j = 0
                  while j < parts.length() {
                    match @internal.field_str(parts[j], "text") {
                      Some(t) => {
                        if !has_text_block {
                          events.push(BlockStart(text_block_index, Text))
                          has_text_block = true
                        }
                        // Gemini 每帧是完整文本，非增量
                        // 简单方式：丢弃旧文本，发新文本
                        if current_text != "" {
                          events.push(BlockDiscard(text_block_index))
                        }
                        current_text = t
                        events.push(
                          BlockDelta(
                            text_block_index,
                            @lux.LucentBlockDelta::text_delta(t),
                          ),
                        )
                      }
                      None => ()
                    }
                    // functionCall（全量返回，一次性完成）
                    match @internal.obj_get(parts[j], "functionCall") {
                      Some(fc) => {
                        let name = @internal.field_str(fc, "name").unwrap_or("")
                        let args = match @internal.obj_get(fc, "args") {
                          Some(a) => a.stringify()
                          None => "{}"
                        }
                        if has_text_block {
                          events.push(BlockEnd(text_block_index))
                          has_text_block = false
                        }
                        text_block_index = text_block_index + 1
                        events.push(
                          BlockStart(
                            text_block_index,
                            @lux.LucentBlockType::tool_call(
                              "fc_" + name + "_" + text_block_index.to_string(),
                              name,
                            ),
                          ),
                        )
                        events.push(
                          BlockDelta(
                            text_block_index,
                            @lux.LucentBlockDelta::tool_arguments_delta(args),
                          ),
                        )
                        events.push(BlockEnd(text_block_index))
                        text_block_index = text_block_index + 1
                      }
                      None => ()
                    }
                    // thought part → 独立 Thinking 块（不静默丢弃，不伪装成 Text）
                    match @internal.obj_get(parts[j], "thought") {
                      Some(True) =>
                        match @internal.field_str(parts[j], "text") {
                          Some(t) => {
                            if has_text_block {
                              events.push(BlockEnd(text_block_index))
                              has_text_block = false
                            }
                            text_block_index = text_block_index + 1
                            events.push(BlockStart(text_block_index, Thinking))
                            events.push(
                              BlockDelta(
                                text_block_index,
                                @lux.LucentBlockDelta::thinking_delta(t),
                              ),
                            )
                            events.push(BlockEnd(text_block_index))
                            text_block_index = text_block_index + 1
                          }
                          None => ()
                        }
                      _ => ()
                    }
                    j = j + 1
                  }
                }
                None => ()
              }
            None => ()
          }
          // finishReason
          match @internal.field_str(cands[0], "finishReason") {
            Some(fr) => {
              if has_text_block {
                events.push(BlockEnd(text_block_index))
                has_text_block = false
              }
              events.push(Finish(@lux.LucentFinishReason::from_string(fr)))
            }
            None => ()
          }
        }
      None => ()
    }
    // usageMetadata（最后一帧含 finishReason）
    match @internal.obj_get(jv, "usageMetadata") {
      Some(u) => {
        let (pt, ct, tt) = @internal.parse_usage_json(
          u,
          "promptTokenCount",
          "candidatesTokenCount",
          Some("totalTokenCount"),
        )
        events.push(Usage(@lux.LucentUsage::new(pt, ct, tt)))
        events.push(Done)
      }
      None => ()
    }
    i = i + 1
  }
  if has_text_block {
    events.push(BlockEnd(text_block_index))
  }
  Ok(@lux.ConversionResult::new(events))
}

///|
/// 6. lux_events_to_gemini_sse — 流编码
pub fn lux_events_to_gemini_sse(
  events : Array[@lux.LucentStreamEvent],
) -> Result[@lux.ConversionResult[String], String] {
  // Gemini 流式是完整帧格式，块周期事件需要合并为完整 candidates
  // 简化实现：累加文本内容，每帧发送完整文本
  let lines : Array[String] = []
  let mut acc_text = ""
  let mut last_text = ""
  let mut blocks_with_args : Array[String] = []
  let mut i = 0
  while i < events.length() {
    match events[i] {
      BlockDelta(_, TextDelta(s)) => {
        acc_text = acc_text + s
        if acc_text != last_text {
          lines.push(
            "data: {\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"text\":\"" +
            @internal.json_escape(acc_text) +
            "\"}]}}]}",
          )
          last_text = acc_text
        }
      }
      BlockDelta(_, ToolArgumentsDelta(s)) => blocks_with_args.push(s)
      BlockStart(_, ToolCall(_, name)) => {
        let args = if blocks_with_args.length() > 0 {
          blocks_with_args.join("")
        } else {
          "{}"
        }
        lines.push(
          "data: {\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"functionCall\":{\"name\":\"" +
          @internal.json_escape(name) +
          "\",\"args\":" +
          args +
          "}}]}}]}",
        )
        blocks_with_args = []
      }
      Finish(fr) => {
        let finish_str = match fr {
          Stop => "STOP"
          Length => "MAX_TOKENS"
          ToolCalls => "STOP"
          Safety => "SAFETY"
          Recitation => "RECITATION"
          MalformedToolCall => "MALFORMED_FUNCTION_CALL"
          Error => "OTHER"
          _ => "STOP"
        }
        lines.push(
          "data: {\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"text\":\"" +
          @internal.json_escape(acc_text) +
          "\"}]},\"finishReason\":\"" +
          finish_str +
          "\"}]}",
        )
      }
      Usage(u) =>
        lines.push(
          "data: {\"candidates\":[],\"usageMetadata\":{\"promptTokenCount\":" +
          u.prompt_tokens.to_string() +
          ",\"candidatesTokenCount\":" +
          u.completion_tokens.to_string() +
          ",\"totalTokenCount\":" +
          u.total_tokens.to_string() +
          "}}",
        )
      _ => ()
    }
    i = i + 1
  }
  Ok(@lux.ConversionResult::new(lines.join("\n") + "\n"))
}
