///|
/// Lux IR 黑盒测试 — 仅通过公开 API 验证契约
///
/// 与白盒测试（_wbtest.mbt）互补：本文件模拟外部调用者视角，
/// 只依赖 pub 构造函数与 to_json/from_json 完成 round-trip 验证。
/// 模式：construct → to_json() → stringify() → @json.parse() → from_json() → assert_eq

///|
/// === @lux.LucentRequest round-trip ===

///|
test "@lux.LucentRequest blackbox - full round trip via JSON string" {
  let msg = @lux.LucentMessage::new(User, [@lux.LucentContent::text("Hello")])
  let req = @lux.LucentRequest::from_messages(
    "gpt-4o",
    Some([@lux.LucentContent::text("You are helpful")]),
    [msg],
    None,
    None,
    @lux.LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
  let s = req.to_json().stringify()
  let parsed = @json.parse(s)
  match @lux.LucentRequest::from_json(parsed) {
    Ok(d) => assert_eq(d, req)
    Err(e) => fail("@lux.LucentRequest round trip failed: " + e)
  }
}

///|
test "@lux.LucentRequest blackbox - from_json rejects empty object" {
  match @lux.LucentRequest::from_json(@json.parse("{}")) {
    Ok(_) => fail("expected Err for empty object")
    Err(_) => ()
  }
}

///|
test "@lux.LucentRequest blackbox - validate flags missing model" {
  let req = @lux.LucentRequest::new(
    "",
    None,
    [],
    None,
    None,
    @lux.LucentOptions::default(),
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
test "@lux.LucentRequest blackbox - validate passes for well-formed request" {
  let msg = @lux.LucentMessage::new(User, [@lux.LucentContent::text("Hi")])
  let req = @lux.LucentRequest::from_messages(
    "gpt-4o",
    None,
    [msg],
    None,
    None,
    @lux.LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
  assert_true(req.validate().valid)
}

///|
/// === @lux.LucentResponse round-trip ===

///|
test "@lux.LucentResponse blackbox - full round trip via JSON string" {
  let choice = @lux.LucentChoice::new(
    0,
    @lux.LucentMessage::new(Assistant, [@lux.LucentContent::text("Hi there")]),
    Stop,
    None,
  )
  let resp = @lux.LucentResponse::new(
    "resp-1",
    "gpt-4o",
    Some(1700000000),
    [choice],
    Some(@lux.LucentUsage::new(10, 5, 15)),
    None,
  )
  let s = resp.to_json().stringify()
  let parsed = @json.parse(s)
  match @lux.LucentResponse::from_json(parsed) {
    Ok(d) => assert_eq(d, resp)
    Err(e) => fail("@lux.LucentResponse round trip failed: " + e)
  }
}

///|
test "@lux.LucentResponse blackbox - get_text returns first choice text" {
  let choice = @lux.LucentChoice::new(
    0,
    @lux.LucentMessage::new(Assistant, [@lux.LucentContent::text("Hello")]),
    Stop,
    None,
  )
  let resp = @lux.LucentResponse::new(
    "resp-2",
    "gpt-4o",
    None,
    [choice],
    None,
    None,
  )
  assert_eq(resp.get_text(), "Hello")
}

///|
/// === @lux.LucentStreamEvent round-trip ===

///|
test "@lux.LucentStreamEvent blackbox - text block events round trip" {
  let events = [
    @lux.LucentStreamEvent::ConversationStart(
      @lux.LucentConversationMeta::new(None, Some("gpt-4o"), None),
    ),
    ItemStart(
      0,
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(Assistant, [@lux.LucentContent::text("")]),
      ),
    ),
    BlockStart(0, @lux.LucentBlockType::text()),
    BlockDelta(0, @lux.LucentBlockDelta::text_delta("Hel")),
    BlockDelta(0, @lux.LucentBlockDelta::text_delta("lo")),
    BlockEnd(0),
    ItemEnd(0),
    Finish(Stop),
    Usage(@lux.LucentUsage::new(10, 5, 15)),
    Done,
  ]
  for ev in events {
    let s = ev.to_json().stringify()
    let parsed = @json.parse(s)
    match @lux.LucentStreamEvent::from_json(parsed) {
      Ok(d) => assert_eq(d, ev)
      Err(e) => fail("@lux.LucentStreamEvent round trip failed: " + e)
    }
  }
}

///|
test "@lux.LucentStreamEvent blackbox - tool call events round trip" {
  let events = [
    @lux.LucentStreamEvent::ItemStart(
      0,
      @lux.LucentConversationItem::tool_call(
        @lux.LucentToolUse::new(
          "call_1",
          "get_weather",
          "{\"city\":\"Beijing\"}",
          None,
        ),
      ),
    ),
    BlockStart(0, @lux.LucentBlockType::tool_call("call_1", "get_weather")),
    BlockDelta(0, @lux.LucentBlockDelta::tool_arguments_delta("{\"city\":\"")),
    BlockDelta(0, @lux.LucentBlockDelta::tool_arguments_delta("Beijing\"}")),
    BlockEnd(0),
    ItemEnd(0),
    Finish(ToolCalls),
    Done,
  ]
  for ev in events {
    let s = ev.to_json().stringify()
    let parsed = @json.parse(s)
    match @lux.LucentStreamEvent::from_json(parsed) {
      Ok(d) => assert_eq(d, ev)
      Err(e) => fail("tool call event round trip failed: " + e)
    }
  }
}

///|
/// === 公开辅助函数 ===

///|
test "@lux.lucent_content_to_text blackbox - concatenates text parts" {
  let parts = [
    @lux.LucentContent::text("Hello"),
    @lux.LucentContent::text(" "),
    @lux.LucentContent::text("World"),
  ]
  assert_eq(@lux.lucent_content_to_text(parts), "Hello World")
}

///|
test "@lux.lucent_stream_events_to_response blackbox - aggregates stream" {
  let events = [
    @lux.LucentStreamEvent::ConversationStart(
      @lux.LucentConversationMeta::new(Some("resp-9"), Some("gpt-4o"), None),
    ),
    ItemStart(
      0,
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(Assistant, [@lux.LucentContent::text("")]),
      ),
    ),
    BlockStart(0, @lux.LucentBlockType::text()),
    BlockDelta(0, @lux.LucentBlockDelta::text_delta("Stream")),
    BlockEnd(0),
    ItemEnd(0),
    Finish(Stop),
    Usage(@lux.LucentUsage::new(3, 6, 9)),
    Done,
  ]
  let resp = @lux.lucent_stream_events_to_response(
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
test "@lux.lux_to_json_string blackbox - stringifies json" {
  let jv = @json.parse("{\"a\":1}")
  assert_eq(@lux.lux_to_json_string(jv), "{\"a\":1}")
}

///|
/// === @lux.ConversionResult::with_diagnostic 不可变性 ===
test "with_diagnostic does not mutate source diagnostics" {
  let base = @lux.ConversionResult::new("hello")
  let derived = base.with_diagnostic(
    @lux.ConversionDiagnostic::new("field", Invalid, Some("detail")),
  )
  // 原结果诊断数组必须保持为空
  assert_eq(base.diagnostics().length(), 0)
  assert_eq(derived.diagnostics().length(), 1)
  assert_eq(derived.value(), "hello")
}

///|
test "with_diagnostic chains append without aliasing" {
  let base = @lux.ConversionResult::new("hello")
  let once = base.with_diagnostic(
    @lux.ConversionDiagnostic::new("a", Invalid, None),
  )
  let twice = once.with_diagnostic(
    @lux.ConversionDiagnostic::new("b", Invalid, None),
  )
  assert_eq(base.diagnostics().length(), 0)
  assert_eq(once.diagnostics().length(), 1)
  assert_eq(twice.diagnostics().length(), 2)
}
