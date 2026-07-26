///|
/// Prism — SDK 主入口
///
/// 使用方式（L1 应用开发者）：
/// ```
/// let prism = Prism::new().with_provider("openai")
/// let json = prism.encode_request("Hello", PrismOptions::default())
/// // json 是提供商 JSON 请求体，Host 发送 HTTP 请求
/// // Host 收到响应后调用 prism.decode_response(json)
/// ```

///|
/// PrismOptions — SDK 请求选项
pub struct PrismOptions {
  model : String?
  temperature : Double?
  max_tokens : Int?
  store : Bool?
  extras : Map[String, Json]?
}

///|
pub fn PrismOptions::default() -> PrismOptions {
  { model: None, temperature: None, max_tokens: None, store: None, extras: None }
}

///|
pub fn PrismOptions::new(
  model : String?,
  temperature : Double?,
  max_tokens : Int?,
  store : Bool?,
  extras : Map[String, Json]?,
) -> PrismOptions {
  { model, temperature, max_tokens, store, extras }
}

///|
/// Prism — 主实例
pub struct Prism {
  provider : String
  api_key : String?
  base_url : String?
}

///|
pub fn Prism::new() -> Prism {
  { provider: "openai", api_key: None, base_url: None }
}

///|
/// 设置 provider 名称
pub fn Prism::with_provider(self : Prism, name : String) -> Prism {
  { ..self, provider: name }
}

///|
/// 设置 API Key
pub fn Prism::with_api_key(self : Prism, key : String) -> Prism {
  { ..self, api_key: Some(key) }
}

///|
/// 设置自定义端点
pub fn Prism::with_base_url(self : Prism, url : String) -> Prism {
  { ..self, base_url: Some(url) }
}

///|
/// === 请求编码 / 响应解码 ===

///|
/// 将文本请求编码为提供商 JSON（L1：文本进，JSON 出）
pub fn Prism::encode_request(
  self : Prism,
  text : String,
  opts : PrismOptions,
) -> Result[String, String] {
  let ctx = Context::new()
  let ctx = ctx.add_user(text)
  let model = match opts.model {
    Some(m) => m
    None => "gpt-4o"
  }
  let req = context_to_lux_request(ctx, model, opts)
  self.encode_lux_request(req)
}

///|
/// 将提供商 JSON 响应解码为纯文本（L1：JSON 进，文本出）
pub fn Prism::decode_response(
  self : Prism,
  json_str : String,
) -> Result[String, String] {
  let provider = self.provider
  match self.decode_to_lux(json_str) {
    Ok(resp) => Ok(resp.get_text())
    Err(e) => Err(e)
  }
}

///|
/// 将提供商 JSON 解码为 LucentResponse（内部使用）
fn decode_to_lux(self : Prism, json_str : String) -> Result[@lux.LucentResponse, String] {
  let provider = self.provider
  if provider == "openai" || provider == "openai-responses" {
    @openai_responses.openai_responses_to_lux_response(json_str)
  } else if provider == "openai-chat" {
    @openai_chat.openai_chat_to_lux_response(json_str)
  } else if provider == "anthropic" {
    @anthropic.anthropic_to_lux_response(json_str)
  } else if provider == "gemini" || provider == "google" {
    @gemini.gemini_to_lux_response(json_str)
  } else {
    Err("unknown provider: " + provider)
  }
}

///|
/// 编码 LucentRequest 为提供商 JSON
fn encode_lux_request(
  self : Prism,
  req : @lux.LucentRequest,
) -> Result[String, String] {
  let provider = self.provider
  if provider == "openai" || provider == "openai-responses" {
    @openai_responses.lux_request_to_openai_responses(req)
  } else if provider == "openai-chat" {
    @openai_chat.lux_request_to_openai_chat(req)
  } else if provider == "anthropic" {
    @anthropic.lux_request_to_anthropic(req)
  } else if provider == "gemini" || provider == "google" {
    @gemini.lux_request_to_gemini(req)
  } else {
    Err("unknown provider: " + provider)
  }
}

///|
/// === 流式接口 ===

///|
/// 将文本请求编码为流式提供商 JSON
pub fn Prism::encode_stream_request(
  self : Prism,
  text : String,
  opts : PrismOptions,
) -> Result[String, String] {
  let ctx = Context::new()
  let ctx = ctx.add_user(text)
  let model = match opts.model {
    Some(m) => m
    None => "gpt-4o"
  }
  let mut req = context_to_lux_request(ctx, model, opts)
  req = @lux.LucentRequest::with_stream(req, true)
  self.encode_lux_request(req)
}

///|
/// 将提供商 SSE 事件解码为 PrismEvent 数组
pub fn Prism::decode_sse(
  self : Prism,
  sse_str : String,
) -> Result[Array[PrismEvent], String] {
  let provider = self.provider
  match decode_sse_inner(provider, sse_str) {
    Ok(raw_events) => Ok(lucent_events_to_prism(raw_events))
    Err(e) => Err(e)
  }
}

///|
/// 将提供商 SSE 解码为原始 LucentStreamEvent（内部使用）
fn decode_sse_inner(provider : String, sse_str : String) -> Result[Array[@lux.LucentStreamEvent], String] {
  if provider == "openai" || provider == "openai-responses" {
    @openai_responses.openai_responses_sse_to_events(sse_str)
  } else if provider == "openai-chat" {
    @openai_chat.openai_chat_sse_to_events(sse_str)
  } else if provider == "anthropic" {
    @anthropic.anthropic_sse_to_events(sse_str)
  } else if provider == "gemini" || provider == "google" {
    @gemini.gemini_sse_to_events(sse_str)
  } else {
    Err("unknown provider: " + provider)
  }
}

///|
/// 将 LucentStreamEvent 数组转为 PrismEvent 数组（SDK 内部）
fn lucent_events_to_prism(events : Array[@lux.LucentStreamEvent]) -> Array[PrismEvent] {
  let result : Array[PrismEvent] = []
  let mut has_finish = false
  for ev in events {
    if has_finish { break }
    match ev {
      BlockDelta(_, TextDelta(s)) => result.push(TextDelta(s))
      BlockDelta(_, ToolArgumentsDelta(_s)) => {
        // L2: 工具参数增量，当前简化
        ()
      }
      ItemStart(_, ToolCall(tu)) => {
        result.push(PrismEvent::ToolCall({
          id: tu.id,
          name: tu.name,
          arguments_json: tu.arguments_json,
        }))
      }
      ItemStart(_, ToolResult(tr)) => {
        result.push(PrismEvent::ToolResult({
          tool_use_id: tr.tool_use_id,
          content: @lux.lucent_content_to_text(tr.content),
          is_error: tr.is_error,
        }))
      }
      BlockStart(_, Thinking) => {
        result.push(PrismEvent::Thinking({
          text: "",
          signature: None,
          redacted: false,
        }))
      }
      BlockDelta(_, ThinkingDelta(s)) => {
        result.push(TextDelta(s)) // thinking 文本流式输出
      }
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

///|
/// === 能力查询 ===

///|
/// 查询指定 provider 的能力声明
pub fn Prism::capability(
  self : Prism,
  provider_name : String,
) -> @lux.ProviderCapability? {
  if provider_name == "openai" || provider_name == "openai-responses" {
    Some(@openai_responses.capability())
  } else if provider_name == "openai-chat" {
    Some(@openai_chat.capability())
  } else if provider_name == "anthropic" {
    Some(@anthropic.capability())
  } else if provider_name == "gemini" || provider_name == "google" {
    Some(@gemini.capability())
  } else {
    None
  }
}
