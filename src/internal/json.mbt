///|
/// JSON 解析辅助 — Provider 适配器共用
///
/// 所有 `field_*` / `obj_get` 均为纯函数，接收 `Json` + `key` 返回结果。
/// 调用方按 `@internal.json.*` 使用。

///|
/// 从 JSON 对象中提取指定 key 的 Json 值
pub fn obj_get(jv : Json, key : String) -> Json? {
  match jv {
    Object(m) => m.get(key)
    _ => None
  }
}

///|
/// 提取 String 字段
pub fn field_str(jv : Json, key : String) -> String? {
  match obj_get(jv, key) {
    Some(String(s)) => Some(s)
    _ => None
  }
}

///|
/// 提取 Array[Json] 字段
pub fn field_arr(jv : Json, key : String) -> Array[Json]? {
  match obj_get(jv, key) {
    Some(Array(a)) => Some(a)
    _ => None
  }
}

///|
/// 提取 Bool 字段
pub fn field_bool(jv : Json, key : String) -> Bool? {
  match obj_get(jv, key) {
    Some(True) => Some(true)
    Some(False) => Some(false)
    _ => None
  }
}

///|
/// 提取数值字段（Double，保留小数精度）
pub fn field_num(jv : Json, key : String) -> Double? {
  match obj_get(jv, key) {
    Some(Number(n, ..)) => Some(n)
    _ => None
  }
}

///|
/// 提取整数字段
pub fn field_int(jv : Json, key : String) -> Int? {
  match obj_get(jv, key) {
    Some(Number(n, ..)) => Some(n.to_int())
    _ => None
  }
}

///|
/// 提取数值字段（Int，直接读不经过 Double）
pub fn field_int_exact(jv : Json, key : String) -> Int? {
  match obj_get(jv, key) {
    Some(Number(n, ..)) =>
      // ignore decimal repr, check if the number's integer value is exact
      if n.to_int().to_double() == n {
        Some(n.to_int())
      } else {
        None
      }
    _ => None
  }
}

///|
/// 清理 JSON 字符串中的 SSE 心跳标记
///
/// 某些 SSE 实现会在数据后附加心跳标记（如 `: keep-alive`），
/// 或把心跳注释行错误合并进 JSON payload（产生 `\: keep-alive.` 等
/// 无效转义序列），导致 JSON 字符串中混入非法内容。此函数移除这些标记。
pub fn clean_sse_heartbeat(s : String) -> String {
  let mut result = s.trim_end().to_owned()
  // 第一类：带反斜杠的心跳片段（`\:` 是非法 JSON 转义，正常数据中不会出现，
  // 只可能来自心跳行被错误合并进 payload，可安全全局移除）
  let escaped_patterns = [
    "\\: keep-alive.", "\\: keep-alive", "\\:keep-alive.", "\\:keep-alive", "\\: heartbeat.",
    "\\: heartbeat", "\\:heartbeat.", "\\:heartbeat",
  ]
  let mut k = 0
  while k < escaped_patterns.length() {
    result = result.replace(old=escaped_patterns[k], new="")
    k = k + 1
  }
  // 第二类：无反斜杠心跳标记（可能带句点），仅移除字符串末尾的标记
  let heartbeat_patterns = [
    ": keep-alive.", ": keep-alive", ":keep-alive.", ":keep-alive", ": heartbeat.",
    ": heartbeat", ":heartbeat.", ":heartbeat",
  ]
  let mut j = 0
  while j < heartbeat_patterns.length() {
    let pattern = heartbeat_patterns[j]
    // 允许 result 恰好等于 pattern（纯心跳行）
    if result.length() >= pattern.length() {
      let suffix = result[result.length() - pattern.length():result.length()].to_owned()
      if suffix == pattern {
        result = result[0:result.length() - pattern.length()].to_owned()
      }
    }
    j = j + 1
  }
  result
}

///|
/// 检测 JSON 字符串是否被截断
///
/// 检查常见截断模式：
/// - 字符串未闭合（奇数个未转义引号）
/// - 对象/数组未闭合（括号不匹配）
pub fn is_json_truncated(s : String) -> Bool {
  let mut in_string = false
  let mut escape_next = false
  let mut brace_depth = 0
  let mut bracket_depth = 0
  let mut i = 0
  while i < s.length() {
    let cp = s[i]
    if escape_next {
      escape_next = false
      i = i + 1
      continue
    }
    if cp == '\\' && in_string {
      escape_next = true
      i = i + 1
      continue
    }
    if cp == '"' {
      in_string = !in_string
    }
    if !in_string {
      if cp == '{' {
        brace_depth = brace_depth + 1
      } else if cp == '}' {
        brace_depth = brace_depth - 1
      } else if cp == '[' {
        bracket_depth = bracket_depth + 1
      } else if cp == ']' {
        bracket_depth = bracket_depth - 1
      }
    }
    i = i + 1
  }
  // 截断条件：字符串未闭合 或 括号不匹配
  in_string || brace_depth != 0 || bracket_depth != 0
}

///|
/// 清理 JSON 字符串中的无效转义序列
///
/// 某些 API（如 OpenAI）可能在字符串字段中包含非标准转义（如 `\:`），
/// 导致标准 JSON 解析器失败。此函数将无效转义 `\X` 替换为 `\\X`。
pub fn sanitize_json_escapes(s : String) -> String {
  let sb = StringBuilder()
  let mut i = 0
  while i < s.length() {
    let cp = s[i]
    if cp == '\\' && i + 1 < s.length() {
      let next = s[i + 1]
      // 有效 JSON 转义: ", \, /, b, f, n, r, t, uXXXX
      if next == '"' ||
        next == '\\' ||
        next == '/' ||
        next == 'b' ||
        next == 'f' ||
        next == 'n' ||
        next == 'r' ||
        next == 't' ||
        next == 'u' {
        sb.write_char(Int::unsafe_to_char(cp.to_int()))
        sb.write_char(Int::unsafe_to_char(next.to_int()))
        i = i + 2
      } else {
        // 无效转义：转义反斜杠本身
        sb.write_string("\\\\")
        sb.write_char(Int::unsafe_to_char(next.to_int()))
        i = i + 2
      }
    } else {
      sb.write_char(Int::unsafe_to_char(cp.to_int()))
      i = i + 1
    }
  }
  sb.to_string()
}

///|
/// JSON 字符串转义（用于 SSE 手动拼接等非标准输出）
pub fn json_escape(s : String) -> String {
  let sb = StringBuilder()
  let mut i = 0
  while i < s.length() {
    let cp = s[i]
    if cp == '"' {
      sb.write_string("\\\"")
    } else if cp == '\\' {
      sb.write_string("\\\\")
    } else if cp == '\n' {
      sb.write_string("\\n")
    } else if cp == '\t' {
      sb.write_string("\\t")
    } else if cp == '\r' {
      sb.write_string("\\r")
    } else {
      sb.write_char(Int::unsafe_to_char(cp.to_int()))
    }
    i = i + 1
  }
  sb.to_string()
}

///|
/// Map 不保证顺序，因此重建为 Object
pub fn obj_set(jv : Json, key : String, value : Json) -> Json {
  match jv {
    Object(m) => {
      m[key] = value
      Json::object(m)
    }
    _ => value
  }
}

///|
/// 在 JSON 对象中删除一个键（重建 Object）
pub fn obj_delete(jv : Json, key : String) -> Json {
  match jv {
    Object(m) => {
      let new_map : Map[String, Json] = Map([])
      for k, v in m {
        if k != key {
          new_map[k] = v
        }
      }
      Json::object(new_map)
    }
    _ => jv
  }
}

///|
/// 安全解析 JSON 字符串为 Json，失败返回 None
pub fn parse_json_opt(s : String) -> Json? {
  let v = @json.parse(s) catch { _ => return None }
  Some(v)
}

///|
/// 解析协议 JSON 字符串 → Result[Json, String]
/// 统一各 provider 解码入口的 `@json.parse catch` 样板。
pub fn parse_protocol_json(s : String) -> Result[Json, String] {
  let v = @json.parse(s) catch { _ => return Err("json parse error") }
  Ok(v)
}

///|
/// 收集 JSON 对象顶层未被已知字段消费的键值对（extras 透传）
/// 已知字段集合 = 该协议解码函数实际读取的顶层字段名。
/// 返回 None 表示无额外字段。
pub fn collect_extra_fields(
  jv : Json,
  known : Array[String],
) -> Map[String, Json]? {
  match jv {
    Object(m) => {
      let extras : Map[String, Json] = Map([])
      let mut found = false
      for k, v in m {
        if !known.contains(k) {
          extras[k] = v
          found = true
        }
      }
      if found {
        Some(extras)
      } else {
        None
      }
    }
    _ => None
  }
}

///|
/// Polymorphic content 解析辅助
///
/// LLM API 的 content 字段有三种形态：
///   - string → 单个文本内容
///   - array  → 多个内容块
///   - null / 缺失 → 空
///
/// 此函数统一处理这三种形态，对 array 中的每个元素调用 `parse_item` 回调。
///
/// 典型用法：
/// ```
/// let parts = @internal.parse_content_polymorphic(
///   msg_jv,
///   "content",
///   parse_content_block,
/// )
/// ```
pub fn parse_content_polymorphic(
  jv : Json,
  field : String,
  parse_item : (Json) -> Array[Json],
) -> Array[Json] {
  match obj_get(jv, field) {
    Some(String(s)) => [Json::string(s)]
    Some(Array(arr)) => {
      let result : Array[Json] = []
      let mut i = 0
      while i < arr.length() {
        let items = parse_item(arr[i])
        let mut j = 0
        while j < items.length() {
          result.push(items[j])
          j = j + 1
        }
        i = i + 1
      }
      result
    }
    _ => []
  }
}

///|
/// 从 JSON 对象中提取 content 字段为字符串数组（简化版）
///
/// 处理 content 的 string/array/null 三态，返回纯文本片段数组。
/// 适用于只关心文本内容、不需要结构化解析的场景。
pub fn extract_text_content(jv : Json, field : String) -> Array[String] {
  match obj_get(jv, field) {
    Some(String(s)) => [s]
    Some(Array(arr)) => {
      let result : Array[String] = []
      let mut i = 0
      while i < arr.length() {
        match arr[i] {
          String(s) => result.push(s)
          Object(_) =>
            match field_str(arr[i], "text") {
              Some(t) => result.push(t)
              None => ()
            }
          _ => ()
        }
        i = i + 1
      }
      result
    }
    _ => []
  }
}

///|
/// 内容块序列化辅助 — 单 text part 快速路径
///
/// LLM API 的 content 字段常见优化：当只有一个 text 类型的内容块时，
/// 直接序列化为字符串而非数组。此函数封装该逻辑。
///
/// 参数：
///   - `parts`：内容块数组
///   - `is_text`：判断某个 part 是否为 text 类型
///   - `get_text`：从 text part 提取文本
///   - `serialize_array`：多 part 时的数组序列化回调
///
/// 返回：序列化后的字符串（单 text 时为纯字符串，否则为数组 JSON）
pub fn[T] serialize_content_with_text_optimization(
  parts : Array[T],
  is_text : (T) -> Bool,
  get_text : (T) -> String,
  serialize_array : (Array[T]) -> String,
) -> String {
  if parts.length() == 1 && is_text(parts[0]) {
    get_text(parts[0])
  } else {
    serialize_array(parts)
  }
}

///|
/// 从 JSON 对象中解析 token 用量
///
/// 统一四个适配器的 usage 解析模式。每个协议的字段名不同：
/// - OpenAI: `prompt_tokens` / `completion_tokens` / `total_tokens`
/// - Anthropic: `input_tokens` / `output_tokens`（无 total，需计算）
/// - Responses: `input_tokens` / `output_tokens` / `total_tokens`
/// - Gemini: `promptTokenCount` / `candidatesTokenCount` / `totalTokenCount`
///
/// `tt_key` 为 None 时，total = pt + ct。
pub fn parse_usage_json(
  u : Json,
  pt_key : String,
  ct_key : String,
  tt_key : String?,
) -> (Int, Int, Int) {
  let pt = field_int(u, pt_key).unwrap_or(0)
  let ct = field_int(u, ct_key).unwrap_or(0)
  let tt = match tt_key {
    Some(key) => field_int(u, key).unwrap_or(pt + ct)
    None => pt + ct
  }
  (pt, ct, tt)
}
