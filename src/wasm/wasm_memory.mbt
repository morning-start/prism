///|
/// WASM 内存管理：scratch buffer、LE 字节辅助、日志系统
fn wasm_envelope_err(e : String) -> String {
  "{\"error\":\"" + e + "\",\"diagnostics\":[]}"
}

///|
/// 通过 SDK 注册表查找 provider
fn lookup(provider : String) -> @sdk.ProviderRegistration? {
  @sdk.match_provider_name(provider)
}

///|
/// === 纯 WASM 大字符串支持 ===
///
/// 固定暂存区（0x0400, stride 512）限制每个参数 ~252 UTF-16 码元。
/// 对于纯 WASM 环境（无法由宿主侧动态扩展内存），
/// 提供在 MoonBit 堆上预分配暂存缓冲区的方案。
///
/// MoonBit runtime 使用引用计数（非移动 GC），对象一旦分配地址不变。
/// Bytes 在 WASM 线性内存中的布局：
///   对象头 (8B: rc + meta/len) | 数据载荷
/// 返回的指针指向数据载荷起始位置（对象头之后）。

///|
/// 将 Bytes 引用转为线性内存地址（i32）。
/// WASM 目标下 Bytes 就是 i32 指针，与 Int 同构。
fn bytes_ptr_to_int(b : Bytes) -> Int = "%identity"

///|
/// 初始化暂存缓冲区。返回缓冲区数据的线性内存地址（i32）。
///
/// 宿主调用一次后，将 UTF-16LE 数据写入返回的地址。
/// 布局：`addr - 4` 处为 u32 LE 字节长度，`addr` 处为 UTF-16LE 载荷。
/// 推荐大小：8192 字节/参数 × 3 参数 = 24576。
pub fn wasm_init_scratch(size : Int) -> Int {
  let buf = Bytes::make(size, b'\x00')
  // Bytes 在 WASM 中是 i32 指针，指向数据载荷（对象头之后 8 字节）
  // MoonBit 对象头：rc(4B) + meta(4B) = 8B
  // Bytes 引用本身指向数据起始位置
  bytes_ptr_to_int(buf)
}

///|
/// 从暂存缓冲区读取字符串参数。
///
/// 调用 `wasm_init_scratch` 后，宿主将 UTF-16LE 数据写入返回的地址。
/// 然后调用本函数读取：`offset` 是缓冲区内偏移量（不含长度头）。
/// 宿主在 `offset - 4` 处写 u32 LE 字节长度，`offset` 处写 UTF-16LE 载荷。
pub fn wasm_read_scratch_arg(buf_ptr : Int, offset : Int) -> String {
  let buf : Bytes = int_to_bytes(buf_ptr)
  let len_view = buf[offset - 4:offset]
  let byte_len = len_view[0]
    .to_int()
    .land(0xFF)
    .lor(len_view[1].to_int().land(0xFF) << 8)
    .lor(len_view[2].to_int().land(0xFF) << 16)
    .lor(len_view[3].to_int().land(0xFF) << 24)
  buf.to_unchecked_string(offset~, length=byte_len)
}

///|
/// 将线性内存地址（i32）转为 Bytes 引用。
/// 与 bytes_ptr_to_int 互逆。
fn int_to_bytes(ptr : Int) -> Bytes = "%identity"

///|
/// === 日志/追踪系统 ===
///
/// Prism WASM 通过共享线性内存缓冲区向宿主传递内部执行日志。
/// 宿主在调用转换函数前后读取缓冲区，即可观察 WASM 内部每一步的状态。
///
/// 设计约束：MoonBit 不支持模块级 `let mut`，因此不维护全局可变状态。
/// 采用"调用方传入缓冲区"模式：
///
/// 宿主侧使用方式：
/// 1. 调用 `wasm_log_init(16384)` → 分配 16KB 日志缓冲区，返回 buf_ptr
/// 2. 调用 `wasm_convert_req_trace(source, json, target, buf_ptr, buf_size)` → 转换 + 写日志
/// 3. 从 buf_ptr 读取 UTF-8 日志内容（跳过前 4 字节的位置头）
/// 4. 调用 `wasm_log_pos(buf_ptr)` 获取当前写入位置，判断日志长度
///
/// 日志格式：每行一条 `[LEVEL] step: message\n`，UTF-8 编码。
/// 缓冲区前 4 字节为 u32 LE 写入位置，之后是日志内容。

///|
/// FixedArray[Byte] ↔ Int 转换（WASM 中都是 i32）
fn fixed_bytes_ptr_to_int(b : FixedArray[Byte]) -> Int = "%identity"

///|
fn int_to_fixed_bytes(ptr : Int) -> FixedArray[Byte] = "%identity"

///|
/// 从 FixedArray[Byte] 读取 u32 LE 值（4 字节）
fn read_le32(buf : FixedArray[Byte], offset : Int) -> Int {
  buf[offset]
  .to_int()
  .land(0xFF)
  .lor(buf[offset + 1].to_int().land(0xFF) << 8)
  .lor(buf[offset + 2].to_int().land(0xFF) << 16)
  .lor(buf[offset + 3].to_int().land(0xFF) << 24)
}

///|
/// 向 FixedArray[Byte] 写入 u32 LE 值（4 字节）
fn write_le32(buf : FixedArray[Byte], offset : Int, value : Int) -> Unit {
  buf[offset] = value.land(0xFF).to_byte()
  buf[offset + 1] = (value >> 8).land(0xFF).to_byte()
  buf[offset + 2] = (value >> 16).land(0xFF).to_byte()
  buf[offset + 3] = (value >> 24).land(0xFF).to_byte()
}

///|
/// 初始化日志缓冲区。返回缓冲区线性内存地址。
/// 缓冲区前 4 字节存储当前写入位置（u32 LE），日志内容从第 5 字节开始。
pub fn wasm_log_init(size : Int) -> Int {
  let buf = FixedArray::make(size + 4, b'\x00')
  fixed_bytes_ptr_to_int(buf)
}

///|
/// 获取日志缓冲区当前写入位置。
/// 宿主通过比较位置变化来判断是否有新日志。
pub fn wasm_log_pos(buf_ptr : Int) -> Int {
  let buf = int_to_fixed_bytes(buf_ptr)
  read_le32(buf, 0)
}

///|
/// 向日志缓冲区追加一条日志。
///
/// `buf_ptr`：`wasm_log_init` 返回的地址
/// `buf_size`：缓冲区总大小（含 4 字节头）
/// `level`：日志级别（0=TRACE, 1=DEBUG, 2=INFO, 3=WARN, 4=ERROR）
/// `step`：步骤标识（如 "decode_request", "convert_to_lux"）
/// `message`：日志内容
fn log_write(
  buf_ptr : Int,
  buf_size : Int,
  level : Int,
  step : String,
  message : String,
) -> Unit {
  let buf = int_to_fixed_bytes(buf_ptr)
  // 读取当前写入位置（前 4 字节）
  let mut pos = read_le32(buf, 0)
  // 如果位置为 0，从第 5 字节开始写
  if pos == 0 {
    pos = 4
  }
  let level_str = match level {
    0 => "TRACE"
    1 => "DEBUG"
    2 => "INFO"
    3 => "WARN"
    4 => "ERROR"
    _ => "UNKNOWN"
  }
  let entry = "[" + level_str + "] " + step + ": " + message + "\n"
  let data_start = 4
  let data_end = buf_size
  // 逐字符写入 UTF-8（ASCII 直接写低字节，非 ASCII 写 3 字节）
  let code_units = entry.code_units()
  let entry_len = code_units.length()
  let mut i = 0
  while i < entry_len {
    let ch = code_units[i].to_int()
    if ch < 128 {
      // ASCII: 1 字节
      if pos >= data_end {
        pos = data_start
      }
      buf[pos] = ch.to_byte()
      pos = pos + 1
    } else if ch < 2048 {
      // 2 字节 UTF-8: 110xxxxx 10xxxxxx
      if pos >= data_end {
        pos = data_start
      }
      buf[pos] = (192 + (ch >> 6)).to_byte()
      pos = pos + 1
      if pos >= data_end {
        pos = data_start
      }
      buf[pos] = (128 + ch.land(63)).to_byte()
      pos = pos + 1
    } else {
      // 3 字节 UTF-8: 1110xxxx 10xxxxxx 10xxxxxx
      if pos >= data_end {
        pos = data_start
      }
      buf[pos] = (224 + (ch >> 12)).to_byte()
      pos = pos + 1
      if pos >= data_end {
        pos = data_start
      }
      buf[pos] = (128 + (ch >> 6).land(63)).to_byte()
      pos = pos + 1
      if pos >= data_end {
        pos = data_start
      }
      buf[pos] = (128 + ch.land(63)).to_byte()
      pos = pos + 1
    }
    i = i + 1
  }
  // 写回位置到头部
  write_le32(buf, 0, pos)
}

///|
/// 带追踪的通用转换：执行转换 + 日志记录。
/// 消除 3 个 trace 函数的重复样板。
fn trace_convert(
  source : String,
  input : String,
  target : String,
  step : String,
  convert : (String, String, String) -> String,
  log_ptr : Int,
  log_size : Int,
) -> String {
  log_write(log_ptr, log_size, 2, step, "start: " + source + " → " + target)
  log_write(
    log_ptr,
    log_size,
    1,
    step,
    "input length: " + input.length().to_string() + " chars",
  )
  let result = convert(source, input, target)
  // 结构化错误检测：检查 JSON 是否以 {"error": 开头
  let is_err = result.length() > 9 && result[0:9] == "{\"error\":"
  if is_err {
    log_write(log_ptr, log_size, 4, step, "failed: " + result)
  } else {
    log_write(
      log_ptr,
      log_size,
      2,
      step,
      "success: " + result.length().to_string() + " chars",
    )
  }
  result
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
  trace_convert(
    source, json_str, target, "convert_req", wasm_convert_request, log_ptr, log_size,
  )
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
  trace_convert(
    source, json_str, target, "convert_resp", wasm_convert_response, log_ptr, log_size,
  )
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
  trace_convert(
    source, sse_str, target, "convert_stream", wasm_convert_stream, log_ptr, log_size,
  )
}

///|
/// === 6 个通用 IR 转换函数 ===

///|
/// provider JSON → LucentRequest JSON（decode request，带诊断信封）
