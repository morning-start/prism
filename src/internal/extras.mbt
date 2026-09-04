///|
/// extras（扩展字段）处理 — Provider 适配器共用
///
/// 四个 provider 的 request_decode / request_encode 对 `extras` 的处理
/// 完全同构：解码时收集未知顶层字段，编码时合并回 JSON。集中于此避免
/// 逐 provider 复制（标准：扩展字段必须可选、未知字段不得使反序列化失败）。

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
/// 将 extras Map 合并到 JSON 编码的 parts 数组中
///
/// 四个 provider 的 request_encode 中都有相同的 extras 合并逻辑：
/// ```
/// match opts.extras {
///   Some(m) => for k, v in m { parts.push("\"" + json_escape(k) + "\":" + v.stringify()) }
///   None => ()
/// }
/// ```
/// 此 helper 封装该模式，接收 parts 数组（引用语义）和 extras（可选 Map）。
pub fn merge_extras_json(
  parts : Array[String],
  extras : Map[String, Json]?,
) -> Unit {
  match extras {
    Some(m) =>
      for k, v in m {
        parts.push("\"" + json_escape(k) + "\":" + v.stringify())
      }
    None => ()
  }
}

///|
/// 从 extras Map 中移除指定键（返回新 Map；移除后为空返回 None）
pub fn extras_without(
  extras : Map[String, Json]?,
  key : String,
) -> Map[String, Json]? {
  match extras {
    Some(m) => {
      let nm : Map[String, Json] = Map([])
      for k, v in m {
        if k != key {
          nm[k] = v
        }
      }
      if nm.is_empty() {
        None
      } else {
        Some(nm)
      }
    }
    None => None
  }
}
