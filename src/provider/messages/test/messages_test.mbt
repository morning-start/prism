///|
/// Anthropic Messages 适配器黑盒测试 — 仅通过公开 API 验证
///
/// 与白盒测试（_wbtest.mbt）互补：模拟外部调用者视角，
/// 通过 6 函数 + capability 的公开契约验证双向转换与 round-trip 语义。

///|
/// === capability ===

///|
test "capability - declares provider name" {
  assert_eq(@messages.capability().provider, "messages")
}

///|
/// === 请求 round-trip ===

///|
test "round trip - request encode then decode preserves semantics" {
  let original = @lux.LucentRequest::from_messages(
    "claude-sonnet-4",
    Some([@lux.LucentContent::text("You are helpful")]),
    [@lux.LucentMessage::new(User, [@lux.LucentContent::text("hi")])],
    None,
    None,
    @lux.LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
  match @messages.lux_request_to_messages(original) {
    Ok(cr) =>
      match @messages.messages_to_lux_request(cr.value()) {
        Ok(round_cr) => {
          let round = round_cr.value()
          assert_eq(round.model, "claude-sonnet-4")
          assert_eq(round.conversation.length(), 1)
          match round.conversation[0] {
            Message(m) => {
              assert_eq(m.role, User)
              match m.content[0] {
                Text(t, _) => assert_eq(t, "hi")
                _ => assert_true(false)
              }
            }
            _ => assert_true(false)
          }
          match round.instructions {
            Some(instrs) =>
              match instrs[0] {
                Text(t, _) => assert_eq(t, "You are helpful")
                _ => assert_true(false)
              }
            None => assert_true(false)
          }
        }
        Err(_) => assert_true(false)
      }
    Err(_) => assert_true(false)
  }
}

///|
/// === 响应 round-trip ===

///|
test "round trip - response encode then decode preserves text" {
  let resp = @lux.LucentResponse::new(
    "resp-1",
    "claude-sonnet-4",
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
  match @messages.lux_response_to_messages(resp) {
    Ok(cr) =>
      match @messages.messages_to_lux_response(cr.value()) {
        Ok(round_cr) => assert_eq(round_cr.value().get_text(), "hi")
        Err(_) => assert_true(false)
      }
    Err(_) => assert_true(false)
  }
}

///|
/// === 错误路径 ===

///|
test "invalid input - malformed JSON returns Err" {
  assert_true(@messages.messages_to_lux_request("{invalid}") is Err(_))
  assert_true(@messages.messages_to_lux_response("{invalid}") is Err(_))
}

///|
/// === 解码覆盖矩阵：畸形块 / 罕见特性分支 ===
///
/// 目的：驱动 messages_to_lux_request 内部的错误分支与特性分支
/// （解析失败必须产生 Degraded 诊断而非静默丢弃；合法变异必须落到
/// 正确的 IR 形态）。

///|
/// 断言 ConversionResult 的诊断列表中存在 detail 含 expect 的条目
fn diag_contains(
  cr : @lux.ConversionResult[@lux.LucentRequest],
  expect : String,
) -> Unit raise {
  for d in cr.diagnostics() {
    match d.detail {
      Some(s) => if s.contains(expect) { return }
      None => ()
    }
  }
  fail("expected diagnostic containing: \{expect}")
}

///|
fn decode_ok(json : String) -> @lux.LucentRequest raise {
  match @messages.messages_to_lux_request(json) {
    Ok(cr) => cr.value()
    Err(e) => fail("expected Ok, got Err: \{e}")
  }
}

///|
test "messages decode - malformed content blocks degrade with diagnostics" {
  let cases : Array[(String, String)] = [
    (
      "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"text\"}]}]}",
      "text block missing 'text' field",
    ),
    (
      "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"image\"}]}]}",
      "image block missing 'source' field",
    ),
    (
      "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"image\",\"source\":{\"type\":\"ftp\",\"url\":\"u\"}}]}]}",
      "image block with unknown source type: ftp",
    ),
    (
      "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"document\"}]}]}",
      "document block missing 'source' field",
    ),
    (
      "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"document\",\"source\":{\"type\":\"ftp\"}}]}]}",
      "document block with unknown source type: ftp",
    ),
    (
      "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"video\"}]}]}",
      "unknown content block type: video",
    ),
    (
      "{\"model\":\"m\",\"messages\":[{\"role\":\"user\"}]}", "message missing content",
    ),
    (
      "{\"model\":\"m\",\"messages\":[{\"role\":\"assistant\"}]}", "assistant message missing content",
    ),
    (
      "{\"model\":\"m\",\"messages\":[{\"role\":\"system\",\"content\":\"x\"}]}",
      "unknown message role: system",
    ),
    (
      "{\"model\":\"m\",\"messages\":[{\"content\":\"x\"}]}", "message missing 'role' field",
    ),
  ]
  for c in cases {
    match @messages.messages_to_lux_request(c.0) {
      Ok(cr) => diag_contains(cr, c.1)
      Err(e) => fail("unexpected Err for \{c.0}: \{e}")
    }
  }
}

///|
test "messages decode - string content becomes single text block" {
  let req = decode_ok(
    "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"},{\"role\":\"assistant\",\"content\":\"yo\"}]}",
  )
  match req.conversation[0] {
    Message(m) =>
      match m.content[0] {
        Text(t, _) => assert_eq(t, "hi")
        _ => fail("expected Text block")
      }
    _ => fail("expected Message item")
  }
}

///|
test "messages decode - tool_use without input defaults to empty object args" {
  let req = decode_ok(
    "{\"model\":\"m\",\"messages\":[{\"role\":\"assistant\",\"content\":[{\"type\":\"tool_use\",\"id\":\"t1\",\"name\":\"f\"}]}]}",
  )
  match req.conversation[0] {
    Message(m) =>
      match m.content[0] {
        ToolUse(tu) => assert_eq(tu.arguments_json, "{}")
        _ => fail("expected ToolUse block")
      }
    _ => fail("expected Message item")
  }
}

///|
test "messages decode - tool_result is_error maps to error tool result" {
  let req = decode_ok(
    "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"tool_result\",\"tool_use_id\":\"t1\",\"is_error\":true,\"content\":[{\"type\":\"text\",\"text\":\"boom\"}]}]}]}",
  )
  match req.conversation[0] {
    ToolResult(tr) => assert_true(tr.is_error)
    _ => fail("expected ToolResult item")
  }
}

///|
test "messages decode - mixed tool_result and text preserves blocks with diagnostic" {
  match
    @messages.messages_to_lux_request(
      "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"tool_result\",\"tool_use_id\":\"t1\",\"content\":[{\"type\":\"text\",\"text\":\"ok\"}]},{\"type\":\"text\",\"text\":\"thanks\"}]}]}",
    ) {
    Ok(cr) => {
      diag_contains(cr, "tool_result mixed with other content")
      match cr.value().conversation[0] {
        Message(m) => assert_eq(m.content.length(), 2)
        _ => fail("expected Message item")
      }
    }
    Err(e) => fail("unexpected Err: \{e}")
  }
}

///|
test "messages decode - image and document sources decode to media sources" {
  let req = decode_ok(
    "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"image\",\"source\":{\"type\":\"base64\",\"media_type\":\"image/png\",\"data\":\"AAA\"}},{\"type\":\"image\",\"source\":{\"type\":\"url\",\"url\":\"http://x\"}},{\"type\":\"document\",\"source\":{\"type\":\"base64\",\"media_type\":\"application/pdf\",\"data\":\"BBB\"}},{\"type\":\"document\",\"source\":{\"type\":\"url\",\"url\":\"http://y\"}}]}]}",
  )
  match req.conversation[0] {
    Message(m) => {
      match m.content[0] {
        Image(mm) =>
          match mm.source {
            Inline(d) => assert_eq(d, "AAA")
            _ => fail("expected Inline source")
          }
        _ => fail("expected Image block")
      }
      match m.content[1] {
        Image(mm) =>
          match mm.source {
            Url(u) => assert_eq(u, "http://x")
            _ => fail("expected Url source")
          }
        _ => fail("expected Image block")
      }
      match m.content[2] {
        File(mm) =>
          match mm.source {
            Inline(d) => assert_eq(d, "BBB")
            _ => fail("expected Inline source")
          }
        _ => fail("expected File block")
      }
      match m.content[3] {
        File(mm) =>
          match mm.source {
            Url(u) => assert_eq(u, "http://y")
            _ => fail("expected Url source")
          }
        _ => fail("expected File block")
      }
    }
    _ => fail("expected Message item")
  }
}

///|
test "messages decode - tools type maps to tool kind" {
  let req = decode_ok(
    "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"tools\":[{\"type\":\"custom\",\"name\":\"f\",\"input_schema\":{}},{\"type\":\"code_execution_20250522\",\"name\":\"c\"},{\"type\":\"bash_20250124\",\"name\":\"b\"},{\"type\":\"weird_20260101\",\"name\":\"w\"},{\"name\":\"n\"}]}",
  )
  match req.tools {
    Some(ts) => {
      assert_eq(ts.length(), 5)
      assert_eq(ts[0].kind, Function)
      assert_eq(ts[1].kind, CodeExecution)
      assert_eq(ts[2].kind, Shell)
      assert_eq(ts[3].kind, Native("weird_20260101"))
      assert_eq(ts[4].kind, Function)
      // input_schema 缺失 → "{}"
      assert_eq(ts[1].parameters_json, "{}")
    }
    None => fail("expected tools")
  }
}

///|
/// 包装辅助：把 payload 塞进标准请求的指定字段，避免手数外层大括号
fn msgs_req(field : String, payload : String) -> String {
  "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"" +
  field +
  "\":" +
  payload +
  "}"
}

///|
test "messages decode - tool_choice variants" {
  assert_eq(
    decode_ok(msgs_req("tool_choice", "{\"type\":\"auto\"}")).tool_choice,
    Some(Auto),
  )
  assert_eq(
    decode_ok(msgs_req("tool_choice", "{\"type\":\"any\"}")).tool_choice,
    Some(Required),
  )
  assert_eq(
    decode_ok(msgs_req("tool_choice", "{\"type\":\"tool\",\"name\":\"f\"}")).tool_choice,
    Some(SpecificTool("f")),
  )
  assert_eq(
    decode_ok(msgs_req("tool_choice", "{\"type\":\"tool\"}")).tool_choice,
    None,
  )
  assert_eq(
    decode_ok(msgs_req("tool_choice", "{\"type\":\"bogus\"}")).tool_choice,
    None,
  )
  // tool_choice 非对象 → None
  assert_eq(decode_ok(msgs_req("tool_choice", "\"auto\"")).tool_choice, None)
}

///|
test "messages decode - thinking config variants" {
  match
    decode_ok(
      msgs_req("thinking", "{\"type\":\"enabled\",\"budget_tokens\":1024}"),
    ).reasoning {
    Some(rc) => {
      assert_true(rc.enabled)
      assert_eq(rc.budget_tokens, Some(1024))
    }
    None => fail("expected reasoning config")
  }
  // enabled 但 budget_tokens 非数字 → budget None
  match
    decode_ok(
      msgs_req("thinking", "{\"type\":\"enabled\",\"budget_tokens\":\"big\"}"),
    ).reasoning {
    Some(rc) => assert_eq(rc.budget_tokens, None)
    None => fail("expected reasoning config")
  }
  // adaptive → 启用、无 budget
  match decode_ok(msgs_req("thinking", "{\"type\":\"adaptive\"}")).reasoning {
    Some(rc) => {
      assert_eq(rc.budget_tokens, None)
      assert_eq(rc.effort, None)
    }
    None => fail("expected reasoning config")
  }
  // 未知形态 → disabled（保守）
  match decode_ok(msgs_req("thinking", "{\"type\":\"weird\"}")).reasoning {
    Some(rc) => assert_false(rc.enabled)
    None => fail("expected reasoning config")
  }
  // thinking 非对象 → 无 reasoning
  assert_eq(decode_ok(msgs_req("thinking", "\"enabled\"")).reasoning, None)
}

///|
test "messages decode - output_config effort variants" {
  assert_eq(
    decode_ok(msgs_req("output_config", "{\"effort\":\"low\"}")).reasoning.unwrap().effort,
    Some(Low),
  )
  assert_eq(
    decode_ok(msgs_req("output_config", "{\"effort\":\"medium\"}")).reasoning.unwrap().effort,
    Some(Medium),
  )
  assert_eq(
    decode_ok(msgs_req("output_config", "{\"effort\":\"high\"}")).reasoning.unwrap().effort,
    Some(High),
  )
  assert_eq(
    decode_ok(msgs_req("output_config", "{\"effort\":\"xhigh\"}")).reasoning.unwrap().effort,
    Some(XHigh),
  )
  // 未知 effort → None（不猜）
  assert_eq(
    decode_ok(msgs_req("output_config", "{\"effort\":\"ultra\"}")).reasoning,
    None,
  )
  // max → XHigh + 降级诊断
  match
    @messages.messages_to_lux_request(
      msgs_req("output_config", "{\"effort\":\"max\"}"),
    ) {
    Ok(cr) => diag_contains(cr, "downgraded to xhigh")
    Err(e) => fail("unexpected Err: \{e}")
  }
}

///|
test "messages decode - output_config format variants" {
  match
    decode_ok(
      msgs_req(
        "output_config", "{\"format\":{\"type\":\"json_schema\",\"schema\":{}}}",
      ),
    ).options.structured_output {
    Some(JsonObject) => ()
    _ => fail("expected JsonObject")
  }
  match
    decode_ok(
      msgs_req("output_config", "{\"format\":{\"type\":\"json_schema\"}}"),
    ).options.structured_output {
    Some(JsonObject) => ()
    _ => fail("expected JsonObject")
  }
  match
    decode_ok(
      msgs_req(
        "output_config", "{\"format\":{\"type\":\"json_schema\",\"schema\":{\"type\":\"object\"}}}",
      ),
    ).options.structured_output {
    Some(JsonSchema(s)) => assert_true(s.contains("object"))
    _ => fail("expected JsonSchema")
  }
  match
    decode_ok(msgs_req("output_config", "{\"format\":{\"type\":\"text\"}}")).options.structured_output {
    Some(Text) => ()
    _ => fail("expected Text")
  }
  // 未知 format → None
  assert_eq(
    decode_ok(msgs_req("output_config", "{\"format\":{\"type\":\"yaml\"}}")).options.structured_output,
    None,
  )
  // format 缺失 → None
  assert_eq(
    decode_ok(msgs_req("output_config", "{\"effort\":\"low\"}")).options.structured_output,
    None,
  )
}

///|
test "messages decode - system array parses text blocks and skips others" {
  let req = decode_ok(
    "{\"model\":\"m\",\"system\":[{\"text\":\"a\"},{\"type\":\"text\",\"text\":\"b\"},{\"image\":\"x\"}],\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}",
  )
  match req.instructions {
    Some(instrs) => assert_eq(instrs.length(), 2)
    None => fail("expected instructions")
  }
}

///|
test "messages decode - metadata keeps only string values" {
  let req = decode_ok(
    "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"metadata\":{\"k\":\"v\",\"n\":42}}",
  )
  match req.metadata {
    Some(m) => {
      assert_eq(m["k"], "v")
      assert_false(m.contains("n"))
    }
    None => fail("expected metadata")
  }
}
