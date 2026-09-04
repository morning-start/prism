///|
/// Lucent IR — 内容与消息反序列化（LucentContent / LucentMessage / LucentConversationItem）
///
/// 共享 helper 见 deserialize_helpers；基础类型见 deserialize_primitives。

///|
/// === LucentContent ===
pub fn LucentContent::from_json(jv : Json) -> Result[LucentContent, String] {
  match jv {
    Object(m) =>
      match m.get("type") {
        Some(String(tp)) =>
          match tp {
            "text" => {
              let text = match get_str(m, "text") {
                Ok(s) => s
                Err(e) => return Err(e)
              }
              let anns : Array[LucentAnnotation]? = match m.get("annotations") {
                Some(Array(items)) =>
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
            "file" => {
              let mm = match m.get("file") {
                Some(j) =>
                  match LucentMultimedia::from_json(j) {
                    Ok(v) => v
                    Err(e) => return Err(e)
                  }
                None => return Err("missing file")
              }
              Ok(File(mm))
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
    Object(m) => {
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
      let reasoning = match m.get("reasoning") {
        Some(r) =>
          match LucentThinking::from_json(r) {
            Ok(v) => Some(v)
            Err(e) => return Err(e)
          }
        None => None
      }
      Ok({ role, content, phase: get_str_opt(m, "phase"), reasoning })
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
    Object(m) =>
      match m.get("type") {
        Some(String(tp)) =>
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
