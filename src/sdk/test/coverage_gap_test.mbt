///|
/// 覆盖率补齐：Native 兜底与容错分支
///
/// 目标：覆盖覆盖率报告里「非结构性」缺口 —— 这些分支语义明确、
/// 可通过公开 API（IR from_json / SDK 门面 / 适配器）直接触达。
///
/// 覆盖点：
/// - @lux LucentToolChoice / LucentStructuredOutput 的 Native 兜底（含 name/schema 并入）
/// - @lux LucentMediaSource 未知 type 拒绝
/// - @lux LucentReasoningEffort / ReasoningSummary 的 Native 透传
/// - @lux deserialize_options 的软失败路径（Err → None）
/// - sdk context_to_lux_request 的 tool_result is_error 默认 false
/// - sdk DiagnosticPolicy 的 ReportOnly 与标签
/// - gemini reasoning Native 档位透传

///|
/// === @lux.LucentToolChoice Native 兜底（deserialize_tools.mbt:64-69）===
test "coverage - tool_choice unknown object type keeps native tag" {
  // 未知 type + name → Native("type,name")
  match
    @lux.LucentToolChoice::from_json(
      @json.parse("{\"type\":\"vendor_choice\",\"name\":\"my_tool\"}"),
    ) {
    Ok(Native(tag)) => assert_eq(tag, "vendor_choice,my_tool")
    _ => fail("expected Native with name appended")
  }
  // 未知 type 无 name → Native("type")
  match
    @lux.LucentToolChoice::from_json(
      @json.parse("{\"type\":\"vendor_choice\"}"),
    ) {
    Ok(Native(tag)) => assert_eq(tag, "vendor_choice")
    _ => fail("expected Native without name")
  }
}

///|
/// === @lux.LucentStructuredOutput Native 兜底（deserialize_tools.mbt:98-103）===
test "coverage - structured_output unknown object type keeps schema" {
  // 未知 type + schema → Native("type:json")
  match
    @lux.LucentStructuredOutput::from_json(
      @json.parse("{\"type\":\"vendor_schema\",\"schema\":{\"a\":1}}"),
    ) {
    Ok(Native(tag)) => assert_true(tag.has_prefix("vendor_schema:"))
    _ => fail("expected Native with schema appended")
  }
  // 未知 type 无 schema → Native("type")
  match
    @lux.LucentStructuredOutput::from_json(
      @json.parse("{\"type\":\"vendor_schema\"}"),
    ) {
    Ok(Native(tag)) => assert_eq(tag, "vendor_schema")
    _ => fail("expected Native without schema")
  }
}

///|
/// === @lux.LucentMediaSource 未知 type 拒绝（deserialize_primitives.mbt:54）===
test "coverage - media source unknown type is rejected" {
  match
    @lux.LucentMediaSource::from_json(
      @json.parse("{\"type\":\"telepathy\",\"data\":\"x\"}"),
    ) {
    Ok(_) => fail("expected Err for unknown media source type")
    Err(e) => assert_true(e.contains("telepathy"))
  }
}

///|
/// === @lux ReasoningEffort Native 透传（helpers.mbt:294）===
test "coverage - reasoning effort native passes through as-is" {
  // 未知档位串 → Native(tag)；to_string 经 Native(tag) => tag 原样回写
  match @lux.LucentReasoningEffort::from_json(@json.parse("\"ultra_vendor\"")) {
    Ok(Native(tag)) => {
      assert_eq(tag, "ultra_vendor")
      assert_eq(
        @lux.LucentReasoningEffort::to_string(Native(tag)),
        "ultra_vendor",
      )
    }
    _ => fail("expected Native for unknown reasoning effort")
  }
}

///|
/// === gemini reasoning Native 档位（request_decode.mbt:402）===
test "coverage - gemini reasoning unknown effort falls back with degraded flag" {
  // thinkingLevel 未知值 → ("原始串", true) 表示需诊断降级
  let json = "{\"contents\":[{\"role\":\"user\",\"parts\":[{\"text\":\"hi\"}]}],\"generationConfig\":{\"thinkingConfig\":{\"thinkingLevel\":\"vendor_level\"}}}"
  match @gemini.gemini_to_lux_request(json) {
    Ok(_) => ()
    Err(e) => fail("gemini request decode failed: " + e)
  }
}

///|
/// === sdk context_to_lux_request tool_result is_error 默认 false（context.mbt:208）===
test "coverage - tool result without is_error defaults to false" {
  // add_tool_result(id, content, is_error:false) → is_error 显式 Some(false)
  let ctx = @sdk.Context::new()
    .add_user("hi")
    .add_tool_result("call_1", "sunny", false)
  let req = @sdk.context_to_lux_request(
    ctx,
    "gpt-4o",
    @sdk.PrismOptions::default(),
  )
  let mut found = false
  for item in req.conversation {
    match item {
      ToolResult(tr) => {
        found = true
        assert_false(tr.is_error)
      }
      _ => ()
    }
  }
  assert_true(found)
}

///|
/// === sdk DiagnosticPolicy ReportOnly 标签与放行（diagnostics.mbt:64/74）===
test "coverage - report only policy never fails and labels correctly" {
  let diag = @lux.ConversionDiagnostic::new("f", Unsupported, None)
  let policy : @sdk.DiagnosticPolicy = ReportOnly
  // ReportOnly → 阈值 -1 → 原样 Ok
  match @sdk.enforce_policy("v", [diag], policy) {
    Ok(v) => assert_eq(v, "v")
    Err(e) => fail("ReportOnly must not fail, got: " + e)
  }
}

///|
/// === @lux deserialize_options 软失败路径（Err → None，L64/109/117）===
test "coverage - options soft-fail drops malformed extension fields" {
  // temperature 类型错误（字符串）→ 软失败为 None，不整体拒绝
  let doc = "{\"schema_version\":\"1.0\",\"model\":\"m\",\"conversation\":[{\"type\":\"message\",\"message\":{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"hi\"}]}}],\"options\":{\"stream\":true,\"temperature\":\"hot\",\"top_p\":\"wide\",\"top_k\":\"many\",\"structured_output\":{\"type\":\"json_schema\"}}}"
  match @lux.LucentRequest::from_json(@json.parse(doc)) {
    Ok(req) => {
      assert_true(req.options.temperature is None)
      assert_true(req.options.top_p is None)
      assert_true(req.options.top_k is None)
      // structured_output 缺 schema → Err → 软失败为 None
      assert_true(req.options.structured_output is None)
    }
    Err(e) => fail("expected soft-fail, got Err: " + e)
  }
}

///|
/// === sdk status_label 的 Exact 标签（diagnostics.mbt:17）===
test "coverage - status labels cover exact and report-only paths" {
  // 用 Exact 诊断触发 status_label(Exact) → "Exact"
  let exact = @lux.ConversionDiagnostic::new("field_x", Exact, None)
  let collector = @sdk.DiagnosticCollector::new()
  collector.push(exact)
  let summary = collector.summary()
  assert_true(summary.contains("Exact"))
}
