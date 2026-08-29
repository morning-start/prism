///|
/// LucentRequest JSON 反序列化
pub fn LucentRequest::from_json(jv : Json) -> Result[LucentRequest, String] {
  match jv {
    Object(m) => {
      let schema_version = match get_str(m, "schema_version") {
        Ok(s) => s
        Err(e) => return Err(e)
      }
      let model = match get_str(m, "model") {
        Ok(s) => s
        Err(e) => return Err(e)
      }
      let instructions : Array[LucentContent]? = match m.get("instructions") {
        Some(Array(items)) => parse_content_opt(items)
        _ => None
      }
      let conversation = match get_arr_item(m, "conversation") {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      let tools : Array[LucentTool]? = match m.get("tools") {
        Some(Array(items)) =>
          match parse_tool_arr(items) {
            Ok(arr) => Some(arr)
            Err(_) => None
          }
        _ => None
      }
      let tool_choice : LucentToolChoice? = match m.get("tool_choice") {
        Some(tc) =>
          match LucentToolChoice::from_json(tc) {
            Ok(v) => Some(v)
            Err(_) => None
          }
        None => None
      }
      let options = match m.get("options") {
        Some(o) =>
          match LucentOptions::from_json(o) {
            Ok(v) => v
            Err(e) => return Err(e)
          }
        None => return Err("missing options")
      }
      let capabilities : LucentCapabilities? = match m.get("capabilities") {
        Some(c) =>
          match LucentCapabilities::from_json(c) {
            Ok(v) => Some(v)
            Err(_) => None
          }
        None => None
      }
      let reasoning : LucentReasoningConfig? = match m.get("reasoning") {
        Some(r) =>
          match LucentReasoningConfig::from_json(r) {
            Ok(v) => Some(v)
            Err(_) => None
          }
        None => None
      }
      let metadata : Map[String, String]? = match m.get("metadata") {
        Some(Object(map)) => {
          let result : Map[String, String] = Map([])
          for entry in map {
            match entry {
              (k, v) =>
                match v {
                  String(s) => result[k] = s
                  _ => ()
                }
            }
          }
          Some(result)
        }
        _ => None
      }
      let extra : Map[String, Json]? = match m.get("extra") {
        Some(Object(map)) => Some(map)
        _ => None
      }
      Ok({
        schema_version,
        model,
        instructions,
        conversation,
        tools,
        tool_choice,
        options,
        capabilities,
        reasoning,
        metadata,
        extra,
      })
    }
    _ => Err("expected object for LucentRequest")
  }
}

///|
/// === LucentUsage ===
