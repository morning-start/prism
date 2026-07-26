///|
/// Lux IR explicit JSON deserialization
///
/// All `from_json()` inputs match outputs of `to_json()` in serialize.mbt.

///|
/// === Helpers ===
fn get_str(m : Map[String, Json], key : String) -> Result[String, String] {
  match m.get(key) {
    Some(Json::String(s)) => Ok(s)
    Some(_) => Err("expected string for " + key)
    None => Err("missing required field " + key)
  }
}

///|
fn get_str_opt(m : Map[String, Json], key : String) -> String? {
  match m.get(key) {
    Some(Json::String(s)) => Some(s)
    _ => None
  }
}

///|
fn get_int(m : Map[String, Json], key : String) -> Result[Int, String] {
  match m.get(key) {
    Some(Json::Number(n, ..)) => Ok(n.to_int())
    Some(_) => Err("expected number for " + key)
    None => Err("missing required field " + key)
  }
}

///|
fn get_int_opt(m : Map[String, Json], key : String) -> Int? {
  match m.get(key) {
    Some(Json::Number(n, ..)) => Some(n.to_int())
    _ => None
  }
}

///|
fn get_double_opt(m : Map[String, Json], key : String) -> Double? {
  match m.get(key) {
    Some(Json::Number(n, ..)) => Some(n)
    _ => None
  }
}

///|
fn get_bool(m : Map[String, Json], key : String) -> Result[Bool, String] {
  match m.get(key) {
    Some(Json::True) => Ok(true)
    Some(Json::False) => Ok(false)
    Some(_) => Err("expected boolean for " + key)
    None => Err("missing required field " + key)
  }
}

///|
fn get_bool_opt(m : Map[String, Json], key : String) -> Bool? {
  match m.get(key) {
    Some(Json::True) => Some(true)
    Some(Json::False) => Some(false)
    _ => None
  }
}

///|
fn get_str_arr_opt(m : Map[String, Json], key : String) -> Array[String]? {
  match m.get(key) {
    Some(Json::Array(items)) => {
      let result : Array[String] = []
      let mut i = 0
      while i < items.length() {
        match items[i] {
          Json::String(s) => result.push(s)
          _ => return None
        }
        i = i + 1
      }
      Some(result)
    }
    _ => None
  }
}

///|
fn parse_content_arr(
  items : Array[Json],
) -> Result[Array[LucentContent], String] {
  let result : Array[LucentContent] = []
  let mut i = 0
  while i < items.length() {
    match LucentContent::from_json(items[i]) {
      Ok(v) => result.push(v)
      Err(e) => return Err(e)
    }
    i = i + 1
  }
  Ok(result)
}

///|
fn parse_content_opt(items : Array[Json]) -> Array[LucentContent]? {
  match parse_content_arr(items) {
    Ok(v) => Some(v)
    Err(_) => None
  }
}

///|
fn parse_tool_arr(items : Array[Json]) -> Result[Array[LucentTool], String] {
  let result : Array[LucentTool] = []
  let mut i = 0
  while i < items.length() {
    match LucentTool::from_json(items[i]) {
      Ok(v) => result.push(v)
      Err(e) => return Err(e)
    }
    i = i + 1
  }
  Ok(result)
}

///|
fn parse_item_arr(
  items : Array[Json],
) -> Result[Array[LucentConversationItem], String] {
  let result : Array[LucentConversationItem] = []
  let mut i = 0
  while i < items.length() {
    match LucentConversationItem::from_json(items[i]) {
      Ok(v) => result.push(v)
      Err(e) => return Err(e)
    }
    i = i + 1
  }
  Ok(result)
}

///|
fn parse_choice_arr(items : Array[Json]) -> Result[Array[LucentChoice], String] {
  let result : Array[LucentChoice] = []
  let mut i = 0
  while i < items.length() {
    match LucentChoice::from_json(items[i]) {
      Ok(v) => result.push(v)
      Err(e) => return Err(e)
    }
    i = i + 1
  }
  Ok(result)
}

///|
fn parse_annotation_arr(
  items : Array[Json],
) -> Result[Array[LucentAnnotation], String] {
  let result : Array[LucentAnnotation] = []
  let mut i = 0
  while i < items.length() {
    match LucentAnnotation::from_json(items[i]) {
      Ok(v) => result.push(v)
      Err(e) => return Err(e)
    }
    i = i + 1
  }
  Ok(result)
}

///|
fn parse_provider_arr(
  items : Array[Json],
) -> Result[Array[ProviderCapability], String] {
  let result : Array[ProviderCapability] = []
  let mut i = 0
  while i < items.length() {
    match ProviderCapability::from_json(items[i]) {
      Ok(v) => result.push(v)
      Err(e) => return Err(e)
    }
    i = i + 1
  }
  Ok(result)
}

///|
fn parse_modality_arr(
  items : Array[Json],
) -> Result[Array[LucentModality], String] {
  let result : Array[LucentModality] = []
  let mut i = 0
  while i < items.length() {
    match LucentModality::from_json(items[i]) {
      Ok(v) => result.push(v)
      Err(e) => return Err(e)
    }
    i = i + 1
  }
  Ok(result)
}

///|
fn parse_safety_arr(
  items : Array[Json],
) -> Result[Array[LucentSafetyRating], String] {
  let result : Array[LucentSafetyRating] = []
  let mut i = 0
  while i < items.length() {
    match LucentSafetyRating::from_json(items[i]) {
      Ok(v) => result.push(v)
      Err(e) => return Err(e)
    }
    i = i + 1
  }
  Ok(result)
}

///|
fn get_arr_content(
  m : Map[String, Json],
  key : String,
) -> Result[Array[LucentContent], String] {
  match m.get(key) {
    Some(Json::Array(items)) => parse_content_arr(items)
    Some(_) => Err("expected array for " + key)
    None => Err("missing required field " + key)
  }
}

///|
fn get_arr_content_opt(
  m : Map[String, Json],
  key : String,
) -> Array[LucentContent]? {
  match m.get(key) {
    Some(Json::Array(items)) => parse_content_opt(items)
    _ => None
  }
}

///|
fn get_arr_item(
  m : Map[String, Json],
  key : String,
) -> Result[Array[LucentConversationItem], String] {
  match m.get(key) {
    Some(Json::Array(items)) => parse_item_arr(items)
    Some(_) => Err("expected array for " + key)
    None => Err("missing required field " + key)
  }
}

///|
fn get_arr_choice(
  m : Map[String, Json],
  key : String,
) -> Result[Array[LucentChoice], String] {
  match m.get(key) {
    Some(Json::Array(items)) => parse_choice_arr(items)
    Some(_) => Err("expected array for " + key)
    None => Err("missing required field " + key)
  }
}

///|
fn get_arr_annotation(
  m : Map[String, Json],
  key : String,
) -> Result[Array[LucentAnnotation], String] {
  match m.get(key) {
    Some(Json::Array(items)) => parse_annotation_arr(items)
    Some(_) => Err("expected array for " + key)
    None => Err("missing required field " + key)
  }
}

///|
fn get_arr_provider(
  m : Map[String, Json],
  key : String,
) -> Result[Array[ProviderCapability], String] {
  match m.get(key) {
    Some(Json::Array(items)) => parse_provider_arr(items)
    Some(_) => Err("expected array for " + key)
    None => Err("missing required field " + key)
  }
}

///|
fn get_arr_modality(
  m : Map[String, Json],
  key : String,
) -> Result[Array[LucentModality], String] {
  match m.get(key) {
    Some(Json::Array(items)) => parse_modality_arr(items)
    Some(_) => Err("expected array for " + key)
    None => Err("missing required field " + key)
  }
}

///|
/// @deprecated 保留未用
// fn get_arr_safety(
//   m : Map[String, Json],
//   key : String,
// ) -> Result[Array[LucentSafetyRating], String] {
//   match m.get(key) {
//     Some(Json::Array(items)) => parse_safety_arr(items)
//     Some(_) => Err("expected array for " + key)
//     None => Err("missing required field " + key)
//   }
// }

///|
/// === LucentModality ===
pub fn LucentModality::from_json(jv : Json) -> Result[LucentModality, String] {
  match jv {
    Json::String(s) =>
      match LucentModality::from_string(s) {
        Some(m) => Ok(m)
        None => Ok(Native(s))
      }
    _ => Err("expected string for LucentModality")
  }
}

///|
/// === LucentMediaSource ===
pub fn LucentMediaSource::from_json(
  jv : Json,
) -> Result[LucentMediaSource, String] {
  match jv {
    Json::Object(m) => {
      let typ = match get_str(m, "type") {
        Ok(t) => t
        Err(e) => return Err(e)
      }
      let data : String = match get_str_opt(m, "data") {
        Some(d) => d
        None => ""
      }
      match typ {
        "inline" => Ok(Inline(data))
        "url" => Ok(Url(data))
        "file_uri" => Ok(FileUri(data))
        _ => Err("unknown media source type: " + typ)
      }
    }
    _ => Err("expected object for LucentMediaSource")
  }
}

///|
/// === LucentMultimedia ===
pub fn LucentMultimedia::from_json(
  jv : Json,
) -> Result[LucentMultimedia, String] {
  match jv {
    Json::Object(m) => {
      let media_type = match get_str(m, "media_type") {
        Ok(s) => s
        Err(e) => return Err(e)
      }
      let source = match m.get("source") {
        Some(src) =>
          match LucentMediaSource::from_json(src) {
            Ok(s) => s
            Err(e) => return Err(e)
          }
        None => return Err("missing source")
      }
      Ok({ media_type, source })
    }
    _ => Err("expected object for LucentMultimedia")
  }
}

///|
/// === LucentAnnotationKind ===
pub fn LucentAnnotationKind::from_json(
  jv : Json,
) -> Result[LucentAnnotationKind, String] {
  match jv {
    Json::String(s) =>
      match s {
        "url" => Ok(Url)
        "file_citation" => Ok(FileCitation)
        "web_search_citation" => Ok(WebSearchCitation)
        _ => Ok(Native(s))
      }
    _ => Err("expected string for LucentAnnotationKind")
  }
}

///|
/// === LucentAnnotation ===
pub fn LucentAnnotation::from_json(
  jv : Json,
) -> Result[LucentAnnotation, String] {
  match jv {
    Json::Object(m) => {
      let km = match m.get("kind") {
        Some(k) =>
          match LucentAnnotationKind::from_json(k) {
            Ok(v) => v
            Err(e) => return Err(e)
          }
        None => return Err("missing kind")
      }
      let text = get_str_opt(m, "text")
      let reference = get_str_opt(m, "ref")
      let start = get_int_opt(m, "start")
      let end_ = get_int_opt(m, "end")
      Ok({ kind: km, text, reference, start, end: end_ })
    }
    _ => Err("expected object for LucentAnnotation")
  }
}

///|
/// === LucentThinking ===
pub fn LucentThinking::from_json(jv : Json) -> Result[LucentThinking, String] {
  match jv {
    Json::Object(m) => {
      let text = match get_str(m, "text") {
        Ok(s) => s
        Err(e) => return Err(e)
      }
      let signature = get_str_opt(m, "signature")
      let redacted = match get_bool(m, "redacted") {
        Ok(b) => b
        Err(e) => return Err(e)
      }
      let summary_opt : Array[LucentContent]? = get_arr_content_opt(
        m, "summary",
      )
      Ok({ text, signature, redacted, summary: summary_opt })
    }
    _ => Err("expected object for LucentThinking")
  }
}

///|
/// === LucentToolUse ===
pub fn LucentToolUse::from_json(jv : Json) -> Result[LucentToolUse, String] {
  match jv {
    Json::Object(m) => {
      let id = match get_str(m, "id") {
        Ok(s) => s
        Err(e) => return Err(e)
      }
      let name = match get_str(m, "name") {
        Ok(s) => s
        Err(e) => return Err(e)
      }
      let arguments_json = match get_str(m, "arguments") {
        Ok(s) => s
        Err(e) => return Err(e)
      }
      Ok({ id, name, arguments_json, arguments_value: None })
    }
    _ => Err("expected object for LucentToolUse")
  }
}

///|
/// === LucentToolResult ===
pub fn LucentToolResult::from_json(
  jv : Json,
) -> Result[LucentToolResult, String] {
  match jv {
    Json::Object(m) => {
      let tool_use_id = match get_str(m, "tool_use_id") {
        Ok(s) => s
        Err(e) => return Err(e)
      }
      let content = match get_arr_content(m, "content") {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      let is_error = match get_bool(m, "is_error") {
        Ok(b) => b
        Err(e) => return Err(e)
      }
      Ok({ tool_use_id, content, is_error })
    }
    _ => Err("expected object for LucentToolResult")
  }
}

///|
/// === LucentAgentAction ===
pub fn LucentAgentAction::from_json(
  jv : Json,
) -> Result[LucentAgentAction, String] {
  match jv {
    Json::Object(m) => {
      let kind = match get_str(m, "kind") {
        Ok(s) => s
        Err(e) => return Err(e)
      }
      let id = match get_str(m, "id") {
        Ok(s) => s
        Err(e) => return Err(e)
      }
      let call_id = get_str_opt(m, "call_id")
      let name = get_str_opt(m, "name")
      let arguments_json = get_str_opt(m, "arguments")
      let result = get_str_opt(m, "result")
      let provider_payload : Json? = match m.get("provider_payload") {
        Some(j) => Some(j)
        None => None
      }
      Ok({ kind, id, call_id, name, arguments_json, result, provider_payload })
    }
    _ => Err("expected object for LucentAgentAction")
  }
}

///|
/// === LucentContent ===
pub fn LucentContent::from_json(jv : Json) -> Result[LucentContent, String] {
  match jv {
    Json::Object(m) =>
      match m.get("type") {
        Some(Json::String(tp)) =>
          match tp {
            "text" => {
              let text = match get_str(m, "text") {
                Ok(s) => s
                Err(e) => return Err(e)
              }
              let anns : Array[LucentAnnotation]? = match m.get("annotations") {
                Some(Json::Array(items)) =>
                  match parse_annotation_arr(items) {
                    Ok(arr) => Some(arr)
                    Err(_) => None
                  }
                _ => None
              }
              Ok(Text(text, anns))
            }
            "tool_use" => {
              let tu = match m.get("tool_use") {
                Some(j) =>
                  match LucentToolUse::from_json(j) {
                    Ok(v) => v
                    Err(e) => return Err(e)
                  }
                None => return Err("missing tool_use")
              }
              Ok(ToolUse(tu))
            }
            "tool_result" => {
              let tr = match m.get("tool_result") {
                Some(j) =>
                  match LucentToolResult::from_json(j) {
                    Ok(v) => v
                    Err(e) => return Err(e)
                  }
                None => return Err("missing tool_result")
              }
              Ok(ToolResult(tr))
            }
            "thinking" => {
              let th = match m.get("thinking") {
                Some(j) =>
                  match LucentThinking::from_json(j) {
                    Ok(v) => v
                    Err(e) => return Err(e)
                  }
                None => return Err("missing thinking")
              }
              Ok(Thinking(th))
            }
            "refusal" => {
              let text = match get_str(m, "refusal") {
                Ok(s) => s
                Err(e) => return Err(e)
              }
              Ok(Refusal(text))
            }
            "image" => {
              let mm = match m.get("image") {
                Some(j) =>
                  match LucentMultimedia::from_json(j) {
                    Ok(v) => v
                    Err(e) => return Err(e)
                  }
                None => return Err("missing image")
              }
              Ok(Image(mm))
            }
            "audio" => {
              let mm = match m.get("audio") {
                Some(j) =>
                  match LucentMultimedia::from_json(j) {
                    Ok(v) => v
                    Err(e) => return Err(e)
                  }
                None => return Err("missing audio")
              }
              Ok(Audio(mm))
            }
            "video" => {
              let mm = match m.get("video") {
                Some(j) =>
                  match LucentMultimedia::from_json(j) {
                    Ok(v) => v
                    Err(e) => return Err(e)
                  }
                None => return Err("missing video")
              }
              Ok(Video(mm))
            }
            "native" => {
              let tag = match get_str(m, "native_tag") {
                Ok(s) => s
                Err(e) => return Err(e)
              }
              let payload : Json = match m.get("native_payload") {
                Some(j) => j
                None => Json::null()
              }
              Ok(Native(tag, payload))
            }
            _ => Err("unknown content type")
          }
        Some(_) => Err("expected string for type")
        None => Err("missing type in LucentContent")
      }
    _ => Err("expected object for LucentContent")
  }
}

///|
/// === LucentMessage ===
pub fn LucentMessage::from_json(jv : Json) -> Result[LucentMessage, String] {
  match jv {
    Json::Object(m) => {
      let role = match m.get("role") {
        Some(r) =>
          match LucentRole::from_json(r) {
            Ok(v) => v
            Err(e) => return Err(e)
          }
        None => return Err("missing role")
      }
      let content = match get_arr_content(m, "content") {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      Ok({ role, content, phase: None })
    }
    _ => Err("expected object for LucentMessage")
  }
}

///|
/// === LucentConversationItem ===
pub fn LucentConversationItem::from_json(
  jv : Json,
) -> Result[LucentConversationItem, String] {
  match jv {
    Json::Object(m) =>
      match m.get("type") {
        Some(Json::String(tp)) =>
          match tp {
            "message" => {
              let msg = match m.get("message") {
                Some(j) =>
                  match LucentMessage::from_json(j) {
                    Ok(v) => v
                    Err(e) => return Err(e)
                  }
                None => return Err("missing message")
              }
              Ok(Message(msg))
            }
            "tool_call" => {
              let tu = match m.get("tool_call") {
                Some(j) =>
                  match LucentToolUse::from_json(j) {
                    Ok(v) => v
                    Err(e) => return Err(e)
                  }
                None => return Err("missing tool_call")
              }
              Ok(ToolCall(tu))
            }
            "tool_result" => {
              let tr = match m.get("tool_result") {
                Some(j) =>
                  match LucentToolResult::from_json(j) {
                    Ok(v) => v
                    Err(e) => return Err(e)
                  }
                None => return Err("missing tool_result")
              }
              Ok(ToolResult(tr))
            }
            "reasoning" => {
              let th = match m.get("reasoning") {
                Some(j) =>
                  match LucentThinking::from_json(j) {
                    Ok(v) => v
                    Err(e) => return Err(e)
                  }
                None => return Err("missing reasoning")
              }
              Ok(Reasoning(th))
            }
            "agent_action" => {
              let aa = match m.get("agent_action") {
                Some(j) =>
                  match LucentAgentAction::from_json(j) {
                    Ok(v) => v
                    Err(e) => return Err(e)
                  }
                None => return Err("missing agent_action")
              }
              Ok(AgentAction(aa))
            }
            _ => Err("unknown conversation item type")
          }
        Some(_) => Err("expected string for type")
        None => Err("missing type in LucentConversationItem")
      }
    _ => Err("expected object for LucentConversationItem")
  }
}

///|
/// === LucentTool ===
pub fn LucentTool::from_json(jv : Json) -> Result[LucentTool, String] {
  match jv {
    Json::Object(m) => {
      let name = match get_str(m, "name") {
        Ok(s) => s
        Err(e) => return Err(e)
      }
      let description = get_str_opt(m, "description")
      let parameters_json = match m.get("parameters") {
        Some(p) => p.stringify()
        None => return Err("missing parameters")
      }
      let strict = get_bool_opt(m, "strict")
      Ok({ name, description, parameters_json, strict, kind: Function })
    }
    _ => Err("expected object for LucentTool")
  }
}

///|
/// === LucentToolChoice ===
pub fn LucentToolChoice::from_json(
  jv : Json,
) -> Result[LucentToolChoice, String] {
  match jv {
    Json::String(s) =>
      match s {
        "auto" => Ok(Auto)
        "none" => Ok(LucentToolChoice::None)
        "required" => Ok(Required)
        _ => Err("unknown tool_choice")
      }
    Json::Object(m) =>
      match m.get("type") {
        Some(Json::String(tp)) if tp == "specific_tool" =>
          match m.get("name") {
            Some(Json::String(name)) => Ok(SpecificTool(name))
            Some(_) => Err("expected string for name")
            None => Err("missing name for specific_tool")
          }
        Some(_) => Err("expected string for type")
        None => Err("missing type in tool_choice object")
      }
    _ => Err("expected string or object for LucentToolChoice")
  }
}

///|
/// === LucentStructuredOutput ===
pub fn LucentStructuredOutput::from_json(
  jv : Json,
) -> Result[LucentStructuredOutput, String] {
  match jv {
    Json::String(s) =>
      match s {
        "json_object" => Ok(JsonObject)
        "text" => Ok(Text)
        _ => Err("unknown structured_output")
      }
    Json::Object(m) =>
      match m.get("type") {
        Some(Json::String(tp)) if tp == "json_schema" =>
          match m.get("schema") {
            Some(schema) => Ok(JsonSchema(schema.stringify()))
            None => Err("missing schema for json_schema")
          }
        Some(_) => Err("expected string for type")
        None => Err("missing type in structured_output object")
      }
    _ => Err("expected string or object for LucentStructuredOutput")
  }
}

///|
/// === LucentReasoningEffort ===
pub fn LucentReasoningEffort::from_json(
  jv : Json,
) -> Result[LucentReasoningEffort, String] {
  match jv {
    Json::String(s) =>
      match s {
        "low" => Ok(Low)
        "medium" => Ok(Medium)
        "high" => Ok(High)
        _ => Err("unknown reasoning effort")
      }
    _ => Err("expected string for LucentReasoningEffort")
  }
}

///|
/// === LucentReasoningSummary ===
pub fn LucentReasoningSummary::from_json(
  jv : Json,
) -> Result[LucentReasoningSummary, String] {
  match jv {
    Json::String(s) =>
      match s {
        "auto" => Ok(Auto)
        "concise" => Ok(Concise)
        "detailed" => Ok(Detailed)
        _ => Err("unknown reasoning summary")
      }
    _ => Err("expected string for LucentReasoningSummary")
  }
}

///|
/// === LucentOptions ===
pub fn LucentOptions::from_json(jv : Json) -> Result[LucentOptions, String] {
  match jv {
    Json::Object(m) => {
      let temperature = get_double_opt(m, "temperature")
      let top_p = get_double_opt(m, "top_p")
      let top_k = get_int_opt(m, "top_k")
      let max_output_tokens = get_int_opt(m, "max_output_tokens")
      let stop = get_str_arr_opt(m, "stop")
      let stream = match get_bool(m, "stream") {
        Ok(b) => b
        Err(e) => return Err(e)
      }
      let candidate_count = get_int_opt(m, "candidate_count")
      let seed = get_int_opt(m, "seed")
      let structured_output : LucentStructuredOutput? = match
        m.get("structured_output") {
        Some(so) =>
          match LucentStructuredOutput::from_json(so) {
            Ok(v) => Some(v)
            Err(_) => None
          }
        None => None
      }
      let store = get_bool_opt(m, "store")
      let extras = match m.get("extras") {
        Some(Object(entries)) => Some(entries)
        _ => None
      }
      Ok({
        temperature,
        top_p,
        top_k,
        max_output_tokens,
        stop,
        stream,
        candidate_count,
        seed,
        structured_output,
        store,
        extras,
      })
    }
    _ => Err("expected object for LucentOptions")
  }
}

///|
/// === LucentReasoningConfig ===
pub fn LucentReasoningConfig::from_json(
  jv : Json,
) -> Result[LucentReasoningConfig, String] {
  match jv {
    Json::Object(m) => {
      let enabled = match get_bool(m, "enabled") {
        Ok(b) => b
        Err(e) => return Err(e)
      }
      let budget_tokens = get_int_opt(m, "budget_tokens")
      let effort : LucentReasoningEffort? = match m.get("effort") {
        Some(e) =>
          match LucentReasoningEffort::from_json(e) {
            Ok(v) => Some(v)
            Err(_) => None
          }
        None => None
      }
      let summary : LucentReasoningSummary? = match m.get("summary") {
        Some(s) =>
          match LucentReasoningSummary::from_json(s) {
            Ok(v) => Some(v)
            Err(_) => None
          }
        None => None
      }
      Ok({ enabled, budget_tokens, effort, summary })
    }
    _ => Err("expected object for LucentReasoningConfig")
  }
}

///|
/// === LucentCapabilities ===
pub fn LucentCapabilities::from_json(
  jv : Json,
) -> Result[LucentCapabilities, String] {
  match jv {
    Json::Object(m) => {
      let tool_calling = match get_bool(m, "tool_calling") {
        Ok(b) => b
        Err(e) => return Err(e)
      }
      let parallel_tool_calls = match get_bool(m, "parallel_tool_calls") {
        Ok(b) => b
        Err(e) => return Err(e)
      }
      let reasoning = match get_bool(m, "reasoning") {
        Ok(b) => b
        Err(e) => return Err(e)
      }
      let multimodal_input = match get_bool(m, "multimodal_input") {
        Ok(b) => b
        Err(e) => return Err(e)
      }
      let structured_output = match get_bool(m, "structured_output") {
        Ok(b) => b
        Err(e) => return Err(e)
      }
      let input_modalities = match get_arr_modality(m, "input_modalities") {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      let output_modalities = match get_arr_modality(m, "output_modalities") {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      Ok({
        tool_calling,
        parallel_tool_calls,
        reasoning,
        multimodal_input,
        structured_output,
        input_modalities,
        output_modalities,
      })
    }
    _ => Err("expected object for LucentCapabilities")
  }
}

///|
/// === LucentRequest ===
pub fn LucentRequest::from_json(jv : Json) -> Result[LucentRequest, String] {
  match jv {
    Json::Object(m) => {
      let schema_version = match get_str(m, "schema_version") {
        Ok(s) => s
        Err(e) => return Err(e)
      }
      let model = match get_str(m, "model") {
        Ok(s) => s
        Err(e) => return Err(e)
      }
      let instructions : Array[LucentContent]? = match m.get("instructions") {
        Some(Json::Array(items)) => parse_content_opt(items)
        _ => None
      }
      let conversation = match get_arr_item(m, "conversation") {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      let tools : Array[LucentTool]? = match m.get("tools") {
        Some(Json::Array(items)) =>
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
        Some(Json::Object(map)) => {
          let result : Map[String, String] = Map([])
          for entry in map {
            match entry {
              (k, v) =>
                match v {
                  Json::String(s) => result[k] = s
                  _ => ()
                }
            }
          }
          Some(result)
        }
        _ => None
      }
      let extra : Map[String, Json]? = match m.get("extra") {
        Some(Json::Object(map)) => Some(map)
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
pub fn LucentUsage::from_json(jv : Json) -> Result[LucentUsage, String] {
  match jv {
    Json::Object(m) => {
      let prompt_tokens = match get_int(m, "prompt_tokens") {
        Ok(n) => n
        Err(e) => return Err(e)
      }
      let completion_tokens = match get_int(m, "completion_tokens") {
        Ok(n) => n
        Err(e) => return Err(e)
      }
      let total_tokens = match get_int(m, "total_tokens") {
        Ok(n) => n
        Err(e) => return Err(e)
      }
      let reasoning_tokens = get_int_opt(m, "reasoning_tokens")
      let cached_tokens = get_int_opt(m, "cached_tokens")
      let cache_creation_tokens = get_int_opt(m, "cache_creation_tokens")
      Ok({
        prompt_tokens,
        completion_tokens,
        total_tokens,
        reasoning_tokens,
        cached_tokens,
        cache_creation_tokens,
      })
    }
    _ => Err("expected object for LucentUsage")
  }
}

///|
/// === LucentFinishReason ===
pub fn LucentFinishReason::from_json(
  jv : Json,
) -> Result[LucentFinishReason, String] {
  match jv {
    Json::String(s) => Ok(LucentFinishReason::from_string(s))
    _ => Err("expected string for LucentFinishReason")
  }
}

///|
/// === LucentSafetyRating ===
pub fn LucentSafetyRating::from_json(
  jv : Json,
) -> Result[LucentSafetyRating, String] {
  match jv {
    Json::Object(m) => {
      let category = match get_str(m, "category") {
        Ok(s) => s
        Err(e) => return Err(e)
      }
      let probability = match get_str(m, "probability") {
        Ok(s) => s
        Err(e) => return Err(e)
      }
      Ok({ category, probability })
    }
    _ => Err("expected object for LucentSafetyRating")
  }
}

///|
/// === LucentChoice ===
pub fn LucentChoice::from_json(jv : Json) -> Result[LucentChoice, String] {
  match jv {
    Json::Object(m) => {
      let index = match get_int(m, "index") {
        Ok(n) => n
        Err(e) => return Err(e)
      }
      let message = match m.get("message") {
        Some(msg) =>
          match LucentMessage::from_json(msg) {
            Ok(v) => v
            Err(e) => return Err(e)
          }
        None => return Err("missing message")
      }
      let finish_reason = match m.get("finish_reason") {
        Some(fr) =>
          match LucentFinishReason::from_json(fr) {
            Ok(v) => v
            Err(e) => return Err(e)
          }
        None => return Err("missing finish_reason")
      }
      let safety_ratings : Array[LucentSafetyRating]? = match
        m.get("safety_ratings") {
        Some(Json::Array(items)) =>
          match parse_safety_arr(items) {
            Ok(arr) => Some(arr)
            Err(_) => None
          }
        _ => None
      }
      Ok({ index, message, finish_reason, safety_ratings })
    }
    _ => Err("expected object for LucentChoice")
  }
}

///|
/// === LucentResponse ===
pub fn LucentResponse::from_json(jv : Json) -> Result[LucentResponse, String] {
  match jv {
    Json::Object(m) => {
      let schema_version = match get_str(m, "schema_version") {
        Ok(s) => s
        Err(e) => return Err(e)
      }
      let id = match get_str(m, "id") {
        Ok(s) => s
        Err(e) => return Err(e)
      }
      let model = match get_str(m, "model") {
        Ok(s) => s
        Err(e) => return Err(e)
      }
      let created_at = get_int_opt(m, "created_at")
      let choices = match get_arr_choice(m, "choices") {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      let usage : LucentUsage? = match m.get("usage") {
        Some(u) =>
          match LucentUsage::from_json(u) {
            Ok(v) => Some(v)
            Err(_) => None
          }
        None => None
      }
      let provider_payload : Json? = match m.get("provider_payload") {
        Some(j) => Some(j)
        None => None
      }
      Ok({
        schema_version,
        id,
        model,
        created_at,
        choices,
        usage,
        provider_payload,
      })
    }
    _ => Err("expected object for LucentResponse")
  }
}

///|
/// === LucentErrorKind ===
pub fn LucentErrorKind::from_json(jv : Json) -> Result[LucentErrorKind, String] {
  match jv {
    Json::String(s) => Ok(LucentErrorKind::from_string(s))
    _ => Err("expected string for LucentErrorKind")
  }
}

///|
/// === LucentError ===
pub fn LucentError::from_json(jv : Json) -> Result[LucentError, String] {
  match jv {
    Json::Object(m) => {
      let kind = match m.get("kind") {
        Some(k) =>
          match LucentErrorKind::from_json(k) {
            Ok(v) => v
            Err(e) => return Err(e)
          }
        None => return Err("missing kind")
      }
      let message = match get_str(m, "message") {
        Ok(s) => s
        Err(e) => return Err(e)
      }
      let provider_code = get_str_opt(m, "provider_code")
      Ok({ kind, message, provider_code })
    }
    _ => Err("expected object for LucentError")
  }
}

///|
/// === LucentConversationMeta ===
pub fn LucentConversationMeta::from_json(
  jv : Json,
) -> Result[LucentConversationMeta, String] {
  match jv {
    Json::Object(m) => {
      let id = get_str_opt(m, "id")
      let model = get_str_opt(m, "model")
      let usage_input = get_int_opt(m, "usage_input")
      Ok({ id, model, usage_input })
    }
    _ => Err("expected object for LucentConversationMeta")
  }
}

///|
/// === LucentBlockType ===
pub fn LucentBlockType::from_json(jv : Json) -> Result[LucentBlockType, String] {
  match jv {
    Json::String(s) =>
      match s {
        "text" => Ok(Text)
        "thinking" => Ok(Thinking)
        "refusal" => Ok(Refusal)
        "image" => Ok(Image)
        "audio" => Ok(Audio)
        "video" => Ok(Video)
        _ => Ok(Native(s))
      }
    Json::Object(m) =>
      match m.get("type") {
        Some(Json::String(tp)) if tp == "tool_call" => {
          let id = match m.get("id") {
            Some(Json::String(i)) => i
            Some(_) => return Err("expected string for id")
            None => return Err("missing id")
          }
          let name = match m.get("name") {
            Some(Json::String(n)) => n
            Some(_) => return Err("expected string for name")
            None => return Err("missing name")
          }
          Ok(ToolCall(id, name))
        }
        Some(_) => Err("expected string for type")
        None => Err("missing type")
      }
    _ => Err("expected string or object for LucentBlockType")
  }
}

///|
/// === LucentBlockDelta ===
pub fn LucentBlockDelta::from_json(
  jv : Json,
) -> Result[LucentBlockDelta, String] {
  match jv {
    Json::Object(m) =>
      match m.get("type") {
        Some(Json::String(tp)) =>
          match tp {
            "text" => {
              let text = match get_str(m, "text") {
                Ok(s) => s
                Err(e) => return Err(e)
              }
              Ok(TextDelta(text))
            }
            "thinking" => {
              let text = match get_str(m, "text") {
                Ok(s) => s
                Err(e) => return Err(e)
              }
              Ok(ThinkingDelta(text))
            }
            "signature" => {
              let sig = match get_str(m, "signature") {
                Ok(s) => s
                Err(e) => return Err(e)
              }
              Ok(SignatureDelta(sig))
            }
            "tool_arguments" => {
              let args = match get_str(m, "arguments") {
                Ok(s) => s
                Err(e) => return Err(e)
              }
              Ok(ToolArgumentsDelta(args))
            }
            "refusal" => {
              let text = match get_str(m, "text") {
                Ok(s) => s
                Err(e) => return Err(e)
              }
              Ok(RefusalDelta(text))
            }
            "native" => {
              let tag = match get_str(m, "native_tag") {
                Ok(s) => s
                Err(e) => return Err(e)
              }
              let payload : Json = match m.get("native_payload") {
                Some(j) => j
                None => Json::null()
              }
              Ok(NativeDelta(tag, payload))
            }
            _ => Err("unknown block delta type")
          }
        Some(_) => Err("expected string for type")
        None => Err("missing type in LucentBlockDelta")
      }
    _ => Err("expected object for LucentBlockDelta")
  }
}

///|
/// === LucentStreamEvent ===
pub fn LucentStreamEvent::from_json(
  jv : Json,
) -> Result[LucentStreamEvent, String] {
  match jv {
    Json::Object(m) =>
      match m.get("event") {
        Some(Json::String(ev)) =>
          match ev {
            "conversation_start" => {
              let meta = match m.get("meta") {
                Some(j) =>
                  match LucentConversationMeta::from_json(j) {
                    Ok(v) => v
                    Err(e) => return Err(e)
                  }
                None => return Err("missing meta")
              }
              Ok(ConversationStart(meta))
            }
            "item_start" => {
              let idx = match get_int(m, "index") {
                Ok(n) => n
                Err(e) => return Err(e)
              }
              let item = match m.get("item") {
                Some(j) =>
                  match LucentConversationItem::from_json(j) {
                    Ok(v) => v
                    Err(e) => return Err(e)
                  }
                None => return Err("missing item")
              }
              Ok(ItemStart(idx, item))
            }
            "block_start" => {
              let idx = match get_int(m, "index") {
                Ok(n) => n
                Err(e) => return Err(e)
              }
              let bt = match m.get("block_type") {
                Some(j) =>
                  match LucentBlockType::from_json(j) {
                    Ok(v) => v
                    Err(e) => return Err(e)
                  }
                None => return Err("missing block_type")
              }
              Ok(BlockStart(idx, bt))
            }
            "block_delta" => {
              let idx = match get_int(m, "index") {
                Ok(n) => n
                Err(e) => return Err(e)
              }
              let delta = match m.get("delta") {
                Some(j) =>
                  match LucentBlockDelta::from_json(j) {
                    Ok(v) => v
                    Err(e) => return Err(e)
                  }
                None => return Err("missing delta")
              }
              Ok(BlockDelta(idx, delta))
            }
            "block_end" => {
              let idx = match get_int(m, "index") {
                Ok(n) => n
                Err(e) => return Err(e)
              }
              Ok(BlockEnd(idx))
            }
            "item_end" => {
              let idx = match get_int(m, "index") {
                Ok(n) => n
                Err(e) => return Err(e)
              }
              Ok(ItemEnd(idx))
            }
            "block_discard" => {
              let idx = match get_int(m, "index") {
                Ok(n) => n
                Err(e) => return Err(e)
              }
              Ok(BlockDiscard(idx))
            }
            "annotations" => {
              let idx = match get_int(m, "index") {
                Ok(n) => n
                Err(e) => return Err(e)
              }
              let annotations = match get_arr_annotation(m, "annotations") {
                Ok(v) => v
                Err(e) => return Err(e)
              }
              Ok(Annotations(idx, annotations))
            }
            "finish" => {
              let fr = match m.get("finish_reason") {
                Some(f) =>
                  match LucentFinishReason::from_json(f) {
                    Ok(v) => v
                    Err(e) => return Err(e)
                  }
                None => return Err("missing finish_reason")
              }
              Ok(Finish(fr))
            }
            "usage" => {
              let usage = match m.get("usage") {
                Some(j) =>
                  match LucentUsage::from_json(j) {
                    Ok(v) => v
                    Err(e) => return Err(e)
                  }
                None => return Err("missing usage")
              }
              Ok(Usage(usage))
            }
            "error" => {
              let err = match m.get("error") {
                Some(j) =>
                  match LucentError::from_json(j) {
                    Ok(v) => v
                    Err(e) => return Err(e)
                  }
                None => return Err("missing error")
              }
              Ok(Error(err))
            }
            "done" => Ok(Done)
            _ => Err("unknown stream event")
          }
        Some(_) => Err("expected string for event")
        None => Err("missing event in LucentStreamEvent")
      }
    _ => Err("expected object for LucentStreamEvent")
  }
}

///|
/// === ProviderCapability ===
pub fn ProviderCapability::from_json(
  jv : Json,
) -> Result[ProviderCapability, String] {
  match jv {
    Json::Object(m) => {
      let model_pattern = match get_str(m, "model_pattern") {
        Ok(s) => s
        Err(e) => return Err(e)
      }
      let provider = match get_str(m, "provider") {
        Ok(s) => s
        Err(e) => return Err(e)
      }
      let capabilities = match m.get("capabilities") {
        Some(j) =>
          match LucentCapabilities::from_json(j) {
            Ok(v) => v
            Err(e) => return Err(e)
          }
        None => return Err("missing capabilities")
      }
      let extra_params : Map[String, Json]? = match m.get("extra_params") {
        Some(Json::Object(map)) => Some(map)
        _ => None
      }
      Ok({ model_pattern, provider, capabilities, extra_params })
    }
    _ => Err("expected object for ProviderCapability")
  }
}

///|
/// === LucentDiscovery ===
pub fn LucentDiscovery::from_json(jv : Json) -> Result[LucentDiscovery, String] {
  match jv {
    Json::Object(m) => {
      let schema_version = match get_str(m, "schema_version") {
        Ok(s) => s
        Err(e) => return Err(e)
      }
      let protocol_version = match get_str(m, "protocol_version") {
        Ok(s) => s
        Err(e) => return Err(e)
      }
      let schema_url = match get_str(m, "schema_url") {
        Ok(s) => s
        Err(e) => return Err(e)
      }
      let providers = match get_arr_provider(m, "providers") {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      Ok({ schema_version, protocol_version, schema_url, providers })
    }
    _ => Err("expected object for LucentDiscovery")
  }
}
