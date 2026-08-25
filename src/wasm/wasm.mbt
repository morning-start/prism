///|
/// Prism WASM 导出层
///
/// 6 个通用转换函数（通过 SDK 注册表分发）+ 5 个高层 SDK API。
/// 所有函数 String 进出，错误以 JSON 格式返回：{"error": "message"}
///
/// 新增 Provider 时只需在 `sdk/provider_capability.mbt` 注册，
/// WASM 层自动支持，无需修改。

///|
/// === 辅助 ===

///|
/// 错误信封：{"error":"...","diagnostics":[]}（与成功信封的诊断字段一致）
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
  buf[0]
  .to_int()
  .land(0xFF)
  .lor(buf[1].to_int().land(0xFF) << 8)
  .lor(buf[2].to_int().land(0xFF) << 16)
  .lor(buf[3].to_int().land(0xFF) << 24)
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
  let mut pos = buf[0]
    .to_int()
    .land(0xFF)
    .lor(buf[1].to_int().land(0xFF) << 8)
    .lor(buf[2].to_int().land(0xFF) << 16)
    .lor(buf[3].to_int().land(0xFF) << 24)
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
  buf[0] = pos.land(0xFF).to_byte()
  buf[1] = (pos >> 8).land(0xFF).to_byte()
  buf[2] = (pos >> 16).land(0xFF).to_byte()
  buf[3] = (pos >> 24).land(0xFF).to_byte()
}

///|
/// 带追踪的请求转换：source 协议 JSON → target 协议 JSON。
/// 每一步写入日志到 `log_ptr` 缓冲区。
pub fn wasm_convert_req_trace(
  source : String,
  json_str : String,
  target : String,
  log_ptr : Int,
  log_size : Int,
) -> String {
  log_write(
    log_ptr,
    log_size,
    2,
    "convert_req",
    "start: " + source + " → " + target,
  )
  log_write(
    log_ptr,
    log_size,
    1,
    "convert_req",
    "input length: " + json_str.length().to_string() + " chars",
  )
  let result = wasm_convert_request(source, json_str, target)
  if result.contains("\"error\"") {
    log_write(log_ptr, log_size, 4, "convert_req", "failed: " + result)
  } else {
    log_write(
      log_ptr,
      log_size,
      2,
      "convert_req",
      "success: " + result.length().to_string() + " chars",
    )
  }
  result
}

///|
/// 带追踪的响应转换：source 协议 JSON → target 协议 JSON。
pub fn wasm_convert_resp_trace(
  source : String,
  json_str : String,
  target : String,
  log_ptr : Int,
  log_size : Int,
) -> String {
  log_write(
    log_ptr,
    log_size,
    2,
    "convert_resp",
    "start: " + source + " → " + target,
  )
  log_write(
    log_ptr,
    log_size,
    1,
    "convert_resp",
    "input length: " + json_str.length().to_string() + " chars",
  )
  let result = wasm_convert_response(source, json_str, target)
  if result.contains("\"error\"") {
    log_write(log_ptr, log_size, 4, "convert_resp", "failed: " + result)
  } else {
    log_write(
      log_ptr,
      log_size,
      2,
      "convert_resp",
      "success: " + result.length().to_string() + " chars",
    )
  }
  result
}

///|
/// 带追踪的流式转换：source 协议 SSE → target 协议 SSE。
pub fn wasm_convert_stream_trace(
  source : String,
  sse_str : String,
  target : String,
  log_ptr : Int,
  log_size : Int,
) -> String {
  log_write(
    log_ptr,
    log_size,
    2,
    "convert_stream",
    "start: " + source + " → " + target,
  )
  log_write(
    log_ptr,
    log_size,
    1,
    "convert_stream",
    "input length: " + sse_str.length().to_string() + " chars",
  )
  let result = wasm_convert_stream(source, sse_str, target)
  if result.contains("\"error\"") {
    log_write(log_ptr, log_size, 4, "convert_stream", "failed: " + result)
  } else {
    log_write(
      log_ptr,
      log_size,
      2,
      "convert_stream",
      "success: " + result.length().to_string() + " chars",
    )
  }
  result
}

///|
/// === 6 个通用 IR 转换函数 ===

///|
/// provider JSON → LucentRequest JSON（decode request，带诊断信封）
pub fn wasm_to_lux_request(provider : String, json_str : String) -> String {
  match lookup(provider) {
    Some(reg) =>
      match (reg.request_decode)(json_str) {
        Ok(cr) =>
          cr.envelope_json(@lux.LucentRequest::to_json(cr.value())).stringify()
        Err(e) => wasm_envelope_err(e)
      }
    None => wasm_envelope_err("unknown provider: " + provider)
  }
}

///|
/// LucentRequest JSON → provider JSON（encode request，带诊断信封）
pub fn wasm_lux_request_to_provider(
  provider : String,
  json_str : String,
) -> String {
  let jv = @json.parse(json_str) catch {
    _ => return wasm_envelope_err("json parse error")
  }
  match @lux.LucentRequest::from_json(jv) {
    Ok(req) =>
      match lookup(provider) {
        Some(reg) =>
          match (reg.request_encode)(req) {
            Ok(cr) => cr.envelope_json(Json::string(cr.value())).stringify()
            Err(e) => wasm_envelope_err(e)
          }
        None => wasm_envelope_err("unknown provider: " + provider)
      }
    Err(e) => wasm_envelope_err(e)
  }
}

///|
/// provider JSON → LucentResponse JSON（decode response，带诊断信封）
pub fn wasm_to_lux_response(provider : String, json_str : String) -> String {
  match lookup(provider) {
    Some(reg) =>
      match (reg.response_decode)(json_str) {
        Ok(cr) =>
          cr.envelope_json(@lux.LucentResponse::to_json(cr.value())).stringify()
        Err(e) => wasm_envelope_err(e)
      }
    None => wasm_envelope_err("unknown provider: " + provider)
  }
}

///|
/// LucentResponse JSON → provider JSON（encode response，带诊断信封）
pub fn wasm_lux_response_to_provider(
  provider : String,
  json_str : String,
) -> String {
  let jv = @json.parse(json_str) catch {
    _ => return wasm_envelope_err("json parse error")
  }
  match @lux.LucentResponse::from_json(jv) {
    Ok(resp) =>
      match lookup(provider) {
        Some(reg) =>
          match (reg.response_encode)(resp) {
            Ok(cr) => cr.envelope_json(Json::string(cr.value())).stringify()
            Err(e) => wasm_envelope_err(e)
          }
        None => wasm_envelope_err("unknown provider: " + provider)
      }
    Err(e) => wasm_envelope_err(e)
  }
}

///|
/// SSE 文本 → StreamEvent JSON 数组（decode SSE，带诊断信封）
pub fn wasm_sse_to_events(provider : String, sse_str : String) -> String {
  match lookup(provider) {
    Some(reg) =>
      match (reg.events_decode)(sse_str) {
        Ok(cr) => {
          let json_arr : Array[Json] = cr.value().map(fn(ev) { ev.to_json() })
          cr.envelope_json(Json::array(json_arr)).stringify()
        }
        Err(e) => wasm_envelope_err(e)
      }
    None => wasm_envelope_err("unknown provider: " + provider)
  }
}

///|
/// StreamEvent JSON 数组 → SSE 文本（encode SSE，带诊断信封）
pub fn wasm_events_to_sse(provider : String, json_str : String) -> String {
  let jv = @json.parse(json_str) catch {
    _ => return wasm_envelope_err("json parse error")
  }
  match jv {
    Array(arr) => {
      let events : Array[@lux.LucentStreamEvent] = []
      let mut i = 0
      while i < arr.length() {
        match @lux.LucentStreamEvent::from_json(arr[i]) {
          Ok(ev) => events.push(ev)
          Err(e) =>
            return wasm_envelope_err("event " + i.to_string() + ": " + e)
        }
        i = i + 1
      }
      match lookup(provider) {
        Some(reg) =>
          match (reg.events_encode)(events) {
            Ok(cr) => cr.envelope_json(Json::string(cr.value())).stringify()
            Err(e) => wasm_envelope_err(e)
          }
        None => wasm_envelope_err("unknown provider: " + provider)
      }
    }
    _ => wasm_envelope_err("expected array for stream events")
  }
}

///|
/// 无诊断信封：{"value":...,"diagnostics":[]}（形状与带诊断信封一致）
fn wasm_envelope(value : Json) -> String {
  let fields : Map[String, Json] = {
    "value": value,
    "diagnostics": Json::array([]),
  }
  Json::object(fields).stringify()
}

///|
/// === SDK 层 API ===

///|
/// 对文本请求进行编码（provider JSON 出，带诊断信封），Host 发送 HTTP
pub fn wasm_sdk_encode_request(provider : String, text : String) -> String {
  let prism = @sdk.Prism::new().with_provider(provider)
  match
    prism.encode_request_with_diagnostics(text, @sdk.PrismOptions::default()) {
    Ok(cr) => cr.envelope_json(Json::string(cr.value())).stringify()
    Err(e) => wasm_envelope_err(e)
  }
}

///|
/// 解码提供商响应 JSON → 纯文本（带诊断信封）
pub fn wasm_sdk_decode_response(
  provider : String,
  resp_json : String,
) -> String {
  let prism = @sdk.Prism::new().with_provider(provider)
  match prism.decode_response_with_diagnostics(resp_json) {
    Ok(cr) => cr.envelope_json(Json::string(cr.value().get_text())).stringify()
    Err(e) => wasm_envelope_err(e)
  }
}

///|
/// 对文本请求进行流式编码（provider JSON 出，无诊断源 → diagnostics: []）
pub fn wasm_sdk_encode_stream(provider : String, text : String) -> String {
  let prism = @sdk.Prism::new().with_provider(provider)
  match prism.encode_stream_request(text, @sdk.PrismOptions::default()) {
    Ok(v) => wasm_envelope(Json::string(v))
    Err(e) => wasm_envelope_err(e)
  }
}

///|
/// 解码提供商 SSE → PrismEvent JSON 数组（无诊断源 → diagnostics: []）
pub fn wasm_sdk_decode_sse(provider : String, sse_str : String) -> String {
  let prism = @sdk.Prism::new().with_provider(provider)
  match prism.decode_sse(sse_str) {
    Ok(events) => {
      let json_arr : Array[Json] = events.map(fn(ev) { prism_event_to_json(ev) })
      wasm_envelope(Json::array(json_arr))
    }
    Err(e) => wasm_envelope_err(e)
  }
}

///|
/// PrismEvent → Json（直接构造，避免拼字符串后再解析）
fn prism_event_to_json(ev : @sdk.PrismEvent) -> Json {
  let m : Map[String, Json] = Map([])
  match ev {
    TextDelta(s) => {
      m["type"] = Json::string("text_delta")
      m["text"] = Json::string(s)
    }
    ToolCall(tc) => {
      m["type"] = Json::string("tool_call")
      m["id"] = Json::string(tc.id)
      m["name"] = Json::string(tc.name)
      // arguments_json 已是 JSON 文本；解析失败则降级为原始字符串
      m["arguments"] = @json.parse(tc.arguments_json) catch {
        _ => Json::string(tc.arguments_json)
      }
    }
    ToolResult(tr) => {
      m["type"] = Json::string("tool_result")
      m["tool_use_id"] = Json::string(tr.tool_use_id)
      m["content"] = Json::string(tr.content)
      m["is_error"] = if tr.is_error {
        Json::boolean(true)
      } else {
        Json::boolean(false)
      }
    }
    Thinking(th) => {
      m["type"] = Json::string("thinking")
      m["text"] = Json::string(th.text)
    }
    Finish(fr) => {
      m["type"] = Json::string("finish")
      m["reason"] = Json::string(
        match fr {
          Stop => "stop"
          Length => "length"
          ToolCalls => "tool_calls"
          ContentFilter => "content_filter"
          Error => "error"
        },
      )
    }
  }
  Json::object(m)
}

///|
/// 查询 provider 能力声明（无诊断源 → diagnostics: []）
pub fn wasm_sdk_capability(provider : String) -> String {
  let prism = @sdk.Prism::new().with_provider(provider)
  match prism.capability(provider) {
    Some(c) => wasm_envelope(c.to_json())
    None => wasm_envelope_err("unknown provider")
  }
}

///|
/// === 中转站协议转发（convert_* 组合入口）===

///|
/// 请求：source 协议 JSON → target 协议 JSON（带诊断信封）
pub fn wasm_convert_request(
  source : String,
  json_str : String,
  target : String,
) -> String {
  match @sdk.convert_request(source, json_str, target) {
    Ok(cr) => cr.envelope_json(Json::string(cr.value())).stringify()
    Err(e) => wasm_envelope_err(e)
  }
}

///|
/// 响应：source 协议 JSON → target 协议 JSON（带诊断信封）
pub fn wasm_convert_response(
  source : String,
  json_str : String,
  target : String,
) -> String {
  match @sdk.convert_response(source, json_str, target) {
    Ok(cr) => cr.envelope_json(Json::string(cr.value())).stringify()
    Err(e) => wasm_envelope_err(e)
  }
}

///|
/// 流式：source 协议 SSE → target 协议 SSE（带诊断信封）
pub fn wasm_convert_stream(
  source : String,
  sse_str : String,
  target : String,
) -> String {
  match @sdk.convert_stream(source, sse_str, target) {
    Ok(cr) => cr.envelope_json(Json::string(cr.value())).stringify()
    Err(e) => wasm_envelope_err(e)
  }
}

///|
/// === 查询 ===

///|
/// 全部 provider 主名称的 JSON 数组
pub fn wasm_list_providers() -> String {
  let names = @sdk.list_provider_names()
  let arr : Array[Json] = names.map(fn(n) { Json::string(n) })
  Json::array(arr).stringify()
}
