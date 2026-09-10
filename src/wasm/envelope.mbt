///|
/// WASM JSON envelope helpers.
///
/// Every host-facing result uses the same object shape. Error messages are
/// encoded as Json values instead of being interpolated into raw JSON.

///|
fn wasm_envelope(value : Json) -> String {
  let fields : Map[String, Json] = {
    "value": value,
    "diagnostics": Json::array([]),
  }
  Json::object(fields).stringify()
}

///|
fn wasm_envelope_err(message : String) -> String {
  let fields : Map[String, Json] = {
    "error": Json::string(message),
    "diagnostics": Json::array([]),
  }
  Json::object(fields).stringify()
}
