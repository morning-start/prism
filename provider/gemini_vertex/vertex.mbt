///|
/// Google Vertex AI Gemini — 基于标准 gemini 的薄封装
///
/// 子协议名：google-vertex
/// 差异：仅端点 URL 和认证方式不同，JSON 接口与公共 Gemini 完全相同
pub fn vertex_to_lux_request(
  json_str : String,
) -> Result[@lux.ConversionResult[@lux.LucentRequest], String] {
  @gemini.gemini_to_lux_request(json_str)
}

///|
pub fn lux_request_to_vertex(
  req : @lux.LucentRequest,
) -> Result[@lux.ConversionResult[String], String] {
  @gemini.lux_request_to_gemini(req)
}

///|
pub fn vertex_to_lux_response(
  json_str : String,
) -> Result[@lux.ConversionResult[@lux.LucentResponse], String] {
  @gemini.gemini_to_lux_response(json_str)
}

///|
pub fn lux_response_to_vertex(
  resp : @lux.LucentResponse,
) -> Result[@lux.ConversionResult[String], String] {
  @gemini.lux_response_to_gemini(resp)
}

///|
pub fn vertex_sse_to_events(
  sse_str : String,
) -> Result[@lux.ConversionResult[Array[@lux.LucentStreamEvent]], String] {
  @gemini.gemini_sse_to_events(sse_str)
}

///|
pub fn lux_events_to_vertex_sse(
  events : Array[@lux.LucentStreamEvent],
) -> Result[@lux.ConversionResult[String], String] {
  @gemini.lux_events_to_gemini_sse(events)
}

///|
/// capability — 适配器能力声明
pub fn capability() -> @lux.ProviderCapability {
  @lux.ProviderCapability::new(
    "gemini-*",
    "google-vertex",
    @lux.LucentCapabilities::create(
      true,
      true,
      true,
      true,
      true,
      [Text, Image, Audio, Video, Pdf],
      [Text],
    ),
    None,
  )
}
