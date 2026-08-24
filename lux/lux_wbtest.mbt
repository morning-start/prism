///|
/// Lux IR 白盒测试 — 覆盖所有新类型
///
/// 依据：docs/lux-ir-design.md
/// 覆盖：核心类型构造/相等、枚举映射、流式累加、辅助函数

///|
/// === 基础枚举 ===

///|
test "LucentRole from_string round trip" {
  assert_eq(LucentRole::from_string("system"), Some(System))
  assert_eq(LucentRole::from_string("user"), Some(User))
  assert_eq(LucentRole::from_string("assistant"), Some(Assistant))
  assert_eq(LucentRole::from_string("tool"), Some(Tool))
  assert_eq(LucentRole::from_string("model"), Some(Model))
  assert_eq(LucentRole::from_string("developer"), Some(Developer))
  assert_eq(LucentRole::from_string("unknown"), None)
  assert_eq(System.to_string(), "system")
  assert_eq(Assistant.to_string(), "assistant")
}

///|
test "LucentModality from_string" {
  assert_eq(LucentModality::from_string("text"), Some(Text))
  assert_eq(LucentModality::from_string("image"), Some(Image))
  assert_eq(LucentModality::from_string("audio"), Some(Audio))
  assert_eq(LucentModality::from_string("video"), Some(Video))
  assert_eq(LucentModality::from_string("pdf"), Some(Pdf))
  assert_eq(LucentModality::from_string("unknown"), None)
}

///|
test "LucentFinishReason from_string variants" {
  assert_true(LucentFinishReason::from_string("stop") is Stop)
  assert_true(LucentFinishReason::from_string("end_turn") is Stop)
  assert_true(LucentFinishReason::from_string("STOP") is Stop)
  assert_true(LucentFinishReason::from_string("length") is Length)
  assert_true(LucentFinishReason::from_string("max_tokens") is Length)
  assert_true(LucentFinishReason::from_string("incomplete") is Length)
  assert_true(LucentFinishReason::from_string("tool_calls") is ToolCalls)
  assert_true(LucentFinishReason::from_string("tool_use") is ToolCalls)
  assert_true(LucentFinishReason::from_string("safety") is Safety)
  assert_true(LucentFinishReason::from_string("SAFETY") is Safety)
  assert_true(LucentFinishReason::from_string("recitation") is Recitation)
  assert_true(
    LucentFinishReason::from_string("malformed_function_call")
    is MalformedToolCall,
  )
  assert_true(LucentFinishReason::from_string("error") is Error)
  match LucentFinishReason::from_string("custom_vendor") {
    Native(s) => assert_eq(s, "custom_vendor")
    _ => assert_true(false)
  }
}

///|
test "LucentFinishReason to_string" {
  assert_eq(Stop.to_string(), "stop")
  assert_eq(Length.to_string(), "length")
  assert_eq(ToolCalls.to_string(), "tool_calls")
  assert_eq(LucentFinishReason::ContentFilter.to_string(), "content_filter")
  assert_eq(Safety.to_string(), "safety")
  assert_eq(Recitation.to_string(), "recitation")
  assert_eq(MalformedToolCall.to_string(), "malformed_function_call")
  assert_eq(LucentFinishReason::Error.to_string(), "error")
}

///|
test "LucentErrorKind from_string" {
  assert_true(LucentErrorKind::from_string("rate_limit") is RateLimit)
  assert_true(LucentErrorKind::from_string("429") is RateLimit)
  assert_true(LucentErrorKind::from_string("400") is InvalidRequest)
  assert_true(LucentErrorKind::from_string("401") is Authentication)
  assert_true(LucentErrorKind::from_string("500") is ServerError)
  assert_true(LucentErrorKind::from_string("content_filter") is ContentFilter)
  match LucentErrorKind::from_string("custom_error") {
    Native(s) => assert_eq(s, "custom_error")
    _ => assert_true(false)
  }
}

///|
/// === 内容类型构造与相等 ===

///|
test "LucentContent text equality" {
  let a = LucentContent::text("ok")
  let b = LucentContent::text("ok")
  let c = LucentContent::text("no")
  assert_eq(a, b)
  assert_true(a != c)
}

///|
test "LucentContent text_with_annotations" {
  let ann = LucentAnnotation::new(
    Url,
    Some("foo"),
    Some("https://x"),
    Some(0),
    Some(3),
  )
  let a = LucentContent::text_with_annotations("foo", [ann])
  match a {
    Text(s, Some(anns)) => {
      assert_eq(s, "foo")
      assert_eq(anns.length(), 1)
      match anns[0] {
        {
          kind: Url,
          text: Some(t),
          reference: Some(r),
          start: Some(0),
          end: Some(3),
        } => {
          assert_eq(t, "foo")
          assert_eq(r, "https://x")
        }
        _ => assert_true(false)
      }
    }
    _ => assert_true(false)
  }
}

///|
test "LucentContent tool_use construction" {
  let c = LucentContent::tool_use(
    "call-1",
    "get_weather",
    "{\"city\":\"Beijing\"}",
    None,
  )
  match c {
    ToolUse(tu) => {
      assert_eq(tu.id, "call-1")
      assert_eq(tu.name, "get_weather")
      assert_eq(tu.arguments_json, "{\"city\":\"Beijing\"}")
      assert_eq(tu.arguments_value, None)
    }
    _ => assert_true(false)
  }
}

///|
test "LucentContent tool_result construction" {
  let c = LucentContent::tool_result("call-1", [
    LucentContent::text("{\"temp\":25}"),
  ])
  match c {
    ToolResult(tr) => {
      assert_eq(tr.tool_use_id, "call-1")
      assert_eq(tr.is_error, false)
      assert_eq(tr.content.length(), 1)
    }
    _ => assert_true(false)
  }
}

///|
test "LucentContent tool_result_error construction" {
  let c = LucentContent::tool_result_error("call-1", [
    LucentContent::text("tool failed"),
  ])
  match c {
    ToolResult(tr) => {
      assert_eq(tr.tool_use_id, "call-1")
      assert_eq(tr.is_error, true)
    }
    _ => assert_true(false)
  }
}

///|
test "LucentContent thinking visible" {
  let c = LucentContent::thinking("Let me think...", Some("sig-123"))
  match c {
    Thinking(th) => {
      assert_eq(th.text, "Let me think...")
      assert_eq(th.signature, Some("sig-123"))
      assert_eq(th.redacted, false)
      assert_eq(th.summary, None)
    }
    _ => assert_true(false)
  }
}

///|
test "LucentContent redacted_thinking" {
  let c = LucentContent::redacted_thinking(Some("sig-abc"))
  match c {
    Thinking(th) => {
      assert_eq(th.text, "")
      assert_eq(th.signature, Some("sig-abc"))
      assert_eq(th.redacted, true)
    }
    _ => assert_true(false)
  }
}

///|
test "LucentContent refusal" {
  let c = LucentContent::refusal("I cannot answer that")
  match c {
    Refusal(s) => assert_eq(s, "I cannot answer that")
    _ => assert_true(false)
  }
}

///|
test "LucentContent image with all source variants" {
  let img_inline = LucentContent::image(
    "image/png",
    LucentMediaSource::inline("iVBORw0KGgo"),
  )
  let img_url = LucentContent::image(
    "image/png",
    LucentMediaSource::url("https://example.com/x.png"),
  )
  let img_file = LucentContent::image(
    "image/png",
    LucentMediaSource::file_uri("file-abc"),
  )
  match img_inline {
    Image(m) => {
      assert_eq(m.media_type, "image/png")
      assert_true(m.source is Inline(_))
    }
    _ => assert_true(false)
  }
  match img_url {
    Image(m) => assert_true(m.source is Url(_))
    _ => assert_true(false)
  }
  match img_file {
    Image(m) => assert_true(m.source is FileUri(_))
    _ => assert_true(false)
  }
}

///|
test "LucentContent audio and video" {
  let _ = LucentContent::audio(
    "audio/wav",
    LucentMediaSource::inline("UklGRiQ"),
  )
  let _ = LucentContent::video(
    "video/mp4",
    LucentMediaSource::url("https://x/v.mp4"),
  )
  // 构造成功即可
  assert_true(true)
}

///|
test "LucentContent native" {
  let raw : Json = @json.parse("{\"vendor\":\"x\"}")
  let c = LucentContent::native("vendor_block", raw)
  match c {
    Native(tag, _) => assert_eq(tag, "vendor_block")
    _ => assert_true(false)
  }
}

///|
/// === LucentMessage / ConversationItem ===

///|
test "LucentMessage new" {
  let m = LucentMessage::new(User, [LucentContent::text("hi")])
  assert_eq(m.role, User)
  assert_eq(m.content.length(), 1)
}

///|
test "LucentConversationItem variants" {
  let mi = LucentConversationItem::message(
    LucentMessage::new(User, [LucentContent::text("hi")]),
  )
  let tc = LucentConversationItem::tool_call(
    LucentToolUse::new("call-1", "f", "{}", None),
  )
  let tr = LucentConversationItem::tool_result(
    LucentToolResult::ok("call-1", [LucentContent::text("ok")]),
  )
  let re = LucentConversationItem::reasoning(
    LucentThinking::visible("thinking", None),
  )
  let aa = LucentConversationItem::agent_action(
    LucentAgentAction::new(
      "computer_call",
      "fc-1",
      Some("call-1"),
      None,
      None,
      None,
      None,
    ),
  )
  assert_true(mi is Message(_))
  assert_true(tc is ToolCall(_))
  assert_true(tr is ToolResult(_))
  assert_true(re is Reasoning(_))
  assert_true(aa is AgentAction(_))
}

///|
test "lucent_items_from_messages" {
  let items = lucent_items_from_messages([
    LucentMessage::new(User, [LucentContent::text("a")]),
    LucentMessage::new(Assistant, [LucentContent::text("b")]),
  ])
  assert_eq(items.length(), 2)
  assert_true(items[0] is Message(_))
  assert_true(items[1] is Message(_))
}

///|
test "lucent_messages_from_items filters only Message" {
  let items : Array[LucentConversationItem] = [
    LucentConversationItem::message(
      LucentMessage::new(User, [LucentContent::text("a")]),
    ),
    LucentConversationItem::tool_call(LucentToolUse::new("c", "f", "{}", None)),
    LucentConversationItem::message(
      LucentMessage::new(Assistant, [LucentContent::text("b")]),
    ),
  ]
  let msgs = lucent_messages_from_items(items)
  assert_eq(msgs.length(), 2)
  assert_eq(msgs[0].role, User)
  assert_eq(msgs[1].role, Assistant)
}

///|
/// === LucentTool / ToolChoice ===

///|
test "LucentTool simple" {
  let t = LucentTool::simple(
    "get_weather", "Get weather", "{\"type\":\"object\"}",
  )
  assert_eq(t.name, "get_weather")
  assert_eq(t.description, Some("Get weather"))
  assert_eq(t.strict, None)
}

///|
test "LucentToolChoice variants" {
  assert_true(LucentToolChoice::Auto != None)
  assert_true(LucentToolChoice::Required != Auto)
  assert_eq(LucentToolChoice::SpecificTool("f"), SpecificTool("f"))
  assert_true(LucentToolChoice::SpecificTool("f") != SpecificTool("g"))
}

///|
/// === LucentOptions / Capabilities / Reasoning ===

///|
test "LucentOptions default" {
  let opts = LucentOptions::default()
  assert_eq(opts.temperature, None)
  assert_eq(opts.top_p, None)
  assert_eq(opts.top_k, None)
  assert_eq(opts.max_output_tokens, None)
  assert_eq(opts.stop, None)
  assert_eq(opts.stream, false)
  assert_eq(opts.candidate_count, None)
  assert_eq(opts.structured_output, None)
}

///|
test "LucentCapabilities default" {
  let caps = LucentCapabilities::default()
  assert_eq(caps.tool_calling, Absent)
  assert_eq(caps.parallel_tool_calls, Absent)
  assert_eq(caps.reasoning, Absent)
  assert_eq(caps.multimodal_input, Absent)
  assert_eq(caps.structured_output, Absent)
  assert_eq(caps.input_modalities.length(), 0)
  assert_eq(caps.output_modalities.length(), 0)
}

///|
test "LucentReasoningConfig enabled/disabled" {
  let en = LucentReasoningConfig::enabled(Some(1024))
  assert_eq(en.enabled, true)
  assert_eq(en.budget_tokens, Some(1024))
  let dis = LucentReasoningConfig::disabled()
  assert_eq(dis.enabled, false)
  assert_eq(dis.budget_tokens, None)
}

///|
/// === LucentRequest ===

///|
test "LucentRequest from_messages" {
  let req = LucentRequest::from_messages(
    "gpt-4o",
    Some([LucentContent::text("You are helpful")]),
    [LucentMessage::new(User, [LucentContent::text("hi")])],
    None,
    None,
    LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
  assert_eq(req.schema_version, "v1")
  assert_eq(req.model, "gpt-4o")
  assert_eq(req.instructions.unwrap().length(), 1)
  assert_eq(req.conversation.length(), 1)
  match req.conversation[0] {
    Message(m) => assert_eq(m.role, User)
    _ => assert_true(false)
  }
}

///|
test "LucentRequest new with conversation" {
  let req = LucentRequest::new(
    "claude-sonnet-4",
    None,
    [
      LucentConversationItem::tool_call(
        LucentToolUse::new("fc-1", "run_code", "{\"code\":\"x\"}", None),
      ),
      LucentConversationItem::tool_result(
        LucentToolResult::ok("call-1", [LucentContent::text("output")]),
      ),
    ],
    None,
    None,
    LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
  assert_eq(req.conversation.length(), 2)
  assert_true(req.conversation[0] is ToolCall(_))
  assert_true(req.conversation[1] is ToolResult(_))
}

///|
/// === LucentUsage ===

///|
test "LucentUsage new" {
  let u = LucentUsage::new(10, 5, 15)
  assert_eq(u.prompt_tokens, 10)
  assert_eq(u.completion_tokens, 5)
  assert_eq(u.total_tokens, 15)
  assert_eq(u.reasoning_tokens, None)
  assert_eq(u.cached_tokens, None)
  assert_eq(u.cache_creation_tokens, None)
}

///|
test "LucentUsage with_reasoning" {
  let u = LucentUsage::with_reasoning(50, 100, 180, 30)
  assert_eq(u.reasoning_tokens, Some(30))
}

///|
/// === LucentResponse ===

///|
test "LucentResponse construction" {
  let resp = LucentResponse::new(
    "resp-1",
    "gpt-4o",
    Some(1700000000),
    [
      LucentChoice::new(
        0,
        LucentMessage::new(Assistant, [LucentContent::text("hello")]),
        Stop,
        None,
      ),
    ],
    Some(LucentUsage::new(10, 5, 15)),
    None,
  )
  assert_eq(resp.schema_version, "v1")
  assert_eq(resp.id, "resp-1")
  assert_eq(resp.created_at, Some(1700000000))
  assert_eq(resp.choices.length(), 1)
  assert_eq(resp.choices[0].index, 0)
  assert_eq(resp.choices[0].finish_reason, Stop)
  assert_eq(resp.usage.unwrap().prompt_tokens, 10)
}

///|
test "LucentChoice with safety_ratings" {
  let choice = LucentChoice::new(
    0,
    LucentMessage::new(Assistant, [LucentContent::text("ok")]),
    Safety,
    Some([LucentSafetyRating::new("HARASSMENT", "NEGLIGIBLE")]),
  )
  match choice.safety_ratings {
    Some(r) => {
      assert_eq(r.length(), 1)
      assert_eq(r[0].category, "HARASSMENT")
      assert_eq(r[0].probability, "NEGLIGIBLE")
    }
    None => assert_true(false)
  }
}

///|
/// === 辅助函数 ===

///|
test "lucent_content_to_text concatenates Text blocks" {
  let parts = [
    LucentContent::text("Hello"),
    LucentContent::tool_use("c", "f", "{}", None), // 非文本块忽略
    LucentContent::text(" world"),
  ]
  assert_eq(lucent_content_to_text(parts), "Hello world")
}

///|
test "lucent_content_to_text empty" {
  let parts : Array[LucentContent] = []
  assert_eq(lucent_content_to_text(parts), "")
}

///|
/// === LucentToolUse / ToolResult 构造器 ===

///|
test "LucentToolUse new" {
  let tu = LucentToolUse::new(
    "call-1",
    "get_weather",
    "{\"city\":\"Beijing\"}",
    None,
  )
  assert_eq(tu.id, "call-1")
  assert_eq(tu.name, "get_weather")
}

///|
test "LucentToolResult ok vs error" {
  let ok = LucentToolResult::ok("c", [LucentContent::text("ok")])
  let err = LucentToolResult::error("c", [LucentContent::text("fail")])
  assert_eq(ok.is_error, false)
  assert_eq(err.is_error, true)
}

///|
test "LucentToolResult new explicit" {
  let tr = LucentToolResult::new("c", [LucentContent::text("x")], true)
  assert_eq(tr.is_error, true)
}

///|
/// === LucentThinking 构造器 ===

///|
test "LucentThinking visible vs redacted" {
  let v = LucentThinking::visible("reasoning text", Some("sig"))
  assert_eq(v.redacted, false)
  assert_eq(v.text, "reasoning text")
  let r = LucentThinking::redacted(Some("sig"))
  assert_eq(r.redacted, true)
  assert_eq(r.text, "")
}

///|
/// === LucentMultimedia 构造器 ===

///|
test "LucentMultimedia new" {
  let m = LucentMultimedia::new("image/png", LucentMediaSource::inline("data"))
  assert_eq(m.media_type, "image/png")
}

///|
/// === LucentAnnotation 构造器 ===

///|
test "LucentAnnotation new" {
  let a = LucentAnnotation::new(Url, None, Some("https://x"), None, None)
  match a.reference {
    Some(r) => assert_eq(r, "https://x")
    None => assert_true(false)
  }
}

///|
/// === 流式事件构造 ===

///|
test "LucentStreamEvent variants construct" {
  let cs = BlockStart(0, Text)
  let cd = BlockDelta(0, LucentBlockDelta::text_delta("Hello"))
  let ce = BlockEnd(0)
  let tc = BlockStart(1, LucentBlockType::tool_call("call-1", "get_weather"))
  let th = BlockStart(2, Thinking)
  let fin = Finish(Stop)
  let us = Usage(LucentUsage::new(10, 5, 15))
  let dn = Done
  assert_eq(cs, BlockStart(0, Text))
  assert_eq(cd, BlockDelta(0, LucentBlockDelta::text_delta("Hello")))
  assert_eq(ce, BlockEnd(0))
  assert_eq(
    tc,
    BlockStart(1, LucentBlockType::tool_call("call-1", "get_weather")),
  )
  assert_eq(th, BlockStart(2, Thinking))
  assert_eq(fin, Finish(Stop))
  assert_eq(us, Usage(LucentUsage::new(10, 5, 15)))
  assert_eq(dn, Done)
}

///|
test "LucentBlockDelta constructors" {
  assert_eq(LucentBlockDelta::text_delta("a"), TextDelta("a"))
  assert_eq(LucentBlockDelta::thinking_delta("a"), ThinkingDelta("a"))
  assert_eq(LucentBlockDelta::signature_delta("a"), SignatureDelta("a"))
  assert_eq(
    LucentBlockDelta::tool_arguments_delta("a"),
    ToolArgumentsDelta("a"),
  )
  assert_eq(LucentBlockDelta::refusal_delta("a"), RefusalDelta("a"))
}

///|
test "LucentError constructors" {
  let e = LucentError::new(RateLimit, "rate limited", Some("429"))
  assert_eq(e.provider_code, Some("429"))
  let simple = LucentError::simple("boom")
  assert_eq(simple.message, "boom")
}

///|
test "LucentConversationMeta new" {
  let m = LucentConversationMeta::new(Some("resp-1"), Some("gpt-4o"), Some(50))
  assert_eq(m.id, Some("resp-1"))
  assert_eq(m.usage_input, Some(50))
}

///|
/// === 流式累加器：lucent_stream_events_to_response ===

///|
test "accumulate - agent actions preserved with diagnostics" {
  let events = [
    ItemStart(
      0,
      AgentAction({
        kind: "computer_call",
        id: "aa1",
        call_id: None,
        name: None,
        arguments_json: None,
        result: None,
        provider_payload: None,
      }),
    ),
    Finish(Stop),
    Done,
  ]
  let acc = lucent_stream_events_to_accumulated(events, "r", "m")
  assert_eq(acc.agent_actions.length(), 1)
  assert_eq(acc.agent_actions[0].id, "aa1")
  assert_eq(acc.diagnostics.length(), 1)
  assert_eq(acc.diagnostics[0].status, Unsupported)
}

///|
test "accumulate - annotations preserved with diagnostics" {
  let events = [
    Annotations(0, [
      LucentAnnotation::new(Url, None, Some("https://x.com"), None, None),
    ]),
    Finish(Stop),
    Done,
  ]
  let acc = lucent_stream_events_to_accumulated(events, "r", "m")
  assert_eq(acc.annotations.length(), 1)
  assert_eq(acc.diagnostics.length(), 1)
  assert_eq(acc.diagnostics[0].status, Unsupported)
}

///|
test "accumulate - native delta preserved with diagnostics" {
  let events = [
    BlockStart(0, Text),
    BlockDelta(0, NativeDelta("vendor-x", "raw")),
    BlockEnd(0),
    Finish(Stop),
    Done,
  ]
  let acc = lucent_stream_events_to_accumulated(events, "r", "m")
  assert_eq(acc.native_events.length(), 1)
  assert_eq(acc.diagnostics.length(), 1)
  assert_eq(acc.diagnostics[0].status, Unsupported)
}

///|
test "accumulate - response still aggregates text" {
  let events = [
    BlockStart(0, Text),
    BlockDelta(0, LucentBlockDelta::text_delta("Hello")),
    BlockEnd(0),
    Finish(Stop),
    Done,
  ]
  let acc = lucent_stream_events_to_accumulated(events, "r", "m")
  assert_eq(acc.response.choices[0].finish_reason, Stop)
  let msg = acc.response.choices[0].message
  assert_eq(msg.content.length(), 1)
  match msg.content[0] {
    Text(t, _) => assert_eq(t, "Hello")
    _ => assert_true(false)
  }
}

///|
test "accumulate - wrapper lucent_stream_events_to_response unchanged" {
  let events = [
    ConversationStart(
      LucentConversationMeta::new(Some("resp-real"), Some("gpt-5"), None),
    ),
    Done,
  ]
  let resp = lucent_stream_events_to_response(
    events, "fallback", "fallback-model",
  )
  assert_eq(resp.id, "resp-real")
  assert_eq(resp.model, "gpt-5")
}

///|
test "accumulator empty events" {
  let events : Array[LucentStreamEvent] = []
  let resp = lucent_stream_events_to_response(
    events, "fallback", "fallback-model",
  )
  assert_eq(resp.id, "fallback")
  assert_eq(resp.model, "fallback-model")
  assert_eq(resp.choices.length(), 1)
  assert_eq(resp.choices[0].finish_reason, Stop)
  assert_eq(resp.choices[0].message.content.length(), 0)
}

///|
test "accumulator ConversationStart overrides fallback" {
  let events = [
    ConversationStart(
      LucentConversationMeta::new(Some("resp-real"), Some("gpt-5"), None),
    ),
    Done,
  ]
  let resp = lucent_stream_events_to_response(
    events, "fallback", "fallback-model",
  )
  assert_eq(resp.id, "resp-real")
  assert_eq(resp.model, "gpt-5")
}

///|
test "accumulator text block lifecycle" {
  let events = [
    BlockStart(0, Text),
    BlockDelta(0, LucentBlockDelta::text_delta("Hello")),
    BlockDelta(0, LucentBlockDelta::text_delta(" world")),
    BlockEnd(0),
    Finish(Stop),
    Done,
  ]
  let resp = lucent_stream_events_to_response(events, "r", "m")
  assert_eq(resp.choices[0].finish_reason, Stop)
  let msg = resp.choices[0].message
  assert_eq(msg.content.length(), 1)
  match msg.content[0] {
    Text(t, _) => assert_eq(t, "Hello world")
    _ => assert_true(false)
  }
}

///|
test "accumulator tool call block lifecycle" {
  let events = [
    BlockStart(0, LucentBlockType::tool_call("call-1", "get_weather")),
    BlockDelta(0, LucentBlockDelta::tool_arguments_delta("{\"city\":")),
    BlockDelta(0, LucentBlockDelta::tool_arguments_delta("\"Beijing\"}")),
    BlockEnd(0),
    Finish(ToolCalls),
    Done,
  ]
  let resp = lucent_stream_events_to_response(events, "r", "m")
  assert_eq(resp.choices[0].finish_reason, ToolCalls)
  match resp.choices[0].message.content[0] {
    ToolUse(tu) => {
      assert_eq(tu.id, "call-1")
      assert_eq(tu.name, "get_weather")
      assert_eq(tu.arguments_json, "{\"city\":\"Beijing\"}")
    }
    _ => assert_true(false)
  }
}

///|
test "accumulator mixed text and tool call" {
  let events = [
    BlockStart(0, Text),
    BlockDelta(0, LucentBlockDelta::text_delta("Let me check.")),
    BlockEnd(0),
    BlockStart(1, LucentBlockType::tool_call("call-1", "get_weather")),
    BlockDelta(1, LucentBlockDelta::tool_arguments_delta("{}")),
    BlockEnd(1),
    Finish(ToolCalls),
    Done,
  ]
  let resp = lucent_stream_events_to_response(events, "r", "m")
  let msg = resp.choices[0].message
  assert_eq(msg.content.length(), 2)
  match msg.content[0] {
    Text(t, _) => assert_eq(t, "Let me check.")
    _ => assert_true(false)
  }
  match msg.content[1] {
    ToolUse(_) => ()
    _ => assert_true(false)
  }
}

///|
test "accumulator thinking block with signature" {
  let events = [
    BlockStart(0, Thinking),
    BlockDelta(0, LucentBlockDelta::thinking_delta("I need to...")),
    BlockDelta(0, LucentBlockDelta::signature_delta("EqwB")),
    BlockEnd(0),
    Finish(Stop),
    Done,
  ]
  let resp = lucent_stream_events_to_response(events, "r", "m")
  // C3：thinking 归位到 message.reasoning，不再进入 content
  match resp.choices[0].message.reasoning {
    Some(th) => {
      assert_eq(th.text, "I need to...")
      assert_eq(th.signature, Some("EqwB"))
      assert_eq(th.redacted, false)
    }
    None => assert_true(false)
  }
  assert_eq(resp.choices[0].message.content.length(), 0)
}

///|
test "accumulator refusal block lifecycle" {
  let events = [
    BlockDelta(0, LucentBlockDelta::refusal_delta("Cannot answer")),
    BlockEnd(0),
    Finish(Stop),
    Done,
  ]
  let resp = lucent_stream_events_to_response(events, "r", "m")
  match resp.choices[0].message.content[0] {
    Refusal(s) => assert_eq(s, "Cannot answer")
    _ => assert_true(false)
  }
}

///|
test "accumulator Usage event" {
  let events = [
    BlockStart(0, Text),
    BlockDelta(0, LucentBlockDelta::text_delta("OK")),
    BlockEnd(0),
    Usage(LucentUsage::new(5, 1, 6)),
    Finish(Stop),
    Done,
  ]
  let resp = lucent_stream_events_to_response(events, "r", "m")
  match resp.usage {
    Some(u) => {
      assert_eq(u.prompt_tokens, 5)
      assert_eq(u.completion_tokens, 1)
    }
    None => assert_true(false)
  }
}

///|
test "accumulator Error event sets Error finish" {
  let events = [
    LucentStreamEvent::Error(LucentError::simple("rate limit exceeded")),
    Done,
  ]
  let resp = lucent_stream_events_to_response(events, "r", "m")
  assert_eq(resp.choices[0].finish_reason, Error)
}

///|
test "accumulator BlockDiscard clears block content" {
  let events = [
    BlockStart(0, Text),
    BlockDelta(0, LucentBlockDelta::text_delta("first")),
    BlockDiscard(0),
    BlockDelta(0, LucentBlockDelta::text_delta("second")),
    BlockEnd(0),
    Finish(Stop),
    Done,
  ]
  let resp = lucent_stream_events_to_response(events, "r", "m")
  match resp.choices[0].message.content[0] {
    Text(t, _) => assert_eq(t, "second") // discard 后 only "second" 保留
    _ => assert_true(false)
  }
}

///|
test "accumulator ItemStart with ToolCall flushes to content" {
  let events = [
    ItemStart(
      0,
      LucentConversationItem::tool_call(
        LucentToolUse::new("fc-1", "run_code", "{\"code\":\"x\"}", None),
      ),
    ),
    ItemEnd(0),
    Finish(ToolCalls),
    Done,
  ]
  let resp = lucent_stream_events_to_response(events, "r", "m")
  match resp.choices[0].message.content[0] {
    ToolUse(tu) => assert_eq(tu.name, "run_code")
    _ => assert_true(false)
  }
}

///|
test "accumulator ItemStart with Message merges content" {
  let events = [
    ItemStart(
      0,
      LucentConversationItem::message(
        LucentMessage::new(Assistant, [LucentContent::text("via item")]),
      ),
    ),
    ItemEnd(0),
    Finish(Stop),
    Done,
  ]
  let resp = lucent_stream_events_to_response(events, "r", "m")
  match resp.choices[0].message.content[0] {
    Text(t, _) => assert_eq(t, "via item")
    _ => assert_true(false)
  }
}

///|
test "accumulator Annotations events ignored in response" {
  let ann = LucentAnnotation::new(
    Url,
    Some("foo"),
    Some("https://x"),
    Some(0),
    Some(3),
  )
  let events = [
    BlockStart(0, Text),
    BlockDelta(0, LucentBlockDelta::text_delta("foo")),
    Annotations(0, [ann]),
    BlockEnd(0),
    Finish(Stop),
    Done,
  ]
  let resp = lucent_stream_events_to_response(events, "r", "m")
  // Annotations 不影响累加内容
  match resp.choices[0].message.content[0] {
    Text(t, _) => assert_eq(t, "foo")
    _ => assert_true(false)
  }
}

///|
test "lucent_collect_annotations extracts all Annotations events" {
  let ann1 = LucentAnnotation::new(
    Url,
    Some("a"),
    Some("https://1"),
    None,
    None,
  )
  let ann2 = LucentAnnotation::new(
    FileCitation,
    Some("b"),
    Some("file-1"),
    None,
    None,
  )
  let events = [
    BlockStart(0, Text),
    Annotations(0, [ann1]),
    BlockDelta(0, LucentBlockDelta::text_delta("x")),
    Annotations(1, [ann2]),
    BlockEnd(0),
    Done,
  ]
  let collected = lucent_collect_annotations(events)
  assert_eq(collected.length(), 2)
  assert_true(collected[0].kind is Url)
  assert_true(collected[1].kind is FileCitation)
}

///|
test "accumulator unflushed text block flushed at stream end" {
  // 未显式 BlockEnd 的块在流结束时应被 flush
  let events = [
    BlockStart(0, Text),
    BlockDelta(0, LucentBlockDelta::text_delta("never ended")),
    Done,
  ]
  let resp = lucent_stream_events_to_response(events, "r", "m")
  match resp.choices[0].message.content[0] {
    Text(t, _) => assert_eq(t, "never ended")
    _ => assert_true(false)
  }
}

///|
test "accumulate - thinking delta does not leak into text" {
  // 先 Text 块收 TextDelta，再 Thinking 块收 ThinkingDelta
  let events = [
    BlockStart(0, Text),
    BlockDelta(0, LucentBlockDelta::text_delta("visible")),
    BlockStart(1, Thinking),
    BlockDelta(1, LucentBlockDelta::thinking_delta("hidden")),
    BlockEnd(1),
    BlockEnd(0),
    Finish(Stop),
    Done,
  ]
  let acc = lucent_stream_events_to_accumulated(events, "r1", "m1")
  let text = lucent_content_to_text(acc.response.choices[0].message.content)
  assert_true(text.contains("visible"))
  assert_false(text.contains("hidden")) // 思考内容不得进入文本
  // C3：thinking 归位到 message.reasoning，content 不含 Thinking
  match acc.response.choices[0].message.reasoning {
    Some(r) => assert_eq(r.text, "hidden")
    None => assert_true(false)
  }
  let mut has_thinking_in_content = false
  for c in acc.response.choices[0].message.content {
    match c {
      Thinking(_) => has_thinking_in_content = true
      _ => ()
    }
  }
  assert_false(has_thinking_in_content)
}

///|
test "accumulate - thinking delta on non-thinking block yields Degraded diagnostic" {
  // ThinkingDelta 到达时块类型为 Text（未显式 BlockStart(Thinking)）→ Degraded 诊断
  let events = [
    BlockStart(0, Text),
    BlockDelta(0, LucentBlockDelta::thinking_delta("stray")),
    BlockEnd(0),
    Finish(Stop),
    Done,
  ]
  let acc = lucent_stream_events_to_accumulated(events, "r1", "m1")
  let mut has_degraded = false
  for d in acc.diagnostics {
    if d.status == Degraded {
      has_degraded = true
    }
  }
  assert_true(has_degraded)
  // 且思考内容不进入文本
  let text = lucent_content_to_text(acc.response.choices[0].message.content)
  assert_false(text.contains("stray"))
}

///|
test "LucentMessage reasoning field - default None via new" {
  let m = LucentMessage::new(User, [LucentContent::text("hi")])
  assert_eq(m.role, User)
  assert_eq(m.reasoning, None)
}

///|
test "LucentMessage reasoning - record literal carries value" {
  let th = LucentThinking::visible("chain of thought", None)
  let m : LucentMessage = {
    role: Assistant,
    content: [LucentContent::text("answer")],
    phase: None,
    reasoning: Some(th),
  }
  match m.reasoning {
    Some(r) => assert_eq(r.text, "chain of thought")
    None => assert_true(false)
  }
}

///|
test "LucentMessage reasoning - to_json/from_json round trip" {
  let th = LucentThinking::visible("intermediate steps", Some("sig-1"))
  let m : LucentMessage = {
    role: Assistant,
    content: [LucentContent::text("final")],
    phase: None,
    reasoning: Some(th),
  }
  let jv = m.to_json()
  let back = LucentMessage::from_json(jv)
  match back {
    Ok(m2) =>
      match m2.reasoning {
        Some(r) => {
          assert_eq(r.text, "intermediate steps")
          assert_eq(r.signature, Some("sig-1"))
        }
        None => assert_true(false)
      }
    Err(_) => assert_true(false)
  }
}

///|
test "LucentResponse reasoning accessor - empty & no reasoning" {
  let empty = LucentResponse::new("r0", "model", None, [], None, None)
  assert_eq(empty.reasoning(), None)

  let no_thinking = LucentResponse::new(
    "r1",
    "model",
    None,
    [
      LucentChoice::new(
        0,
        LucentMessage::new(Assistant, [LucentContent::text("plain")]),
        Stop,
        None,
      ),
    ],
    None,
    None,
  )
  assert_eq(no_thinking.reasoning(), None)
}

///|
test "LucentResponse reasoning accessor - with reasoning" {
  let th = LucentThinking::visible("thought", None)
  let msg : LucentMessage = {
    role: Assistant,
    content: [LucentContent::text("answer")],
    phase: None,
    reasoning: Some(th),
  }
  let resp = LucentResponse::new(
    "r2",
    "model",
    None,
    [LucentChoice::new(0, msg, Stop, None)],
    None,
    None,
  )
  match resp.reasoning() {
    Some(r) => assert_eq(r.text, "thought")
    None => assert_true(false)
  }
}
