///|
/// WASM 内存管理（wasm-gc 后端专用，TASK-2b 方案 A 降级实现）
///
/// 背景（RISK-006 / POC-1，见 .agent-team/docs/02-技术可行性.md）：
/// 原 memory.mbt 的 scratch/log ABI 用 `= "%identity"` 把 Int32 强转为
/// Bytes / FixedArray[Byte] 引用——这是线性内存指针技巧，仅在纯 wasm
/// 后端成立。wasm-gc 后端下这些类型是 GC 托管结构，i32 无法 cast 成
/// (ref n)，生成的模块被引擎校验直接拒绝，连坐其余 22 项合法转换导出
/// 也无法加载。
///
/// 本文件提供 wasm-gc 后端的降级实现：scratch/log 6 个导出按原签名返回
/// 无效指针（0）或错误信封，保证模块可加载、22 项转换导出可用。
/// 大字符串/日志通道在 wasm-gc 的完整重建（方案 B）登记为 TD-004。

///|
/// 通过 SDK 注册表查找 provider
fn lookup(provider : String) -> @sdk.ProviderRegistration? {
  @sdk.match_provider_name(provider)
}

///|
/// wasm-gc 下暂存缓冲区不可用（线性内存指针技巧不成立），恒返回 0。
///
/// 宿主应把返回值 0 视为"此构建不支持 scratch 通道"，改用 String 直传
/// ABI（各转换导出参数本身即 String，UTF-16 由宿主运行时直接承载）。
pub fn wasm_init_scratch(size : Int32) -> Int32 {
  let _ = size
  0
}

///|
/// wasm-gc 下无 scratch 缓冲区可读，恒返回错误信封。
pub fn wasm_read_scratch_arg(buf_ptr : Int32, offset : Int32) -> String {
  let _ = buf_ptr
  let _ = offset
  wasm_envelope_err(
    "wasm_read_scratch_arg is not supported on wasm-gc backend " +
    "(scratch buffer is a linear-memory technique); " +
    "pass String arguments directly instead",
  )
}

///|
/// wasm-gc 下无共享日志缓冲区，恒返回 0。
pub fn wasm_log_init(size : Int32) -> Int32 {
  let _ = size
  0
}

///|
/// wasm-gc 下无共享日志缓冲区，恒返回 0。
pub fn wasm_log_pos(buf_ptr : Int32) -> Int32 {
  let _ = buf_ptr
  0
}

///|
/// 带追踪的请求转换（wasm-gc 降级：日志通道不可用，直调转换并丢弃追踪）。
pub fn wasm_convert_req_trace(
  source : String,
  json_str : String,
  target : String,
  log_ptr : Int32,
  log_size : Int32,
) -> String {
  let _ = log_ptr
  let _ = log_size
  wasm_convert_request(source, json_str, target)
}

///|
/// 带追踪的响应转换（wasm-gc 降级：同上）。
pub fn wasm_convert_resp_trace(
  source : String,
  json_str : String,
  target : String,
  log_ptr : Int32,
  log_size : Int32,
) -> String {
  let _ = log_ptr
  let _ = log_size
  wasm_convert_response(source, json_str, target)
}

///|
/// 带追踪的流式转换（wasm-gc 降级：同上）。
pub fn wasm_convert_stream_trace(
  source : String,
  sse_str : String,
  target : String,
  log_ptr : Int32,
  log_size : Int32,
) -> String {
  let _ = log_ptr
  let _ = log_size
  wasm_convert_stream(source, sse_str, target)
}
