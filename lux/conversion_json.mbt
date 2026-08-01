///|
/// 转换信封 JSON 编解码 — ConversionStatus / ConversionDiagnostic / ConversionResult
///
/// 让 Exact/Degraded/Unsupported/Invalid 成为可检测的协议输出。
/// JSON 形状：
///   ConversionStatus:    "exact" | "degraded" | "unsupported" | "invalid"
///   ConversionDiagnostic: {"field":"...","status":"...","detail":"..."}
///   ConversionResult:     {"value":<T>,"diagnostics":[...]}
///   envelope_json:        {"value":<value_json>,"diagnostics":[...]}

///|
/// === ConversionStatus ===

///|
pub fn ConversionStatus::to_json(self : ConversionStatus) -> Json {
  match self {
    Exact => Json::string("exact")
    Degraded => Json::string("degraded")
    Unsupported => Json::string("unsupported")
    Invalid => Json::string("invalid")
  }
}

///|
pub fn ConversionStatus::from_json(
  jv : Json,
) -> Result[ConversionStatus, String] {
  match jv {
    String(s) =>
      match s {
        "exact" => Ok(Exact)
        "degraded" => Ok(Degraded)
        "unsupported" => Ok(Unsupported)
        "invalid" => Ok(Invalid)
        _ => Err("unknown ConversionStatus: " + s)
      }
    _ => Err("expected string for ConversionStatus")
  }
}

///|
/// === ConversionDiagnostic ===

///|
pub fn ConversionDiagnostic::to_json(self : ConversionDiagnostic) -> Json {
  let fields : Map[String, Json] = {
    "field": Json::string(self.field),
    "status": self.status.to_json(),
  }
  match self.detail {
    Some(d) => fields.set("detail", Json::string(d))
    None => ()
  }
  Json::object(fields)
}

///|
pub fn ConversionDiagnostic::from_json(
  jv : Json,
) -> Result[ConversionDiagnostic, String] {
  match jv {
    Object(map) => {
      let field = match map.get("field") {
        Some(String(s)) => s
        _ => return Err("missing or invalid field for ConversionDiagnostic")
      }
      let status = match map.get("status") {
        Some(v) =>
          match ConversionStatus::from_json(v) {
            Ok(s) => s
            Err(e) => return Err(e)
          }
        None => return Err("missing status for ConversionDiagnostic")
      }
      let detail = match map.get("detail") {
        Some(String(s)) => Some(s)
        _ => None
      }
      Ok(ConversionDiagnostic::new(field, status, detail))
    }
    _ => Err("expected object for ConversionDiagnostic")
  }
}

///|
/// === ConversionResult ===

///|
/// 序列化：value 由调用方提供编码函数，diagnostics 统一编码。
pub fn[T] ConversionResult::to_json(
  self : ConversionResult[T],
  encode : (T) -> Json,
) -> Json {
  let diags : Array[Json] = self.diagnostics.map(fn(d) { d.to_json() })
  let fields : Map[String, Json] = {
    "value": encode(self.value),
    "diagnostics": Json::array(diags),
  }
  Json::object(fields)
}

///|
/// 反序列化：value 由调用方提供解码函数。
pub fn[T] ConversionResult::from_json(
  jv : Json,
  decode : (Json) -> Result[T, String],
) -> Result[ConversionResult[T], String] {
  match jv {
    Object(map) => {
      let value = match map.get("value") {
        Some(v) =>
          match decode(v) {
            Ok(t) => t
            Err(e) => return Err("value decode failed: " + e)
          }
        None => return Err("missing value for ConversionResult")
      }
      let mut result = ConversionResult::new(value)
      match map.get("diagnostics") {
        Some(Array(arr)) =>
          for item in arr {
            match ConversionDiagnostic::from_json(item) {
              Ok(d) => result = result.with_diagnostic(d)
              Err(e) => return Err("diagnostic decode failed: " + e)
            }
          }
        _ => ()
      }
      Ok(result)
    }
    _ => Err("expected object for ConversionResult")
  }
}

///|
/// 信封 JSON：`{"value":<value_json>,"diagnostics":[...]}`（WASM/SDK 边界用）。
pub fn[T] ConversionResult::envelope_json(
  self : ConversionResult[T],
  value_json : Json,
) -> Json {
  let diags : Array[Json] = self.diagnostics.map(fn(d) { d.to_json() })
  let fields : Map[String, Json] = {
    "value": value_json,
    "diagnostics": Json::array(diags),
  }
  Json::object(fields)
}
