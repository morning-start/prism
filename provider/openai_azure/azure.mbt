///|
/// Azure OpenAI Responses — 基于标准 openai_responses 的薄封装
///
/// 子协议名：azure-openai-responses
/// 差异：端点 URL 和认证方式不同，JSON 接口与标准 Responses 基本相同
/// 特有扩展：content_filters[] 提取到 provider_payload

///|
/// 1. 请求解码
pub fn azure_to_lux_request(
  json_str : String,
) -> Result[@lux.LucentRequest, String] {
  @openai_responses.openai_responses_to_lux_request(json_str)
}

///|
/// 2. 请求编码
pub fn lux_request_to_azure(req : @lux.LucentRequest) -> Result[String, String] {
  @openai_responses.lux_request_to_openai_responses(req)
}

///|
/// 3. 响应解码 — 提取 Azure 特有的 content_filters 到 provider_payload
pub fn azure_to_lux_response(
  json_str : String,
) -> Result[@lux.LucentResponse, String] {
  let jv = @json.parse(json_str) catch { _ => return Err("json parse error") }
  match @openai_responses.openai_responses_to_lux_response(json_str) {
    Ok(base) =>
      match @lux.obj_get(jv, "content_filters") {
        Some(filters) => Ok(base.with_provider_payload(Some(filters)))
        None => Ok(base)
      }
    Err(e) => Err(e)
  }
}

///|
/// 4. 响应编码
pub fn lux_response_to_azure(
  resp : @lux.LucentResponse,
) -> Result[String, String] {
  @openai_responses.lux_response_to_openai_responses(resp)
}

///|
/// 5. 流解码
pub fn azure_sse_to_events(
  sse_str : String,
) -> Result[Array[@lux.LucentStreamEvent], String] {
  @openai_responses.openai_responses_sse_to_events(sse_str)
}

///|
/// 6. 流编码
pub fn lux_events_to_azure_sse(
  events : Array[@lux.LucentStreamEvent],
) -> Result[String, String] {
  @openai_responses.lux_events_to_openai_responses_sse(events)
}

///|
/// capability — 适配器能力声明
pub fn capability() -> @lux.ProviderCapability {
  @lux.ProviderCapability::new(
    "azure-*",
    "azure-openai",
    @lux.LucentCapabilities::create(
      true,
      true,
      true,
      true,
      true,
      [@lux.Text, @lux.Image, @lux.Pdf],
      [@lux.Text],
    ),
    None,
  )
}
