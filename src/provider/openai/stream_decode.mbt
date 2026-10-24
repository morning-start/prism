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

///|
/// OpenAI Chat 流解码的跨帧状态（P1 修复）。
///
/// 块生命周期（文本块是否打开、thinking 块是否打开、当前工具块索引）是
/// **跨帧**的：OpenAI 无显式块边界，工具索引切换时必须由解码器先补
/// `BlockEnd(旧)` 再发 `BlockStart(新)`。此前这些状态是解码函数的局部变量，
/// 逐帧调用时每帧重建 → 切换不再补 BlockEnd，改由下游规整器在 Finish 处
/// 逆序补闭合 → `content_block_stop` 顺序与整批不一致。会话化后两条路径
/// 共享同一份状态机。
pub struct OpenaiStreamState {
  mut text_block_open : Bool
  mut thinking_block_open : Bool
  mut current_tool_block : Int32
}

///|
pub fn OpenaiStreamState::new() -> OpenaiStreamState {
  {
    text_block_open: false,
    thinking_block_open: false,
    current_tool_block: -1,
  }
}

///|
pub fn openai_sse_to_events(
  sse_str : String,
) -> Result[@lux.ConversionResult[Array[@lux.LucentStreamEvent]], String] {
  openai_decode_frames(sse_str, OpenaiStreamState::new())
}

///|
/// 解码一帧 SSE（复用会话内跨帧状态）
fn openai_decode_frames(
  sse_str : String,
  st : OpenaiStreamState,
) -> Result[@lux.ConversionResult[Array[@lux.LucentStreamEvent]], String] {
  let events : Array[@lux.LucentStreamEvent] = []
  let messages = @internal.parse_sse_messages(sse_str)
  let mut text_block_open = st.text_block_open // 是否有未闭合的文本块
  let mut thinking_block_open = st.thinking_block_open // 是否有未闭合的 thinking 块
  let thinking_block_idx = 1 // thinking 块使用固定索引 1，避免与 text 块（索引 0）冲突
  let mut current_tool_block = st.current_tool_block // 当前工具调用块索引（-1 表示无）
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
    // 错误帧：官方错误帧不包 chunk 外壳（无 id / choices），
    // 形如 data: {"error":{"type":"rate_limit_error","message":"...","code":"429"}}
    // 此前 openai 源不识别该帧 → 整帧静默丢弃，流式错误链路断在解码侧
    // （encode 侧一直有 Error → error 帧的映射，响应侧 response.mbt 也解 error）。
    //
    // 必须先判字符串形态：`obj_get` 返回的是 error 键的值本身，字符串值若
    // 落进对象分支，field_str 取不到 message/type → 退化成 "unknown error"，
    // 真正的错误文本被丢掉。顺序：String → 对象 → 缺失。
    match @internal.obj_get(jv, "error") {
      Some(String(err_str)) =>
        events.push(Error(@lux.LucentError::simple(err_str)))
      Some(err_obj) => {
        let err_type = @internal.field_str(err_obj, "type")
        let err_code = @internal.field_str(err_obj, "code")
        let msg = match @internal.field_str(err_obj, "message") {
          Some(m) => m
          None =>
            match err_type {
              Some(t) => t
              None => "unknown error"
            }
        }
        let kind = @lux.LucentErrorKind::from_string(err_type.unwrap_or(""))
        let code = match err_code {
          Some(c) => c
          None =>
            match err_type {
              Some(t) => t
              None => ""
            }
        }
        events.push(Error(@lux.LucentError::new(kind, msg, Some(code))))
      }
      None => ()
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
                  // 首帧 chunk 顶层的非建模字段（system_fingerprint / service_tier 等）
                  // 进 ConversationStart.extra —— 非流式响应路径同样保留这些字段
                  // （见 openai/response.mbt 的 payload_fields），流式此前一律填 None，
                  // 造成「流式丢、非流式留」的不一致。
                  let extra = @internal.build_meta_extra(jv, [
                    "id", "model", "created", "object", "choices", "usage",
                  ])
                  events.push(
                    ConversationStart(
                      @lux.LucentConversationMeta::new_full(
                        chunk_id,
                        chunk_model,
                        None,
                        chunk_created,
                        extra,
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
                    // 不变量：同一 block_index 任一时刻至多一个打开的块。先闭合
                    // 占用索引 0 的工具块（tool_calls[i].index 与 text 块分区重叠，
                    // OpenAI 的 tool index 从 0 起）。若直接再发一个 BlockStart(0)，
                    // 下游 EventNormalizer 会按索引去重丢弃，混合流（先文本后工具
                    // 调用）的工具调用将整体丢失。
                    if current_tool_block == 0 {
                      events.push(BlockEnd(0))
                      current_tool_block = -1
                    }
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
                    // 同 text 块闭合逻辑：先闭合占用 thinking 索引 1 的工具块
                    // （第二个及以后的 tool_calls[i].index 可为 1）。
                    if current_tool_block == thinking_block_idx {
                      events.push(BlockEnd(thinking_block_idx))
                      current_tool_block = -1
                    }
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
                      // 同一索引每个时刻至多一个打开的块：先闭合占用该索引的
                      // text（idx 0）/ thinking（idx 1）块，否则下游按索引去重
                      // 会把本 BlockStart 当重复事件丢弃 → 工具调用丢失。
                      if idx == 0 && text_block_open {
                        events.push(BlockEnd(0))
                        text_block_open = false
                      }
                      if idx == thinking_block_idx && thinking_block_open {
                        events.push(BlockEnd(thinking_block_idx))
                        thinking_block_open = false
                      }
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
              events.push(
                Finish(@lux.LucentFinishReason::from_string(fr), None),
              )
            }
            None => ()
          }
        }
      None => ()
    }
    i = i + 1
  }
  // 跨帧状态写回会话
  st.text_block_open = text_block_open
  st.thinking_block_open = thinking_block_open
  st.current_tool_block = current_tool_block
  Ok(@lux.ConversionResult::new(events))
}

///|
/// 创建 openai 流解码会话（T5 增量转换入口，跨帧状态由会话持有）
///
/// `decode` 逐帧调用复用同一状态：工具索引切换时仍会先补 BlockEnd(旧)，
/// 使逐帧输出的块闭合顺序与整批一致。`finish` 闭合仍打开的块（截断流）。
pub fn openai_stream_decoder() -> @lux.LucentStreamDecoder {
  let st = OpenaiStreamState::new()
  @lux.LucentStreamDecoder::new(fn(frame) { openai_decode_frames(frame, st) }, fn() {
    let closing : Array[@lux.LucentStreamEvent] = []
    if st.text_block_open {
      closing.push(BlockEnd(0))
      st.text_block_open = false
    }
    if st.thinking_block_open {
      closing.push(BlockEnd(1))
      st.thinking_block_open = false
    }
    if st.current_tool_block >= 0 {
      closing.push(BlockEnd(st.current_tool_block))
      st.current_tool_block = -1
    }
    closing
  })
}
