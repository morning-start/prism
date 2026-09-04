///|
/// Lucent IR — 生成参数反序列化（ReasoningEffort / ReasoningSummary / Options / ReasoningConfig / Capabilities）
///
/// 共享 helper 见 deserialize_helpers；基础类型见 deserialize_primitives。

///|
/// === LucentReasoningEffort ===
pub fn LucentReasoningEffort::from_json(
  jv : Json,
) -> Result[LucentReasoningEffort, String] {
  match jv {
    String(s) =>
      match s {
        "low" => Ok(Low)
        "medium" => Ok(Medium)
        "high" => Ok(High)
        "xhigh" => Ok(XHigh)
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
    String(s) =>
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
    Object(m) => {
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
    Object(m) => {
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
    Object(m) => {
      let tool_calling = match get_support_level(m, "tool_calling") {
        Ok(l) => l
        Err(e) => return Err(e)
      }
      let parallel_tool_calls = match
        get_support_level(m, "parallel_tool_calls") {
        Ok(l) => l
        Err(e) => return Err(e)
      }
      let reasoning = match get_support_level(m, "reasoning") {
        Ok(l) => l
        Err(e) => return Err(e)
      }
      let multimodal_input = match get_support_level(m, "multimodal_input") {
        Ok(l) => l
        Err(e) => return Err(e)
      }
      let structured_output = match get_support_level(m, "structured_output") {
        Ok(l) => l
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
