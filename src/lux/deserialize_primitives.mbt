///|
/// Lucent IR — 基础类型反序列化（LucentModality ~ LucentAgentAction）
///
/// 其余段落见 deserialize_content / deserialize_tools / deserialize_options；
/// 共享 helper 见 deserialize_helpers。

///|
/// === LucentModality ===
pub fn LucentModality::from_json(jv : Json) -> Result[LucentModality, String] {
  match jv {
    String(s) =>
      match LucentModality::from_string(s) {
        Some(m) => Ok(m)
        None => Ok(Native(s))
      }
    _ => Err("expected string for LucentModality")
  }
}

///|
/// === SupportLevel ===
pub fn SupportLevel::from_json(jv : Json) -> Result[SupportLevel, String] {
  match jv {
    String(s) =>
      match SupportLevel::from_string(s) {
        Some(l) => Ok(l)
        None => Err("unknown support level: " + s)
      }
    _ => Err("expected string for support level")
  }
}

///|
/// === LucentMediaSource ===
pub fn LucentMediaSource::from_json(
  jv : Json,
) -> Result[LucentMediaSource, String] {
  match jv {
    Object(m) => {
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
    Object(m) => {
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
    String(s) =>
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
    Object(m) => {
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
    Object(m) => {
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
    Object(m) => {
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
    Object(m) => {
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
    Object(m) => {
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
