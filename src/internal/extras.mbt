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
/// extras 合并的键撞名检测（纯函数，不依赖 lux 诊断类型）。
///
/// 返回与 `parts` 中任一已编码片段同名的 extras 键。**为什么必须检测**：
/// `parts` 的每个元素都是一个已编码的 `"key":value` 片段，而 extras 是直接
/// 字符串拼接在末尾的。若 extras 里存在与 body 已发出的键同名的条目（跨协议
/// 中转时很常见 —— 例如把含 `messages` 的 body 按 responses 解码，`messages`
/// 落入 extras，再编码到 messages 目标时又与编码器自己发出的 `messages`
/// 撞名），结果就是同一对象里出现**重复键**：严格 JSON 解析器拒绝，宽容
/// 解析器静默丢弃先前那个键 —— 两者都不是想要的语义。
///
/// 调用方对返回的每个键打 Degraded 诊断并跳过写入（不是"无损"：它来自源
/// 协议的 wire 字段，与目标协议按 IR 重新编码出的同名字段语义不同）。
fn extras_colliding_keys(
  parts : Array[String],
  extras : Map[String, Json]?,
) -> Array[String] {
  let out : Array[String] = []
  match extras {
    Some(m) =>
      for k, _ in m {
        let prefix = "\"" + json_escape(k) + "\":"
        let mut collides = false
        for part in parts {
          if part.has_prefix(prefix) {
            collides = true
          }
        }
        if collides {
          out.push(k)
        }
      }
    None => ()
  }
  out
}

///|
/// 合并 extras 到已编码片段数组，**跳过**与已有键撞名的条目，返回被跳过的键。
///
/// 这是 `merge_extras_json` 的安全版本：调用方应先检查返回值非空，并为每个
/// 被跳过的键补一条 Degraded 诊断 —— 该键来自源协议 wire，与目标协议按 IR
/// 重新编码出的同名字段语义不同，丢弃必须显式。
pub fn merge_extras_json_dedup(
  parts : Array[String],
  extras : Map[String, Json]?,
) -> Array[String] {
  let dropped = extras_colliding_keys(parts, extras)
  match extras {
    Some(m) =>
      for k, v in m {
        if !dropped.contains(k) {
          parts.push("\"" + json_escape(k) + "\":" + v.stringify())
        }
      }
    None => ()
  }
  dropped
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
