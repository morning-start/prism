///|
/// Google Gemini — 流解码（SSE → LucentStreamEvent）
///
/// 官方流式语义（关键）：
///   - `streamGenerateContent` 每个 chunk 的 `parts[].text` 是**增量**
///     （官方原文：the new text, not the running total. Concatenate; do not replace）
///   - `functionCall` 一次性整块到达（不是增量）
///   - **没有** `[DONE]` 终止符：`finishReason` 即终止信号
///
/// 因此这里不做 full-frame diff、也不发 `BlockDiscard`：增量直接透传为
/// `BlockDelta`，与官方 chunk 语义一致（旧实现把增量当累计文本，会重复输出）。

///|
/// 关闭仍打开的块（文本 / 思考），返回重置后的状态。
fn close_gemini_blocks(
  events : Array[@lux.LucentStreamEvent],
  open_text : Int?,
  open_thinking : Int?,
) -> (Int?, Int?) {
  match open_text {
    Some(idx) => events.push(BlockEnd(idx))
    None => ()
  }
  match open_thinking {
    Some(idx) => events.push(BlockEnd(idx))
    None => ()
  }
  (None, None)
}

///|
pub fn gemini_sse_to_events(
  sse_str : String,
) -> Result[@lux.ConversionResult[Array[@lux.LucentStreamEvent]], String] {
  let events : Array[@lux.LucentStreamEvent] = []
  // Gemini 流式用单 \n 分隔消息（非标准 SSE），归一化为 \n\n
  // 先将 \n\n 压为 \n，再将 \n 展开为 \n\n，保证每个 data: 行独占一个消息块。
  // 必须 replace_all：String::replace 只替换首次出现，用 replace 会让第 2 帧
  // 起与后续帧并成一块（多帧 JSON 拼在一起 → 解析失败 → 丢帧）。
  let normalized = sse_str
    .replace_all(old="\r\n", new="\n")
    .replace_all(old="\n\n", new="\n")
    .replace_all(old="\n", new="\n\n")
  let messages = @internal.parse_sse_messages(normalized)
  // functionCall 序号：与 request_decode/response 的 fc_<name>_<n> 规则保持一致
  // （按函数名独立计数），避免与块序号混用导致跨帧配对错位（标准 §10.1）
  let call_seq : Map[String, Int] = Map([])
  let mut next_index = 0
  let mut open_text : Int? = None
  let mut open_thinking : Int? = None
  let mut done_emitted = false
  let mut i = 0
  while i < messages.length() {
    let jv = match @internal.parse_sse_frame(messages[i].data) {
      Some(v) => v
      None => {
        i = i + 1
        continue
      }
    }
    match @internal.field_arr(jv, "candidates") {
      Some(cands) =>
        if cands.length() > 0 {
          match @internal.obj_get(cands[0], "content") {
            Some(content) =>
              match @internal.field_arr(content, "parts") {
                Some(parts) => {
                  let mut j = 0
                  while j < parts.length() {
                    let part = parts[j]
                    let has_thought = match @internal.obj_get(part, "thought") {
                      Some(True) => true
                      Some(String(_)) => true
                      _ => false
                    }
                    let text = @internal.field_str(part, "text")
                    match text {
                      Some(t) =>
                        if has_thought {
                          // thought part → 独立 Thinking 块（增量语义）
                          match open_text {
                            Some(idx) => {
                              events.push(BlockEnd(idx))
                              open_text = None
                            }
                            None => ()
                          }
                          let idx = match open_thinking {
                            Some(idx) => idx
                            None => {
                              let idx = next_index
                              next_index = next_index + 1
                              open_thinking = Some(idx)
                              events.push(BlockStart(idx, Thinking))
                              idx
                            }
                          }
                          events.push(
                            BlockDelta(
                              idx,
                              @lux.LucentBlockDelta::thinking_delta(t),
                            ),
                          )
                        } else {
                          match open_thinking {
                            Some(idx) => {
                              events.push(BlockEnd(idx))
                              open_thinking = None
                            }
                            None => ()
                          }
                          let idx = match open_text {
                            Some(idx) => idx
                            None => {
                              let idx = next_index
                              next_index = next_index + 1
                              open_text = Some(idx)
                              events.push(BlockStart(idx, Text))
                              idx
                            }
                          }
                          events.push(
                            BlockDelta(
                              idx,
                              @lux.LucentBlockDelta::text_delta(t),
                            ),
                          )
                        }
                      None => ()
                    }
                    // thoughtSignature：跨轮思考延续凭证（无 text 的帧也会带）
                    match @internal.field_str(part, "thoughtSignature") {
                      Some(sig) => {
                        let (t2, th2) = close_gemini_blocks(
                          events, open_text, open_thinking,
                        )
                        open_text = t2
                        open_thinking = th2
                        let idx = next_index
                        next_index = next_index + 1
                        events.push(BlockStart(idx, Thinking))
                        events.push(
                          BlockDelta(
                            idx,
                            @lux.LucentBlockDelta::signature_delta(sig),
                          ),
                        )
                        events.push(BlockEnd(idx))
                      }
                      None => ()
                    }
                    // functionCall（官方为整块到达，非增量）
                    match @internal.obj_get(part, "functionCall") {
                      Some(fc) => {
                        let name = @internal.field_str(fc, "name").unwrap_or("")
                        let args = match @internal.obj_get(fc, "args") {
                          Some(a) => a.stringify()
                          None => "{}"
                        }
                        // 显式 id 优先（跨协议精确配对），否则按 fc_<name>_<seq> 合成
                        let id = match @internal.field_str(fc, "id") {
                          Some(v) =>
                            if v == "" {
                              gemini_synthetic_call_id(call_seq, name)
                            } else {
                              v
                            }
                          None => gemini_synthetic_call_id(call_seq, name)
                        }
                        let (t2, th2) = close_gemini_blocks(
                          events, open_text, open_thinking,
                        )
                        open_text = t2
                        open_thinking = th2
                        let idx = next_index
                        next_index = next_index + 1
                        events.push(
                          BlockStart(
                            idx,
                            @lux.LucentBlockType::tool_call(id, name),
                          ),
                        )
                        events.push(
                          BlockDelta(
                            idx,
                            @lux.LucentBlockDelta::tool_arguments_delta(args),
                          ),
                        )
                        events.push(BlockEnd(idx))
                      }
                      None => ()
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
              let (t2, th2) = close_gemini_blocks(
                events, open_text, open_thinking,
              )
              open_text = t2
              open_thinking = th2
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
  let (_, _) = close_gemini_blocks(events, open_text, open_thinking)
  // 兜底：末帧既无 finishReason 也无 usageMetadata 时（异常流）仍发 Done，避免消费者挂起
  if !done_emitted {
    events.push(Done)
  }
  Ok(@lux.ConversionResult::new(events))
}

///|
/// 生成 `fc_<name>_<seq>` 合成调用 ID（与 request_decode / response 解码规则一致）。
fn gemini_synthetic_call_id(
  call_seq : Map[String, Int],
  name : String,
) -> String {
  let seq = match call_seq.get(name) {
    Some(v) => v
    None => 0
  }
  call_seq[name] = seq + 1
  "fc_" + name + "_" + seq.to_string()
}
