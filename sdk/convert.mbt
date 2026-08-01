///|
/// convert_* 组合入口 — 中转站（场景 2）
///
/// 协议 A JSON/SSE → Lux IR → 协议 B JSON/SSE。
/// 实现 = source 解码 + target 编码，零新增转换逻辑，复用 ProviderRegistration 注册表。

///|
/// 请求：source 协议 JSON → target 协议 JSON
pub fn convert_request(
  source : String,
  json_str : String,
  target : String,
) -> Result[String, String] {
  match match_provider_name(source) {
    Some(src) =>
      match match_provider_name(target) {
        Some(dst) =>
          decode_encode_request(
            json_str,
            src.request_decode,
            dst.request_encode,
          )
        None => Err("unknown provider: " + target)
      }
    None => Err("unknown provider: " + source)
  }
}

///|
/// 响应：source 协议 JSON → target 协议 JSON
pub fn convert_response(
  source : String,
  json_str : String,
  target : String,
) -> Result[String, String] {
  match match_provider_name(source) {
    Some(src) =>
      match match_provider_name(target) {
        Some(dst) =>
          decode_encode_response(
            json_str,
            src.response_decode,
            dst.response_encode,
          )
        None => Err("unknown provider: " + target)
      }
    None => Err("unknown provider: " + source)
  }
}

///|
/// 流式：source 协议 SSE → target 协议 SSE（事件级转换）
pub fn convert_stream(
  source : String,
  sse_str : String,
  target : String,
) -> Result[String, String] {
  match match_provider_name(source) {
    Some(src) =>
      match match_provider_name(target) {
        Some(dst) =>
          decode_encode_stream(sse_str, src.events_decode, dst.events_encode)
        None => Err("unknown provider: " + target)
      }
    None => Err("unknown provider: " + source)
  }
}

///|
/// 通用：source 解码 → target 编码
fn decode_encode_request(
  json_str : String,
  decode : (String) -> Result[@lux.LucentRequest, String],
  encode : (@lux.LucentRequest) -> Result[String, String],
) -> Result[String, String] {
  match decode(json_str) {
    Ok(req) => encode(req)
    Err(e) => Err(e)
  }
}

///|
/// 通用：source 解码 → target 编码
fn decode_encode_response(
  json_str : String,
  decode : (String) -> Result[@lux.LucentResponse, String],
  encode : (@lux.LucentResponse) -> Result[String, String],
) -> Result[String, String] {
  match decode(json_str) {
    Ok(resp) => encode(resp)
    Err(e) => Err(e)
  }
}

///|
/// 通用：source 事件解码 → target 事件编码
fn decode_encode_stream(
  sse_str : String,
  decode : (String) -> Result[Array[@lux.LucentStreamEvent], String],
  encode : (Array[@lux.LucentStreamEvent]) -> Result[String, String],
) -> Result[String, String] {
  match decode(sse_str) {
    Ok(events) => encode(events)
    Err(e) => Err(e)
  }
}
