///|
/// === 流解码：OpenAI Chat SSE → LucentStreamEvent[] ===

///|
/// 5. openai_sse_to_events — 流解码
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
      if current_tool_block >= 0 {
        events.push(BlockEnd(current_tool_block))
        current_tool_block = -1
      }
      events.push(Done)
      i = i + 1
      continue
    }
    // 清理心跳、截断检测、转义清理
    let payload = @internal.sanitize_json_escapes(
      @internal.clean_sse_heartbeat(payload_raw),
    )
    if @internal.is_json_truncated(payload) {
      i = i + 1
      continue
    }
    let jv = @json.parse(payload) catch {
      _ => {
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
        events.push(Usage(@lux.LucentUsage::new(pt, ct, tt)))
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
                Some("assistant") =>
                  events.push(
                    ConversationStart(
                      @lux.LucentConversationMeta::new(None, None, None),
                    ),
                  )
                _ => ()
              }
              // content
              match @internal.field_str(delta, "content") {
                Some(s) => {
                  if !text_block_open {
                    events.push(BlockStart(0, Text))
                    text_block_open = true
                  }
                  events.push(
                    BlockDelta(0, @lux.LucentBlockDelta::text_delta(s)),
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

///|
/// === 流编码：LucentStreamEvent[] → OpenAI Chat SSE ===

///|
/// 6. lux_events_to_openai_sse — 流编码
///
/// 把 Lux 事件流编码为 OpenAI Chat SSE 格式：
/// - ConversationStart → data: {"choices":[{"delta":{"role":"assistant"}}]}
/// - BlockDelta(TextDelta) → data: {"choices":[{"delta":{"content":"..."}]}]}
/// - BlockDelta(ToolArgumentsDelta) → data: {"choices":[{"delta":{"tool_calls":[{"index":N,"function":{"arguments":"..."}}]}]}
/// - BlockStart(ToolCall(id,name)) → data: {"choices":[{"delta":{"tool_calls":[{"index":N,"id":"...","type":"function","function":{"name":"..."}}]}]}
/// - Finish(reason) → data: {"choices":[{"delta":{},"finish_reason":"..."}]}
/// - Usage(u) → data: {"usage":{...}}
/// - Done → data: [DONE]

///|
/// 每个 chunk 的公共前缀：id / object / created / model
fn chunk_prefix(id : String, model : String, created : Int) -> String {
  "data: {\"id\":\"" +
  @internal.json_escape(id) +
  "\",\"object\":\"chat.completion.chunk\",\"created\":" +
  created.to_string() +
  ",\"model\":\"" +
  @internal.json_escape(model) +
  "\","
}

///|
pub fn lux_events_to_openai_sse(
  events : Array[@lux.LucentStreamEvent],
) -> Result[@lux.ConversionResult[String], String] {
  let out : Array[String] = []
  let mut i = 0
  // 从 ConversationStart 提取，注入每个 chunk
  let mut chat_id = ""
  let mut chat_model = ""
  let mut chat_created : Int = 0
  while i < events.length() {
    match events[i] {
      ConversationStart(meta) => {
        chat_id = meta.id.unwrap_or("chatcmpl-0")
        chat_model = meta.model.unwrap_or("")
        chat_created = meta.created_at.unwrap_or(0)
        out.push(
          chunk_prefix(chat_id, chat_model, chat_created) +
          "\"choices\":[{\"delta\":{\"role\":\"assistant\"}}]}",
        )
      }
      ItemStart(_, _) | ItemEnd(_) | BlockDiscard(_) | Annotations(_, _) => ()
      // 块边界在 OpenAI Chat 流中不显式（无 BlockStart/BlockEnd 对应）
      // 但 ToolCall 的 BlockStart 携带 id/name，需编码为 tool_calls 首帧
      BlockStart(idx, bt) =>
        match bt {
          ToolCall(id, name) =>
            out.push(
              chunk_prefix(chat_id, chat_model, chat_created) +
              "\"choices\":[{\"delta\":{\"tool_calls\":[" +
              "{\"index\":" +
              idx.to_string() +
              ",\"id\":\"" +
              @internal.json_escape(id) +
              "\",\"type\":\"function\",\"function\":{\"name\":\"" +
              @internal.json_escape(name) +
              "\"}}]}}]}",
            )
          _ => ()
        }
      BlockEnd(_) => ()
      BlockDelta(idx, delta) =>
        match delta {
          TextDelta(s) =>
            out.push(
              chunk_prefix(chat_id, chat_model, chat_created) +
              "\"choices\":[{\"delta\":{\"content\":\"" +
              @internal.json_escape(s) +
              "\"}}]}",
            )
          ToolArgumentsDelta(s) =>
            out.push(
              chunk_prefix(chat_id, chat_model, chat_created) +
              "\"choices\":[{\"delta\":{\"tool_calls\":[" +
              "{\"index\":" +
              idx.to_string() +
              ",\"function\":{\"arguments\":\"" +
              @internal.json_escape(s) +
              "\"}}]}}]}",
            )
          ThinkingDelta(_) | SignatureDelta(_) | RefusalDelta(_) => ()
          // 标准 OpenAI Chat 流无原生 thinking/refusal 增量（vLLM 扩展由 openai_vllm 子协议承载）
          // OpenAI Chat 流无原生 signature/refusal 增量，编码时忽略
          NativeDelta(_, _) => ()
        }
      Finish(fr) =>
        out.push(
          chunk_prefix(chat_id, chat_model, chat_created) +
          "\"choices\":[{\"delta\":{},\"finish_reason\":\"" +
          @internal.json_escape(fr.to_string()) +
          "\"}]}",
        )
      Usage(u) =>
        // 附带空 choices 保证 Chat Completions 格式合法
        out.push(
          chunk_prefix(chat_id, chat_model, chat_created) +
          "\"choices\":[],\"usage\":{\"prompt_tokens\":" +
          u.prompt_tokens.to_string() +
          ",\"completion_tokens\":" +
          u.completion_tokens.to_string() +
          ",\"total_tokens\":" +
          u.total_tokens.to_string() +
          "}}",
        )
      Error(e) =>
        out.push(
          chunk_prefix(chat_id, chat_model, chat_created) +
          "\"error\":{\"message\":\"" +
          @internal.json_escape(e.message) +
          "\"}}",
        )
      Done => out.push("data: [DONE]")
    }
    i = i + 1
  }
  Ok(@lux.ConversionResult::new(out.join("\n\n") + "\n\n"))
}
