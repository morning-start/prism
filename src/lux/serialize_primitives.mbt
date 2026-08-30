///|
/// Lux IR explicit JSON serialization/deserialization
///
/// All `to_json()` outputs match `schemas/lux-ir-v1.json`.
/// NOTE: Json enum variants (Object, String, True, False, Array, Number, Null)
/// are read-only — use lowercase factory functions: Json::object, Json::string,
/// Json::boolean, Json::array, Json::number, Json::null.

///|
/// === LucentRole ===
pub fn LucentRole::to_json(self : LucentRole) -> Json {
  Json::string(self.to_string())
}

///|
pub fn LucentRole::from_json(jv : Json) -> Result[LucentRole, String] {
  match jv {
    String(s) =>
      match LucentRole::from_string(s) {
        Some(r) => Ok(r)
        None => Ok(Native(s))
      }
    _ => Err("expected string for LucentRole")
  }
}

///|
pub fn LucentModality::to_json(self : LucentModality) -> Json {
  match self {
    Text => Json::string("text")
    Image => Json::string("image")
    Audio => Json::string("audio")
    Video => Json::string("video")
    Pdf => Json::string("pdf")
    Native(s) => Json::string(s)
  }
}

///|
pub fn LucentMediaSource::to_json(self : LucentMediaSource) -> Json {
  match self {
    Inline(data) =>
      Json::object({
        "type": Json::string("inline"),
        "data": Json::string(data),
      })
    Url(data) =>
      Json::object({ "type": Json::string("url"), "data": Json::string(data) })
    FileUri(data) =>
      Json::object({
        "type": Json::string("file_uri"),
        "data": Json::string(data),
      })
  }
}

///|
pub fn LucentMultimedia::to_json(self : LucentMultimedia) -> Json {
  Json::object({
    "media_type": Json::string(self.media_type),
    "source": self.source.to_json(),
  })
}

///|
pub fn LucentAnnotationKind::to_json(self : LucentAnnotationKind) -> String {
  match self {
    Url => "url"
    FileCitation => "file_citation"
    WebSearchCitation => "web_search_citation"
    Native(s) => s
  }
}

///|
pub fn LucentAnnotation::to_json(self : LucentAnnotation) -> Json {
  let fields : Map[String, Json] = { "kind": Json::string(self.kind.to_json()) }
  match self.text {
    Some(t) => fields["text"] = Json::string(t)
    None => ()
  }
  match self.reference {
    Some(r) => fields["ref"] = Json::string(r)
    None => ()
  }
  match self.start {
    Some(s) => fields["start"] = s.to_json()
    None => ()
  }
  match self.end {
    Some(e) => fields["end"] = e.to_json()
    None => ()
  }
  Json::object(fields)
}

///|
pub fn LucentThinking::to_json(self : LucentThinking) -> Json {
  let fields : Map[String, Json] = {
    "text": Json::string(self.text),
    "redacted": self.redacted.to_json(),
  }
  match self.signature {
    Some(s) => fields["signature"] = Json::string(s)
    None => ()
  }
  match self.summary {
    Some(arr) => fields["summary"] = Json::array(arr.map(fn(c) { c.to_json() }))
    None => ()
  }
  Json::object(fields)
}

///|
pub fn LucentToolUse::to_json(self : LucentToolUse) -> Json {
  Json::object({
    "id": Json::string(self.id),
    "name": Json::string(self.name),
    "arguments": Json::string(self.arguments_json),
  })
}

///|
pub fn LucentToolResult::to_json(self : LucentToolResult) -> Json {
  Json::object({
    "tool_use_id": Json::string(self.tool_use_id),
    "content": Json::array(self.content.map(fn(c) { c.to_json() })),
    "is_error": self.is_error.to_json(),
  })
}

///|
pub fn LucentAgentAction::to_json(self : LucentAgentAction) -> Json {
  let fields : Map[String, Json] = {
    "kind": Json::string(self.kind),
    "id": Json::string(self.id),
  }
  match self.call_id {
    Some(s) => fields["call_id"] = Json::string(s)
    None => ()
  }
  match self.name {
    Some(s) => fields["name"] = Json::string(s)
    None => ()
  }
  match self.arguments_json {
    Some(s) => fields["arguments"] = Json::string(s)
    None => ()
  }
  match self.result {
    Some(s) => fields["result"] = Json::string(s)
    None => ()
  }
  match self.provider_payload {
    Some(js) => fields["provider_payload"] = js
    None => ()
  }
  Json::object(fields)
}

///|
pub fn LucentContent::to_json(self : LucentContent) -> Json {
  match self {
    Text(s, anns) => {
      let fields : Map[String, Json] = {
        "type": Json::string("text"),
        "text": Json::string(s),
      }
      match anns {
        Some(a) =>
          fields["annotations"] = Json::array(a.map(fn(x) { x.to_json() }))
        None => ()
      }
      Json::object(fields)
    }
    ToolUse(tu) =>
      Json::object({
        "type": Json::string("tool_use"),
        "tool_use": tu.to_json(),
      })
    ToolResult(tr) =>
      Json::object({
        "type": Json::string("tool_result"),
        "tool_result": tr.to_json(),
      })
    Thinking(th) =>
      Json::object({
        "type": Json::string("thinking"),
        "thinking": th.to_json(),
      })
    Refusal(r) =>
      Json::object({
        "type": Json::string("refusal"),
        "refusal": Json::string(r),
      })
    Image(m) =>
      Json::object({ "type": Json::string("image"), "image": m.to_json() })
    Audio(m) =>
      Json::object({ "type": Json::string("audio"), "audio": m.to_json() })
    Video(m) =>
      Json::object({ "type": Json::string("video"), "video": m.to_json() })
    File(m) =>
      Json::object({ "type": Json::string("file"), "file": m.to_json() })
    Native(tag, raw) =>
      Json::object({
        "type": Json::string("native"),
        "native_tag": Json::string(tag),
        "native_payload": raw,
      })
  }
}

///|
pub fn LucentMessage::to_json(self : LucentMessage) -> Json {
  let fields : Map[String, Json] = {
    "role": self.role.to_json(),
    "content": Json::array(self.content.map(fn(c) { c.to_json() })),
  }
  match self.phase {
    Some(p) => fields["phase"] = Json::string(p)
    None => ()
  }
  match self.reasoning {
    Some(r) => fields["reasoning"] = r.to_json()
    None => ()
  }
  Json::object(fields)
}

///|
pub fn LucentConversationItem::to_json(self : LucentConversationItem) -> Json {
  match self {
    Message(m) =>
      Json::object({ "type": Json::string("message"), "message": m.to_json() })
    ToolCall(tu) =>
      Json::object({
        "type": Json::string("tool_call"),
        "tool_call": tu.to_json(),
      })
    ToolResult(tr) =>
      Json::object({
        "type": Json::string("tool_result"),
        "tool_result": tr.to_json(),
      })
    Reasoning(th) =>
      Json::object({
        "type": Json::string("reasoning"),
        "reasoning": th.to_json(),
      })
    AgentAction(aa) =>
      Json::object({
        "type": Json::string("agent_action"),
        "agent_action": aa.to_json(),
      })
  }
}

///|
pub fn LucentTool::to_json(self : LucentTool) -> Json {
  let params = @json.parse(self.parameters_json) catch { _ => Json::null() }
  let kind_str = match self.kind {
    Function => "function"
    FileSearch => "file_search"
    WebSearch => "web_search"
    CodeInterpreter => "code_interpreter"
    ComputerUse => "computer_use"
    CodeExecution => "code_execution"
    Shell => "shell"
    ApplyPatch => "apply_patch"
    MCP => "mcp"
    Native(s) => s
  }
  let fields : Map[String, Json] = {
    "name": Json::string(self.name),
    "kind": Json::string(kind_str),
    "parameters": params,
  }
  match self.description {
    Some(d) => fields["description"] = Json::string(d)
    None => ()
  }
  match self.strict {
    Some(s) => fields["strict"] = s.to_json()
    None => ()
  }
  Json::object(fields)
}

///|
pub fn LucentToolChoice::to_json(self : LucentToolChoice) -> Json {
  match self {
    Auto => Json::string("auto")
    None => Json::string("none")
    Required => Json::string("required")
    SpecificTool(name) =>
      Json::object({
        "type": Json::string("specific_tool"),
        "name": Json::string(name),
      })
  }
}

///|
pub fn LucentStructuredOutput::to_json(self : LucentStructuredOutput) -> Json {
  match self {
    JsonObject => Json::string("json_object")
    Text => Json::string("text")
    JsonSchema(schema_str) => {
      let schema = @json.parse(schema_str) catch { _ => Json::object(Map([])) }
      Json::object({ "type": Json::string("json_schema"), "schema": schema })
    }
  }
}

///|
pub fn LucentOptions::to_json(self : LucentOptions) -> Json {
  let fields : Map[String, Json] = { "stream": self.stream.to_json() }
  match self.temperature {
    Some(t) => fields["temperature"] = t.to_json()
    None => ()
  }
  match self.top_p {
    Some(p) => fields["top_p"] = p.to_json()
    None => ()
  }
  match self.top_k {
    Some(k) => fields["top_k"] = k.to_json()
    None => ()
  }
  match self.max_output_tokens {
    Some(n) => fields["max_output_tokens"] = n.to_json()
    None => ()
  }
  match self.stop {
    Some(arr) =>
      fields["stop"] = Json::array(arr.map(fn(s) { Json::string(s) }))
    None => ()
  }
  match self.candidate_count {
    Some(n) => fields["candidate_count"] = n.to_json()
    None => ()
  }
  match self.structured_output {
    Some(so) => fields["structured_output"] = so.to_json()
    None => ()
  }
  match self.store {
    Some(s) => fields["store"] = s.to_json()
    None => ()
  }
  match self.extras {
    Some(ext) => fields["extras"] = Json::object(ext)
    None => ()
  }
  Json::object(fields)
}

///|
pub fn LucentReasoningConfig::to_json(self : LucentReasoningConfig) -> Json {
  let fields : Map[String, Json] = { "enabled": self.enabled.to_json() }
  match self.budget_tokens {
    Some(n) => fields["budget_tokens"] = n.to_json()
    None => ()
  }
  match self.effort {
    Some(e) =>
      fields["effort"] = match e {
        Low => Json::string("low")
        Medium => Json::string("medium")
        High => Json::string("high")
        XHigh => Json::string("xhigh")
      }
    None => ()
  }
  match self.summary {
    Some(s) =>
      fields["summary"] = match s {
        Auto => Json::string("auto")
        Concise => Json::string("concise")
        Detailed => Json::string("detailed")
      }
    None => ()
  }
  Json::object(fields)
}

///|
pub fn SupportLevel::to_json(self : SupportLevel) -> Json {
  Json::string(self.to_string())
}

///|
pub fn LucentCapabilities::to_json(self : LucentCapabilities) -> Json {
  Json::object({
    "tool_calling": self.tool_calling.to_json(),
    "parallel_tool_calls": self.parallel_tool_calls.to_json(),
    "reasoning": self.reasoning.to_json(),
    "multimodal_input": self.multimodal_input.to_json(),
    "structured_output": self.structured_output.to_json(),
    "input_modalities": Json::array(
      self.input_modalities.map(fn(m) { m.to_json() }),
    ),
    "output_modalities": Json::array(
      self.output_modalities.map(fn(m) { m.to_json() }),
    ),
  })
}
