///|
/// OpenAI Chat — 流解码（SSE → LucentStreamEvent[]）
///
/// OpenAI Chat SSE 格式：
///   data: {"choices":[{"delta":{"role":"assistant"|"content":"..."|"tool_calls":[...]},"finish_reason":null|"stop"|...}]}
///   data: [DONE]
///
/// 块生命周期合成规则（OpenAI 无显式边界，需凭空造）：
/// - delta.role → ConversationStart + Role 隐式
/// - delta.content → BlockStart(0,Text)（首次）+ BlockDelta(TextDelta) + 隐式 BlockEnd
/// - delta.tool_calls[i].index 切换 → 切换块索引，BlockEnd 旧块 + BlockStart 新块
/// - finish_reason → Finish
/// - usage → Usage（最后一帧）
/// - [DONE] → Done
pub fn openai_sse_to_events(
  sse_str : String,
) -> Result[@lux.ConversionResult[Array[@lux.LucentStreamEvent]], String] {
  let events : Array[@lux.LucentStreamEvent] = []
  let messages = @internal.parse_sse_messages(sse_str)
  let mut text_block_open = false // 是否有未闭合的文本块
  let mut thinking_block_open = false // 是否有未闭合的 thinking 块
  let thinking_block_idx = 1 // thinking 块使用固定索引 1，避免与 text 块（索引 0）冲突
  let mut current_tool_block = -1 // 当前工具调用块索引（-1 表示无）
  let mut i = 0
  while i < messages.length() {
    let payload_raw = messages[i].data.trim().to_owned()
    // [DONE] 终止信号
    if payload_raw == "[DONE]" {
      if text_block_open {
        events.push(BlockEnd(0))
        text_block_open = false
      }
      if thinking_block_open {
        events.push(BlockEnd(thinking_block_idx))
        thinking_block_open = false
      }
      if current_tool_block >= 0 {
        events.push(BlockEnd(current_tool_block))
        current_tool_block = -1
      }
      events.push(Done)
      i = i + 1
      continue
    }
    let jv = match @internal.parse_sse_frame(messages[i].data) {
      Some(v) => v
      None => {
        i = i + 1
        continue
      }
    }
    // usage 帧（choices 空的最后一帧）
    match @internal.obj_get(jv, "usage") {
      Some(u) => {
        let (pt, ct, tt) = @internal.parse_usage_json(
          u,
          "prompt_tokens",
          "completion_tokens",
          Some("total_tokens"),
        )
        let reasoning = @internal.parse_reasoning_tokens(u, [
          "completion_tokens_details",
        ])
        let cached = @internal.parse_cached_tokens(u, ["prompt_tokens_details"])
        events.push(
          Usage(@lux.LucentUsage::full(pt, ct, tt, reasoning, cached, None)),
        )
      }
      None => ()
    }
    // choices[0].delta
    match @internal.field_arr(jv, "choices") {
      Some(choices) =>
        if choices.length() > 0 {
          match @internal.obj_get(choices[0], "delta") {
            Some(delta) => {
              // role
              match @internal.field_str(delta, "role") {
                Some("assistant") => {
                  // 从 chunk 顶层提取真实 id/model/created，供 response.created 使用
                  let chunk_id = @internal.field_str(jv, "id")
                  let chunk_model = @internal.field_str(jv, "model")
                  let chunk_created = @internal.field_int(jv, "created")
                  events.push(
                    ConversationStart(
                      @lux.LucentConversationMeta::new_full(
                        chunk_id,
                        chunk_model,
                        None,
                        chunk_created,
                        None,
                      ),
                    ),
                  )
                }
                _ => ()
              }
              // content（空字符串不触发文本块：上游首个 chunk 常为 role + content:""，
              // 若触发会导致 message item 先于 reasoning 创建，思考块被渲染到答案下方）
              match @internal.field_str(delta, "content") {
                Some(s) if s.length() > 0 => {
                  if !text_block_open {
                    events.push(BlockStart(0, Text))
                    text_block_open = true
                  }
                  events.push(
                    BlockDelta(0, @lux.LucentBlockDelta::text_delta(s)),
                  )
                }
                _ => ()
              }
              // reasoning_content（DeepSeek/vLLM thinking 内容）；
              // delta.reasoning（OpenRouter 等流式标准字段）与 message.reasoning 对称
              let reasoning_text = match
                @internal.field_str(delta, "reasoning_content") {
                Some(s) => Some(s)
                None => @internal.field_str(delta, "reasoning")
              }
              match reasoning_text {
                Some(s) => {
                  if !thinking_block_open {
                    events.push(BlockStart(thinking_block_idx, Thinking))
                    thinking_block_open = true
                  }
                  events.push(
                    BlockDelta(
                      thinking_block_idx,
                      @lux.LucentBlockDelta::thinking_delta(s),
                    ),
                  )
                }
                None => ()
              }
              // tool_calls
              match @internal.field_arr(delta, "tool_calls") {
                Some(tcs) => {
                  let mut k = 0
                  while k < tcs.length() {
                    let tc = tcs[k]
                    let idx = @internal.field_int(tc, "index").unwrap_or(0)
                    if current_tool_block >= 0 && current_tool_block != idx {
                      events.push(BlockEnd(current_tool_block))
                    }
                    if current_tool_block != idx {
                      let id = @internal.field_str(tc, "id").unwrap_or("")
                      let name = match @internal.obj_get(tc, "function") {
                        Some(fn_obj) =>
                          @internal.field_str(fn_obj, "name").unwrap_or("")
                        None => ""
                      }
                      events.push(
                        BlockStart(
                          idx,
                          @lux.LucentBlockType::tool_call(id, name),
                        ),
                      )
                      current_tool_block = idx
                    }
                    match @internal.obj_get(tc, "function") {
                      Some(fn_obj) =>
                        match @internal.field_str(fn_obj, "arguments") {
                          Some(args) =>
                            events.push(
                              BlockDelta(
                                idx,
                                @lux.LucentBlockDelta::tool_arguments_delta(
                                  args,
                                ),
                              ),
                            )
                          None => ()
                        }
                      None => ()
                    }
                    k = k + 1
                  }
                }
                None => ()
              }
            }
            None => ()
          }
          // finish_reason
          match @internal.field_str(choices[0], "finish_reason") {
            Some(fr) => {
              if text_block_open {
                events.push(BlockEnd(0))
                text_block_open = false
              }
              if thinking_block_open {
                events.push(BlockEnd(thinking_block_idx))
                thinking_block_open = false
              }
              if current_tool_block >= 0 {
                events.push(BlockEnd(current_tool_block))
                current_tool_block = -1
              }
              events.push(Finish(@lux.LucentFinishReason::from_string(fr)))
            }
            None => ()
          }
        }
      None => ()
    }
    i = i + 1
  }
  Ok(@lux.ConversionResult::new(events))
}
