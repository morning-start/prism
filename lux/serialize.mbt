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
    Json::String(s) =>
      match LucentRole::from_string(s) {
        Some(r) => Ok(r)
        None => Ok(Native(s))
      }
    _ => Err("expected string for LucentRole")
  }
}

///|
/// === LucentModality ===
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
/// === LucentMediaSource ===
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
/// === LucentMultimedia ===
pub fn LucentMultimedia::to_json(self : LucentMultimedia) -> Json {
  Json::object({
    "media_type": Json::string(self.media_type),
    "source": self.source.to_json(),
  })
}

///|
/// === LucentAnnotationKind ===
pub fn LucentAnnotationKind::to_json(self : LucentAnnotationKind) -> String {
  match self {
    Url => "url"
    FileCitation => "file_citation"
    WebSearchCitation => "web_search_citation"
    Native(s) => s
  }
}

///|
/// === LucentAnnotation ===
pub fn LucentAnnotation::to_json(self : LucentAnnotation) -> Json {
  let fields : Map[String, Json] = { "kind": Json::string(self.kind.to_json()) }
  match self.text {
    Some(t) => fields["text"] = Json::string(t)
    None => ()
  }
  match self.ref_ {
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
/// === LucentThinking ===
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
/// === LucentToolUse ===
pub fn LucentToolUse::to_json(self : LucentToolUse) -> Json {
  Json::object({
    "id": Json::string(self.id),
    "name": Json::string(self.name),
    "arguments": Json::string(self.arguments_json),
  })
}

///|
/// === LucentToolResult ===
pub fn LucentToolResult::to_json(self : LucentToolResult) -> Json {
  Json::object({
    "tool_use_id": Json::string(self.tool_use_id),
    "content": Json::array(self.content.map(fn(c) { c.to_json() })),
    "is_error": self.is_error.to_json(),
  })
}

///|
/// === LucentAgentAction ===
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
/// === LucentContent ===
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
    Native(tag, raw) =>
      Json::object({
        "type": Json::string("native"),
        "native_tag": Json::string(tag),
        "native_payload": raw,
      })
  }
}

///|
/// === LucentMessage ===
pub fn LucentMessage::to_json(self : LucentMessage) -> Json {
  Json::object({
    "role": self.role.to_json(),
    "content": Json::array(self.content.map(fn(c) { c.to_json() })),
  })
}

///|
/// === LucentConversationItem ===
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
/// === LucentTool ===
pub fn LucentTool::to_json(self : LucentTool) -> Json {
  let params = @json.parse(self.parameters_json) catch { _ => Json::null() }
  let fields : Map[String, Json] = {
    "name": Json::string(self.name),
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
/// === LucentToolChoice ===
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
/// === LucentStructuredOutput ===
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
/// === LucentOptions ===
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
  match self.seed {
    Some(n) => fields["seed"] = n.to_json()
    None => ()
  }
  match self.structured_output {
    Some(so) => fields["structured_output"] = so.to_json()
    None => ()
  }
  Json::object(fields)
}

///|
/// === LucentReasoningConfig ===
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
/// === LucentCapabilities ===
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

///|
/// === LucentRequest ===
pub fn LucentRequest::to_json(self : LucentRequest) -> Json {
  let fields : Map[String, Json] = {
    "schema_version": Json::string(self.schema_version),
    "model": Json::string(self.model),
    "conversation": Json::array(self.conversation.map(fn(ci) { ci.to_json() })),
    "options": self.options.to_json(),
  }
  match self.instructions {
    Some(instrs) =>
      fields["instructions"] = Json::array(instrs.map(fn(c) { c.to_json() }))
    None => ()
  }
  match self.tools {
    Some(tools) =>
      fields["tools"] = Json::array(tools.map(fn(t) { t.to_json() }))
    None => ()
  }
  match self.tool_choice {
    Some(tc) => fields["tool_choice"] = tc.to_json()
    None => ()
  }
  match self.capabilities {
    Some(cap) => fields["capabilities"] = cap.to_json()
    None => ()
  }
  match self.reasoning {
    Some(rc) => fields["reasoning"] = rc.to_json()
    None => ()
  }
  match self.metadata {
    Some(m) => {
      let meta_fields : Map[String, Json] = Map([])
      for entry in m {
        match entry {
          (k, v) => meta_fields[k] = Json::string(v)
        }
      }
      if meta_fields.length() > 0 {
        fields["metadata"] = Json::object(meta_fields)
      }
    }
    None => ()
  }
  match self.extra {
    Some(e) => {
      let extra_fields : Map[String, Json] = Map([])
      for entry in e {
        match entry {
          (k, v) => extra_fields[k] = v
        }
      }
      if extra_fields.length() > 0 {
        fields["extra"] = Json::object(extra_fields)
      }
    }
    None => ()
  }
  Json::object(fields)
}

///|
/// === LucentUsage ===
pub fn LucentUsage::to_json(self : LucentUsage) -> Json {
  let fields : Map[String, Json] = {
    "prompt_tokens": self.prompt_tokens.to_json(),
    "completion_tokens": self.completion_tokens.to_json(),
    "total_tokens": self.total_tokens.to_json(),
  }
  match self.reasoning_tokens {
    Some(n) => fields["reasoning_tokens"] = n.to_json()
    None => ()
  }
  match self.cached_tokens {
    Some(n) => fields["cached_tokens"] = n.to_json()
    None => ()
  }
  match self.cache_creation_tokens {
    Some(n) => fields["cache_creation_tokens"] = n.to_json()
    None => ()
  }
  Json::object(fields)
}

///|
/// === LucentFinishReason ===
pub fn LucentFinishReason::to_json(self : LucentFinishReason) -> Json {
  Json::string(self.to_string())
}

///|
/// === LucentSafetyRating ===
pub fn LucentSafetyRating::to_json(self : LucentSafetyRating) -> Json {
  Json::object({
    "category": Json::string(self.category),
    "probability": Json::string(self.probability),
  })
}

///|
/// === LucentChoice ===
pub fn LucentChoice::to_json(self : LucentChoice) -> Json {
  let fields : Map[String, Json] = {
    "index": self.index.to_json(),
    "message": self.message.to_json(),
    "finish_reason": self.finish_reason.to_json(),
  }
  match self.safety_ratings {
    Some(arr) =>
      fields["safety_ratings"] = Json::array(arr.map(fn(sr) { sr.to_json() }))
    None => ()
  }
  Json::object(fields)
}

///|
/// === LucentResponse ===
pub fn LucentResponse::to_json(self : LucentResponse) -> Json {
  let fields : Map[String, Json] = {
    "schema_version": Json::string(self.schema_version),
    "id": Json::string(self.id),
    "model": Json::string(self.model),
    "choices": Json::array(self.choices.map(fn(c) { c.to_json() })),
  }
  match self.created_at {
    Some(n) => fields["created_at"] = n.to_json()
    None => ()
  }
  match self.usage {
    Some(u) => fields["usage"] = u.to_json()
    None => ()
  }
  match self.provider_payload {
    Some(p) => fields["provider_payload"] = p
    None => ()
  }
  Json::object(fields)
}

///|
/// === LucentError ===
pub fn LucentError::to_json(self : LucentError) -> Json {
  let fields : Map[String, Json] = {
    "kind": self.kind.to_json(),
    "message": Json::string(self.message),
  }
  match self.provider_code {
    Some(c) => fields["provider_code"] = Json::string(c)
    None => ()
  }
  Json::object(fields)
}

///|
/// === LucentErrorKind ===
pub fn LucentErrorKind::to_json(self : LucentErrorKind) -> Json {
  match self {
    RateLimit => Json::string("rate_limit")
    InvalidRequest => Json::string("invalid_request")
    Authentication => Json::string("authentication")
    ServerError => Json::string("server_error")
    ContentFilter => Json::string("content_filter")
    Native(s) => Json::string(s)
  }
}

///|
/// === LucentConversationMeta ===
pub fn LucentConversationMeta::to_json(self : LucentConversationMeta) -> Json {
  let fields : Map[String, Json] = Map([])
  match self.id {
    Some(id) => fields["id"] = Json::string(id)
    None => ()
  }
  match self.model {
    Some(m) => fields["model"] = Json::string(m)
    None => ()
  }
  match self.usage_input {
    Some(n) => fields["usage_input"] = n.to_json()
    None => ()
  }
  Json::object(fields)
}

///|
/// === LucentBlockType ===
pub fn LucentBlockType::to_json(self : LucentBlockType) -> Json {
  match self {
    Text => Json::string("text")
    ToolCall(id, name) =>
      Json::object({
        "type": Json::string("tool_call"),
        "id": Json::string(id),
        "name": Json::string(name),
      })
    Thinking => Json::string("thinking")
    Refusal => Json::string("refusal")
    Image => Json::string("image")
    Audio => Json::string("audio")
    Video => Json::string("video")
    Native(tag) => Json::string(tag)
  }
}

///|
/// === LucentBlockDelta ===
pub fn LucentBlockDelta::to_json(self : LucentBlockDelta) -> Json {
  match self {
    TextDelta(s) =>
      Json::object({ "type": Json::string("text"), "text": Json::string(s) })
    ThinkingDelta(s) =>
      Json::object({ "type": Json::string("thinking"), "text": Json::string(s) })
    SignatureDelta(s) =>
      Json::object({
        "type": Json::string("signature"),
        "signature": Json::string(s),
      })
    ToolArgumentsDelta(s) =>
      Json::object({
        "type": Json::string("tool_arguments"),
        "arguments": Json::string(s),
      })
    RefusalDelta(s) =>
      Json::object({ "type": Json::string("refusal"), "text": Json::string(s) })
    NativeDelta(tag, raw) =>
      Json::object({
        "type": Json::string("native"),
        "native_tag": Json::string(tag),
        "native_payload": raw,
      })
  }
}

///|
/// === LucentStreamEvent ===
pub fn LucentStreamEvent::to_json(self : LucentStreamEvent) -> Json {
  match self {
    ConversationStart(meta) =>
      Json::object({
        "event": Json::string("conversation_start"),
        "meta": meta.to_json(),
      })
    ItemStart(idx, item) =>
      Json::object({
        "event": Json::string("item_start"),
        "index": idx.to_json(),
        "item": item.to_json(),
      })
    BlockStart(idx, bt) =>
      Json::object({
        "event": Json::string("block_start"),
        "index": idx.to_json(),
        "block_type": bt.to_json(),
      })
    BlockDelta(idx, delta) =>
      Json::object({
        "event": Json::string("block_delta"),
        "index": idx.to_json(),
        "delta": delta.to_json(),
      })
    BlockEnd(idx) =>
      Json::object({
        "event": Json::string("block_end"),
        "index": idx.to_json(),
      })
    ItemEnd(idx) =>
      Json::object({ "event": Json::string("item_end"), "index": idx.to_json() })
    BlockDiscard(idx) =>
      Json::object({
        "event": Json::string("block_discard"),
        "index": idx.to_json(),
      })
    Annotations(idx, anns) =>
      Json::object({
        "event": Json::string("annotations"),
        "index": idx.to_json(),
        "annotations": Json::array(anns.map(fn(a) { a.to_json() })),
      })
    Finish(fr) =>
      Json::object({
        "event": Json::string("finish"),
        "finish_reason": fr.to_json(),
      })
    Usage(u) =>
      Json::object({ "event": Json::string("usage"), "usage": u.to_json() })
    Error(e) =>
      Json::object({ "event": Json::string("error"), "error": e.to_json() })
    Done => Json::object({ "event": Json::string("done") })
  }
}

///|
/// === ProviderCapability ===
pub fn ProviderCapability::to_json(self : ProviderCapability) -> Json {
  let fields : Map[String, Json] = {
    "model_pattern": Json::string(self.model_pattern),
    "provider": Json::string(self.provider),
    "capabilities": self.capabilities.to_json(),
  }
  match self.extra_params {
    Some(ep) => {
      let ep_fields : Map[String, Json] = Map([])
      for entry in ep {
        match entry {
          (k, v) => ep_fields[k] = v
        }
      }
      if ep_fields.length() > 0 {
        fields["extra_params"] = Json::object(ep_fields)
      }
    }
    None => ()
  }
  Json::object(fields)
}

///|
/// === LucentDiscovery ===
pub fn LucentDiscovery::to_json(self : LucentDiscovery) -> Json {
  Json::object({
    "schema_version": Json::string(self.schema_version),
    "protocol_version": Json::string(self.protocol_version),
    "schema_url": Json::string(self.schema_url),
    "providers": Json::array(self.providers.map(fn(p) { p.to_json() })),
  })
}

///|
/// === Helper: stringify a Lux type to JSON ===
pub fn lux_to_json_string(jv : Json) -> String {
  jv.stringify()
}
