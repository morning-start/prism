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
  {
    model: None,
    temperature: None,
    max_tokens: None,
    store: None,
    extras: None,
  }
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
  /// @deprecated 纯编解码 façade 不消费 API key；认证由 Host/Transport 层负责
  api_key : String?
  /// @deprecated 纯编解码 façade 不消费自定义端点；由 Host/Transport 层负责
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
  match self.decode_to_lux(json_str) {
    Ok(resp) => Ok(resp.get_text())
    Err(e) => Err(e)
  }
}

///|
/// 将提供商响应解码为完整 LucentResponse，并返回结构化校验诊断。
pub fn Prism::decode_response_with_diagnostics(
  self : Prism,
  json_str : String,
) -> Result[@lux.ConversionResult[@lux.LucentResponse], String] {
  match self.decode_to_lux(json_str) {
    Ok(resp) => {
      let result = @lux.ConversionResult::new(resp)
      match get_schema(self.provider) {
        Some(schema) => {
          let mut checked = result
          for error in schema.validate_response(resp) {
            checked = checked.with_diagnostic(
              @lux.ConversionDiagnostic::new(
                "response",
                @lux.Invalid,
                Some(error),
              ),
            )
          }
          Ok(checked)
        }
        None => Ok(result)
      }
    }
    Err(e) => Err(e)
  }
}

///|
/// 将文本请求编码为提供商 JSON，并返回结构化校验诊断。
pub fn Prism::encode_request_with_diagnostics(
  self : Prism,
  text : String,
  opts : PrismOptions,
) -> Result[@lux.ConversionResult[String], String] {
  let ctx = Context::new()
  let ctx = ctx.add_user(text)
  let model = match opts.model {
    Some(m) => m
    None => "gpt-4o"
  }
  let req = context_to_lux_request(ctx, model, opts)
  let mut result = @lux.ConversionResult::new(req)
  match get_schema(self.provider) {
    Some(schema) =>
      for error in schema.validate_request(req) {
        result = result.with_diagnostic(
          @lux.ConversionDiagnostic::new("request", @lux.Invalid, Some(error)),
        )
      }
    None => ()
  }
  match self.encode_lux_request(result.value()) {
    Ok(json) => {
      let mut encoded = @lux.ConversionResult::new(json)
      for diagnostic in result.diagnostics() {
        encoded = encoded.with_diagnostic(diagnostic)
      }
      Ok(encoded)
    }
    Err(e) => Err(e)
  }
}

///|
/// 将提供商 JSON 解码为 LucentResponse（基于 ProviderRegistration 注册表）
fn Prism::decode_to_lux(
  self : Prism,
  json_str : String,
) -> Result[@lux.LucentResponse, String] {
  let provider = self.provider
  match match_provider_name(provider) {
    Some(reg) =>
      match (reg.response_decode)(json_str) {
        Ok(cr) => Ok(cr.value())
        Err(e) => Err(e)
      }
    None => Err("unknown provider: " + provider)
  }
}

///|
/// 编码 LucentRequest 为提供商 JSON（基于 ProviderRegistration 注册表）
fn Prism::encode_lux_request(
  self : Prism,
  req : @lux.LucentRequest,
) -> Result[String, String] {
  let provider = self.provider
  match match_provider_name(provider) {
    Some(reg) =>
      match (reg.request_encode)(req) {
        Ok(cr) => Ok(cr.value())
        Err(e) => Err(e)
      }
    None => Err("unknown provider: " + provider)
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
/// L1 零配置：文本进、文本出（HTTP 由 Host 注入 send）
pub fn Prism::complete(
  self : Prism,
  text : String,
  opts : PrismOptions,
  send : (String) -> Result[String, String],
) -> Result[String, String] {
  match self.encode_request(text, opts) {
    Ok(json) =>
      match send(json) {
        Ok(resp_json) => self.decode_response(resp_json)
        Err(e) => Err(e)
      }
    Err(e) => Err(e)
  }
}

///|
/// L2 Agent 循环：流式请求 + 5 事件解码（HTTP 由 Host 注入 send）
pub fn Prism::stream(
  self : Prism,
  ctx : Context,
  send : (String) -> Result[String, String],
) -> Result[Array[PrismEvent], String] {
  let model = "gpt-4o"
  let mut req = context_to_lux_request(ctx, model, PrismOptions::default())
  req = @lux.LucentRequest::with_stream(req, true)
  match self.encode_lux_request(req) {
    Ok(json) =>
      match send(json) {
        Ok(sse) => self.decode_sse(sse)
        Err(e) => Err(e)
      }
    Err(e) => Err(e)
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

///|
/// === 能力查询 ===

///|
/// 查询指定 provider 的能力声明（基于注册表）
pub fn Prism::capability(
  _self : Prism,
  provider_name : String,
) -> @lux.ProviderCapability? {
  match match_provider_name(provider_name) {
    Some(reg) => Some(reg.capability)
    None => None
  }
}
