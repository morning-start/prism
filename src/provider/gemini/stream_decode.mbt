///|
/// Google Gemini — 流解码（SSE → LucentStreamEvent）
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
  // functionCall 序号：与 request_decode/response 的 fc_<name>_<n> 规则保持一致
  // （按函数名独立计数），避免与块序号混用导致跨帧配对错位（标准 §10.1）
  let call_seq : Map[String, Int] = Map([])
  let mut i = 0
  let mut done_emitted = false
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
                        // ID 规则与 request_decode 对齐：fc_<name>_<按函数名序号>
                        let seq = match call_seq.get(name) {
                          Some(v) => v
                          None => 0
                        }
                        call_seq[name] = seq + 1
                        text_block_index = text_block_index + 1
                        events.push(
                          BlockStart(
                            text_block_index,
                            @lux.LucentBlockType::tool_call(
                              "fc_" + name + "_" + seq.to_string(),
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
              // 原生 Gemini 无 [DONE]；finishReason 即终止信号，补发 Done
              if !done_emitted {
                events.push(Done)
                done_emitted = true
              }
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
        let reasoning = @internal.parse_reasoning_tokens(u, [])
        let cached = @internal.parse_cached_tokens_gemini(u)
        events.push(
          Usage(@lux.LucentUsage::full(pt, ct, tt, reasoning, cached, None)),
        )
        if !done_emitted {
          events.push(Done)
          done_emitted = true
        }
      }
      None => ()
    }
    i = i + 1
  }
  if has_text_block {
    events.push(BlockEnd(text_block_index))
  }
  // 兜底：末帧既无 finishReason 也无 usageMetadata 时（异常流）仍发 Done，避免消费者挂起
  if !done_emitted {
    events.push(Done)
  }
  Ok(@lux.ConversionResult::new(events))
}
