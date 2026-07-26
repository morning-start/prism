///|
/// Anthropic Messages 适配器白盒测试

///|
/// === 1. 请求解码 ===

///|
test "anthropic_to_lux_request - simple user message" {
  let json = "{\"model\":\"claude-sonnet-4\",\"max_tokens\":1024,\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"Hello\"}]}]}"
  match anthropic_to_lux_request(json) {
    Ok(req) => {
      assert_eq(req.model, "claude-sonnet-4")
      assert_eq(req.conversation.length(), 1)
      match req.conversation[0] {
        Message(m) => {
          assert_eq(m.role, User)
          assert_eq(m.content.length(), 1)
          match m.content[0] {
            Text(t, _) => assert_eq(t, "Hello")
            _ => assert_true(false)
          }
        }
        _ => assert_true(false)
      }
      assert_eq(req.options.max_output_tokens, Some(1024))
    }
    Err(e) => fail("unexpected error: \{e}")
  }
}

///|
test "anthropic_to_lux_request - system instruction extracted" {
  let json = "{\"model\":\"claude-sonnet-4\",\"max_tokens\":1024,\"system\":\"You are helpful\",\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"hi\"}]}]}"
  match anthropic_to_lux_request(json) {
    Ok(req) =>
      match req.instructions {
        Some(instrs) => assert_eq(instrs.length(), 1)
        None => assert_true(false)
      }
    Err(_) => assert_true(false)
  }
}

///|
test "anthropic_to_lux_request - system array of text blocks" {
  let json = "{\"model\":\"claude-sonnet-4\",\"max_tokens\":1024,\"system\":[{\"type\":\"text\",\"text\":\"You are\"},{\"type\":\"text\",\"text\":\"helpful\"}],\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"hi\"}]}]}"
  match anthropic_to_lux_request(json) {
    Ok(req) =>
      match req.instructions {
        Some(instrs) => assert_eq(instrs.length(), 2)
        None => assert_true(false)
      }
    Err(_) => assert_true(false)
  }
}

///|
test "anthropic_to_lux_request - assistant with tool_use and thinking" {
  let json = "{\"model\":\"claude-sonnet-4\",\"max_tokens\":1024,\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"weather?\"}]},{\"role\":\"assistant\",\"content\":[{\"type\":\"thinking\",\"thinking\":\"Let me check...\",\"signature\":\"sig-1\"},{\"type\":\"text\",\"text\":\"Sure\"},{\"type\":\"tool_use\",\"id\":\"toolu_1\",\"name\":\"get_weather\",\"input\":{\"city\":\"Beijing\"}}]}]}"
  match anthropic_to_lux_request(json) {
    Ok(req) => {
      assert_eq(req.conversation.length(), 2)
      match req.conversation[1] {
        Message(m) => {
          assert_eq(m.content.length(), 3)
          match m.content[0] {
            Thinking(th) => {
              assert_eq(th.text, "Let me check...")
              assert_eq(th.signature, Some("sig-1"))
            }
            _ => assert_true(false)
          }
          match m.content[2] {
            ToolUse(tu) => {
              assert_eq(tu.name, "get_weather")
              assert_eq(tu.id, "toolu_1")
            }
            _ => assert_true(false)
          }
        }
        _ => assert_true(false)
      }
    }
    Err(_) => assert_true(false)
  }
}

///|
test "anthropic_to_lux_request - tool_result in user message" {
  let json = "{\"model\":\"claude-sonnet-4\",\"max_tokens\":1024,\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"tool_result\",\"tool_use_id\":\"toolu_1\",\"content\":[{\"type\":\"text\",\"text\":\"{\\\"temp\\\":25}\"}],\"is_error\":false}]}]}"
  match anthropic_to_lux_request(json) {
    Ok(req) => {
      assert_eq(req.conversation.length(), 1)
      match req.conversation[0] {
        ToolResult(tr) => {
          assert_eq(tr.tool_use_id, "toolu_1")
          assert_eq(tr.is_error, false)
          assert_eq(tr.content.length(), 1)
        }
        _ => assert_true(false)
      }
    }
    Err(_) => assert_true(false)
  }
}

///|
test "anthropic_to_lux_request - tools with input_schema" {
  let json = "{\"model\":\"claude-sonnet-4\",\"max_tokens\":1024,\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"hi\"}]}],\"tools\":[{\"name\":\"get_weather\",\"description\":\"Get weather\",\"input_schema\":{\"type\":\"object\",\"properties\":{}}}]}"
  match anthropic_to_lux_request(json) {
    Ok(req) =>
      match req.tools {
        Some(tools) => {
          assert_eq(tools.length(), 1)
          assert_eq(tools[0].name, "get_weather")
        }
        None => assert_true(false)
      }
    Err(_) => assert_true(false)
  }
}

///|
test "anthropic_to_lux_request - tool_choice auto" {
  let json = "{\"model\":\"claude-sonnet-4\",\"max_tokens\":1024,\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"hi\"}]}],\"tool_choice\":{\"type\":\"auto\"}}"
  match anthropic_to_lux_request(json) {
    Ok(req) => assert_eq(req.tool_choice, Some(Auto))
    Err(_) => assert_true(false)
  }
}

///|
test "anthropic_to_lux_request - options mapping" {
  let json = "{\"model\":\"claude-sonnet-4\",\"max_tokens\":1024,\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"hi\"}]}],\"temperature\":0.5,\"top_p\":0.9,\"top_k\":10,\"stop_sequences\":[\"END\"],\"stream\":true}"
  match anthropic_to_lux_request(json) {
    Ok(req) => {
      match req.options.temperature {
        Some(t) => assert_true(t > 0.4 && t < 0.6)
        None => assert_true(false)
      }
      match req.options.top_p {
        Some(p) => assert_true(p > 0.8 && p < 1.0)
        None => assert_true(false)
      }
      assert_eq(req.options.top_k, Some(10))
      assert_eq(req.options.stream, true)
      match req.options.stop {
        Some(arr) => assert_eq(arr.length(), 1)
        None => assert_true(false)
      }
    }
    Err(_) => assert_true(false)
  }
}

///|
test "anthropic_to_lux_request - thinking config" {
  let json = "{\"model\":\"claude-sonnet-4\",\"max_tokens\":1024,\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"hi\"}]}],\"thinking\":{\"type\":\"enabled\",\"budget_tokens\":2048}}"
  match anthropic_to_lux_request(json) {
    Ok(req) =>
      match req.reasoning {
        Some(rc) => {
          assert_eq(rc.enabled, true)
          assert_eq(rc.budget_tokens, Some(2048))
        }
        None => assert_true(false)
      }
    Err(_) => assert_true(false)
  }
}

///|
test "anthropic_to_lux_request - redacted_thinking" {
  let json = "{\"model\":\"claude-sonnet-4\",\"max_tokens\":1024,\"messages\":[{\"role\":\"assistant\",\"content\":[{\"type\":\"redacted_thinking\",\"signature\":\"sig-redacted\"},{\"type\":\"text\",\"text\":\"ok\"}]}]}"
  match anthropic_to_lux_request(json) {
    Ok(req) =>
      match req.conversation[0] {
        Message(m) =>
          match m.content[0] {
            Thinking(th) => {
              assert_eq(th.redacted, true)
              assert_eq(th.signature, Some("sig-redacted"))
            }
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    Err(_) => assert_true(false)
  }
}

///|
test "anthropic_to_lux_request - invalid json" {
  match anthropic_to_lux_request("not json") {
    Ok(_) => assert_true(false)
    Err(_) => ()
  }
}

///|
test "anthropic_to_lux_request - metadata" {
  let json = "{\"model\":\"claude-sonnet-4\",\"max_tokens\":1024,\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"hi\"}]}],\"metadata\":{\"user_id\":\"user_123\"}}"
  match anthropic_to_lux_request(json) {
    Ok(req) =>
      match req.metadata {
        Some(m) =>
          match m.get("user_id") {
            Some("user_123") => ()
            _ => assert_true(false)
          }
        None => assert_true(false)
      }
    Err(_) => assert_true(false)
  }
}

///|
/// === 2. 请求编码 ===

///|
test "lux_request_to_anthropic - simple user message" {
  let req = @lux.LucentRequest::from_messages(
    "claude-sonnet-4",
    None,
    [@lux.LucentMessage::new(@lux.User, [@lux.LucentContent::text("Hello")])],
    None,
    None,
    @lux.LucentOptions::new(
      None,
      None,
      None,
      Some(1024),
      None,
      false,
      None,
      None,
      None,
      None,
      None,
    ),
    None,
    None,
    None,
    None,
  )
  match lux_request_to_anthropic(req) {
    Ok(s) => {
      assert_true(s.contains("\"model\":\"claude-sonnet-4\""))
      assert_true(s.contains("\"max_tokens\":1024"))
      assert_true(s.contains("\"role\":\"user\""))
    }
    Err(_) => assert_true(false)
  }
}

///|
test "lux_request_to_anthropic - instructions as system" {
  let req = @lux.LucentRequest::from_messages(
    "claude-sonnet-4",
    Some([@lux.LucentContent::text("You are helpful")]),
    [@lux.LucentMessage::new(@lux.User, [@lux.LucentContent::text("hi")])],
    None,
    None,
    @lux.LucentOptions::new(
      None,
      None,
      None,
      Some(1024),
      None,
      false,
      None,
      None,
      None,
      None,
      None,
    ),
    None,
    None,
    None,
    None,
  )
  match lux_request_to_anthropic(req) {
    Ok(s) => assert_true(s.contains("\"system\":\"You are helpful\""))
    Err(_) => assert_true(false)
  }
}

///|
test "lux_request_to_anthropic - tool_use encoded" {
  let req = @lux.LucentRequest::from_messages(
    "claude-sonnet-4",
    None,
    [
      @lux.LucentMessage::new(@lux.User, [@lux.LucentContent::text("weather?")]),
      @lux.LucentMessage::new(@lux.Assistant, [
        @lux.LucentContent::tool_use(
          "tu_1",
          "get_weather",
          "{\"city\":\"Beijing\"}",
          None,
        ),
      ]),
    ],
    None,
    None,
    @lux.LucentOptions::new(
      None,
      None,
      None,
      Some(1024),
      None,
      false,
      None,
      None,
      None,
      None,
      None,
    ),
    None,
    None,
    None,
    None,
  )
  match lux_request_to_anthropic(req) {
    Ok(s) => {
      assert_true(s.contains("\"type\":\"tool_use\""))
      assert_true(s.contains("\"id\":\"tu_1\""))
    }
    Err(_) => assert_true(false)
  }
}

///|
test "lux_request_to_anthropic - tool_result encoded" {
  let req = @lux.LucentRequest::new(
    "claude-sonnet-4",
    None,
    [
      @lux.LucentConversationItem::tool_result(
        @lux.LucentToolResult::ok("tu_1", [@lux.LucentContent::text("sunny")]),
      ),
    ],
    None,
    None,
    @lux.LucentOptions::new(
      None,
      None,
      None,
      Some(1024),
      None,
      false,
      None,
      None,
      None,
      None,
      None,
    ),
    None,
    None,
    None,
    None,
  )
  match lux_request_to_anthropic(req) {
    Ok(s) => assert_true(s.contains("\"type\":\"tool_result\""))
    Err(_) => assert_true(false)
  }
}

///|
test "lux_request_to_anthropic - thinking encoded" {
  let req = @lux.LucentRequest::new(
    "claude-sonnet-4",
    None,
    [
      @lux.LucentConversationItem::reasoning(
        @lux.LucentThinking::visible("Let me think", Some("sig-1")),
      ),
    ],
    None,
    None,
    @lux.LucentOptions::new(
      None,
      None,
      None,
      Some(1024),
      None,
      false,
      None,
      None,
      None,
      None,
      None,
    ),
    None,
    None,
    None,
    None,
  )
  match lux_request_to_anthropic(req) {
    Ok(s) => assert_true(s.contains("\"type\":\"thinking\""))
    Err(_) => assert_true(false)
  }
}

///|
test "lux_request_to_anthropic - tools with input_schema" {
  let req = @lux.LucentRequest::from_messages(
    "claude-sonnet-4",
    None,
    [@lux.LucentMessage::new(@lux.User, [@lux.LucentContent::text("hi")])],
    Some([
      @lux.LucentTool::simple(
        "get_weather", "Get weather", "{\"type\":\"object\"}",
      ),
    ]),
    None,
    @lux.LucentOptions::new(
      None,
      None,
      None,
      Some(1024),
      None,
      false,
      None,
      None,
      None,
      None,
      None,
    ),
    None,
    None,
    None,
    None,
  )
  match lux_request_to_anthropic(req) {
    Ok(s) => assert_true(s.contains("\"input_schema\":"))
    Err(_) => assert_true(false)
  }
}

///|
test "lux_request_to_anthropic - thinking config" {
  let req = @lux.LucentRequest::from_messages(
    "claude-sonnet-4",
    None,
    [@lux.LucentMessage::new(@lux.User, [@lux.LucentContent::text("hi")])],
    None,
    None,
    @lux.LucentOptions::new(
      None,
      None,
      None,
      Some(1024),
      None,
      false,
      None,
      None,
      None,
      None,
      None,
    ),
    None,
    Some(@lux.LucentReasoningConfig::enabled(Some(2048))),
    None,
    None,
  )
  match lux_request_to_anthropic(req) {
    Ok(s) => assert_true(s.contains("\"budget_tokens\":2048"))
    Err(_) => assert_true(false)
  }
}

///|
/// === 3. 响应解码 ===

///|
test "anthropic_to_lux_response - text and thinking" {
  let json = "{\"id\":\"msg_1\",\"type\":\"message\",\"role\":\"assistant\",\"model\":\"claude-sonnet-4\",\"content\":[{\"type\":\"thinking\",\"thinking\":\"Let me think\",\"signature\":\"sig-1\"},{\"type\":\"text\",\"text\":\"Hello!\"}],\"stop_reason\":\"end_turn\",\"usage\":{\"input_tokens\":10,\"output_tokens\":20}}"
  match anthropic_to_lux_response(json) {
    Ok(resp) => {
      assert_eq(resp.id, "msg_1")
      assert_eq(resp.model, "claude-sonnet-4")
      assert_eq(resp.choices.length(), 1)
      assert_eq(resp.choices[0].finish_reason, Stop)
      // content: thinking + text
      let content = resp.choices[0].message.content
      assert_eq(content.length(), 2)
      match content[0] {
        Thinking(th) => {
          assert_eq(th.text, "Let me think")
          assert_eq(th.signature, Some("sig-1"))
        }
        _ => assert_true(false)
      }
      match content[1] {
        Text(t, _) => assert_eq(t, "Hello!")
        _ => assert_true(false)
      }
      match resp.usage {
        Some(u) => {
          assert_eq(u.prompt_tokens, 10)
          assert_eq(u.completion_tokens, 20)
        }
        None => assert_true(false)
      }
    }
    Err(_) => assert_true(false)
  }
}

///|
test "anthropic_to_lux_response - tool_use response" {
  let json = "{\"id\":\"msg_2\",\"model\":\"claude-sonnet-4\",\"content\":[{\"type\":\"tool_use\",\"id\":\"tu_1\",\"name\":\"get_weather\",\"input\":{\"city\":\"Beijing\"}}],\"stop_reason\":\"tool_use\",\"usage\":{\"input_tokens\":5,\"output_tokens\":10}}"
  match anthropic_to_lux_response(json) {
    Ok(resp) => {
      assert_eq(resp.choices[0].finish_reason, ToolCalls)
      match resp.choices[0].message.content[0] {
        ToolUse(tu) => {
          assert_eq(tu.name, "get_weather")
          assert_eq(tu.id, "tu_1")
          // input JSON object → stringified as arguments_json
          assert_true(tu.arguments_json.contains("\"city\""))
        }
        _ => assert_true(false)
      }
    }
    Err(_) => assert_true(false)
  }
}

///|
test "anthropic_to_lux_response - max_tokens stop" {
  let json = "{\"id\":\"msg_3\",\"model\":\"claude-sonnet-4\",\"content\":[{\"type\":\"text\",\"text\":\"partial\"}],\"stop_reason\":\"max_tokens\",\"usage\":{\"input_tokens\":5,\"output_tokens\":50}}"
  match anthropic_to_lux_response(json) {
    Ok(resp) => assert_eq(resp.choices[0].finish_reason, Length)
    Err(_) => assert_true(false)
  }
}

///|
test "anthropic_to_lux_response - invalid json" {
  match anthropic_to_lux_response("not json") {
    Ok(_) => assert_true(false)
    Err(_) => ()
  }
}

///|
/// === 4. 响应编码 ===

///|
test "lux_response_to_anthropic - text response" {
  let content = @lux.LucentContent::text("Hello!")
  let msg = @lux.LucentMessage::new(@lux.Assistant, [content])
  let choice = @lux.LucentChoice::new(0, msg, @lux.Stop, None)
  let resp = @lux.LucentResponse::new(
    "msg_1",
    "claude-sonnet-4",
    None,
    [choice],
    Some(@lux.LucentUsage::new(10, 20, 30)),
    None,
  )
  match lux_response_to_anthropic(resp) {
    Ok(s) => {
      assert_true(s.contains("\"id\":\"msg_1\""))
      assert_true(s.contains("\"model\":\"claude-sonnet-4\""))
      assert_true(s.contains("\"type\":\"message\""))
      assert_true(s.contains("\"stop_reason\":\"end_turn\""))
      assert_true(s.contains("\"role\":\"assistant\""))
      assert_true(s.contains("\"input_tokens\":10"))
    }
    Err(_) => assert_true(false)
  }
}

///|
test "lux_response_to_anthropic - with tool_use" {
  let tu = @lux.LucentContent::tool_use(
    "tu_1",
    "get_weather",
    "{\"city\":\"Beijing\"}",
    None,
  )
  let msg = @lux.LucentMessage::new(@lux.Assistant, [tu])
  let choice = @lux.LucentChoice::new(0, msg, @lux.ToolCalls, None)
  let resp = @lux.LucentResponse::new(
    "msg_2",
    "claude-sonnet-4",
    None,
    [choice],
    None,
    None,
  )
  match lux_response_to_anthropic(resp) {
    Ok(s) => {
      assert_true(s.contains("\"stop_reason\":\"tool_use\""))
      assert_true(s.contains("\"type\":\"tool_use\""))
      assert_true(s.contains("\"id\":\"tu_1\""))
      assert_true(s.contains("\"input\":{\"city\":\"Beijing\"}"))
    }
    Err(_) => assert_true(false)
  }
}

///|
test "lux_response_to_anthropic - empty choices returns error" {
  let resp = @lux.LucentResponse::new("msg_0", "model", None, [], None, None)
  match lux_response_to_anthropic(resp) {
    Ok(_) => assert_true(false)
    Err(e) => assert_eq(e, "response has no choices")
  }
}

///|
/// === 5. 流解码 ===

///|
test "anthropic_sse_to_events - text sequence" {
  let sse = "event: message_start\ndata: {\"type\":\"message_start\",\"message\":{\"id\":\"msg_1\",\"model\":\"claude-sonnet-4\"}}\n\nevent: content_block_start\ndata: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}\n\nevent: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Hello\"}}\n\nevent: content_block_stop\ndata: {\"type\":\"content_block_stop\",\"index\":0}\n\nevent: message_delta\ndata: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\"},\"usage\":{\"output_tokens\":5}}\n\nevent: message_stop\ndata: {\"type\":\"message_stop\"}\n\n"
  match anthropic_sse_to_events(sse) {
    Ok(events) => {
      assert_true(events.length() >= 4)
      match events[0] {
        ConversationStart(_) => ()
        _ => assert_true(false)
      }
      assert_true(events[events.length() - 1] is Done)
    }
    Err(e) => fail("sse decode error: \{e}")
  }
}

///|
test "anthropic_sse_to_events - tool call with thinking" {
  let sse = "event: message_start\ndata: {\"type\":\"message_start\",\"message\":{\"id\":\"msg_2\",\"model\":\"claude-sonnet-4\"}}\n\nevent: content_block_start\ndata: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"thinking\",\"thinking\":\"\"}}\n\nevent: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"thinking_delta\",\"thinking\":\"Let me check\"}}\n\nevent: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"signature_delta\",\"signature\":\"sig_abc\"}}\n\nevent: content_block_stop\ndata: {\"type\":\"content_block_stop\",\"index\":0}\n\nevent: content_block_start\ndata: {\"type\":\"content_block_start\",\"index\":1,\"content_block\":{\"type\":\"tool_use\",\"id\":\"tu_1\",\"name\":\"get_weather\",\"input\":{}}}\n\nevent: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":1,\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\"{\\\"city\\\":\\\"Beijing\\\"}\"}}\n\nevent: content_block_stop\ndata: {\"type\":\"content_block_stop\",\"index\":1}\n\nevent: message_delta\ndata: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"tool_use\"}}\n\nevent: message_stop\ndata: {\"type\":\"message_stop\"}\n\n"
  match anthropic_sse_to_events(sse) {
    Ok(events) => {
      assert_true(events.length() >= 10)
      // check thinking block start
      let has_thinking = {
        let mut found = false
        for ev in events {
          match ev {
            BlockStart(0, Thinking) => found = true
            _ => ()
          }
        }
        found
      }
      assert_true(has_thinking)
      // check tool call block start
      let has_tool = {
        let mut found = false
        for ev in events {
          match ev {
            BlockStart(1, ToolCall(_, _)) => found = true
            _ => ()
          }
        }
        found
      }
      assert_true(has_tool)
      // check finish
      let has_finish = {
        let mut found = false
        for ev in events {
          match ev {
            Finish(ToolCalls) => found = true
            _ => ()
          }
        }
        found
      }
      assert_true(has_finish)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "anthropic_sse_to_events - done event" {
  let sse = "event: message_start\ndata: {\"type\":\"message_start\",\"message\":{\"id\":\"m\",\"model\":\"m\"}}\n\nevent: message_stop\ndata: {\"type\":\"message_stop\"}\n\n"
  match anthropic_sse_to_events(sse) {
    Ok(events) => assert_true(events[events.length() - 1] is Done)
    Err(_) => assert_true(false)
  }
}

///|
/// === 6. 流式编码 ===

///|
test "lux_events_to_anthropic_sse - text sequence" {
  let events : Array[@lux.LucentStreamEvent] = [
    ConversationStart(
      @lux.LucentConversationMeta::new(
        Some("msg_1"),
        Some("claude-sonnet-4"),
        None,
      ),
    ),
    BlockStart(0, Text),
    BlockDelta(0, @lux.LucentBlockDelta::text_delta("Hello")),
    BlockEnd(0),
    Finish(Stop),
    Done,
  ]
  match lux_events_to_anthropic_sse(events) {
    Ok(sse) => {
      assert_true(sse.contains("event: message_start"))
      assert_true(sse.contains("event: content_block_start"))
      assert_true(sse.contains("event: content_block_delta"))
      assert_true(sse.contains("event: content_block_stop"))
      assert_true(sse.contains("event: message_delta"))
      assert_true(sse.contains("event: message_stop"))
      assert_true(sse.contains("\"text_delta\""))
      assert_true(sse.contains("\"text\":\"Hello\""))
    }
    Err(_) => assert_true(false)
  }
}

///|
test "lux_events_to_anthropic_sse - tool call with thinking" {
  let events : Array[@lux.LucentStreamEvent] = [
    ConversationStart(
      @lux.LucentConversationMeta::new(
        Some("msg_2"),
        Some("claude-sonnet-4"),
        None,
      ),
    ),
    BlockStart(0, Thinking),
    BlockDelta(0, @lux.LucentBlockDelta::thinking_delta("Let me check")),
    BlockDelta(0, @lux.LucentBlockDelta::signature_delta("sig_abc")),
    BlockEnd(0),
    BlockStart(1, @lux.LucentBlockType::tool_call("tu_1", "get_weather")),
    BlockDelta(
      1,
      @lux.LucentBlockDelta::tool_arguments_delta("{\"city\":\"Beijing\"}"),
    ),
    BlockEnd(1),
    Finish(ToolCalls),
    Done,
  ]
  match lux_events_to_anthropic_sse(events) {
    Ok(sse) => {
      assert_true(sse.contains("thinking_delta"))
      assert_true(sse.contains("signature_delta"))
      assert_true(sse.contains("input_json_delta"))
      assert_true(sse.contains("tool_use"))
    }
    Err(_) => assert_true(false)
  }
}
