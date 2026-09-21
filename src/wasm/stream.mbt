///|
/// 增量流转换会话 ABI（T5）
///
/// wasm 导出是无状态 String 进出；有状态会话（@sdk.StreamConverter）
/// 经整数句柄暴露：
/// - wasm_stream_new(source, target) → {"value": handle}
/// - wasm_stream_feed(handle, chunk)  → {"value": ["<sse frame>", ...]}
/// - wasm_stream_finish(handle)       → {"value": ["<sse frame>", ...]}
/// - wasm_stream_free(handle)         → {"value": true}
///
/// 句柄表由本模块持有（wasm 单线程，无并发问题）；free 后槽位复用。
/// host 每次 feed 立即取得目标协议 SSE 帧并转发——TFTB 从整条响应
/// 降到首帧到达（审计 P0-7 的 wasm 侧落地）。

///|
/// 会话表（None = 已释放槽位，可复用）
let stream_sessions : Array[@sdk.StreamConverter?] = []

///|
/// 分配句柄（复用已释放槽位，否则追加）
fn alloc_stream_slot(conv : @sdk.StreamConverter) -> Int {
  let mut i = 0
  while i < stream_sessions.length() {
    match stream_sessions[i] {
      None => {
        stream_sessions[i] = Some(conv)
        return i
      }
      Some(_) => ()
    }
    i = i + 1
  }
  stream_sessions.push(Some(conv))
  stream_sessions.length() - 1
}

///|
/// 取会话（句柄越界或已释放 → None）
fn get_stream_session(handle : Int) -> @sdk.StreamConverter? {
  if handle < 0 || handle >= stream_sessions.length() {
    None
  } else {
    stream_sessions[handle]
  }
}

///|
/// 帧数组 → JSON 数组信封
fn frames_envelope(frames : Array[String]) -> String {
  let arr : Array[Json] = []
  for f in frames {
    arr.push(Json::string(f))
  }
  wasm_envelope(Json::array(arr))
}

///|
/// 创建增量流转换会话 → {"value": handle}
pub fn wasm_stream_new(source : String, target : String) -> String {
  match @sdk.StreamConverter::new(source, target) {
    Ok(conv) => wasm_envelope(Json::number(alloc_stream_slot(conv).to_double()))
    Err(e) => wasm_envelope_err(e)
  }
}

///|
/// 喂入一个上游 chunk → {"value": [目标 SSE 帧...]}（可能为空数组）
pub fn wasm_stream_feed(handle : Int, chunk : String) -> String {
  match get_stream_session(handle) {
    Some(conv) =>
      match conv.feed(chunk) {
        Ok(frames) => frames_envelope(frames)
        Err(e) => wasm_envelope_err(e)
      }
    None => wasm_envelope_err("invalid stream handle: " + handle.to_string())
  }
}

///|
/// 流结束：冲刷尾部半帧并发射保持的 Finish 帧
pub fn wasm_stream_finish(handle : Int) -> String {
  match get_stream_session(handle) {
    Some(conv) =>
      match conv.finish() {
        Ok(frames) => frames_envelope(frames)
        Err(e) => wasm_envelope_err(e)
      }
    None => wasm_envelope_err("invalid stream handle: " + handle.to_string())
  }
}

///|
/// 释放会话（槽位置空复用）；重复释放返回错误
pub fn wasm_stream_free(handle : Int) -> String {
  if handle < 0 || handle >= stream_sessions.length() {
    return wasm_envelope_err("invalid stream handle: " + handle.to_string())
  }
  match stream_sessions[handle] {
    Some(_) => {
      stream_sessions[handle] = None
      wasm_envelope(Json::boolean(true))
    }
    None =>
      wasm_envelope_err("stream handle already freed: " + handle.to_string())
  }
}
