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
/// 响应转换（带来源元信息）：source 协议 JSON → target 协议 JSON。
/// meta.source_provider 为注册表解析的规范 source 名（别名/模型正则归一）。
pub fn convert_response_with_meta(
  source : String,
  json_str : String,
  target : String,
) -> Result[ConvertMetaResult, String] {
  match match_provider_name(source) {
    Some(src) =>
      match match_provider_name(target) {
        Some(dst) =>
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
        None => Err("unknown provider: " + target)
      }
    None => Err("unknown provider: " + source)
  }
}

///|
/// 请求：source 协议 JSON → target 协议 JSON（带诊断）
pub fn convert_request(
  source : String,
  json_str : String,
  target : String,
) -> Result[@lux.ConversionResult[String], String] {
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
/// 响应：source 协议 JSON → target 协议 JSON（带诊断）
pub fn convert_response(
  source : String,
  json_str : String,
  target : String,
) -> Result[@lux.ConversionResult[String], String] {
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
/// 流式：source 协议 SSE → target 协议 SSE（事件级转换，带诊断）
pub fn convert_stream(
  source : String,
  sse_str : String,
  target : String,
) -> Result[@lux.ConversionResult[String], String] {
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
/// 通用：source 解码 → target 编码（合并解码+编码诊断，返回带诊断结果）
fn decode_encode_request(
  json_str : String,
  decode : (String) -> Result[@lux.ConversionResult[@lux.LucentRequest], String],
  encode : (@lux.LucentRequest) -> Result[@lux.ConversionResult[String], String],
) -> Result[@lux.ConversionResult[String], String] {
  match decode(json_str) {
    Ok(dcr) =>
      match encode(dcr.value()) {
        Ok(ecr) => Ok(merge_diagnostics(ecr, dcr.diagnostics()))
        Err(e) => Err(e)
      }
    Err(e) => Err(e)
  }
}

///|
/// 通用：source 解码 → target 编码（合并诊断）
fn decode_encode_response(
  json_str : String,
  decode : (String) -> Result[
    @lux.ConversionResult[@lux.LucentResponse],
    String,
  ],
  encode : (@lux.LucentResponse) -> Result[
    @lux.ConversionResult[String],
    String,
  ],
) -> Result[@lux.ConversionResult[String], String] {
  match decode(json_str) {
    Ok(dcr) =>
      match encode(dcr.value()) {
        Ok(ecr) => Ok(merge_diagnostics(ecr, dcr.diagnostics()))
        Err(e) => Err(e)
      }
    Err(e) => Err(e)
  }
}

///|
/// 通用：source 事件解码 → target 事件编码（合并诊断）
fn decode_encode_stream(
  sse_str : String,
  decode : (String) -> Result[
    @lux.ConversionResult[Array[@lux.LucentStreamEvent]],
    String,
  ],
  encode : (Array[@lux.LucentStreamEvent]) -> Result[
    @lux.ConversionResult[String],
    String,
  ],
) -> Result[@lux.ConversionResult[String], String] {
  match decode(sse_str) {
    Ok(dcr) =>
      match encode(dcr.value()) {
        Ok(ecr) => Ok(merge_diagnostics(ecr, dcr.diagnostics()))
        Err(e) => Err(e)
      }
    Err(e) => Err(e)
  }
}

///|
/// 合并两组诊断：以编码结果为主体，把解码诊断并入
fn merge_diagnostics(
  main : @lux.ConversionResult[String],
  other_diags : Array[@lux.ConversionDiagnostic],
) -> @lux.ConversionResult[String] {
  let mut merged = main
  for d in other_diags {
    merged = merged.with_diagnostic(d)
  }
  merged
}
