///|
/// Lux IR from_json 白盒测试 — round-trip 验证
///
/// 模式：construct → to_json() → stringify() → @json.parse() → from_json() → assert_eq

///|
/// === LucentRole ===
test "LucentRole round trip - all variants" {
  let values = [
    LucentRole::System,
    LucentRole::User,
    LucentRole::Assistant,
    LucentRole::Tool,
    LucentRole::Model,
    LucentRole::Developer,
    LucentRole::Native("custom"),
  ]
  for v in values {
    let s = v.to_json().stringify()
    let parsed = @json.parse(s)
    match LucentRole::from_json(parsed) {
      Ok(d) => assert_eq(v, d)
      Err(e) => fail("LucentRole round trip failed: " + e)
    }
  }
}

///|
/// === LucentModality ===
test "LucentModality round trip - all variants" {
  let values = [
    LucentModality::Text,
    LucentModality::Image,
    LucentModality::Audio,
    LucentModality::Video,
    LucentModality::Pdf,
    LucentModality::Native("haptic"),
  ]
  for v in values {
    let s = v.to_json().stringify()
    let parsed = @json.parse(s)
    match LucentModality::from_json(parsed) {
      Ok(d) => assert_true(v == d)
      Err(e) => fail("LucentModality round trip failed: " + e)
    }
  }
}

///|
/// === LucentMultimedia ===
test "LucentMultimedia round trip - all sources" {
  let values = [
    LucentMultimedia::new(
      "image/jpeg",
      LucentMediaSource::Url("https://example.com/photo.jpg"),
    ),
    LucentMultimedia::new("audio/wav", LucentMediaSource::Inline("base64data")),
    LucentMultimedia::new("image/png", LucentMediaSource::FileUri("file-abc")),
  ]
  for v in values {
    let s = v.to_json().stringify()
    let parsed = @json.parse(s)
    match LucentMultimedia::from_json(parsed) {
      Ok(d) => assert_true(v == d)
      Err(e) => fail("LucentMultimedia round trip failed: " + e)
    }
  }
}

///|
/// === LucentAnnotation ===
test "LucentAnnotation round trip - full and minimal" {
  let values = [
    LucentAnnotation::new(
      LucentAnnotationKind::Url,
      Some("https://source.com"),
      Some("ref-1"),
      Some(0),
      Some(100),
    ),
    LucentAnnotation::new(
      LucentAnnotationKind::FileCitation,
      None,
      None,
      None,
      None,
    ),
  ]
  for v in values {
    let s = v.to_json().stringify()
    let parsed = @json.parse(s)
    match LucentAnnotation::from_json(parsed) {
      Ok(d) => assert_true(v == d)
      Err(e) => fail("LucentAnnotation round trip failed: " + e)
    }
  }
}

///|
/// === LucentThinking ===
test "LucentThinking round trip - visible and redacted" {
  let values = [
    LucentThinking::new(
      "Let me think...",
      Some("sig-abc"),
      false,
      Some([LucentContent::text("step 1"), LucentContent::text("step 2")]),
    ),
    LucentThinking::redacted(None),
  ]
  for v in values {
    let s = v.to_json().stringify()
    let parsed = @json.parse(s)
    match LucentThinking::from_json(parsed) {
      Ok(d) => assert_true(v == d)
      Err(e) => fail("LucentThinking round trip failed: " + e)
    }
  }
}

///|
/// === LucentToolUse ===
test "LucentToolUse round trip" {
  let v = LucentToolUse::new(
    "call-1",
    "get_weather",
    "{\"city\":\"Beijing\"}",
    None,
  )
  let s = v.to_json().stringify()
  let parsed = @json.parse(s)
  match LucentToolUse::from_json(parsed) {
    Ok(d) => assert_true(v == d)
    Err(e) => fail("LucentToolUse round trip failed: " + e)
  }
}

///|
/// === LucentToolResult ===
test "LucentToolResult round trip - ok and error" {
  let values = [
    LucentToolResult::ok("call-1", [LucentContent::text("sunny")]),
    LucentToolResult::error("call-2", [LucentContent::text("error occurred")]),
  ]
  for v in values {
    let s = v.to_json().stringify()
    let parsed = @json.parse(s)
    match LucentToolResult::from_json(parsed) {
      Ok(d) => assert_true(v == d)
      Err(e) => fail("LucentToolResult round trip failed: " + e)
    }
  }
}

///|
/// === LucentAgentAction ===
test "LucentAgentAction round trip - minimal and all fields" {
  let values = [
    LucentAgentAction::new("custom_tool", "act-1", None, None, None, None, None),
    LucentAgentAction::new(
      "research",
      "act-2",
      Some("call-99"),
      Some("web_search"),
      Some("{\"q\":\"weather\"}"),
      Some("sunny"),
      Some(@json.parse("\"raw\"")),
    ),
  ]
  for v in values {
    let s = v.to_json().stringify()
    let parsed = @json.parse(s)
    match LucentAgentAction::from_json(parsed) {
      Ok(d) => assert_true(v == d)
      Err(e) => fail("LucentAgentAction round trip failed: " + e)
    }
  }
}

///|
/// === LucentContent ===
test "LucentContent round trip - all variants" {
  let ann = LucentAnnotation::new(
    LucentAnnotationKind::Url,
    Some("https://src"),
    None,
    None,
    None,
  )
  let values = [
    LucentContent::text("Hello world"),
    LucentContent::text_with_annotations("cited text", [ann]),
    LucentContent::tool_use("call-1", "get_weather", "{}", None),
    LucentContent::tool_result("call-1", [LucentContent::text("result")]),
    LucentContent::thinking("hmm...", Some("sig-1")),
    LucentContent::refusal("I cannot answer that"),
    LucentContent::image(
      "image/png",
      LucentMediaSource::Url("https://example.com/img.png"),
    ),
    LucentContent::audio("audio/mp3", LucentMediaSource::Inline("base64audio")),
    LucentContent::video(
      "video/mp4",
      LucentMediaSource::Url("https://example.com/vid.mp4"),
    ),
    LucentContent::native("custom_format", @json.parse("{\"key\":\"val\"}")),
  ]
  for v in values {
    let s = v.to_json().stringify()
    let parsed = @json.parse(s)
    match LucentContent::from_json(parsed) {
      Ok(d) => assert_true(v == d)
      Err(e) => fail("LucentContent round trip failed: " + e)
    }
  }
}

///|
/// === LucentMessage ===
test "LucentMessage round trip" {
  let v = LucentMessage::new(LucentRole::User, [
    LucentContent::text("Hello"),
    LucentContent::text("World"),
  ])
  let s = v.to_json().stringify()
  let parsed = @json.parse(s)
  match LucentMessage::from_json(parsed) {
    Ok(d) => assert_true(v == d)
    Err(e) => fail("LucentMessage round trip failed: " + e)
  }
}

///|
/// === LucentConversationItem ===
test "LucentConversationItem round trip - all variants" {
  let values = [
    LucentConversationItem::message(
      LucentMessage::new(LucentRole::Assistant, [LucentContent::text("ok")]),
    ),
    LucentConversationItem::tool_call(
      LucentToolUse::new("call-1", "search", "{}", None),
    ),
    LucentConversationItem::tool_result(
      LucentToolResult::ok("call-1", [LucentContent::text("ok")]),
    ),
    LucentConversationItem::reasoning(
      LucentThinking::new("thinking...", None, false, None),
    ),
    LucentConversationItem::agent_action(
      LucentAgentAction::new("custom", "act-1", None, None, None, None, None),
    ),
  ]
  for v in values {
    let s = v.to_json().stringify()
    let parsed = @json.parse(s)
    match LucentConversationItem::from_json(parsed) {
      Ok(d) => assert_true(v == d)
      Err(e) => fail("LucentConversationItem round trip failed: " + e)
    }
  }
}

///|
/// === LucentTool ===
test "LucentTool round trip - simple and with strict" {
  let values = [
    LucentTool::simple(
      "get_weather", "Get the weather", "{\"type\":\"object\"}",
    ),
    LucentTool::new(
      "calculator",
      Some("Do math"),
      "{\"type\":\"object\"}",
      Some(true),
    ),
  ]
  for v in values {
    let s = v.to_json().stringify()
    let parsed = @json.parse(s)
    match LucentTool::from_json(parsed) {
      Ok(d) => assert_true(v == d)
      Err(e) => fail("LucentTool round trip failed: " + e)
    }
  }
}

///|
/// === LucentToolChoice ===
test "LucentToolChoice round trip - all variants" {
  let values = [
    LucentToolChoice::Auto,
    (None : LucentToolChoice),
    LucentToolChoice::Required,
    LucentToolChoice::SpecificTool("search"),
  ]
  for v in values {
    let s = v.to_json().stringify()
    let parsed = @json.parse(s)
    match LucentToolChoice::from_json(parsed) {
      Ok(d) => assert_true(v == d)
      Err(e) => fail("LucentToolChoice round trip failed: " + e)
    }
  }
}

///|
/// === LucentStructuredOutput ===
test "LucentStructuredOutput round trip - all variants" {
  let values = [
    LucentStructuredOutput::JsonObject,
    LucentStructuredOutput::Text,
    LucentStructuredOutput::JsonSchema("{\"type\":\"object\"}"),
  ]
  for v in values {
    let s = v.to_json().stringify()
    let parsed = @json.parse(s)
    match LucentStructuredOutput::from_json(parsed) {
      Ok(d) => assert_true(v == d)
      Err(e) => fail("LucentStructuredOutput round trip failed: " + e)
    }
  }
}

///|
/// === LucentOptions ===
test "LucentOptions round trip - defaults and all fields" {
  let values = [
    LucentOptions::default(),
    LucentOptions::new(
      Some(0.7),
      Some(0.9),
      Some(40),
      Some(4096),
      Some(["STOP"]),
      true,
      Some(1),
      Some(42),
      Some(LucentStructuredOutput::JsonObject),
    ),
  ]
  for v in values {
    let s = v.to_json().stringify()
    let parsed = @json.parse(s)
    match LucentOptions::from_json(parsed) {
      Ok(d) => assert_true(v == d)
      Err(e) => fail("LucentOptions round trip failed: " + e)
    }
  }
}

///|
/// === LucentReasoningConfig ===
test "LucentReasoningConfig round trip - disabled, enabled, with effort" {
  let values = [
    LucentReasoningConfig::disabled(),
    LucentReasoningConfig::enabled(Some(2048)),
  ]
  for v in values {
    let s = v.to_json().stringify()
    let parsed = @json.parse(s)
    match LucentReasoningConfig::from_json(parsed) {
      Ok(d) => assert_true(v == d)
      Err(e) => fail("LucentReasoningConfig round trip failed: " + e)
    }
  }
}

///|
/// === LucentCapabilities ===
test "LucentCapabilities round trip - default" {
  let v = LucentCapabilities::default()
  let s = v.to_json().stringify()
  let parsed = @json.parse(s)
  match LucentCapabilities::from_json(parsed) {
    Ok(d) => assert_true(v == d)
    Err(e) => fail("LucentCapabilities round trip failed: " + e)
  }
}

///|
/// === LucentRequest ===
test "LucentRequest round trip - minimal and with all fields" {
  let tool = LucentTool::simple(
    "search", "Search tool", "{\"type\":\"object\"}",
  )
  let values = [
    LucentRequest::from_messages(
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
    ),
    LucentRequest::new(
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
    ),
  ]
  for v in values {
    let s = v.to_json().stringify()
    let parsed = @json.parse(s)
    match LucentRequest::from_json(parsed) {
      Ok(d) => assert_true(v == d)
      Err(e) => fail("LucentRequest round trip failed: " + e)
    }
  }
}

///|
/// === LucentResponse ===
test "LucentResponse round trip" {
  let content = LucentContent::text("Hello!")
  let msg = LucentMessage::new(LucentRole::Assistant, [content])
  let choice = LucentChoice::new(0, msg, LucentFinishReason::Stop, None)
  let v = LucentResponse::new(
    "resp-1",
    "gpt-4o",
    Some(1_700_000_000),
    [choice],
    Some(LucentUsage::new(10, 20, 30)),
    None,
  )
  let s = v.to_json().stringify()
  let parsed = @json.parse(s)
  match LucentResponse::from_json(parsed) {
    Ok(d) => assert_true(v == d)
    Err(e) => fail("LucentResponse round trip failed: " + e)
  }
}

///|
/// === LucentUsage ===
test "LucentUsage round trip - basic and with reasoning" {
  let values = [
    LucentUsage::new(5, 10, 15),
    LucentUsage::with_reasoning(100, 50, 150, 20),
  ]
  for v in values {
    let s = v.to_json().stringify()
    let parsed = @json.parse(s)
    match LucentUsage::from_json(parsed) {
      Ok(d) => assert_true(v == d)
      Err(e) => fail("LucentUsage round trip failed: " + e)
    }
  }
}

///|
/// === LucentFinishReason ===
test "LucentFinishReason round trip" {
  let values = [
    LucentFinishReason::Stop,
    LucentFinishReason::Length,
    LucentFinishReason::ToolCalls,
    LucentFinishReason::Safety,
    LucentFinishReason::Recitation,
    LucentFinishReason::MalformedToolCall,
    LucentFinishReason::Error,
    LucentFinishReason::Native("custom"),
  ]
  for v in values {
    let s = v.to_json().stringify()
    let parsed = @json.parse(s)
    match LucentFinishReason::from_json(parsed) {
      Ok(d) => assert_true(v == d)
      Err(e) => fail("LucentFinishReason round trip failed: " + e)
    }
  }
}

///|
/// === LucentSafetyRating ===
test "LucentSafetyRating round trip" {
  let v = LucentSafetyRating::new("harassment", "low")
  let s = v.to_json().stringify()
  let parsed = @json.parse(s)
  match LucentSafetyRating::from_json(parsed) {
    Ok(d) => assert_true(v == d)
    Err(e) => fail("LucentSafetyRating round trip failed: " + e)
  }
}

///|
/// === LucentChoice ===
test "LucentChoice round trip - without and with safety_ratings" {
  let values = [
    LucentChoice::new(
      0,
      LucentMessage::new(LucentRole::Assistant, [LucentContent::text("ok")]),
      LucentFinishReason::Stop,
      None,
    ),
    LucentChoice::new(
      0,
      LucentMessage::new(LucentRole::Assistant, [LucentContent::text("ok")]),
      LucentFinishReason::Safety,
      Some([LucentSafetyRating::new("HARASSMENT", "NEGLIGIBLE")]),
    ),
  ]
  for v in values {
    let s = v.to_json().stringify()
    let parsed = @json.parse(s)
    match LucentChoice::from_json(parsed) {
      Ok(d) => assert_true(v == d)
      Err(e) => fail("LucentChoice round trip failed: " + e)
    }
  }
}

///|
/// === LucentError + LucentErrorKind ===
test "LucentError round trip" {
  let v = LucentError::new(
    LucentErrorKind::RateLimit,
    "Too many requests",
    Some("429"),
  )
  let s = v.to_json().stringify()
  let parsed = @json.parse(s)
  match LucentError::from_json(parsed) {
    Ok(d) => assert_true(v == d)
    Err(e) => fail("LucentError round trip failed: " + e)
  }
}

///|
test "LucentErrorKind round trip" {
  let values = [
    LucentErrorKind::RateLimit,
    LucentErrorKind::InvalidRequest,
    LucentErrorKind::Authentication,
    LucentErrorKind::ServerError,
    LucentErrorKind::ContentFilter,
    LucentErrorKind::Native("custom"),
  ]
  for v in values {
    let s = v.to_json().stringify()
    let parsed = @json.parse(s)
    match LucentErrorKind::from_json(parsed) {
      Ok(d) => assert_true(v == d)
      Err(e) => fail("LucentErrorKind round trip failed: " + e)
    }
  }
}

///|
/// === LucentBlockType ===
test "LucentBlockType round trip" {
  let values = [
    LucentBlockType::Text,
    LucentBlockType::Thinking,
    LucentBlockType::ToolCall("call-1", "search"),
    LucentBlockType::Native("custom"),
  ]
  for v in values {
    let s = v.to_json().stringify()
    let parsed = @json.parse(s)
    match LucentBlockType::from_json(parsed) {
      Ok(d) => assert_true(v == d)
      Err(e) => fail("LucentBlockType round trip failed: " + e)
    }
  }
}

///|
/// === LucentBlockDelta ===
test "LucentBlockDelta round trip - all variants" {
  let values = [
    LucentBlockDelta::text_delta("Hello"),
    LucentBlockDelta::thinking_delta("Let me think..."),
    LucentBlockDelta::signature_delta("EqwB"),
    LucentBlockDelta::tool_arguments_delta("{\"city\":\"Paris\"}"),
    LucentBlockDelta::refusal_delta("Cannot do that"),
  ]
  for v in values {
    let s = v.to_json().stringify()
    let parsed = @json.parse(s)
    match LucentBlockDelta::from_json(parsed) {
      Ok(d) => assert_true(v == d)
      Err(e) => fail("LucentBlockDelta round trip failed: " + e)
    }
  }
}

///|
/// === LucentStreamEvent ===
test "LucentStreamEvent round trip - all events" {
  let meta = LucentConversationMeta::new(
    Some("conv-1"),
    Some("gpt-4o"),
    Some(5),
  )
  let msg = LucentMessage::new(LucentRole::User, [LucentContent::text("hi")])
  let ci = LucentConversationItem::message(msg)
  let bt = LucentBlockType::ToolCall("call-1", "search")
  let usage = LucentUsage::new(5, 10, 15)
  let err = LucentError::new(
    LucentErrorKind::ServerError,
    "internal error",
    None,
  )
  let ann = LucentAnnotation::new(
    LucentAnnotationKind::Url,
    Some("https://src"),
    None,
    None,
    None,
  )
  let values = [
    LucentStreamEvent::ConversationStart(meta),
    LucentStreamEvent::ItemStart(0, ci),
    LucentStreamEvent::ItemEnd(0),
    LucentStreamEvent::BlockStart(0, bt),
    LucentStreamEvent::BlockDelta(0, LucentBlockDelta::text_delta("partial")),
    LucentStreamEvent::BlockEnd(0),
    LucentStreamEvent::BlockDiscard(0),
    LucentStreamEvent::Finish(LucentFinishReason::Stop),
    LucentStreamEvent::Usage(usage),
    LucentStreamEvent::Error(err),
    LucentStreamEvent::Done,
    LucentStreamEvent::Annotations(0, [ann]),
  ]
  for v in values {
    let s = v.to_json().stringify()
    let parsed = @json.parse(s)
    match LucentStreamEvent::from_json(parsed) {
      Ok(d) => assert_true(v == d)
      Err(e) => fail("LucentStreamEvent round trip failed: " + e)
    }
  }
}

///|
/// === LucentConversationMeta ===
test "LucentConversationMeta round trip - full and empty" {
  let values = [
    LucentConversationMeta::new(Some("conv-1"), Some("gpt-4o"), Some(42)),
    LucentConversationMeta::new(None, None, None),
  ]
  for v in values {
    let s = v.to_json().stringify()
    let parsed = @json.parse(s)
    match LucentConversationMeta::from_json(parsed) {
      Ok(d) => assert_true(v == d)
      Err(e) => fail("LucentConversationMeta round trip failed: " + e)
    }
  }
}

///|
/// === ProviderCapability ===
test "ProviderCapability round trip" {
  let caps = LucentCapabilities::default()
  let v = ProviderCapability::new("gpt-*", "openai", caps, None)
  let s = v.to_json().stringify()
  let parsed = @json.parse(s)
  match ProviderCapability::from_json(parsed) {
    Ok(d) => assert_true(v == d)
    Err(e) => fail("ProviderCapability round trip failed: " + e)
  }
}

///|
/// === LucentDiscovery ===
test "LucentDiscovery round trip" {
  let caps = LucentCapabilities::default()
  let pc = ProviderCapability::new("gpt-*", "openai", caps, None)
  let v = LucentDiscovery::new(
    "lux-v1",
    "https://raw.githubusercontent.com/moonbit-community/prism/main/schemas/lux-ir-v1.json",
    [pc],
  )
  let s = v.to_json().stringify()
  let parsed = @json.parse(s)
  match LucentDiscovery::from_json(parsed) {
    Ok(d) => assert_true(v == d)
    Err(e) => fail("LucentDiscovery round trip failed: " + e)
  }
}
