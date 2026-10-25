///|
/// 请求解码形状守卫 — 4 端 request decode 入口共用（TASK-4b，QA P1-1）。
/// 落点 meta：四端共享、依赖 lux 诊断类型（extras.mbt / finish.mbt 先例）；
/// 不放 internal（底层原语层不反向依赖 lux）。

///|
/// 请求解码顶层形状守卫 — 4 端 request decode 入口共用（TASK-4b，QA P1-1）
///
/// 背景：此前「可解析但结构畸形」的请求文档（顶层数组/标量）会静默降级为
/// 空 IR 请求且 0 诊断——错型 body 被转成带默认 max_tokens 的空请求发往
/// 下游，违反「绝不静默丢弃」。response 通路对同形态显式报错，此处对齐。
///
/// 契约：顶层必须是 JSON Object，否则返回 Err（不产出 IR）。
pub fn require_request_object(json : Json) -> Result[Unit, String] {
  match json {
    Object(_) => Ok(())
    _ => Err("request document must be a JSON object")
  }
}

///|
/// 请求解码关键字段类型守卫 — messages/contents 这类「字段本体应为数组」
/// 的载体适用（TASK-4b）。
///
/// 契约：字段存在但既非 Array 也非 Null → Invalid 诊断（调用方继续按缺失
/// 处理，回退安全默认值——对齐 encode 端 Invalid 既有契约）；缺失 / 数组 /
/// null 均放行。responses 的 input 是 string|Array 多态载体，用
/// `require_request_field_flexible`。
pub fn require_request_array_field(
  json : Json,
  field : String,
  diagnostics : Array[@lux.ConversionDiagnostic],
) -> Unit {
  match @internal.obj_get(json, field) {
    Some(Array(_)) | Some(Null) | None => ()
    Some(other) => {
      let msg = "request field \"" +
        field +
        "\" must be an array, got " +
        json_kind(other) +
        "; ignored"
      diagnostics.push(@lux.ConversionDiagnostic::invalid(field, Some(msg)))
    }
  }
}

///|
/// 请求解码关键字段类型守卫（多态载体版）— responses `input` 专用（TASK-4b）
///
/// `input` 官方契约是 `string | Array[item]`；存在但两者皆非（且非 null）
/// → Invalid 诊断，其余放行。
pub fn require_request_field_flexible(
  json : Json,
  field : String,
  diagnostics : Array[@lux.ConversionDiagnostic],
) -> Unit {
  match @internal.obj_get(json, field) {
    Some(String(_)) | Some(Array(_)) | Some(Null) | None => ()
    Some(other) => {
      let msg = "request field \"" +
        field +
        "\" must be a string or an array, got " +
        json_kind(other) +
        "; ignored"
      diagnostics.push(@lux.ConversionDiagnostic::invalid(field, Some(msg)))
    }
  }
}

///|
/// JSON 值的种类名（诊断文案用）
fn json_kind(json : Json) -> String {
  match json {
    Object(_) => "object"
    Array(_) => "array"
    String(_) => "string"
    Number(_) => "number"
    True | False => "boolean"
    Null => "null"
  }
}
