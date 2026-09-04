///|
/// SSE 行解析辅助 — Provider 适配器共用
///
/// 提供 SSE（Server-Sent Events）行的通用解析能力。
/// 支持 event: 和 data: 前缀的识别。

///|
/// SSE 行解析结果
pub struct SseLine {
  event : String?
  data : String?
}

///|
/// 解析单行 SSE 文本
///
/// 返回值说明：
/// - `Some({event: Some("xxx"), data: Some("yyy")})` — event: + data: 行
/// - `Some({event: None, data: Some("yyy")})` — 仅 data: 行
/// - `None` — 非 SSE 行（空行或注释行）
pub fn parse_sse_line(line : StringView) -> SseLine? {
  let l_str = line.to_owned()
  if l_str.length() == 0 {
    return None
  }
  // 跳过注释行（以 : 开头）
  if l_str[0] == ':' {
    return None
  }
  // 检查 "event: " 前缀
  if l_str.has_prefix("event: ") {
    return Some({ event: Some(l_str[7:].to_owned()), data: None })
  }
  // 检查 "data: " 前缀（带空格）
  if l_str.has_prefix("data: ") {
    return Some({ event: None, data: Some(l_str[6:].to_owned()) })
  }
  // 检查无空格 "data:"
  if l_str.has_prefix("data:") {
    return Some({ event: None, data: Some(l_str[5:].to_owned()) })
  }
  None
}

///|
/// 从 SSE 流中提取所有 data 行并合并
///
/// SSE 规范允许多个 data: 行合并为一个事件（用换行符连接）。
/// 此函数正确处理多行 data，并过滤注释行和心跳。
pub fn extract_sse_events(sse_str : String) -> Array[String] {
  let events : Array[String] = []
  let lines = sse_str.split("\n").to_array()
  let mut current_data : Array[String] = []
  for raw_line in lines {
    let line = raw_line.to_owned()
    // 空行表示事件边界
    if line.trim() == "" {
      if current_data.length() > 0 {
        events.push(current_data.join("\n"))
        current_data = []
      }
      continue
    }
    // 跳过注释行（以 : 开头，如心跳 : keep-alive）
    if line.length() > 0 && line[0] == ':' {
      continue
    }
    // 检查 data: 前缀
    if line.has_prefix("data: ") {
      current_data.push(line[6:].to_owned())
    } else if line.has_prefix("data:") {
      current_data.push(line[5:].to_owned())
    }
    // 忽略其他行（event: 等）
  }
  // 处理最后一个事件（如果没有尾部空行）
  if current_data.length() > 0 {
    events.push(current_data.join("\n"))
  }
  events
}

///|
/// SseMessage — 解析后的 SSE 消息（event 类型 + data 内容）
///
/// SSE 规范中一个消息由多行组成：
///   event: <type>    （可选）
///   data: <payload>  （可多行，用换行符连接）
///   空行             （消息边界）
pub struct SseMessage {
  event_type : String?
  data : String
} derive(Eq, Debug)

///|
/// 解析单个 SSE 消息块为 SseMessage
///
/// 输入为一个消息块的文本（不含尾部空行），例如：
///   "event: content_block_delta\ndata: {\"type\":\"text_delta\",\"text\":\"hello\"}"
///
/// 返回 None 表示空块或纯注释块。
pub fn parse_sse_message(msg_block : String) -> SseMessage? {
  let normalized = msg_block
    .replace(old="\r\n", new="\n")
    .replace(old="\r", new="\n")
  let lines = normalized.split("\n").to_array()
  let mut event_type : String? = None
  let data_parts : Array[String] = []
  for raw_line in lines {
    let line = raw_line.to_owned()
    // 跳过空行和注释行
    if line.length() == 0 {
      continue
    }
    if line[0] == ':' {
      continue
    }
    // 解析 event: 行
    let parsed = parse_sse_line(line.view())
    match parsed {
      Some(sl) =>
        match sl.event {
          Some(e) => event_type = Some(e)
          None =>
            match sl.data {
              Some(d) => data_parts.push(d)
              None => ()
            }
        }
      None => ()
    }
  }
  if data_parts.length() == 0 {
    return None
  }
  Some({ event_type, data: data_parts.join("\n") })
}

///|
/// 从 SSE 流中解析所有消息
///
/// 按 `\n\n` 分割消息块，逐块解析为 SseMessage。
/// 跳过空块和纯注释块。
pub fn parse_sse_messages(sse_str : String) -> Array[SseMessage] {
  let messages : Array[SseMessage] = []
  // HTTP/SSE streams commonly use CRLF; normalize all line endings first.
  let normalized = sse_str
    .replace(old="\r\n", new="\n")
    .replace(old="\r", new="\n")
  let blocks = normalized.split("\n\n").to_array()
  for raw_block in blocks {
    let block = raw_block.to_owned()
    if block.trim() == "" {
      continue
    }
    match parse_sse_message(block) {
      Some(msg) => messages.push(msg)
      None => ()
    }
  }
  messages
}

///|
/// SSE 帧预处理流水线 — 四个 provider 共用的标准化管线
///
/// 将原始 SSE data 行内容经过：
///   1. trim
///   2. 心跳清理（clean_sse_heartbeat）
///   3. 转义修复（sanitize_json_escapes）
///   4. 截断检测（is_json_truncated）
///   5. JSON 解析
///
/// 返回 `Some(jv)` 表示成功，`None` 表示该帧应跳过（空、心跳、截断、非法 JSON）。
pub fn parse_sse_frame(data_raw : String) -> Json? {
  let trimmed = data_raw.trim().to_owned()
  if trimmed == "" {
    return None
  }
  let cleaned = sanitize_json_escapes(clean_sse_heartbeat(trimmed))
  if is_json_truncated(cleaned) {
    return None
  }
  let jv = @json.parse(cleaned) catch { _ => return None }
  Some(jv)
}

///|
/// SSE 帧预处理（带失败原因诊断版）— responses 流解码专用
///
/// 与 `parse_sse_frame` 同一管线，但区分失败原因供调用方发诊断：
/// - `(Some(jv), None)`：解析成功
/// - `(None, None)`：空帧/心跳帧，静默跳过（无诊断）
/// - `(None, Some(reason))`：截断或非法 JSON，调用方应发 Invalid 诊断
///
/// 收敛目的（iteration-008 方向 B）：responses 原为手动逐帧预处理，
/// 与 messages/openai/gemini 的 `parse_sse_frame` 管线不对称；此 helper
/// 让 responses 复用同一管线，同时保留其"失败必诊断"的语义。
pub fn parse_sse_frame_with_reason(data_raw : String) -> (Json?, String?) {
  let trimmed = data_raw.trim().to_owned()
  if trimmed == "" {
    return (None, None)
  }
  let cleaned = sanitize_json_escapes(clean_sse_heartbeat(trimmed))
  if cleaned == "" {
    return (None, None)
  }
  if is_json_truncated(cleaned) {
    return (
      None,
      Some("truncated JSON in SSE data (stream may be incomplete): " + data_raw),
    )
  }
  let jv = @json.parse(cleaned) catch {
    _ => return (None, Some("invalid JSON in SSE data: " + data_raw))
  }
  (Some(jv), None)
}
