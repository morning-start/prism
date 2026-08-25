///|
/// Prism WASM 导出入口
///
/// 这是可执行包：`moon build` 只把本包的 `pub fn` 放进 WASM export section。
/// 实现全部委托给 `wasm/` 库包，避免双份维护导出逻辑。
///
/// 6 个通用 IR 转换 + 3 个中转 + 6 个 SDK/查询：
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
/// === 中转站协议转发 ===

///|
/// 请求：source 协议 JSON → target 协议 JSON
pub fn wasm_convert_req(
  source : String,
  json_str : String,
  target : String,
) -> String {
  @wasm.wasm_convert_request(source, json_str, target)
}

///|
/// 响应：source 协议 JSON → target 协议 JSON
pub fn wasm_convert_resp(
  source : String,
  json_str : String,
  target : String,
) -> String {
  @wasm.wasm_convert_response(source, json_str, target)
}

///|
/// 流式：source 协议 SSE → target 协议 SSE
pub fn wasm_convert_stream(
  source : String,
  sse_str : String,
  target : String,
) -> String {
  @wasm.wasm_convert_stream(source, sse_str, target)
}

///|
/// === 查询 ===

///|
/// 全部 provider 主名称的 JSON 数组
pub fn wasm_list_providers() -> String {
  @wasm.wasm_list_providers()
}

///|
/// === 纯 WASM 大字符串支持 ===

///|
/// 初始化暂存缓冲区，返回线性内存地址
pub fn wasm_init_scratch(size : Int) -> Int {
  @wasm.wasm_init_scratch(size)
}

///|
/// 从暂存缓冲区读取字符串参数
pub fn wasm_read_scratch_arg(buf_ptr : Int, offset : Int) -> String {
  @wasm.wasm_read_scratch_arg(buf_ptr, offset)
}

///|
/// === 日志系统 ===

///|
/// 初始化日志缓冲区，返回线性内存地址
pub fn wasm_log_init(size : Int) -> Int {
  @wasm.wasm_log_init(size)
}

///|
/// 获取日志缓冲区当前写入位置
pub fn wasm_log_pos(buf_ptr : Int) -> Int {
  @wasm.wasm_log_pos(buf_ptr)
}

///|
/// 带追踪的请求转换
pub fn wasm_convert_req_trace(
  source : String,
  json_str : String,
  target : String,
  log_ptr : Int,
  log_size : Int,
) -> String {
  @wasm.wasm_convert_req_trace(source, json_str, target, log_ptr, log_size)
}

///|
/// 带追踪的响应转换
pub fn wasm_convert_resp_trace(
  source : String,
  json_str : String,
  target : String,
  log_ptr : Int,
  log_size : Int,
) -> String {
  @wasm.wasm_convert_resp_trace(source, json_str, target, log_ptr, log_size)
}

///|
/// 带追踪的流式转换
pub fn wasm_convert_stream_trace(
  source : String,
  sse_str : String,
  target : String,
  log_ptr : Int,
  log_size : Int,
) -> String {
  @wasm.wasm_convert_stream_trace(source, sse_str, target, log_ptr, log_size)
}

///|
fn main {
  let _ = @sdk.list_provider_names()
}
