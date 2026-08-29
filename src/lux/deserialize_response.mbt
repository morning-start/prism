///|
/// LucentResponse JSON 反序列化
pub fn LucentUsage::from_json(jv : Json) -> Result[LucentUsage, String] {
  match jv {
    Object(m) => {
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
    String(s) => Ok(LucentFinishReason::from_string(s))
    _ => Err("expected string for LucentFinishReason")
  }
}

///|
/// === LucentSafetyRating ===
pub fn LucentSafetyRating::from_json(
  jv : Json,
) -> Result[LucentSafetyRating, String] {
  match jv {
    Object(m) => {
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
    Object(m) => {
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
        Some(Array(items)) =>
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
    Object(m) => {
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
    String(s) => Ok(LucentErrorKind::from_string(s))
    _ => Err("expected string for LucentErrorKind")
  }
}

///|
/// === LucentError ===
pub fn LucentError::from_json(jv : Json) -> Result[LucentError, String] {
  match jv {
    Object(m) => {
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
    Object(m) => {
      let id = get_str_opt(m, "id")
      let model = get_str_opt(m, "model")
      let usage_input = get_int_opt(m, "usage_input")
      let created_at = get_int_opt(m, "created_at")
      let extra = m.get("extra")
      Ok({ id, model, usage_input, created_at, extra })
    }
    _ => Err("expected object for LucentConversationMeta")
  }
}

///|
/// === LucentBlockType ===
pub fn LucentBlockType::from_json(jv : Json) -> Result[LucentBlockType, String] {
  match jv {
    String(s) =>
      match s {
        "text" => Ok(Text)
        "thinking" => Ok(Thinking)
        "refusal" => Ok(Refusal)
        "image" => Ok(Image)
        "audio" => Ok(Audio)
        "video" => Ok(Video)
        _ => Ok(Native(s))
      }
    Object(m) =>
      match m.get("type") {
        Some(String(tp)) if tp == "tool_call" => {
          let id = match m.get("id") {
            Some(String(i)) => i
            Some(_) => return Err("expected string for id")
            None => return Err("missing id")
          }
          let name = match m.get("name") {
            Some(String(n)) => n
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
    Object(m) =>
      match m.get("type") {
        Some(String(tp)) =>
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
