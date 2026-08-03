///|
/// Google Vertex AI Gemini 适配器白盒测试
///
/// Vertex 是标准 Gemini 的薄封装，差异仅在于端点 URL 和认证方式，
/// JSON 接口完全一致，因此直接委托给 gemini 包。

///|
/// === 1. 请求解码 ===

///|
test "vertex_to_lux_request - simple user message" {
  let json = "{\"model\":\"gemini-2.5-pro\",\"contents\":[{\"role\":\"user\",\"parts\":[{\"text\":\"Hello\"}]}]}"
  match vertex_to_lux_request(json) {
    Ok(cr) => {
      let req = cr.value()
      assert_eq(req.model, "gemini-2.5-pro")
      assert_eq(req.conversation.length(), 1)
    }
    Err(e) => fail("unexpected: \{e}")
  }
}

///|
test "vertex_to_lux_request - systemInstruction extracted" {
  let json = "{\"model\":\"gemini-2.5-pro\",\"systemInstruction\":{\"role\":\"system\",\"parts\":[{\"text\":\"Be helpful\"}]},\"contents\":[{\"role\":\"user\",\"parts\":[{\"text\":\"hi\"}]}]}"
  match vertex_to_lux_request(json) {
    Ok(cr) =>
      match cr.value().instructions {
        Some(instrs) => assert_eq(instrs.length(), 1)
        None => assert_true(false)
      }
    Err(_) => assert_true(false)
  }
}

///|
test "vertex_to_lux_request - model role mapped to assistant" {
  let json = "{\"model\":\"gemini-2.5-pro\",\"contents\":[{\"role\":\"model\",\"parts\":[{\"text\":\"hello\"}]}]}"
  match vertex_to_lux_request(json) {
    Ok(cr) =>
      match cr.value().conversation[0] {
        Message(m) => assert_eq(m.role, Assistant)
        _ => assert_true(false)
      }
    Err(_) => assert_true(false)
  }
}

///|
test "vertex_to_lux_request - functionCall and functionResponse" {
  let json = "{\"model\":\"gemini-2.5-pro\",\"contents\":[{\"role\":\"model\",\"parts\":[{\"functionCall\":{\"name\":\"search\",\"args\":{\"q\":\"x\"}}}]},{\"role\":\"tool\",\"parts\":[{\"functionResponse\":{\"name\":\"search\",\"response\":{\"name\":\"search\",\"content\":{\"result\":\"ok\"}}}}]}]}"
  match vertex_to_lux_request(json) {
    Ok(cr) => {
      let req = cr.value()
      assert_eq(req.conversation.length(), 2)
      match req.conversation[1] {
        ToolResult(tr) => assert_eq(tr.tool_use_id, "fc_search_0")
        _ => assert_true(false)
      }
    }
    Err(_) => assert_true(false)
  }
}

///|
test "vertex_to_lux_request - invalid json" {
  match vertex_to_lux_request("not json") {
    Ok(_) => assert_true(false)
    Err(_) => ()
  }
}

///|
/// === 2. 请求编码 ===

///|
test "lux_request_to_vertex - simple user message" {
  let req = @lux.LucentRequest::from_messages(
    "gemini-2.5-pro",
    None,
    [@lux.LucentMessage::new(User, [@lux.LucentContent::text("hi")])],
    None,
    None,
    @lux.LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
  match lux_request_to_vertex(req) {
    Ok(cr) => {
      let s = cr.value()
      assert_true(s.contains("\"contents\":"))
      assert_true(s.contains("\"role\":\"user\""))
    }
    Err(_) => assert_true(false)
  }
}

///|
/// === 3. 响应解码 ===

///|
test "vertex_to_lux_response - text response" {
  let json = "{\"candidates\":[{\"index\":0,\"content\":{\"role\":\"model\",\"parts\":[{\"text\":\"Hello!\"}]},\"finishReason\":\"STOP\"}],\"usageMetadata\":{\"promptTokenCount\":10,\"candidatesTokenCount\":5,\"totalTokenCount\":15}}"
  match vertex_to_lux_response(json) {
    Ok(cr) => {
      let resp = cr.value()
      assert_eq(resp.choices.length(), 1)
      assert_eq(resp.choices[0].finish_reason, Stop)
      match resp.usage {
        Some(u) => {
          assert_eq(u.prompt_tokens, 10)
          assert_eq(u.completion_tokens, 5)
        }
        None => assert_true(false)
      }
    }
    Err(_) => assert_true(false)
  }
}

///|
test "vertex_to_lux_response - invalid json" {
  match vertex_to_lux_response("not json") {
    Ok(_) => assert_true(false)
    Err(_) => ()
  }
}

///|
/// === 4. 响应编码 ===

///|
test "lux_response_to_vertex - text response" {
  let msg = @lux.LucentMessage::new(Assistant, [
    @lux.LucentContent::text("Hello"),
  ])
  let choice = @lux.LucentChoice::new(0, msg, Stop, None)
  let resp = @lux.LucentResponse::new(
    "",
    "gemini-2.5-pro",
    None,
    [choice],
    Some(@lux.LucentUsage::new(10, 5, 15)),
    None,
  )
  match lux_response_to_vertex(resp) {
    Ok(cr) => {
      let s = cr.value()
      assert_true(s.contains("\"candidates\":"))
      assert_true(s.contains("\"finishReason\":\"STOP\""))
    }
    Err(_) => assert_true(false)
  }
}

///|
/// === 5. 流解码 ===

///|
test "vertex_sse_to_events - text chunks" {
  let sse = "data: {\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"text\":\"Hello\"}]}}]}\ndata: {\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"text\":\" world\"}]},\"finishReason\":\"STOP\"}],\"usageMetadata\":{\"promptTokenCount\":10,\"candidatesTokenCount\":5,\"totalTokenCount\":15}}\n"
  match vertex_sse_to_events(sse) {
    Ok(cr) => assert_true(cr.value().length() >= 3)
    Err(_) => assert_true(false)
  }
}

///|
/// === 6. 流编码 ===

///|
test "lux_events_to_vertex_sse - text sequence" {
  let events : Array[@lux.LucentStreamEvent] = [
    BlockStart(0, Text),
    BlockDelta(0, @lux.LucentBlockDelta::text_delta("Hello")),
    Finish(Stop),
    Usage(@lux.LucentUsage::new(10, 5, 15)),
  ]
  match lux_events_to_vertex_sse(events) {
    Ok(cr) => {
      let sse = cr.value()
      assert_true(sse.contains("\"text\":\"Hello\""))
      assert_true(sse.contains("\"finishReason\":\"STOP\""))
    }
    Err(_) => assert_true(false)
  }
}

///|
/// === round-trip 一致性 ===

///|
test "round trip - vertex request encode then decode" {
  let original = @lux.LucentRequest::from_messages(
    "gemini-2.5-pro",
    Some([@lux.LucentContent::text("Be helpful")]),
    [@lux.LucentMessage::new(User, [@lux.LucentContent::text("hi")])],
    None,
    None,
    @lux.LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
  match lux_request_to_vertex(original) {
    Ok(cr) =>
      match vertex_to_lux_request(cr.value()) {
        Ok(cr2) => {
          let round = cr2.value()
          assert_eq(round.model, "gemini-2.5-pro")
          assert_eq(round.conversation.length(), 1)
        }
        Err(_) => assert_true(false)
      }
    Err(_) => assert_true(false)
  }
}
