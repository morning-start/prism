///|
/// Lux IR to_json 白盒测试
///
/// 验证所有 to_json() 输出可通过 @json.parse 反序列化，
/// 且关键字段与预期一致。

///|
/// === 工具函数 ===

///|
fn json_get(jv : Json, key : String) -> Json? {
  match jv {
    Object(m) => m.get(key)
    _ => None
  }
}

///|
fn json_str(jv : Json, key : String) -> String? {
  match jv {
    Object(m) =>
      match m.get(key) {
        Some(String(s)) => Some(s)
        _ => None
      }
    _ => None
  }
}

///|
fn json_arr(jv : Json, key : String) -> Array[Json]? {
  match jv {
    Object(m) =>
      match m.get(key) {
        Some(Array(a)) => Some(a)
        _ => None
      }
    _ => None
  }
}

///|
fn json_bool(jv : Json, key : String) -> Bool? {
  match jv {
    Object(m) =>
      match m.get(key) {
        Some(True) => Some(true)
        Some(False) => Some(false)
        _ => None
      }
    _ => None
  }
}

///|
fn json_num(jv : Json, key : String) -> Double? {
  match jv {
    Object(m) =>
      match m.get(key) {
        Some(Number(n, ..)) => Some(n)
        _ => None
      }
    _ => None
  }
}

///|
/// === LucentRole ===
test "LucentRole::to_json - all variants" {
  assert_eq(LucentRole::System.to_json().stringify(), "\"system\"")
  assert_eq(LucentRole::User.to_json().stringify(), "\"user\"")
  assert_eq(LucentRole::Assistant.to_json().stringify(), "\"assistant\"")
  assert_eq(LucentRole::Tool.to_json().stringify(), "\"tool\"")
  assert_eq(LucentRole::Model.to_json().stringify(), "\"model\"")
  assert_eq(LucentRole::Developer.to_json().stringify(), "\"developer\"")
  assert_eq(LucentRole::Native("custom").to_json().stringify(), "\"custom\"")
}

///|
test "LucentRole::from_json - round trip" {
  let jv = @json.parse("\"user\"")
  match LucentRole::from_json(jv) {
    Ok(LucentRole::User) => ()
    _ => fail("expected User")
  }
  let jv2 = @json.parse("\"assistant\"")
  match LucentRole::from_json(jv2) {
    Ok(LucentRole::Assistant) => ()
    _ => fail("expected Assistant")
  }
  let jv3 = @json.parse("\"custom\"")
  match LucentRole::from_json(jv3) {
    Ok(LucentRole::Native(s)) => assert_eq(s, "custom")
    _ => fail("expected Native(custom)")
  }
}

///|
/// === LucentModality ===
test "LucentModality::to_json - all variants" {
  assert_eq(LucentModality::Text.to_json().stringify(), "\"text\"")
  assert_eq(LucentModality::Image.to_json().stringify(), "\"image\"")
  assert_eq(LucentModality::Audio.to_json().stringify(), "\"audio\"")
  assert_eq(LucentModality::Video.to_json().stringify(), "\"video\"")
  assert_eq(LucentModality::Pdf.to_json().stringify(), "\"pdf\"")
  assert_eq(
    LucentModality::Native("haptic").to_json().stringify(),
    "\"haptic\"",
  )
}

///|
/// === LucentMultimedia ===
test "LucentMultimedia::to_json - url source" {
  let mm = LucentMultimedia::new(
    "image/jpeg",
    LucentMediaSource::Url("https://example.com/photo.jpg"),
  )
  let jv = mm.to_json()
  let s = jv.stringify()
  let parsed = @json.parse(s)
  match json_str(parsed, "media_type") {
    Some(v) => assert_eq(v, "image/jpeg")
    _ => fail("missing media_type")
  }
  match json_get(parsed, "source") {
    Some(src) =>
      match json_str(src, "type") {
        Some(t) => assert_eq(t, "url")
        _ => fail("source missing type")
      }
    _ => fail("missing source")
  }
}

///|
test "LucentMultimedia::to_json - inline source" {
  let mm = LucentMultimedia::new(
    "audio/wav",
    LucentMediaSource::Inline("base64data"),
  )
  let jv = mm.to_json()
  match json_get(jv, "source") {
    Some(src) =>
      match json_str(src, "type") {
        Some(t) => assert_eq(t, "inline")
        _ => fail("source missing type")
      }
    _ => fail("missing source")
  }
}

///|
/// === LucentAnnotation ===
test "LucentAnnotation::to_json - all fields" {
  let ann = LucentAnnotation::new(
    LucentAnnotationKind::Url,
    Some("https://source.com"),
    Some("ref-1"),
    Some(0),
    Some(100),
  )
  let jv = ann.to_json()
  match json_str(jv, "kind") {
    Some(v) => assert_eq(v, "url")
    _ => fail("missing kind")
  }
  match json_str(jv, "text") {
    Some(v) => assert_eq(v, "https://source.com")
    _ => fail("missing text")
  }
  match json_str(jv, "ref") {
    Some(v) => assert_eq(v, "ref-1")
    _ => fail("missing ref")
  }
  match json_num(jv, "start") {
    Some(v) => assert_eq(v, 0.0)
    _ => fail("missing start")
  }
  match json_num(jv, "end") {
    Some(v) => assert_eq(v, 100.0)
    _ => fail("missing end")
  }
}

///|
test "LucentAnnotation::to_json - minimal fields" {
  let ann = LucentAnnotation::new(
    LucentAnnotationKind::FileCitation,
    None,
    None,
    None,
    None,
  )
  let jv = ann.to_json()
  match json_str(jv, "kind") {
    Some(v) => assert_eq(v, "file_citation")
    _ => fail("missing kind")
  }
  assert_true(json_get(jv, "text") is None)
  assert_true(json_get(jv, "ref") is None)
  assert_true(json_get(jv, "start") is None)
  assert_true(json_get(jv, "end") is None)
}

///|
/// === LucentThinking ===
test "LucentThinking::to_json - visible with signature and summary" {
  let th = LucentThinking::new(
    "Let me think...",
    Some("sig-abc"),
    false,
    Some([LucentContent::text("step 1"), LucentContent::text("step 2")]),
  )
  let jv = th.to_json()
  match json_str(jv, "text") {
    Some(v) => assert_eq(v, "Let me think...")
    _ => fail("missing text")
  }
  match json_str(jv, "signature") {
    Some(v) => assert_eq(v, "sig-abc")
    _ => fail("missing signature")
  }
  match json_bool(jv, "redacted") {
    Some(v) => assert_eq(v, false)
    _ => fail("missing redacted")
  }
  match json_arr(jv, "summary") {
    Some(arr) => assert_eq(arr.length(), 2)
    _ => fail("missing summary")
  }
}

///|
test "LucentThinking::to_json - redacted no optional fields" {
  let th = LucentThinking::redacted(None)
  let jv = th.to_json()
  match json_bool(jv, "redacted") {
    Some(v) => assert_eq(v, true)
    _ => fail("missing redacted")
  }
  assert_true(json_get(jv, "signature") is None)
  assert_true(json_get(jv, "summary") is None)
}

///|
/// === LucentToolUse ===
test "LucentToolUse::to_json" {
  let tu = LucentToolUse::new(
    "call-1",
    "get_weather",
    "{\"city\":\"Beijing\"}",
    None,
  )
  let jv = tu.to_json()
  match json_str(jv, "id") {
    Some(v) => assert_eq(v, "call-1")
    _ => fail("missing id")
  }
  match json_str(jv, "name") {
    Some(v) => assert_eq(v, "get_weather")
    _ => fail("missing name")
  }
  match json_str(jv, "arguments") {
    Some(v) => assert_eq(v, "{\"city\":\"Beijing\"}")
    _ => fail("missing arguments")
  }
}

///|
/// === LucentToolResult ===
test "LucentToolResult::to_json" {
  let tr = LucentToolResult::ok("call-1", [LucentContent::text("sunny")])
  let jv = tr.to_json()
  match json_str(jv, "tool_use_id") {
    Some(v) => assert_eq(v, "call-1")
    _ => fail("missing tool_use_id")
  }
  match json_bool(jv, "is_error") {
    Some(v) => assert_eq(v, false)
    _ => fail("missing is_error")
  }
  match json_arr(jv, "content") {
    Some(arr) => assert_eq(arr.length(), 1)
    _ => fail("missing content")
  }
}

///|
test "LucentToolResult::to_json - error" {
  let tr = LucentToolResult::error("call-2", [
    LucentContent::text("error occurred"),
  ])
  let jv = tr.to_json()
  match json_bool(jv, "is_error") {
    Some(v) => assert_eq(v, true)
    _ => fail("missing is_error")
  }
}

///|
/// === LucentAgentAction ===
test "LucentAgentAction::to_json - minimal" {
  let aa = LucentAgentAction::new(
    "custom_tool",
    "act-1",
    None,
    None,
    None,
    None,
    None,
  )
  let jv = aa.to_json()
  match json_str(jv, "kind") {
    Some(v) => assert_eq(v, "custom_tool")
    _ => fail("missing kind")
  }
  match json_str(jv, "id") {
    Some(v) => assert_eq(v, "act-1")
    _ => fail("missing id")
  }
  assert_true(json_get(jv, "call_id") is None)
  assert_true(json_get(jv, "name") is None)
  assert_true(json_get(jv, "arguments") is None)
  assert_true(json_get(jv, "result") is None)
}

///|
test "LucentAgentAction::to_json - all fields" {
  let aa = LucentAgentAction::new(
    "research",
    "act-2",
    Some("call-99"),
    Some("web_search"),
    Some("{\"q\":\"weather\"}"),
    Some("sunny"),
    Some(@json.parse("\"raw\"")),
  )
  let jv = aa.to_json()
  match json_str(jv, "kind") {
    Some(v) => assert_eq(v, "research")
    _ => fail("missing kind")
  }
  match json_str(jv, "call_id") {
    Some(v) => assert_eq(v, "call-99")
    _ => fail("missing call_id")
  }
  match json_str(jv, "name") {
    Some(v) => assert_eq(v, "web_search")
    _ => fail("missing name")
  }
  match json_str(jv, "arguments") {
    Some(v) => assert_eq(v, "{\"q\":\"weather\"}")
    _ => fail("missing arguments")
  }
  match json_str(jv, "result") {
    Some(v) => assert_eq(v, "sunny")
    _ => fail("missing result")
  }
}

///|
/// === LucentContent ===
test "LucentContent::to_json - text" {
  let c = LucentContent::text("Hello world")
  let jv = c.to_json()
  match json_str(jv, "type") {
    Some(v) => assert_eq(v, "text")
    _ => fail("wrong type")
  }
  match json_str(jv, "text") {
    Some(v) => assert_eq(v, "Hello world")
    _ => fail("wrong text")
  }
}

///|
test "LucentContent::to_json - text with annotations" {
  let ann = LucentAnnotation::new(
    LucentAnnotationKind::Url,
    Some("https://src"),
    None,
    None,
    None,
  )
  let c = LucentContent::text_with_annotations("cited text", [ann])
  let jv = c.to_json()
  match json_str(jv, "type") {
    Some(v) => assert_eq(v, "text")
    _ => fail("wrong type")
  }
  match json_arr(jv, "annotations") {
    Some(arr) => assert_eq(arr.length(), 1)
    _ => fail("missing annotations")
  }
}

///|
test "LucentContent::to_json - tool_use" {
  let c = LucentContent::tool_use("call-1", "get_weather", "{}", None)
  let jv = c.to_json()
  match json_str(jv, "type") {
    Some(v) => assert_eq(v, "tool_use")
    _ => fail("wrong type")
  }
}

///|
test "LucentContent::to_json - tool_result" {
  let c = LucentContent::tool_result("call-1", [LucentContent::text("result")])
  let jv = c.to_json()
  match json_str(jv, "type") {
    Some(v) => assert_eq(v, "tool_result")
    _ => fail("wrong type")
  }
}

///|
test "LucentContent::to_json - thinking" {
  let c = LucentContent::thinking("hmm...", Some("sig-1"))
  let jv = c.to_json()
  match json_str(jv, "type") {
    Some(v) => assert_eq(v, "thinking")
    _ => fail("wrong type")
  }
}

///|
test "LucentContent::to_json - refusal" {
  let c = LucentContent::refusal("I cannot answer that")
  let jv = c.to_json()
  match json_str(jv, "type") {
    Some(v) => assert_eq(v, "refusal")
    _ => fail("wrong type")
  }
  match json_str(jv, "refusal") {
    Some(v) => assert_eq(v, "I cannot answer that")
    _ => fail("wrong text")
  }
}

///|
test "LucentContent::to_json - image" {
  let c = LucentContent::image(
    "image/png",
    LucentMediaSource::Url("https://example.com/img.png"),
  )
  let jv = c.to_json()
  match json_str(jv, "type") {
    Some(v) => assert_eq(v, "image")
    _ => fail("wrong type")
  }
}

///|
test "LucentContent::to_json - audio" {
  let c = LucentContent::audio(
    "audio/mp3",
    LucentMediaSource::Inline("base64audio"),
  )
  let jv = c.to_json()
  match json_str(jv, "type") {
    Some(v) => assert_eq(v, "audio")
    _ => fail("wrong type")
  }
}

///|
test "LucentContent::to_json - video" {
  let c = LucentContent::video(
    "video/mp4",
    LucentMediaSource::Url("https://example.com/vid.mp4"),
  )
  let jv = c.to_json()
  match json_str(jv, "type") {
    Some(v) => assert_eq(v, "video")
    _ => fail("wrong type")
  }
}

///|
test "LucentContent::to_json - native" {
  let c = LucentContent::native(
    "custom_format",
    @json.parse("{\"key\":\"val\"}"),
  )
  let jv = c.to_json()
  match json_str(jv, "type") {
    Some(v) => assert_eq(v, "native")
    _ => fail("wrong type")
  }
  match json_str(jv, "native_tag") {
    Some(v) => assert_eq(v, "custom_format")
    _ => fail("wrong native_tag")
  }
}

///|
/// === LucentMessage ===
test "LucentMessage::to_json" {
  let msg = LucentMessage::new(LucentRole::User, [
    LucentContent::text("Hello"),
    LucentContent::text("World"),
  ])
  let jv = msg.to_json()
  match json_str(jv, "role") {
    Some(v) => assert_eq(v, "user")
    _ => fail("wrong role")
  }
  match json_arr(jv, "content") {
    Some(arr) => assert_eq(arr.length(), 2)
    _ => fail("wrong content count")
  }
}

///|
/// === LucentConversationItem ===
test "LucentConversationItem::to_json - message" {
  let ci = LucentConversationItem::message(
    LucentMessage::new(LucentRole::Assistant, [LucentContent::text("ok")]),
  )
  let jv = ci.to_json()
  match json_str(jv, "type") {
    Some(v) => assert_eq(v, "message")
    _ => fail("wrong type")
  }
}

///|
test "LucentConversationItem::to_json - tool_call" {
  let tu = LucentToolUse::new("call-1", "search", "{}", None)
  let ci = LucentConversationItem::tool_call(tu)
  let jv = ci.to_json()
  match json_str(jv, "type") {
    Some(v) => assert_eq(v, "tool_call")
    _ => fail("wrong type")
  }
}

///|
test "LucentConversationItem::to_json - reasoning" {
  let th = LucentThinking::new("thinking...", None, false, None)
  let ci = LucentConversationItem::reasoning(th)
  let jv = ci.to_json()
  match json_str(jv, "type") {
    Some(v) => assert_eq(v, "reasoning")
    _ => fail("wrong type")
  }
}

///|
test "LucentConversationItem::to_json - agent_action" {
  let aa = LucentAgentAction::new(
    "custom",
    "act-1",
    None,
    None,
    None,
    None,
    None,
  )
  let ci = LucentConversationItem::agent_action(aa)
  let jv = ci.to_json()
  match json_str(jv, "type") {
    Some(v) => assert_eq(v, "agent_action")
    _ => fail("wrong type")
  }
}

///|
/// === LucentTool ===
test "LucentTool::to_json - simple" {
  let tool = LucentTool::simple(
    "get_weather", "Get the weather", "{\"type\":\"object\"}",
  )
  let jv = tool.to_json()
  match json_str(jv, "name") {
    Some(v) => assert_eq(v, "get_weather")
    _ => fail("missing name")
  }
  match json_str(jv, "description") {
    Some(v) => assert_eq(v, "Get the weather")
    _ => fail("missing description")
  }
  assert_true(json_get(jv, "strict") is None)
}

///|
test "LucentTool::to_json - with strict" {
  let tool = LucentTool::new(
    "calculator",
    Some("Do math"),
    "{\"type\":\"object\"}",
    Some(true),
  )
  let jv = tool.to_json()
  match json_str(jv, "name") {
    Some(v) => assert_eq(v, "calculator")
    _ => fail("missing name")
  }
  match json_bool(jv, "strict") {
    Some(v) => assert_eq(v, true)
    _ => fail("missing strict")
  }
}

///|
/// === LucentToolChoice ===
test "LucentToolChoice::to_json - all variants" {
  assert_eq(LucentToolChoice::Auto.to_json().stringify(), "\"auto\"")
  assert_eq((None : LucentToolChoice).to_json().stringify(), "\"none\"")
  assert_eq(LucentToolChoice::Required.to_json().stringify(), "\"required\"")
}

///|
test "LucentToolChoice::to_json - specific tool" {
  let jv = LucentToolChoice::SpecificTool("search").to_json()
  match json_str(jv, "type") {
    Some(v) => assert_eq(v, "specific_tool")
    _ => fail("wrong type")
  }
  match json_str(jv, "name") {
    Some(v) => assert_eq(v, "search")
    _ => fail("wrong name")
  }
}

///|
/// === LucentStructuredOutput ===
test "LucentStructuredOutput::to_json - all variants" {
  assert_eq(
    LucentStructuredOutput::JsonObject.to_json().stringify(),
    "\"json_object\"",
  )
  assert_eq(LucentStructuredOutput::Text.to_json().stringify(), "\"text\"")
}

///|
test "LucentStructuredOutput::to_json - json_schema" {
  let jv = LucentStructuredOutput::JsonSchema("{\"type\":\"object\"}").to_json()
  match json_str(jv, "type") {
    Some(v) => assert_eq(v, "json_schema")
    _ => fail("wrong type")
  }
}

///|
/// === LucentOptions ===
test "LucentOptions::to_json - defaults" {
  let opts = LucentOptions::default()
  let jv = opts.to_json()
  match json_bool(jv, "stream") {
    Some(v) => assert_eq(v, false)
    _ => fail("missing stream")
  }
  assert_true(json_get(jv, "temperature") is None)
  assert_true(json_get(jv, "structured_output") is None)
}

///|
test "LucentOptions::to_json - all fields" {
  let opts = LucentOptions::new(
    Some(0.7),
    Some(0.9),
    Some(40),
    Some(4096),
    Some(["STOP"]),
    true,
    Some(1),
    Some(42),
    Some(LucentStructuredOutput::JsonObject),
  )
  let jv = opts.to_json()
  match json_num(jv, "temperature") {
    Some(v) => assert_eq(v, 0.7)
    _ => fail("missing temperature")
  }
  match json_num(jv, "top_p") {
    Some(v) => assert_eq(v, 0.9)
    _ => fail("missing top_p")
  }
  match json_num(jv, "top_k") {
    Some(v) => assert_eq(v, 40.0)
    _ => fail("missing top_k")
  }
  match json_bool(jv, "stream") {
    Some(v) => assert_eq(v, true)
    _ => fail("missing stream")
  }
  match json_num(jv, "max_output_tokens") {
    Some(v) => assert_eq(v, 4096.0)
    _ => fail("missing max")
  }
  match json_num(jv, "seed") {
    Some(v) => assert_eq(v, 42.0)
    _ => fail("missing seed")
  }
  match json_arr(jv, "stop") {
    Some(arr) => assert_eq(arr.length(), 1)
    _ => fail("missing stop")
  }
  match json_str(jv, "structured_output") {
    Some(v) => assert_eq(v, "json_object")
    _ => fail("missing structured_output")
  }
}

///|
/// === LucentReasoningConfig ===
test "LucentReasoningConfig::to_json - disabled" {
  let rc = LucentReasoningConfig::disabled()
  let jv = rc.to_json()
  match json_bool(jv, "enabled") {
    Some(v) => assert_eq(v, false)
    _ => fail("should be disabled")
  }
}

///|
test "LucentReasoningConfig::to_json - enabled with effort" {
  let rc = LucentReasoningConfig::enabled(Some(2048))
  let jv = rc.to_json()
  match json_bool(jv, "enabled") {
    Some(v) => assert_eq(v, true)
    _ => fail("should be enabled")
  }
  match json_num(jv, "budget_tokens") {
    Some(v) => assert_eq(v, 2048.0)
    _ => fail("missing budget")
  }
}

///|
/// === LucentCapabilities ===
test "LucentCapabilities::to_json - default" {
  let caps = LucentCapabilities::default()
  let jv = caps.to_json()
  match json_bool(jv, "tool_calling") {
    Some(v) => assert_eq(v, false)
    _ => fail("wrong tool_calling")
  }
  match json_arr(jv, "input_modalities") {
    Some(_) => ()
    _ => fail("missing input_modalities")
  }
  match json_arr(jv, "output_modalities") {
    Some(_) => ()
    _ => fail("missing output_modalities")
  }
}

///|
/// === LucentRequest ===
test "LucentRequest::to_json - minimal request" {
  let req = LucentRequest::from_messages(
    "gpt-4o",
    None,
    [LucentMessage::new(LucentRole::User, [LucentContent::text("hi")])],
    None,
    None,
    LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
  let jv = req.to_json()
  match json_str(jv, "schema_version") {
    Some(v) => assert_eq(v, "v1")
    _ => fail("wrong schema")
  }
  match json_str(jv, "model") {
    Some(v) => assert_eq(v, "gpt-4o")
    _ => fail("wrong model")
  }
  match json_arr(jv, "conversation") {
    Some(arr) => assert_eq(arr.length(), 1)
    _ => fail("missing or empty conversation")
  }
  assert_true(json_get(jv, "instructions") is None)
  assert_true(json_get(jv, "tools") is None)
  assert_true(json_get(jv, "tool_choice") is None)
  assert_true(json_get(jv, "metadata") is None)
}

///|
test "LucentRequest::to_json - with all fields" {
  let tool = LucentTool::simple(
    "search", "Search tool", "{\"type\":\"object\"}",
  )
  let req = LucentRequest::new(
    "1.0",
    Some([LucentContent::text("You are helpful")]),
    [
      LucentConversationItem::message(
        LucentMessage::new(LucentRole::User, [LucentContent::text("query")]),
      ),
    ],
    Some([tool]),
    Some(LucentToolChoice::Auto),
    LucentOptions::default(),
    Some(LucentCapabilities::default()),
    Some(LucentReasoningConfig::disabled()),
    Some({ "user_id": "abc" }),
    Some({ "custom": @json.parse("\"value\"") }),
  )
  let jv = req.to_json()
  match json_str(jv, "model") {
    Some(v) => assert_eq(v, "1.0")
    _ => fail("wrong model")
  }
  match json_arr(jv, "instructions") {
    Some(arr) => assert_eq(arr.length(), 1)
    _ => fail("missing instructions")
  }
  match json_arr(jv, "tools") {
    Some(arr) => assert_eq(arr.length(), 1)
    _ => fail("missing tools")
  }
  match json_str(jv, "tool_choice") {
    Some(v) => assert_eq(v, "auto")
    _ => fail("missing tool_choice")
  }
}

///|
/// === LucentResponse ===
test "LucentResponse::to_json" {
  let content = LucentContent::text("Hello!")
  let msg = LucentMessage::new(LucentRole::Assistant, [content])
  let choice = LucentChoice::new(0, msg, LucentFinishReason::Stop, None)
  let resp = LucentResponse::new(
    "resp-1",
    "gpt-4o",
    Some(1_700_000_000),
    [choice],
    Some(LucentUsage::new(10, 20, 30)),
    None,
  )
  let jv = resp.to_json()
  match json_str(jv, "schema_version") {
    Some(v) => assert_eq(v, "v1")
    _ => fail("wrong schema")
  }
  match json_str(jv, "id") {
    Some(v) => assert_eq(v, "resp-1")
    _ => fail("wrong id")
  }
  match json_str(jv, "model") {
    Some(v) => assert_eq(v, "gpt-4o")
    _ => fail("wrong model")
  }
  match json_num(jv, "created_at") {
    Some(v) => assert_eq(v, 1_700_000_000.0)
    _ => fail("wrong created_at")
  }
  match json_arr(jv, "choices") {
    Some(arr) => assert_eq(arr.length(), 1)
    _ => fail("wrong choices")
  }
}

///|
/// === LucentUsage ===
test "LucentUsage::to_json - with reasoning" {
  let usage = LucentUsage::with_reasoning(100, 50, 150, 20)
  let jv = usage.to_json()
  match json_num(jv, "prompt_tokens") {
    Some(v) => assert_eq(v, 100.0)
    _ => fail("wrong prompt")
  }
  match json_num(jv, "completion_tokens") {
    Some(v) => assert_eq(v, 50.0)
    _ => fail("wrong completion")
  }
  match json_num(jv, "total_tokens") {
    Some(v) => assert_eq(v, 150.0)
    _ => fail("wrong total")
  }
  match json_num(jv, "reasoning_tokens") {
    Some(v) => assert_eq(v, 20.0)
    _ => fail("wrong reasoning")
  }
}

///|
test "LucentUsage::to_json - basic" {
  let usage = LucentUsage::new(5, 10, 15)
  let jv = usage.to_json()
  assert_true(json_get(jv, "reasoning_tokens") is None)
  assert_true(json_get(jv, "cached_tokens") is None)
}

///|
/// === LucentSafetyRating ===
test "LucentSafetyRating::to_json" {
  let sr = LucentSafetyRating::new("harassment", "low")
  let jv = sr.to_json()
  match json_str(jv, "category") {
    Some(v) => assert_eq(v, "harassment")
    _ => fail("wrong category")
  }
  match json_str(jv, "probability") {
    Some(v) => assert_eq(v, "low")
    _ => fail("wrong probability")
  }
}

///|
/// === LucentError + LucentErrorKind ===
test "LucentError::to_json" {
  let err = LucentError::new(
    LucentErrorKind::RateLimit,
    "Too many requests",
    Some("429"),
  )
  let jv = err.to_json()
  match json_str(jv, "message") {
    Some(v) => assert_eq(v, "Too many requests")
    _ => fail("wrong message")
  }
  match json_str(jv, "provider_code") {
    Some(v) => assert_eq(v, "429")
    _ => fail("wrong code")
  }
}

///|
test "LucentErrorKind::to_json - all built-in" {
  assert_eq(LucentErrorKind::RateLimit.to_json().stringify(), "\"rate_limit\"")
  assert_eq(
    LucentErrorKind::InvalidRequest.to_json().stringify(),
    "\"invalid_request\"",
  )
  assert_eq(
    LucentErrorKind::Authentication.to_json().stringify(),
    "\"authentication\"",
  )
  assert_eq(
    LucentErrorKind::ServerError.to_json().stringify(),
    "\"server_error\"",
  )
  assert_eq(
    LucentErrorKind::ContentFilter.to_json().stringify(),
    "\"content_filter\"",
  )
  assert_eq(
    LucentErrorKind::Native("custom").to_json().stringify(),
    "\"custom\"",
  )
}

///|
/// === LucentBlockType ===
test "LucentBlockType::to_json - text" {
  assert_eq(LucentBlockType::Text.to_json().stringify(), "\"text\"")
}

///|
test "LucentBlockType::to_json - tool_call" {
  let jv = LucentBlockType::ToolCall("call-1", "search").to_json()
  match json_str(jv, "type") {
    Some(v) => assert_eq(v, "tool_call")
    _ => fail("wrong type")
  }
  match json_str(jv, "id") {
    Some(v) => assert_eq(v, "call-1")
    _ => fail("wrong id")
  }
  match json_str(jv, "name") {
    Some(v) => assert_eq(v, "search")
    _ => fail("wrong name")
  }
}

///|
/// === LucentBlockDelta ===
test "LucentBlockDelta::to_json - text" {
  let jv = LucentBlockDelta::text_delta("Hello").to_json()
  match json_str(jv, "type") {
    Some(v) => assert_eq(v, "text")
    _ => fail("wrong type")
  }
  match json_str(jv, "text") {
    Some(v) => assert_eq(v, "Hello")
    _ => fail("wrong text")
  }
}

///|
test "LucentBlockDelta::to_json - thinking" {
  let jv = LucentBlockDelta::thinking_delta("Let me think...").to_json()
  match json_str(jv, "type") {
    Some(v) => assert_eq(v, "thinking")
    _ => fail("wrong type")
  }
}

///|
test "LucentBlockDelta::to_json - tool_arguments" {
  let jv = LucentBlockDelta::tool_arguments_delta("{\"city\":\"Paris\"}").to_json()
  match json_str(jv, "type") {
    Some(v) => assert_eq(v, "tool_arguments")
    _ => fail("wrong type")
  }
}

///|
test "LucentBlockDelta::to_json - refusal" {
  let jv = LucentBlockDelta::refusal_delta("Cannot do that").to_json()
  match json_str(jv, "type") {
    Some(v) => assert_eq(v, "refusal")
    _ => fail("wrong type")
  }
}

///|
/// === LucentStreamEvent ===
test "LucentStreamEvent::to_json - conversation_start" {
  let meta = LucentConversationMeta::new(
    Some("conv-1"),
    Some("gpt-4o"),
    Some(5),
  )
  let ev = LucentStreamEvent::ConversationStart(meta)
  let jv = ev.to_json()
  match json_str(jv, "event") {
    Some(v) => assert_eq(v, "conversation_start")
    _ => fail("wrong event")
  }
}

///|
test "LucentStreamEvent::to_json - item_start and item_end" {
  let msg = LucentMessage::new(LucentRole::User, [LucentContent::text("hi")])
  let ci = LucentConversationItem::message(msg)
  let start = LucentStreamEvent::ItemStart(0, ci)
  let end = LucentStreamEvent::ItemEnd(0)
  match json_str(start.to_json(), "event") {
    Some(v) => assert_eq(v, "item_start")
    _ => fail("wrong event")
  }
  match json_num(start.to_json(), "index") {
    Some(v) => assert_eq(v, 0.0)
    _ => fail("wrong index")
  }
  match json_str(end.to_json(), "event") {
    Some(v) => assert_eq(v, "item_end")
    _ => fail("wrong event")
  }
}

///|
test "LucentStreamEvent::to_json - block lifecycle" {
  let bt = LucentBlockType::ToolCall("call-1", "search")
  let bs = LucentStreamEvent::BlockStart(0, bt)
  let bd = LucentStreamEvent::BlockDelta(
    0,
    LucentBlockDelta::text_delta("partial"),
  )
  let be = LucentStreamEvent::BlockEnd(0)
  match json_str(bs.to_json(), "event") {
    Some(v) => assert_eq(v, "block_start")
    _ => fail("wrong block_start event")
  }
  match json_str(bd.to_json(), "event") {
    Some(v) => assert_eq(v, "block_delta")
    _ => fail("wrong block_delta event")
  }
  match json_str(be.to_json(), "event") {
    Some(v) => assert_eq(v, "block_end")
    _ => fail("wrong block_end event")
  }
}

///|
test "LucentStreamEvent::to_json - finish" {
  let ev = LucentStreamEvent::Finish(LucentFinishReason::Stop)
  let jv = ev.to_json()
  match json_str(jv, "event") {
    Some(v) => assert_eq(v, "finish")
    _ => fail("wrong event")
  }
  match json_str(jv, "finish_reason") {
    Some(v) => assert_eq(v, "stop")
    _ => fail("wrong reason")
  }
}

///|
test "LucentStreamEvent::to_json - usage event" {
  let usage = LucentUsage::new(5, 10, 15)
  let ev = LucentStreamEvent::Usage(usage)
  let jv = ev.to_json()
  match json_str(jv, "event") {
    Some(v) => assert_eq(v, "usage")
    _ => fail("wrong event")
  }
}

///|
test "LucentStreamEvent::to_json - error event" {
  let err = LucentError::new(
    LucentErrorKind::ServerError,
    "internal error",
    None,
  )
  let ev = LucentStreamEvent::Error(err)
  let jv = ev.to_json()
  match json_str(jv, "event") {
    Some(v) => assert_eq(v, "error")
    _ => fail("wrong event")
  }
}

///|
test "LucentStreamEvent::to_json - done" {
  let jv = LucentStreamEvent::Done.to_json()
  match json_str(jv, "event") {
    Some(v) => assert_eq(v, "done")
    _ => fail("wrong event")
  }
}

///|
test "LucentStreamEvent::to_json - annotations" {
  let ann = LucentAnnotation::new(
    LucentAnnotationKind::Url,
    Some("https://src"),
    None,
    None,
    None,
  )
  let ev = LucentStreamEvent::Annotations(0, [ann])
  let jv = ev.to_json()
  match json_str(jv, "event") {
    Some(v) => assert_eq(v, "annotations")
    _ => fail("wrong event")
  }
  match json_arr(jv, "annotations") {
    Some(arr) => assert_eq(arr.length(), 1)
    _ => fail("missing annotations")
  }
}

///|
/// === LucentConversationMeta ===
test "LucentConversationMeta::to_json - all fields" {
  let meta = LucentConversationMeta::new(
    Some("conv-1"),
    Some("gpt-4o"),
    Some(42),
  )
  let jv = meta.to_json()
  match json_str(jv, "id") {
    Some(v) => assert_eq(v, "conv-1")
    _ => fail("wrong id")
  }
  match json_str(jv, "model") {
    Some(v) => assert_eq(v, "gpt-4o")
    _ => fail("wrong model")
  }
  match json_num(jv, "usage_input") {
    Some(v) => assert_eq(v, 42.0)
    _ => fail("wrong usage_input")
  }
}

///|
test "LucentConversationMeta::to_json - empty" {
  let meta = LucentConversationMeta::new(None, None, None)
  let jv = meta.to_json()
  assert_true(json_get(jv, "id") is None)
  assert_true(json_get(jv, "model") is None)
  assert_true(json_get(jv, "usage_input") is None)
}

///|
/// === ProviderCapability ===
test "ProviderCapability::to_json" {
  let caps = LucentCapabilities::default()
  let pc = ProviderCapability::new("gpt-*", "openai", caps, None)
  let jv = pc.to_json()
  match json_str(jv, "model_pattern") {
    Some(v) => assert_eq(v, "gpt-*")
    _ => fail("wrong pattern")
  }
  match json_str(jv, "provider") {
    Some(v) => assert_eq(v, "openai")
    _ => fail("wrong provider")
  }
}

///|
/// === LucentDiscovery ===
test "LucentDiscovery::to_json" {
  let caps = LucentCapabilities::default()
  let pc = ProviderCapability::new("gpt-*", "openai", caps, None)
  let disc = LucentDiscovery::new(
    "lux-v1",
    "https://raw.githubusercontent.com/moonbit-community/prism/main/schemas/lux-ir-v1.json",
    [pc],
  )
  let jv = disc.to_json()
  match json_str(jv, "schema_version") {
    Some(v) => assert_eq(v, "v1")
    _ => fail("wrong schema")
  }
  match json_str(jv, "protocol_version") {
    Some(v) => assert_eq(v, "lux-v1")
    _ => fail("wrong protocol")
  }
  match json_str(jv, "schema_url") {
    Some(v) =>
      assert_eq(
        v, "https://raw.githubusercontent.com/moonbit-community/prism/main/schemas/lux-ir-v1.json",
      )
    _ => fail("wrong url")
  }
  match json_arr(jv, "providers") {
    Some(arr) => assert_eq(arr.length(), 1)
    _ => fail("missing providers")
  }
}

///|
/// === lux_to_json_string ===
test "lux_to_json_string helper" {
  let jv = Json::string("hello")
  let s = lux_to_json_string(jv)
  assert_eq(s, "\"hello\"")
}

///|
/// === Serialization round-trip via @json.parse + .stringify() ===
test "round trip - simple types" {
  let values : Array[Json] = [
    LucentRole::System.to_json(),
    LucentRole::User.to_json(),
    LucentModality::Text.to_json(),
    LucentModality::Image.to_json(),
    LucentFinishReason::Stop.to_json(),
    LucentFinishReason::Length.to_json(),
    LucentToolChoice::Auto.to_json(),
    LucentToolChoice::Required.to_json(),
    LucentErrorKind::RateLimit.to_json(),
    LucentErrorKind::InvalidRequest.to_json(),
    LucentStructuredOutput::JsonObject.to_json(),
  ]
  for v in values {
    let s = v.stringify()
    let parsed = @json.parse(s)
    let s2 = parsed.stringify()
    assert_eq(s, s2)
  }
}

///|
test "round trip - complex value" {
  let msg = LucentMessage::new(LucentRole::User, [
    LucentContent::text("Hello, world!"),
  ])
  let jv = msg.to_json()
  let s = jv.stringify()
  let parsed = @json.parse(s)
  match json_str(parsed, "role") {
    Some(v) => assert_eq(v, "user")
    _ => fail("missing role after round trip")
  }
}

///|
/// === Edge cases ===
test "edge - empty content array" {
  let msg = LucentMessage::new(LucentRole::Assistant, [])
  let jv = msg.to_json()
  match json_arr(jv, "content") {
    Some(arr) => assert_eq(arr.length(), 0)
    _ => fail("missing content")
  }
}

///|
test "edge - nested tool_use in conversation" {
  let tu = LucentToolUse::new("call-1", "search", "{\"q\":\"weather\"}", None)
  let ci = LucentConversationItem::tool_call(tu)
  let req = LucentRequest::new(
    "1.0",
    None,
    [
      LucentConversationItem::message(
        LucentMessage::new(LucentRole::User, [LucentContent::text("hi")]),
      ),
      ci,
    ],
    None,
    None,
    LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
  let jv = req.to_json()
  match json_arr(jv, "conversation") {
    Some(arr) => assert_eq(arr.length(), 2)
    _ => fail("missing conversation")
  }
}

///|
test "edge - string with special characters" {
  let c = LucentContent::text("line1\nline2\ttab\"quote\"\\slash")
  let jv = c.to_json()
  let parsed = @json.parse(jv.stringify())
  match json_str(parsed, "text") {
    Some(v) => assert_eq(v, "line1\nline2\ttab\"quote\"\\slash")
    _ => fail("wrong text after round trip")
  }
}

///|
test "edge - multiple messages" {
  let msgs = [
    LucentMessage::new(LucentRole::System, [
      LucentContent::text("You are a bot"),
    ]),
    LucentMessage::new(LucentRole::User, [LucentContent::text("Hi")]),
    LucentMessage::new(LucentRole::Assistant, [LucentContent::text("Hello!")]),
  ]
  let items = lucent_items_from_messages(msgs)
  let req = LucentRequest::new(
    "1.0",
    None,
    items,
    None,
    None,
    LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
  let jv = req.to_json()
  match json_arr(jv, "conversation") {
    Some(arr) => assert_eq(arr.length(), 3)
    _ => fail("missing conversation")
  }
}
