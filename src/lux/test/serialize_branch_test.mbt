///|
/// src/lux SERIALIZE-side branch coverage (BLACKBOX)
///
/// Targets the uncovered `Option` / `match` / fallback arms of the `to_json`
/// family in src/lux plus the stream accumulator helpers:
/// - diagnostics_json.mbt   ConversionResult/Diagnostic from_json rejection arms
/// - stream.mbt             accumulator: fallback id/model, media flush,
///                          merged reasoning, refusal-on-thinking, tool result
/// - helpers.mbt            ValidateResult / with_conversation /
///                          with_provider_payload / get_text / effort strings
/// - serialize_primitives   annotation kind, tool kind, description absent,
///                          store/extras, effort/summary
/// - serialize_response     cached tokens, provider_payload, created_at, extra
/// - serialize_meta         ProviderCapability extra_params
/// - serialize_stream       block_type refusal/image/audio/video/native arms,
///                          block_delta native arm
///
/// Every test builds the IR value with the optional field SET and again with it
/// UNSET so both arms of each conditional are asserted. Where a cluster has
/// several symmetric arms the cases are loops / tuples instead of N copies.
///
/// NOTE: bare enum constructors are used deliberately. Fully qualified
/// spellings (`@lux.LucentBlockType::Text` style annotations) trip warning 73
/// under `--deny-warn`; type inference resolves the bare constructor.

///|
/// Stand-in value decoder for ConversionResult::from_json (success path).
fn ser_decode_ok(_v : Json) -> Result[Int, String] {
  Ok(1)
}

///|
/// Stand-in value decoder for ConversionResult::from_json (failure path).
fn ser_decode_fail(_v : Json) -> Result[Int, String] {
  Err("decoder rejected the value payload")
}

///|
/// === diagnostics_json.mbt ===

///|
test "lux serialize - diagnostics json from_json rejection arms" {
  let diagnostic_rejects : Array[String] = [
    // payload is not an object at all
    "123",
    // object without "field"
     "{}",
    // unknown status string
     "{\"field\":\"temperature\",\"status\":\"bogus\"}",
    // status present but not a string
     "{\"field\":\"temperature\",\"status\":42}",
  ]
  for raw in diagnostic_rejects {
    match @lux.ConversionDiagnostic::from_json(@json.parse(raw)) {
      Ok(_) => fail("expected Err for diagnostic payload: \{raw}")
      Err(_) => ()
    }
  }

  let result_rejects : Array[String] = [
    // "value" absent
    "{\"diagnostics\":[]}",
    // diagnostics entry that is not an object
     "{\"value\":1,\"diagnostics\":[\"oops\"]}",
    // payload is not an object at all
     "[]",
  ]
  for raw in result_rejects {
    match @lux.ConversionResult::from_json(@json.parse(raw), ser_decode_ok) {
      Ok(_) => fail("expected Err for result payload: \{raw}")
      Err(_) => ()
    }
  }

  // the caller supplied decoder refuses the value
  match
    @lux.ConversionResult::from_json(
      @json.parse("{\"value\":1}"),
      ser_decode_fail,
    ) {
    Ok(_) => fail("expected Err when the value decoder rejects")
    Err(e) => assert_true(e.contains("value decode failed"))
  }

  // diagnostics present but not an array is tolerated (soft-absent)
  match
    @lux.ConversionResult::from_json(
      @json.parse("{\"value\":1,\"diagnostics\":\"oops\"}"),
      ser_decode_ok,
    ) {
    Ok(r) => assert_eq(r.diagnostics().length(), 0)
    Err(e) => fail("expected Ok for non-array diagnostics: \{e}")
  }
}

///|
test "lux serialize - diagnostics json detail arms" {
  let bare = @lux.ConversionDiagnostic::new("temperature", Degraded, None)
  let detailed = @lux.ConversionDiagnostic::new(
    "temperature",
    Degraded,
    Some("2.5 clamped to 2.0"),
  )
  let bare_str = bare.to_json().stringify()
  let detailed_str = detailed.to_json().stringify()
  assert_false(bare_str.contains("\"detail\""))
  assert_true(detailed_str.contains("\"detail\":\"2.5 clamped to 2.0\""))
  assert_true(detailed_str.contains("\"status\":\"degraded\""))

  let result = @lux.ConversionResult::new("value-1")
  let plain = result.to_json(fn(v) { Json::string(v) }).stringify()
  assert_true(plain.contains("\"value\":\"value-1\""))
  assert_true(plain.contains("\"diagnostics\":[]"))

  let with_diag = result.with_diagnostic(detailed)
  let envelope = with_diag.envelope_json(Json::string("value-1")).stringify()
  assert_true(envelope.contains("\"diagnostics\":["))
  assert_true(envelope.contains("\"field\":\"temperature\""))
}

///|
/// === stream.mbt (accumulator) ===

///|
test "lux serialize - stream start event keeps fallback identity" {
  let events = [
    @lux.LucentStreamEvent::ConversationStart(
      @lux.LucentConversationMeta::new(None, None, None),
    ),
    Done,
  ]
  let resp = @lux.lucent_stream_events_to_response(
    events, "fallback-id", "fallback-model",
  )
  assert_eq(resp.id, "fallback-id")
  assert_eq(resp.model, "fallback-model")
}

///|
test "lux serialize - stream merges chained reasoning items" {
  let first = @lux.LucentThinking::new("alpha ", Some("sig-1"), true, None)
  let second = @lux.LucentThinking::new("beta", None, false, None)
  let events = [
    @lux.LucentStreamEvent::ItemStart(
      0,
      @lux.LucentConversationItem::reasoning(first),
    ),
    ItemStart(1, @lux.LucentConversationItem::reasoning(second)),
    Done,
  ]
  let resp = @lux.lucent_stream_events_to_response(events, "id-1", "gpt-4o")
  match resp.choices[0].message.reasoning {
    Some(th) => {
      assert_eq(th.text, "alpha beta")
      assert_eq(th.signature, Some("sig-1"))
      assert_true(th.redacted)
    }
    None => fail("expected merged reasoning")
  }
}

///|
test "lux serialize - stream flush falls back to block text" {
  // thinking block that only ever received a TextDelta: flush_block must read
  // block_texts because block_thinking stayed empty
  let events = [
    @lux.LucentStreamEvent::BlockStart(0, @lux.LucentBlockType::thinking()),
    BlockDelta(0, @lux.LucentBlockDelta::text_delta("plain")),
    BlockEnd(0),
    Done,
  ]
  let resp = @lux.lucent_stream_events_to_response(events, "id-1", "gpt-4o")
  match resp.choices[0].message.reasoning {
    Some(th) => assert_eq(th.text, "plain")
    None => fail("expected reasoning built from block text")
  }
  assert_eq(resp.choices[0].message.content.length(), 0)
}

///|
test "lux serialize - stream flush skips media blocks" {
  // native block type: flush_block drops the accumulated text entirely and
  // leaves reasoning untouched
  let events = [
    @lux.LucentStreamEvent::BlockStart(
      1,
      @lux.LucentBlockType::native("vendor"),
    ),
    BlockDelta(1, @lux.LucentBlockDelta::text_delta("dropped")),
    BlockEnd(1),
    Done,
  ]
  let resp = @lux.lucent_stream_events_to_response(events, "id-1", "gpt-4o")
  assert_eq(resp.choices[0].message.content.length(), 0)
  match resp.choices[0].message.reasoning {
    Some(_) => fail("media block must not become reasoning")
    None => ()
  }
}

///|
test "lux serialize - stream refusal delta on thinking block" {
  // RefusalDelta only converts a Text block; on any other block type the
  // delta is appended to the text buffer without retyping the block
  let events = [
    @lux.LucentStreamEvent::BlockStart(0, @lux.LucentBlockType::thinking()),
    BlockDelta(0, @lux.LucentBlockDelta::refusal_delta("no")),
    Done,
  ]
  let resp = @lux.lucent_stream_events_to_response(events, "id-1", "gpt-4o")
  match resp.choices[0].message.reasoning {
    Some(th) => assert_eq(th.text, "no")
    None => fail("thinking block must stay thinking on refusal delta")
  }
  assert_eq(resp.choices[0].message.content.length(), 0)
}

///|
test "lux serialize - stream item start tool result" {
  let tr = @lux.LucentToolResult::error("call_1", [
    @lux.LucentContent::text("boom"),
  ])
  let events = [
    @lux.LucentStreamEvent::ItemStart(
      0,
      @lux.LucentConversationItem::tool_result(tr),
    ),
    Done,
  ]
  let resp = @lux.lucent_stream_events_to_response(events, "id-1", "gpt-4o")
  let content = resp.choices[0].message.content
  assert_eq(content.length(), 1)
  match content[0] {
    ToolResult(parsed) => {
      assert_eq(parsed.tool_use_id, "call_1")
      assert_true(parsed.is_error)
    }
    _ => fail("expected a tool_result content block")
  }
}

///|
/// === serialize_meta.mbt ===

///|
test "lux serialize - discovery capability extra params" {
  let caps = @lux.LucentCapabilities::create(
    Full,
    Partial,
    Absent,
    Full,
    Partial,
    [Text, Image],
    [Text],
  )
  let extra : Map[String, Json] = { "trace": Json::boolean(true) }
  let cap = @lux.ProviderCapability::new("gpt-*", "openai", caps, Some(extra))
  let cap_str = cap.to_json().stringify()
  assert_true(cap_str.contains("\"extra_params\""))
  assert_true(cap_str.contains("\"trace\":true"))

  let bare = @lux.ProviderCapability::new("gpt-*", "openai", caps, None)
  assert_false(bare.to_json().stringify().contains("extra_params"))

  let discovery = @lux.LucentDiscovery::new(
    "1.0",
    "https://example.com/lux-ir-v1.json",
    [cap, bare],
  )
  assert_true(discovery.to_json().stringify().contains("\"providers\""))
}

///|
/// === serialize_primitives.mbt ===

///|
test "lux serialize - annotation kind web search citation" {
  assert_eq(
    @lux.LucentAnnotationKind::WebSearchCitation.to_json(),
    "web_search_citation",
  )
  assert_eq(
    @lux.LucentAnnotationKind::Native("vendor_cite").to_json(),
    "vendor_cite",
  )
}

///|
test "lux serialize - tool kind apply patch and absent description" {
  let patch = @lux.LucentTool::new(
    "apply_patch",
    None,
    "{\"type\":\"object\"}",
    None,
    ApplyPatch,
  )
  let patch_str = patch.to_json().stringify()
  assert_true(patch_str.contains("\"kind\":\"apply_patch\""))
  assert_false(patch_str.contains("\"description\""))

  let search = @lux.LucentTool::simple("search", "Web search", "{}")
  assert_true(
    search.to_json().stringify().contains("\"description\":\"Web search\""),
  )

  let mcp = @lux.LucentTool::new("mcp_tool", None, "{}", None, MCP)
  assert_true(mcp.to_json().stringify().contains("\"kind\":\"mcp\""))
}

///|
test "lux serialize - options store and extras arms" {
  let base = @lux.LucentOptions::default()
  let opts = base
    .with_store(Some(true))
    .with_extras(Some({ "tenant": Json::string("acme") }))
  let opts_str = opts.to_json().stringify()
  assert_true(opts_str.contains("\"store\":true"))
  assert_true(opts_str.contains("\"extras\""))
  assert_true(opts_str.contains("\"tenant\":\"acme\""))

  let plain = @lux.LucentOptions::default().to_json().stringify()
  assert_false(plain.contains("store"))
  assert_false(plain.contains("extras"))
}

///|
test "lux serialize - reasoning config effort and summary arms" {
  let efforts : Array[(@lux.LucentReasoningEffort, String)] = [
    (Low, "low"),
    (Medium, "medium"),
    (High, "high"),
    (XHigh, "xhigh"),
  ]
  for pair in efforts {
    let cfg = @lux.LucentReasoningConfig::new(Some(pair.0), None)
    assert_true(
      cfg.to_json().stringify().contains("\"effort\":\"" + pair.1 + "\""),
    )
  }

  let summaries : Array[(@lux.LucentReasoningSummary, String)] = [
    (Auto, "auto"),
    (Concise, "concise"),
    (Detailed, "detailed"),
  ]
  for pair in summaries {
    let cfg = @lux.LucentReasoningConfig::new(None, Some(pair.0))
    assert_true(
      cfg.to_json().stringify().contains("\"summary\":\"" + pair.1 + "\""),
    )
  }

  let off = @lux.LucentReasoningConfig::new(None, None)
  assert_false(off.to_json().stringify().contains("\"effort\""))
  assert_false(off.to_json().stringify().contains("\"summary\""))
}

///|
/// === serialize_response.mbt ===

///|
test "lux serialize - usage cached and reasoning token arms" {
  let usage = @lux.LucentUsage::full(10, 20, 30, Some(4), Some(5), Some(6))
  let usage_str = usage.to_json().stringify()
  assert_true(usage_str.contains("\"reasoning_tokens\":4"))
  assert_true(usage_str.contains("\"cached_tokens\":5"))
  assert_true(usage_str.contains("\"cache_creation_tokens\":6"))

  let plain = @lux.LucentUsage::new(1, 2, 3).to_json().stringify()
  assert_false(plain.contains("cached_tokens"))
  assert_false(plain.contains("cache_creation_tokens"))
}

///|
test "lux serialize - response created at and provider payload arms" {
  let resp = @lux.LucentResponse::new(
    "resp-1",
    "gpt-4o",
    Some(1700000000),
    [
      @lux.LucentChoice::new(
        0,
        @lux.LucentMessage::new(Assistant, [@lux.LucentContent::text("hi")]),
        Stop,
        None,
      ),
    ],
    Some(@lux.LucentUsage::new(1, 2, 3)),
    Some(@json.parse("{\"vendor\":true}")),
  )
  let resp_str = resp.to_json().stringify()
  assert_true(resp_str.contains("\"created_at\":1700000000"))
  assert_true(resp_str.contains("\"provider_payload\":{\"vendor\":true}"))
}

///|
test "lux serialize - conversation meta full and empty arms" {
  let empty = @lux.LucentConversationMeta::new(None, None, None)
  assert_false(empty.to_json().stringify().contains("\"id\""))
  assert_false(empty.to_json().stringify().contains("\"created_at\""))

  let full = @lux.LucentConversationMeta::new_full(
    Some("resp-1"),
    Some("gpt-4o"),
    Some(7),
    Some(1700000000),
    Some(@json.parse("{\"hint\":\"x\"}")),
  )
  let full_str = full.to_json().stringify()
  assert_true(full_str.contains("\"id\":\"resp-1\""))
  assert_true(full_str.contains("\"usage_input\":7"))
  assert_true(full_str.contains("\"created_at\":1700000000"))
  assert_true(full_str.contains("\"extra\":{\"hint\":\"x\"}"))
}

///|
/// === serialize_stream.mbt ===

///|
test "lux serialize - stream block type media arms" {
  assert_eq(
    @lux.LucentBlockType::refusal().to_json().stringify(),
    "\"refusal\"",
  )
  let media : Array[@lux.LucentBlockType] = [
    Image,
    Audio,
    Video,
    Native("vendor_block"),
  ]
  for bt in media {
    let event = @lux.LucentStreamEvent::BlockStart(0, bt)
    let event_str = event.to_json().stringify()
    assert_true(event_str.contains("\"block_type\":\""))
    assert_true(event_str.contains("\"event\":\"block_start\""))
  }
}

///|
test "lux serialize - stream block delta native arm" {
  let delta = @lux.LucentBlockDelta::native_delta(
    "vendor_delta",
    @json.parse("{\"part\":1}"),
  )
  let delta_str = delta.to_json().stringify()
  assert_true(delta_str.contains("\"type\":\"native\""))
  assert_true(delta_str.contains("\"native_tag\":\"vendor_delta\""))
  assert_true(delta_str.contains("\"native_payload\":{\"part\":1}"))
}

///|
/// === helpers.mbt ===

///|
test "lux serialize - validate result constructors" {
  let ok = @lux.ValidateResult::ok()
  assert_true(ok.valid)
  assert_eq(ok.errors.length(), 0)
  assert_eq(ok.warnings.length(), 0)

  let bad = @lux.ValidateResult::error("model is required")
  assert_false(bad.valid)
  assert_eq(bad.errors.length(), 1)
  assert_eq(bad.errors[0], "model is required")
  assert_eq(bad.warnings.length(), 0)
}

///|
test "lux serialize - request conversation copy" {
  let first = @lux.LucentConversationItem::message(
    @lux.LucentMessage::new(User, [@lux.LucentContent::text("one")]),
  )
  let second = @lux.LucentConversationItem::message(
    @lux.LucentMessage::new(Assistant, [@lux.LucentContent::text("two")]),
  )
  let req = @lux.LucentRequest::new(
    "gpt-4o",
    None,
    [first],
    None,
    None,
    @lux.LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
  let widened = req.with_conversation([first, second])
  assert_eq(widened.conversation.length(), 2)
  assert_eq(req.conversation.length(), 1)
}

///|
test "lux serialize - response provider payload copy" {
  let resp = @lux.LucentResponse::new(
    "resp-1",
    "gpt-4o",
    None,
    [
      @lux.LucentChoice::new(
        0,
        @lux.LucentMessage::new(Assistant, [@lux.LucentContent::text("hi")]),
        Stop,
        None,
      ),
    ],
    None,
    None,
  )
  assert_false(resp.to_json().stringify().contains("provider_payload"))

  let with_payload = resp.with_provider_payload(Some(@json.parse("{\"k\":1}")))
  assert_true(
    with_payload
    .to_json()
    .stringify()
    .contains("\"provider_payload\":{\"k\":1}"),
  )
}

///|
test "lux serialize - response get text without choices" {
  let empty = @lux.LucentResponse::new(
    "no-choices",
    "gpt-4o",
    None,
    [],
    None,
    None,
  )
  assert_eq(empty.get_text(), "")
  match empty.reasoning() {
    Some(_) => fail("expected no reasoning without choices")
    None => ()
  }
}

///|
test "lux serialize - reasoning effort string mapping" {
  assert_eq(@lux.LucentReasoningEffort::Low.to_string(), "low")
  assert_eq(@lux.LucentReasoningEffort::Medium.to_string(), "medium")
  assert_eq(@lux.LucentReasoningEffort::High.to_string(), "high")
  assert_eq(@lux.LucentReasoningEffort::XHigh.to_string(), "xhigh")
}
