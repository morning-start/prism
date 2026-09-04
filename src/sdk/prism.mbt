///|
/// ═══ 功能组：facade（对外入口）═══
/// Prism 门面类型 + PrismOptions/ConversionMeta/DecodedResponse。
/// 只做转发，编码/解码实现见 pipeline.mbt。

///|
/// SDK 默认 provider 名称（Prism::new() 使用）
pub const DEFAULT_PROVIDER : String = "openai"

///|
/// SDK 默认模型名称（请求编码时的 fallback）
pub const DEFAULT_MODEL : String = "gpt-4o"

///|
/// ConversionMeta — 转换来源元信息（D8）
///
/// 回答"这个 LUX 值是从哪个协议解码来的"，并附带转换损失诊断
/// 与厂商特有字段（provider_payload / extra_fields）。
/// 开发者可用 `source_provider` 做按需特判（if 分支），主路径代码仍只写一次。
pub struct ConversionMeta {
  source_provider : String
  diagnostics : Array[@lux.ConversionDiagnostic]
  provider_payload : Json?
  extra_fields : Map[String, Json]?
}

///|
pub fn ConversionMeta::new(
  source_provider : String,
  diagnostics : Array[@lux.ConversionDiagnostic],
  provider_payload : Json?,
  extra_fields : Map[String, Json]?,
) -> ConversionMeta {
  { source_provider, diagnostics, provider_payload, extra_fields }
}

///|
/// DecodedResponse — 解码结果：主路径文本 + 溯源元信息
pub struct DecodedResponse {
  text : String
  meta : ConversionMeta
}

///|
pub fn DecodedResponse::new(
  text : String,
  meta : ConversionMeta,
) -> DecodedResponse {
  { text, meta }
}

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
}

///|
pub fn Prism::new() -> Prism {
  { provider: DEFAULT_PROVIDER }
}

///|
/// 设置 provider 名称
pub fn Prism::with_provider(_self : Prism, name : String) -> Prism {
  { provider: name }
}

///|
/// 将文本请求编码为提供商 JSON（L1：文本进，JSON 出）
pub fn Prism::encode_request(
  self : Prism,
  text : String,
  opts : PrismOptions,
) -> Result[String, String] {
  self.encode_lux_request(build_request_from_text(text, opts))
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
/// 将提供商 JSON 响应解码为 DecodedResponse（文本 + 来源元信息）。
///
/// meta.source_provider 为运行时从注册表解析的规范 provider 名
/// （精确匹配/别名/模型正则），开发者可据此做按需特判。
pub fn Prism::decode_response_with_meta(
  self : Prism,
  json_str : String,
) -> Result[DecodedResponse, String] {
  let source = match match_provider_name(self.provider) {
    Some(reg) => reg.name
    None => self.provider
  }
  match self.decode_to_lux(json_str) {
    Ok(resp) => {
      let meta = ConversionMeta::new(source, [], resp.provider_payload, None)
      Ok(DecodedResponse::new(resp.get_text(), meta))
    }
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
              @lux.ConversionDiagnostic::new("response", Invalid, Some(error)),
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
  let req = build_request_from_text(text, opts)
  let mut result = @lux.ConversionResult::new(req)
  match get_schema(self.provider) {
    Some(schema) =>
      for error in schema.validate_request(req) {
        result = result.with_diagnostic(
          @lux.ConversionDiagnostic::new("request", Invalid, Some(error)),
        )
      }
    None => ()
  }
  // capability 消费：请求所需能力 vs provider 声明（iteration-008 方向 A）
  for diagnostic in self.check_capability(result.value()) {
    result = result.with_diagnostic(diagnostic)
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
/// === 流式接口 ===

///|
/// 将文本请求编码为流式提供商 JSON
pub fn Prism::encode_stream_request(
  self : Prism,
  text : String,
  opts : PrismOptions,
) -> Result[String, String] {
  let mut req = build_request_from_text(text, opts)
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
  let model = DEFAULT_MODEL
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

///|
/// 能力校验（capability 消费落地，iteration-008 架构审计方向 A）
///
/// 将请求所需能力与 provider 的 `ProviderCapability` 声明对照，
/// 声明为 `Absent` 的能力若请求实际使用，产生 `Unsupported` 诊断——
/// 让能力声明从"死数据"变为运行时契约（呼应 AGENTS.md
/// "Unsupported capabilities MUST fail explicitly"）。
///
/// 检查项：
/// - 请求含 `tools` 但声明 `tool_calling=Absent` → Unsupported
/// - 请求启用 `reasoning` 但声明 `reasoning=Absent` → Unsupported
/// - 请求含 `structured_output` 但声明 `structured_output=Absent` → Unsupported
///
/// 空数组表示请求能力全部被支持。
pub fn Prism::check_capability(
  self : Prism,
  req : @lux.LucentRequest,
) -> Array[@lux.ConversionDiagnostic] {
  let diagnostics : Array[@lux.ConversionDiagnostic] = []
  match match_provider_name(self.provider) {
    Some(reg) => {
      let caps = reg.capability.capabilities
      // 1. 工具调用
      match req.tools {
        Some(tools) if tools.length() > 0 =>
          if caps.tool_calling == Absent {
            diagnostics.push(
              @lux.ConversionDiagnostic::unsupported(
                "request.tools",
                Some(self.provider + " declares tool_calling=none"),
              ),
            )
          }
        _ => ()
      }
      // 2. 推理
      match req.reasoning {
        Some(rc) if rc.enabled =>
          if caps.reasoning == Absent {
            diagnostics.push(
              @lux.ConversionDiagnostic::unsupported(
                "request.reasoning",
                Some(self.provider + " declares reasoning=none"),
              ),
            )
          }
        _ => ()
      }
      // 3. 结构化输出
      match req.options.structured_output {
        Some(_) =>
          if caps.structured_output == Absent {
            diagnostics.push(
              @lux.ConversionDiagnostic::unsupported(
                "request.options.structured_output",
                Some(self.provider + " declares structured_output=none"),
              ),
            )
          }
        None => ()
      }
    }
    None => ()
  }
  diagnostics
}
