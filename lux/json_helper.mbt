///|
/// JSON 解析辅助 — Provider 适配器共用
///
/// 所有 `field_*` / `obj_get` 均为纯函数，接收 `Json` + `key` 返回结果。
/// 调用方按 `@lux.json_helper.*` 使用。
///
/// 注意：这些 helper 只覆盖 `lux.Lucent*` 类型**之外的**中间 JSON 解析（即
/// 从 Provider 原生 JSON 对象中读取字段），不参与 IR 自身的序列化/反序列化。
/// IR 的序列化由 `serialize.mbt` / `deserialize.mbt` 负责。

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
    Some(Json::String(s)) => Some(s)
    _ => None
  }
}

///|
/// 提取 Array[Json] 字段
pub fn field_arr(jv : Json, key : String) -> Array[Json]? {
  match obj_get(jv, key) {
    Some(Json::Array(a)) => Some(a)
    _ => None
  }
}

///|
/// 提取 Bool 字段
pub fn field_bool(jv : Json, key : String) -> Bool? {
  match obj_get(jv, key) {
    Some(Json::True) => Some(true)
    Some(Json::False) => Some(false)
    _ => None
  }
}

///|
/// 提取数值字段（Double，保留小数精度）
pub fn field_num(jv : Json, key : String) -> Double? {
  match obj_get(jv, key) {
    Some(Json::Number(n, ..)) => Some(n)
    _ => None
  }
}

///|
/// 提取整数字段
pub fn field_int(jv : Json, key : String) -> Int? {
  match obj_get(jv, key) {
    Some(Json::Number(n, ..)) => Some(n.to_int())
    _ => None
  }
}

///|
/// 提取数值字段（Int，直接读不经过 Double）
pub fn field_int_exact(jv : Json, key : String) -> Int? {
  match obj_get(jv, key) {
    Some(Json::Number(n, dec)) =>
      if dec == 0.0 {
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
  let mut r = ""
  let mut i = 0
  while i < s.length() {
    let cp = s[i]
    if cp == '"' {
      r = r + "\\\""
    } else if cp == '\\' {
      r = r + "\\\\"
    } else if cp == '\n' {
      r = r + "\\n"
    } else if cp == '\t' {
      r = r + "\\t"
    } else if cp == '\r' {
      r = r + "\\r"
    } else {
      let ch = Char::from_int(cp.to_int())
      r = r + "\{ch}"
    }
    i = i + 1
  }
  r
}

///|
/// Map 不保证顺序，因此重建为 Object
pub fn obj_set(jv : Json, key : String, value : Json) -> Json {
  match jv {
    Object(m) => {
      m[key] = value
      Object(m)
    }
    _ => value
  }
}

///|
/// 在 JSON 对象中删除一个键（重建 Object）
pub fn obj_delete(jv : Json, key : String) -> Json {
  match jv {
    Object(m) => {
      m.delete(key)
      Object(m)
    }
    _ => jv
  }

///|
/// 安全解析 JSON 字符串为 Json，失败返回 None
pub fn parse_json_opt(s : String) -> Json? {
  @json.parse(s) catch {
    _ => None
  }
