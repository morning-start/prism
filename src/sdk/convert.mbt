///|
/// convert_* 组合入口 — 中转站（场景 2）
///
/// 协议 A JSON/SSE → Lux IR → 协议 B JSON/SSE。
/// 实现 = source 解码 + target 编码，零新增转换逻辑，复用 ProviderRegistration 注册表。

///|
/// ConvertMetaResult — convert 结果：目标协议 JSON + 来源元信息（D8）
pub struct ConvertMetaResult {
  value : String
  meta : ConversionMeta
}

///|
pub fn ConvertMetaResult::new(
  value : String,
  meta : ConversionMeta,
) -> ConvertMetaResult {
  { value, meta }
}

///|
pub fn ConvertMetaResult::value(self : ConvertMetaResult) -> String {
  self.value
}

///|
pub fn ConvertMetaResult::meta(self : ConvertMetaResult) -> ConversionMeta {
  self.meta
}

///|
/// 解析 source 和 target provider。
fn resolve_pair(
  source : String,
  target : String,
) -> Result[(ProviderRegistration, ProviderRegistration), String] {
  let src = match match_provider_name(source) {
    Some(reg) => reg
    None => { return Err("unknown provider: " + source) }
  }
  let dst = match match_provider_name(target) {
    Some(reg) => reg
    None => { return Err("unknown provider: " + target) }
  }
  Ok((src, dst))
}

///|
/// 响应转换（带来源元信息）：source 协议 JSON → target 协议 JSON。
pub fn convert_response_with_meta(
  source : String,
  json_str : String,
  target : String,
) -> Result[ConvertMetaResult, String] {
  match resolve_pair(source, target) {
    Ok((src, dst)) =>
      match (src.response_decode)(json_str) {
        Ok(dcr) =>
          match (dst.response_encode)(dcr.value()) {
            Ok(ecr) => {
              let merged = merge_diagnostics(ecr, dcr.diagnostics())
              let meta = ConversionMeta::new(
                src.name,
                merged.diagnostics(),
                dcr.value().provider_payload,
                None,
              )
              Ok(ConvertMetaResult::new(merged.value(), meta))
            }
            Err(e) => Err(e)
          }
        Err(e) => Err(e)
      }
    Err(e) => Err(e)
  }
}

///|
/// 请求：source 协议 JSON → target 协议 JSON（带诊断）
pub fn convert_request(
  source : String,
  json_str : String,
  target : String,
) -> Result[@lux.ConversionResult[String], String] {
  match resolve_pair(source, target) {
    Ok((src, dst)) =>
      decode_encode_request(json_str, src.request_decode, dst.request_encode)
    Err(e) => Err(e)
  }
}

///|
/// 响应：source 协议 JSON → target 协议 JSON（带诊断）
pub fn convert_response(
  source : String,
  json_str : String,
  target : String,
) -> Result[@lux.ConversionResult[String], String] {
  match resolve_pair(source, target) {
    Ok((src, dst)) =>
      decode_encode_response(
        json_str,
        src.response_decode,
        dst.response_encode,
      )
    Err(e) => Err(e)
  }
}

///|
/// 流式：source 协议 SSE → target 协议 SSE（事件级转换，带诊断）
pub fn convert_stream(
  source : String,
  sse_str : String,
  target : String,
) -> Result[@lux.ConversionResult[String], String] {
  match resolve_pair(source, target) {
    Ok((src, dst)) =>
      decode_encode_stream(sse_str, src.events_decode, dst.events_encode)
    Err(e) => Err(e)
  }
}
