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
    return Some({ event: Some(l_str[7:].to_owned()), data: None, })
  }
  // 检查 "data: " 前缀（带空格）
  if l_str.has_prefix("data: ") {
    return Some({ event: None, data: Some(l_str[6:].to_owned()), })
  }
  // 检查无空格 "data:"
  if l_str.has_prefix("data:") {
    return Some({ event: None, data: Some(l_str[5:].to_owned()), })
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
/// explicit: Eq::equal kept as a regular method (implicit promotion is deprecated, E0079)
pub extend SseMessage with Eq::{equal}

///|
#deprecated("Use `!=` instead", skip_current_package=true)
#doc(hidden)
pub extend SseMessage with Eq::{not_equal}

///|
#deprecated("Use `Debug::to_repr` instead", skip_current_package=true)
#doc(hidden)
pub extend SseMessage with @moonbitlang/core/debug.Debug::{to_repr}

///|
/// 解析单个 SSE 消息块为 SseMessage
///
/// 输入为一个消息块的文本（不含尾部空行），例如：
///   "event: content_block_delta\ndata: {\"type\":\"text_delta\",\"text\":\"hello\"}"
///
/// 返回 None 表示空块或纯注释块。
pub fn parse_sse_message(msg_block : String) -> SseMessage? {
  let normalized = msg_block
    .replace_all(old="\r\n", new="\n")
    .replace_all(old="\r", new="\n")
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
  Some({ event_type, data: data_parts.join("\n"), })
}

///|
/// 从 SSE 流中解析所有消息
///
/// 按 `\n\n` 分割消息块，逐块解析为 SseMessage。
/// 跳过空块和纯注释块。
pub fn parse_sse_messages(sse_str : String) -> Array[SseMessage] {
  let messages : Array[SseMessage] = []
  // HTTP/SSE streams commonly use CRLF; normalize all line endings first.
  // 注意：必须用 replace_all —— String::replace 只替换首次出现（MoonBit 语义），
  // 用 replace 会导致第 2 个及以后的 CRLF 残留，使多帧流被并成一块。
  let normalized = sse_str
    .replace_all(old="\r\n", new="\n")
    .replace_all(old="\r", new="\n")
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

///|
/// ═══ 增量帧分割（T5，流式宿主逐 chunk 喂入）═══
/// 既有 parse_sse_messages 是全缓冲版（split("\n\n")）；本组提供
/// chunk-boundary-safe 的增量分割器，供中转中间件逐 chunk 转发。

///|
/// 查找第一个空行分隔符（"\n\n"）的位置；未找到返回 None
fn find_blank_line(s : String) -> Int32? {
  let mut i = 0
  while i + 1 < s.length() {
    if s[i] == '\n' && s[i + 1] == '\n' {
      return Some(i)
    }
    i = i + 1
  }
  None
}

///|
/// SseFrameSplitter — 增量 SSE 帧分割器
///
/// 喂入任意边界的 chunk，输出完整帧（消息块文本，不含空行分隔符）；
/// 跨 chunk 的半帧在内部缓冲。特性：
/// - CRLF / CR / LF 三种行尾统一归一化为 LF
/// - 正确处理切在 `\r`|`\n` 边界的 chunk（pending_cr 挂起机制：
///    chunk 尾部独立 `\r` 挂起，下一 chunk 首字符为 `\n` 则配对消费，
///   否则该 `\r` 是独立行尾，补一个 `\n`）
/// - 空帧（纯注释/空白）不产出
///
/// 用法：
/// ```moonbit nocheck
/// let splitter = SseFrameSplitter::new()
///
/// let frames = splitter.feed(chunk) // 可能为空（半帧缓冲中）
///
/// let tail = splitter.flush() // 流结束冲刷尾部半帧
/// ```
pub struct SseFrameSplitter {
  mut buffer : String
  mut pending_cr : Bool
}

///|
pub fn SseFrameSplitter::new() -> SseFrameSplitter {
  { buffer: "", pending_cr: false, }
}

///|
/// 喂入一个 chunk，返回其中包含的完整帧数组（可能为空）
pub fn SseFrameSplitter::feed(
  self : SseFrameSplitter,
  chunk : String,
) -> Array[String] {
  let mut s = chunk
  // 上一 chunk 挂起的 \r：与首字符 \n 配对则吃掉重复，否则补独立行尾
  if self.pending_cr {
    self.pending_cr = false
    if s.length() > 0 && s[0] == '\n' {
      s = s[1:].to_owned()
    }
    s = "\n" + s
  }
  // 本 chunk 以 \r 结尾：挂起等下一 chunk（避免 \r|\n 被切成两个行尾）
  if s.length() > 0 && s[s.length() - 1] == '\r' {
    self.pending_cr = true
    s = s[0:s.length() - 1].to_owned()
  }
  let normalized = s
    .replace_all(old="\r\n", new="\n")
    .replace_all(old="\r", new="\n")
  self.buffer = self.buffer + normalized
  self.extract_frames()
}

///|
/// 从缓冲区切出所有完整帧（空行分隔）；纯注释/空白帧不产出
/// （复用 parse_sse_message 的语义：None 表示空块或纯注释块）
fn SseFrameSplitter::extract_frames(self : SseFrameSplitter) -> Array[String] {
  let frames : Array[String] = []
  while true {
    match find_blank_line(self.buffer) {
      Some(pos) => {
        let frame = self.buffer[0:pos].to_owned()
        self.buffer = self.buffer[pos + 2:].to_owned()
        match parse_sse_message(frame) {
          Some(_) => frames.push(frame)
          None => ()
        }
      }
      None => break
    }
  }
  frames
}

///|
/// 流结束：冲刷缓冲区中剩余的不完整帧（无尾部空行的流）
///
/// 挂起的 pending_cr 是一个未完结的行尾，先补 "\n" 再切帧，
/// 避免尾部半帧的行尾信息丢失。
pub fn SseFrameSplitter::flush(self : SseFrameSplitter) -> Array[String] {
  if self.pending_cr {
    self.buffer = self.buffer + "\n"
    self.pending_cr = false
  }
  let frames = self.extract_frames()
  let rest = self.buffer
  self.buffer = ""
  if rest.trim() == "" {
    frames
  } else {
    match parse_sse_message(rest) {
      Some(_) => {
        frames.push(rest)
        frames
      }
      None => frames
    }
  }
}
