///|
/// ═══ 功能组：pipeline（编码解码编排）═══
/// 本文件：Prism 门面内部方法（encode/decode 样板）。
/// 通用 source→target 管线见 codec_pipeline.mbt。

///|
/// SDK request/response/stream conversion pipeline (internal implementation)

///|
/// 从文本和选项构建 LucentRequest（消除 3 处重复的 Context→model→request 样板）
fn build_request_from_text(
  text : String,
  opts : PrismOptions,
) -> @lux.LucentRequest {
  let ctx = Context::new().add_user(text)
  let model = opts.model.unwrap_or(DEFAULT_MODEL)
  context_to_lux_request(ctx, model, opts)
}

///|
/// 将提供商 JSON 解码为 LucentResponse（基于 ProviderRegistration 注册表）
fn Prism::decode_to_lux(
  self : Prism,
  json_str : String,
) -> Result[@lux.LucentResponse, String] {
  match match_provider_name(self.provider) {
    Some(reg) =>
      match (reg.response_decode)(json_str) {
        Ok(cr) => Ok(cr.value())
        Err(e) => Err(e)
      }
    None => Err("unknown provider: " + self.provider)
  }
}

///|
/// 编码 LucentRequest 为提供商 JSON（基于 ProviderRegistration 注册表）
fn Prism::encode_lux_request(
  self : Prism,
  req : @lux.LucentRequest,
) -> Result[String, String] {
  match match_provider_name(self.provider) {
    Some(reg) =>
      match (reg.request_encode)(req) {
        Ok(cr) => Ok(cr.value())
        Err(e) => Err(e)
      }
    None => Err("unknown provider: " + self.provider)
  }
}

///|
/// 将提供商 SSE 解码为原始 LucentStreamEvent（基于注册表）
fn decode_sse_inner(
  provider : String,
  sse_str : String,
) -> Result[Array[@lux.LucentStreamEvent], String] {
  match match_provider_name(provider) {
    Some(reg) =>
      match (reg.events_decode)(sse_str) {
        Ok(cr) => Ok(cr.value())
        Err(e) => Err(e)
      }
    None => Err("unknown provider: " + provider)
  }
}

///|
/// 发射一个完整 ToolCall PrismEvent（工具块冲刷共用）
fn push_tool_call_event(
  result : Array[PrismEvent],
  id : String,
  name : String,
  arguments_json : String,
) -> Unit {
  result.push(ToolCall({ id, name, arguments_json, }))
}

///|
/// 将 LucentStreamEvent 数组转为 PrismEvent 数组（SDK 内部）
///
/// 工具调用累积状态机（覆盖三家 provider 的流形态）：
/// - openai/messages：BlockStart(ToolCall(id,name)) → BlockDelta(ToolArgumentsDelta)
///   → BlockEnd(idx)
/// - responses：ItemStart(idx, ToolCall 骨架) → BlockDelta(ToolArgumentsDelta)
///   → BlockEnd(idx)（两者同一 output_index 空间）
/// 块结束（或流尾）时发射完整 ToolCall 事件，含累积后的 arguments_json。
/// 修复记录：此前只消费 ItemStart，openai/messages 的 BlockStart/BlockDelta
/// 路径无人处理——默认 provider 的流式 tool call 被完全静默丢弃。
fn lucent_events_to_prism(
  events : Array[@lux.LucentStreamEvent],
) -> Array[PrismEvent] {
  let result : Array[PrismEvent] = []
  let mut has_finish = false
  // 当前 tool 块累积状态
  let mut tool_active = false
  let mut tool_idx : Int = -1
  let mut tool_id : String = ""
  let mut tool_name : String = ""
  let mut tool_args : String = ""
  for ev in events {
    if has_finish {
      break
    }
    match ev {
      BlockDelta(_, TextDelta(s)) => result.push(TextDelta(s))
      BlockStart(idx, ToolCall(id, name)) => {
        if tool_active {
          push_tool_call_event(result, tool_id, tool_name, tool_args)
        }
        tool_active = true
        tool_idx = idx
        tool_id = id
        tool_name = name
        tool_args = ""
      }
      BlockStart(_, _) =>
        // 非 tool 块开始：冲刷未闭合 tool 块
        if tool_active {
          push_tool_call_event(result, tool_id, tool_name, tool_args)
          tool_active = false
          tool_args = ""
        }
      BlockDelta(idx, ToolArgumentsDelta(s)) =>
        if tool_active && idx == tool_idx {
          tool_args = tool_args + s
        }
      BlockEnd(idx) =>
        if tool_active && idx == tool_idx {
          push_tool_call_event(result, tool_id, tool_name, tool_args)
          tool_active = false
          tool_args = ""
        }
      BlockDiscard(idx) =>
        // Gemini 全量帧覆盖：丢弃该块（不发射 ToolCall）
        if tool_active && idx == tool_idx {
          tool_active = false
          tool_args = ""
        }
      ItemStart(idx, ToolCall(tu)) => {
        // responses 路径：骨架开启 tool 块（arguments 可能已在骨架中）
        if tool_active {
          push_tool_call_event(result, tool_id, tool_name, tool_args)
        }
        tool_active = true
        tool_idx = idx
        tool_id = tu.id
        tool_name = tu.name
        tool_args = tu.arguments_json
      }
      ItemStart(_, ToolResult(tr)) =>
        result.push(
          ToolResult({
            tool_use_id: tr.tool_use_id,
            content: @lux.lucent_content_to_text(tr.content),
            is_error: tr.is_error,
          }),
        )
      ItemStart(_, _) =>
        // 新 item 开始：冲刷未闭合 tool 块
        if tool_active {
          push_tool_call_event(result, tool_id, tool_name, tool_args)
          tool_active = false
          tool_args = ""
        }
      BlockDelta(_, ThinkingDelta(s)) =>
        result.push(Thinking({ text: s, signature: None, redacted: false, }))
      Finish(fr) => {
        let pfr = match fr {
          Stop => Stop
          Length => Length
          ToolCalls => ToolCalls
          ContentFilter => ContentFilter
          _ => Error
        }
        result.push(Finish(pfr))
        has_finish = true
      }
      _ => ()
    }
  }
  // 流尾冲刷：未闭合的 tool 块也要发射，避免静默丢失
  if tool_active {
    push_tool_call_event(result, tool_id, tool_name, tool_args)
  }
  result
}
