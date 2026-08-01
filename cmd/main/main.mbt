///|
/// Prism WASM 导出入口
///
/// 这是可执行包：`moon build` 只把本包的 `pub fn` 放进 WASM export section。
/// 实现全部委托给 `wasm/` 库包，避免双份维护导出逻辑。
///
/// 6 个通用 IR 转换 + 5 个高层 SDK API：
/// 每个函数 String 进出，错误以 {"error": "message"} 返回。

///|
/// provider JSON → LucentReq JSON（decode req）
pub fn wasm_to_lux_req(provider : String, json_str : String) -> String {
  @wasm.wasm_to_lux_request(provider, json_str)
}

///|
/// LucentReq JSON → provider JSON（encode req）
pub fn wasm_lux_req_to_provider(provider : String, json_str : String) -> String {
  @wasm.wasm_lux_request_to_provider(provider, json_str)
}

///|
/// provider JSON → LucentResp JSON（decode resp）
pub fn wasm_to_lux_resp(provider : String, json_str : String) -> String {
  @wasm.wasm_to_lux_response(provider, json_str)
}

///|
/// LucentResp JSON → provider JSON（encode resp）
pub fn wasm_lux_resp_to_provider(
  provider : String,
  json_str : String,
) -> String {
  @wasm.wasm_lux_response_to_provider(provider, json_str)
}

///|
/// SSE 文本 → StreamEvent JSON 数组（decode SSE）
pub fn wasm_sse_to_events(provider : String, sse_str : String) -> String {
  @wasm.wasm_sse_to_events(provider, sse_str)
}

///|
/// StreamEvent JSON 数组 → SSE 文本（encode SSE）
pub fn wasm_events_to_sse(provider : String, json_str : String) -> String {
  @wasm.wasm_events_to_sse(provider, json_str)
}

///|
/// === SDK 层 API ===

///|
/// 文本 → provider JSON（encode req）
pub fn wasm_sdk_encode_req(provider : String, text : String) -> String {
  @wasm.wasm_sdk_encode_request(provider, text)
}

///|
/// provider JSON → 文本（decode resp）
pub fn wasm_sdk_decode_resp(provider : String, resp_json : String) -> String {
  @wasm.wasm_sdk_decode_response(provider, resp_json)
}

///|
/// 文本 → 流式 provider JSON（encode stream）
pub fn wasm_sdk_encode_stream(provider : String, text : String) -> String {
  @wasm.wasm_sdk_encode_stream(provider, text)
}

///|
/// 解码提供商 SSE → PrismEvent JSON 数组
pub fn wasm_sdk_decode_sse(provider : String, sse_str : String) -> String {
  @wasm.wasm_sdk_decode_sse(provider, sse_str)
}

///|
/// 查询 provider 能力声明
pub fn wasm_sdk_capability(provider : String) -> String {
  @wasm.wasm_sdk_capability(provider)
}

///|
fn main {
  let _ = @sdk.list_provider_names()
}
