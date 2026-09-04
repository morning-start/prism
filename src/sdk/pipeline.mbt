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
/// 将 LucentStreamEvent 数组转为 PrismEvent 数组（SDK 内部）
fn lucent_events_to_prism(
  events : Array[@lux.LucentStreamEvent],
) -> Array[PrismEvent] {
  let result : Array[PrismEvent] = []
  let mut has_finish = false
  for ev in events {
    if has_finish {
      break
    }
    match ev {
      BlockDelta(_, TextDelta(s)) => result.push(TextDelta(s))
      BlockDelta(_, ToolArgumentsDelta(_s)) =>
        // L2: 工具参数增量，当前简化
        ()
      ItemStart(_, ToolCall(tu)) =>
        result.push(
          ToolCall({
            id: tu.id,
            name: tu.name,
            arguments_json: tu.arguments_json,
          }),
        )
      ItemStart(_, ToolResult(tr)) =>
        result.push(
          ToolResult({
            tool_use_id: tr.tool_use_id,
            content: @lux.lucent_content_to_text(tr.content),
            is_error: tr.is_error,
          }),
        )
      BlockStart(_, Thinking) => ()
      BlockDelta(_, ThinkingDelta(s)) =>
        result.push(Thinking({ text: s, signature: None, redacted: false }))
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
  result
}
