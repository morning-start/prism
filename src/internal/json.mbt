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
