///|
/// Lux IR 黑盒测试 — 仅通过公开 API 验证契约
///
/// 与白盒测试（_wbtest.mbt）互补：本文件模拟外部调用者视角，
/// 只依赖 pub 构造函数与 to_json/from_json 完成 round-trip 验证。
/// 模式：construct → to_json() → stringify() → @json.parse() → from_json() → assert_eq

///|
/// === LucentRequest round-trip ===

///|
test "LucentRequest blackbox - full round trip via JSON string" {
  let msg = LucentMessage::new(User, [LucentContent::text("Hello")])
  let req = LucentRequest::from_messages(
    "gpt-4o",
    Some([LucentContent::text("You are helpful")]),
    [msg],
    None,
    None,
    LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
  let s = req.to_json().stringify()
  let parsed = @json.parse(s)
  match LucentRequest::from_json(parsed) {
    Ok(d) => assert_eq(d, req)
    Err(e) => fail("LucentRequest round trip failed: " + e)
  }
}

///|
test "LucentRequest blackbox - from_json rejects empty object" {
  match LucentRequest::from_json(@json.parse("{}")) {
    Ok(_) => fail("expected Err for empty object")
    Err(_) => ()
  }
}

///|
test "LucentRequest blackbox - validate flags missing model" {
  let req = LucentRequest::new(
    "",
    None,
    [],
    None,
    None,
    LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
  let result = req.validate()
  assert_false(result.valid)
  assert_true(result.errors.length() > 0)
}

///|
test "LucentRequest blackbox - validate passes for well-formed request" {
  let msg = LucentMessage::new(User, [LucentContent::text("Hi")])
  let req = LucentRequest::from_messages(
    "gpt-4o",
    None,
    [msg],
    None,
    None,
    LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
  assert_true(req.validate().valid)
}

///|
/// === LucentResponse round-trip ===

///|
test "LucentResponse blackbox - full round trip via JSON string" {
  let choice = LucentChoice::new(
    0,
    LucentMessage::new(Assistant, [LucentContent::text("Hi there")]),
    Stop,
    None,
  )
  let resp = LucentResponse::new(
    "resp-1",
    "gpt-4o",
    Some(1700000000),
    [choice],
    Some(LucentUsage::new(10, 5, 15)),
    None,
  )
  let s = resp.to_json().stringify()
  let parsed = @json.parse(s)
  match LucentResponse::from_json(parsed) {
    Ok(d) => assert_eq(d, resp)
    Err(e) => fail("LucentResponse round trip failed: " + e)
  }
}

///|
test "LucentResponse blackbox - get_text returns first choice text" {
  let choice = LucentChoice::new(
    0,
    LucentMessage::new(Assistant, [LucentContent::text("Hello")]),
    Stop,
    None,
  )
  let resp = LucentResponse::new("resp-2", "gpt-4o", None, [choice], None, None)
  assert_eq(resp.get_text(), "Hello")
}

///|
/// === LucentStreamEvent round-trip ===

///|
test "LucentStreamEvent blackbox - text block events round trip" {
  let events = [
    LucentStreamEvent::ConversationStart(
      LucentConversationMeta::new(None, Some("gpt-4o"), None),
    ),
    ItemStart(
      0,
      LucentConversationItem::message(
        LucentMessage::new(Assistant, [LucentContent::text("")]),
      ),
    ),
    BlockStart(0, LucentBlockType::text()),
    BlockDelta(0, LucentBlockDelta::text_delta("Hel")),
    BlockDelta(0, LucentBlockDelta::text_delta("lo")),
    BlockEnd(0),
    ItemEnd(0),
    Finish(Stop),
    Usage(LucentUsage::new(10, 5, 15)),
    Done,
  ]
  for ev in events {
    let s = ev.to_json().stringify()
    let parsed = @json.parse(s)
    match LucentStreamEvent::from_json(parsed) {
      Ok(d) => assert_eq(d, ev)
      Err(e) => fail("LucentStreamEvent round trip failed: " + e)
    }
  }
}

///|
test "LucentStreamEvent blackbox - tool call events round trip" {
  let events = [
    LucentStreamEvent::ItemStart(
      0,
      LucentConversationItem::tool_call(
        LucentToolUse::new(
          "call_1",
          "get_weather",
          "{\"city\":\"Beijing\"}",
          None,
        ),
      ),
    ),
    BlockStart(0, LucentBlockType::tool_call("call_1", "get_weather")),
    BlockDelta(0, LucentBlockDelta::tool_arguments_delta("{\"city\":\"")),
    BlockDelta(0, LucentBlockDelta::tool_arguments_delta("Beijing\"}")),
    BlockEnd(0),
    ItemEnd(0),
    Finish(ToolCalls),
    Done,
  ]
  for ev in events {
    let s = ev.to_json().stringify()
    let parsed = @json.parse(s)
    match LucentStreamEvent::from_json(parsed) {
      Ok(d) => assert_eq(d, ev)
      Err(e) => fail("tool call event round trip failed: " + e)
    }
  }
}

///|
/// === 公开辅助函数 ===

///|
test "lucent_content_to_text blackbox - concatenates text parts" {
  let parts = [
    LucentContent::text("Hello"),
    LucentContent::text(" "),
    LucentContent::text("World"),
  ]
  assert_eq(lucent_content_to_text(parts), "Hello World")
}

///|
test "lucent_stream_events_to_response blackbox - aggregates stream" {
  let events = [
    LucentStreamEvent::ConversationStart(
      LucentConversationMeta::new(Some("resp-9"), Some("gpt-4o"), None),
    ),
    ItemStart(
      0,
      LucentConversationItem::message(
        LucentMessage::new(Assistant, [LucentContent::text("")]),
      ),
    ),
    BlockStart(0, LucentBlockType::text()),
    BlockDelta(0, LucentBlockDelta::text_delta("Stream")),
    BlockEnd(0),
    ItemEnd(0),
    Finish(Stop),
    Usage(LucentUsage::new(3, 6, 9)),
    Done,
  ]
  let resp = lucent_stream_events_to_response(
    events, "fallback-id", "fallback-model",
  )
  assert_eq(resp.id, "resp-9")
  assert_eq(resp.model, "gpt-4o")
  assert_eq(resp.get_text(), "Stream")
  match resp.usage {
    Some(u) => assert_eq(u.total_tokens, 9)
    None => fail("expected usage")
  }
}

///|
test "lux_to_json_string blackbox - stringifies json" {
  let jv = @json.parse("{\"a\":1}")
  assert_eq(lux_to_json_string(jv), "{\"a\":1}")
}

///|
/// === ConversionResult::with_diagnostic 不可变性 ===
test "with_diagnostic does not mutate source diagnostics" {
  let base = ConversionResult::new("hello")
  let derived = base.with_diagnostic(
    ConversionDiagnostic::new("field", Invalid, Some("detail")),
  )
  // 原结果诊断数组必须保持为空
  assert_eq(base.diagnostics().length(), 0)
  assert_eq(derived.diagnostics().length(), 1)
  assert_eq(derived.value(), "hello")
}

///|
test "with_diagnostic chains append without aliasing" {
  let base = ConversionResult::new("hello")
  let once = base.with_diagnostic(ConversionDiagnostic::new("a", Invalid, None))
  let twice = once.with_diagnostic(
    ConversionDiagnostic::new("b", Invalid, None),
  )
  assert_eq(base.diagnostics().length(), 0)
  assert_eq(once.diagnostics().length(), 1)
  assert_eq(twice.diagnostics().length(), 2)
}
