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
