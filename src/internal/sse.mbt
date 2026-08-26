///|
/// SSE 行解析辅助 — Provider 适配器共用
///
/// 提供 SSE（Server-Sent Events）行的通用解析能力。
/// 支持 event: 和 data: 前缀的逐字符识别。

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
  // 检查 "event: " 前缀（至少 7 个字符）
  let has_event = l_str.length() >= 7 &&
    l_str[0] == 'e' &&
    l_str[1] == 'v' &&
    l_str[2] == 'e' &&
    l_str[3] == 'n' &&
    l_str[4] == 't' &&
    l_str[5] == ':' &&
    l_str[6] == ' '
  if has_event {
    let mut event_type = ""
    let mut k = 7
    while k < l_str.length() {
      let ch = Int::unsafe_to_char(l_str[k].to_int())
      event_type = event_type + "\{ch}"
      k = k + 1
    }
    return Some({ event: Some(event_type), data: None })
  }
  // 检查 "data: " 前缀（至少 5 个字符，或精确匹配 "data:" 4 字符）
  let is_data_long = l_str.length() >= 6 &&
    l_str[0] == 'd' &&
    l_str[1] == 'a' &&
    l_str[2] == 't' &&
    l_str[3] == 'a' &&
    l_str[4] == ':' &&
    l_str[5] == ' '
  if is_data_long {
    let mut data_str = ""
    let mut k = 6
    while k < l_str.length() {
      let ch = Int::unsafe_to_char(l_str[k].to_int())
      data_str = data_str + "\{ch}"
      k = k + 1
    }
    return Some({ event: None, data: Some(data_str) })
  }
  // 检查无空格 "data:"（4 字符）
  let is_data_short = l_str.length() >= 5 &&
    l_str[0] == 'd' &&
    l_str[1] == 'a' &&
    l_str[2] == 't' &&
    l_str[3] == 'a' &&
    l_str[4] == ':'
  if is_data_short {
    let mut data_str = ""
    let mut k = 5
    while k < l_str.length() {
      let ch = Int::unsafe_to_char(l_str[k].to_int())
      data_str = data_str + "\{ch}"
      k = k + 1
    }
    return Some({ event: None, data: Some(data_str) })
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
  let mut i = 0
  while i < lines.length() {
    let line = lines[i].to_owned()
    // 空行表示事件边界
    if line.trim() == "" {
      if current_data.length() > 0 {
        events.push(current_data.join("\n"))
        current_data = []
      }
      i = i + 1
      continue
    }
    // 跳过注释行（以 : 开头，如心跳 : keep-alive）
    if line.length() > 0 && line[0] == ':' {
      i = i + 1
      continue
    }
    // 检查 data: 前缀
    let is_data = line.length() >= 5 &&
      line[0] == 'd' &&
      line[1] == 'a' &&
      line[2] == 't' &&
      line[3] == 'a' &&
      line[4] == ':'
    if is_data {
      // 提取 data: 后的内容
      let mut payload = ""
      let mut p = 5
      // 跳过 data: 后的可选空格
      if p < line.length() && line[p] == ' ' {
        p = p + 1
      }
      while p < line.length() {
        let ch = Int::unsafe_to_char(line[p].to_int())
        payload = payload + "\{ch}"
        p = p + 1
      }
      current_data.push(payload)
    }
    // 忽略其他行（event: 等）
    i = i + 1
  }
  // 处理最后一个事件（如果没有尾部空行）
  if current_data.length() > 0 {
    events.push(current_data.join("\n"))
  }
  events
}
