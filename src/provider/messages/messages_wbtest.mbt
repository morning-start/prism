///|
/// Anthropic Messages 适配器白盒测试

///|
/// === 1. 请求解码 ===

///|
test "messages_to_lux_request - simple user message" {
  let json = "{\"model\":\"claude-sonnet-4\",\"max_tokens\":1024,\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"Hello\"}]}]}"
  match messages_to_lux_request(json) {
    Ok(cr) => {
      let req = cr.value()
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
test "messages_to_lux_request - system instruction extracted" {
  let json = "{\"model\":\"claude-sonnet-4\",\"max_tokens\":1024,\"system\":\"You are helpful\",\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"hi\"}]}]}"
  match messages_to_lux_request(json) {
    Ok(cr) =>
      match cr.value().instructions {
        Some(instrs) => assert_eq(instrs.length(), 1)
        None => assert_true(false)
      }
    Err(_) => assert_true(false)
  }
}

///|
test "messages_to_lux_request - system array of text blocks" {
  let json = "{\"model\":\"claude-sonnet-4\",\"max_tokens\":1024,\"system\":[{\"type\":\"text\",\"text\":\"You are\"},{\"type\":\"text\",\"text\":\"helpful\"}],\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"hi\"}]}]}"
  match messages_to_lux_request(json) {
    Ok(cr) =>
      match cr.value().instructions {
        Some(instrs) => assert_eq(instrs.length(), 2)
        None => assert_true(false)
      }
    Err(_) => assert_true(false)
  }
}

///|
test "messages_to_lux_request - assistant with tool_use and thinking" {
  let json = "{\"model\":\"claude-sonnet-4\",\"max_tokens\":1024,\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"weather?\"}]},{\"role\":\"assistant\",\"content\":[{\"type\":\"thinking\",\"thinking\":\"Let me check...\",\"signature\":\"sig-1\"},{\"type\":\"text\",\"text\":\"Sure\"},{\"type\":\"tool_use\",\"id\":\"toolu_1\",\"name\":\"get_weather\",\"input\":{\"city\":\"Beijing\"}}]}]}"
  match messages_to_lux_request(json) {
    Ok(cr) => {
      let req = cr.value()
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
test "messages_to_lux_request - tool_result in user message" {
  let json = "{\"model\":\"claude-sonnet-4\",\"max_tokens\":1024,\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"tool_result\",\"tool_use_id\":\"toolu_1\",\"content\":[{\"type\":\"text\",\"text\":\"{\\\"temp\\\":25}\"}],\"is_error\":false}]}]}"
  match messages_to_lux_request(json) {
    Ok(cr) => {
      let req = cr.value()
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
test "messages_to_lux_request - tools with input_schema" {
  let json = "{\"model\":\"claude-sonnet-4\",\"max_tokens\":1024,\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"hi\"}]}],\"tools\":[{\"name\":\"get_weather\",\"description\":\"Get weather\",\"input_schema\":{\"type\":\"object\",\"properties\":{}}}]}"
  match messages_to_lux_request(json) {
    Ok(cr) =>
      match cr.value().tools {
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
test "messages_to_lux_request - tool types mapped to kinds" {
  let json = "{\"model\":\"claude-sonnet-4\",\"max_tokens\":1024,\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"hi\"}]}],\"tools\":[{\"type\":\"custom\",\"name\":\"f\",\"input_schema\":{\"type\":\"object\"}},{\"type\":\"code_execution_20250522\"},{\"type\":\"bash_20250124\",\"name\":\"bash\",\"description\":\"Run shell\"}]}"
  match messages_to_lux_request(json) {
    Ok(cr) =>
      match cr.value().tools {
        Some(tools) => {
          assert_eq(tools.length(), 3)
          assert_eq(tools[0].kind, Function)
          assert_eq(tools[1].kind, CodeExecution)
          assert_eq(tools[2].kind, Shell)
        }
        None => assert_true(false)
      }
    Err(_) => assert_true(false)
  }
}

///|
test "messages_to_lux_request - tool_choice auto" {
  let json = "{\"model\":\"claude-sonnet-4\",\"max_tokens\":1024,\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"hi\"}]}],\"tool_choice\":{\"type\":\"auto\"}}"
  match messages_to_lux_request(json) {
    Ok(cr) => assert_eq(cr.value().tool_choice, Some(Auto))
    Err(_) => assert_true(false)
  }
}

///|
test "messages_to_lux_request - options mapping" {
  let json = "{\"model\":\"claude-sonnet-4\",\"max_tokens\":1024,\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"hi\"}]}],\"temperature\":0.5,\"top_p\":0.9,\"top_k\":10,\"stop_sequences\":[\"END\"],\"stream\":true}"
  match messages_to_lux_request(json) {
    Ok(cr) => {
      let req = cr.value()
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
test "messages_to_lux_request - thinking config" {
  let json = "{\"model\":\"claude-sonnet-4\",\"max_tokens\":1024,\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"hi\"}]}],\"thinking\":{\"type\":\"enabled\",\"budget_tokens\":2048}}"
  match messages_to_lux_request(json) {
    Ok(cr) =>
      match cr.value().reasoning {
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
test "messages_to_lux_request - redacted_thinking" {
  let json = "{\"model\":\"claude-sonnet-4\",\"max_tokens\":1024,\"messages\":[{\"role\":\"assistant\",\"content\":[{\"type\":\"redacted_thinking\",\"signature\":\"sig-redacted\"},{\"type\":\"text\",\"text\":\"ok\"}]}]}"
  match messages_to_lux_request(json) {
    Ok(cr) =>
      match cr.value().conversation[0] {
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
test "messages_to_lux_request - invalid json" {
  match messages_to_lux_request("not json") {
    Ok(_) => assert_true(false)
    Err(_) => ()
  }
}

///|
test "messages_to_lux_request - metadata" {
  let json = "{\"model\":\"claude-sonnet-4\",\"max_tokens\":1024,\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"hi\"}]}],\"metadata\":{\"user_id\":\"user_123\"}}"
  match messages_to_lux_request(json) {
    Ok(cr) =>
      match cr.value().metadata {
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
test "lux_request_to_messages - simple user message" {
  let req = @lux.LucentRequest::from_messages(
    "claude-sonnet-4",
    None,
    [@lux.LucentMessage::new(User, [@lux.LucentContent::text("Hello")])],
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
    ),
    None,
    None,
    None,
    None,
  )
  match lux_request_to_messages(req) {
    Ok(cr) => {
      let s = cr.value()
      assert_true(s.contains("\"model\":\"claude-sonnet-4\""))
      assert_true(s.contains("\"max_tokens\":1024"))
      assert_true(s.contains("\"role\":\"user\""))
    }
    Err(_) => assert_true(false)
  }
}

///|
test "lux_request_to_messages - instructions as system" {
  let req = @lux.LucentRequest::from_messages(
    "claude-sonnet-4",
    Some([@lux.LucentContent::text("You are helpful")]),
    [@lux.LucentMessage::new(User, [@lux.LucentContent::text("hi")])],
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
    ),
    None,
    None,
    None,
    None,
  )
  match lux_request_to_messages(req) {
    Ok(cr) => assert_true(cr.value().contains("\"system\":\"You are helpful\""))
    Err(_) => assert_true(false)
  }
}

///|
test "lux_request_to_messages - tool_use encoded" {
  let req = @lux.LucentRequest::from_messages(
    "claude-sonnet-4",
    None,
    [
      @lux.LucentMessage::new(User, [@lux.LucentContent::text("weather?")]),
      @lux.LucentMessage::new(Assistant, [
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
    ),
    None,
    None,
    None,
    None,
  )
  match lux_request_to_messages(req) {
    Ok(cr) => {
      let s = cr.value()
      assert_true(s.contains("\"type\":\"tool_use\""))
      assert_true(s.contains("\"id\":\"tu_1\""))
    }
    Err(_) => assert_true(false)
  }
}

///|
test "lux_request_to_messages - tool_result encoded" {
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
    ),
    None,
    None,
    None,
    None,
  )
  match lux_request_to_messages(req) {
    Ok(cr) => assert_true(cr.value().contains("\"type\":\"tool_result\""))
    Err(_) => assert_true(false)
  }
}

///|
test "lux_request_to_messages - thinking encoded" {
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
    ),
    None,
    None,
    None,
    None,
  )
  match lux_request_to_messages(req) {
    Ok(cr) => assert_true(cr.value().contains("\"type\":\"thinking\""))
    Err(_) => assert_true(false)
  }
}

///|
test "lux_request_to_messages - tools with input_schema" {
  let req = @lux.LucentRequest::from_messages(
    "claude-sonnet-4",
    None,
    [@lux.LucentMessage::new(User, [@lux.LucentContent::text("hi")])],
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
    ),
    None,
    None,
    None,
    None,
  )
  match lux_request_to_messages(req) {
    Ok(cr) => assert_true(cr.value().contains("\"input_schema\":"))
    Err(_) => assert_true(false)
  }
}

///|
test "lux_request_to_messages - tool kinds encoded" {
  let req = @lux.LucentRequest::from_messages(
    "claude-sonnet-4",
    None,
    [@lux.LucentMessage::new(User, [@lux.LucentContent::text("hi")])],
    Some([
      @lux.LucentTool::new(
        "f",
        Some("d"),
        "{\"type\":\"object\"}",
        None,
        Function,
      ),
      @lux.LucentTool::new("", None, "{}", None, CodeExecution),
      @lux.LucentTool::new("bash", Some("Run shell"), "{}", None, Shell),
    ]),
    None,
    @lux.LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
  match lux_request_to_messages(req) {
    Ok(cr) => {
      let s = cr.value()
      // custom 工具保持 name + input_schema，无 type 字段
      assert_true(s.contains("\"input_schema\":"))
      // code_execution_20250522 只有 type
      assert_true(s.contains("\"type\":\"code_execution_20250522\""))
      // bash_20250124 携带 name
      assert_true(s.contains("\"type\":\"bash_20250124\""))
    }
    Err(_) => assert_true(false)
  }
}

///|
test "lux_request_to_messages - thinking config" {
  let req = @lux.LucentRequest::from_messages(
    "claude-sonnet-4",
    None,
    [@lux.LucentMessage::new(User, [@lux.LucentContent::text("hi")])],
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
    ),
    None,
    Some(@lux.LucentReasoningConfig::enabled(Some(2048))),
    None,
    None,
  )
  match lux_request_to_messages(req) {
    Ok(cr) => assert_true(cr.value().contains("\"budget_tokens\":2048"))
    Err(_) => assert_true(false)
  }
}

///|
/// === 3. 响应解码 ===

///|
test "messages_to_lux_response - text and thinking" {
  let json = "{\"id\":\"msg_1\",\"type\":\"message\",\"role\":\"assistant\",\"model\":\"claude-sonnet-4\",\"content\":[{\"type\":\"thinking\",\"thinking\":\"Let me think\",\"signature\":\"sig-1\"},{\"type\":\"text\",\"text\":\"Hello!\"}],\"stop_reason\":\"end_turn\",\"usage\":{\"input_tokens\":10,\"output_tokens\":20}}"
  match messages_to_lux_response(json) {
    Ok(cr) => {
      let resp = cr.value()
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
test "messages_to_lux_response - tool_use response" {
  let json = "{\"id\":\"msg_2\",\"model\":\"claude-sonnet-4\",\"content\":[{\"type\":\"tool_use\",\"id\":\"tu_1\",\"name\":\"get_weather\",\"input\":{\"city\":\"Beijing\"}}],\"stop_reason\":\"tool_use\",\"usage\":{\"input_tokens\":5,\"output_tokens\":10}}"
  match messages_to_lux_response(json) {
    Ok(cr) => {
      let resp = cr.value()
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
test "messages_to_lux_response - max_tokens stop" {
  let json = "{\"id\":\"msg_3\",\"model\":\"claude-sonnet-4\",\"content\":[{\"type\":\"text\",\"text\":\"partial\"}],\"stop_reason\":\"max_tokens\",\"usage\":{\"input_tokens\":5,\"output_tokens\":50}}"
  match messages_to_lux_response(json) {
    Ok(cr) => assert_eq(cr.value().choices[0].finish_reason, Length)
    Err(_) => assert_true(false)
  }
}

///|
test "messages_to_lux_response - invalid json" {
  match messages_to_lux_response("not json") {
    Ok(_) => assert_true(false)
    Err(_) => ()
  }
}

///|
/// === 4. 响应编码 ===

///|
test "lux_response_to_messages - text response" {
  let content = @lux.LucentContent::text("Hello!")
  let msg = @lux.LucentMessage::new(Assistant, [content])
  let choice = @lux.LucentChoice::new(0, msg, Stop, None)
  let resp = @lux.LucentResponse::new(
    "msg_1",
    "claude-sonnet-4",
    None,
    [choice],
    Some(@lux.LucentUsage::new(10, 20, 30)),
    None,
  )
  match lux_response_to_messages(resp) {
    Ok(cr) => {
      let s = cr.value()
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
test "lux_response_to_messages - with tool_use" {
  let tu = @lux.LucentContent::tool_use(
    "tu_1",
    "get_weather",
    "{\"city\":\"Beijing\"}",
    None,
  )
  let msg = @lux.LucentMessage::new(Assistant, [tu])
  let choice = @lux.LucentChoice::new(0, msg, ToolCalls, None)
  let resp = @lux.LucentResponse::new(
    "msg_2",
    "claude-sonnet-4",
    None,
    [choice],
    None,
    None,
  )
  match lux_response_to_messages(resp) {
    Ok(cr) => {
      let s = cr.value()
      assert_true(s.contains("\"stop_reason\":\"tool_use\""))
      assert_true(s.contains("\"type\":\"tool_use\""))
      assert_true(s.contains("\"id\":\"tu_1\""))
      assert_true(s.contains("\"input\":{\"city\":\"Beijing\"}"))
    }
    Err(_) => assert_true(false)
  }
}

///|
test "lux_response_to_messages - empty choices returns error" {
  let resp = @lux.LucentResponse::new("msg_0", "model", None, [], None, None)
  match lux_response_to_messages(resp) {
    Ok(_) => assert_true(false)
    Err(e) => assert_eq(e, "response has no choices")
  }
}

///|
/// 跨协议链路：vLLM 消息级 reasoning → IR → Anthropic 出站 → thinking block
test "lux_response_to_messages - message-level reasoning emits thinking block" {
  let th = @lux.LucentThinking::visible("step by step", None)
  let msg = @lux.LucentMessage::with_reasoning(
    Assistant,
    [@lux.LucentContent::text("answer")],
    Some(th),
  )
  let resp = @lux.LucentResponse::new(
    "msg_1",
    "model",
    None,
    [@lux.LucentChoice::new(0, msg, Stop, None)],
    None,
    None,
  )
  match lux_response_to_messages(resp) {
    Ok(cr) => {
      let s = cr.value()
      // 消息级 reasoning 前置为 thinking block
      assert_true(
        s.contains("{\"type\":\"thinking\",\"thinking\":\"step by step\"}"),
      )
      // content 保留可见文本
      assert_true(s.contains("{\"type\":\"text\",\"text\":\"answer\"}"))
    }
    Err(_) => assert_true(false)
  }
}

///|
/// 跨协议链路：signature 保留（Anthropic 原生承载，非 Degraded）
test "lux_response_to_messages - message-level reasoning keeps signature" {
  let th = @lux.LucentThinking::visible("thought", Some("sig-abc"))
  let msg = @lux.LucentMessage::with_reasoning(
    Assistant,
    [@lux.LucentContent::text("answer")],
    Some(th),
  )
  let resp = @lux.LucentResponse::new(
    "msg_1",
    "model",
    None,
    [@lux.LucentChoice::new(0, msg, Stop, None)],
    None,
    None,
  )
  match lux_response_to_messages(resp) {
    Ok(cr) => {
      let s = cr.value()
      assert_true(s.contains("\"signature\":\"sig-abc\""))
      // signature 可承载，不应产生 Degraded
      let mut has_degraded = false
      for d in cr.diagnostics() {
        if d.status == Degraded {
          has_degraded = true
        }
      }
      assert_false(has_degraded)
    }
    Err(_) => assert_true(false)
  }
}

///|
/// 双载体并存：message.reasoning 优先，content Thinking 跳过 → Degraded
test "lux_response_to_messages - dual carrier yields Degraded" {
  let th = @lux.LucentThinking::visible("msg reasoning", None)
  let msg = @lux.LucentMessage::with_reasoning(
    Assistant,
    [@lux.LucentContent::thinking("block reasoning", None)],
    Some(th),
  )
  let resp = @lux.LucentResponse::new(
    "msg_1",
    "model",
    None,
    [@lux.LucentChoice::new(0, msg, Stop, None)],
    None,
    None,
  )
  match lux_response_to_messages(resp) {
    Ok(cr) => {
      let mut has_dual = false
      for d in cr.diagnostics() {
        if d.field == "reasoning.dual_carrier" && d.status == Degraded {
          has_dual = true
        }
      }
      assert_true(has_dual)
      // message.reasoning 胜出，content Thinking 被跳过（不重复输出）
      let s = cr.value()
      assert_true(s.contains("\"thinking\":\"msg reasoning\""))
      assert_false(s.contains("\"thinking\":\"block reasoning\""))
    }
    Err(_) => assert_true(false)
  }
}

///|
/// === 5. 流解码 ===

///|
test "messages_sse_to_events - text sequence" {
  let sse = "event: message_start\ndata: {\"type\":\"message_start\",\"message\":{\"id\":\"msg_1\",\"model\":\"claude-sonnet-4\"}}\n\nevent: content_block_start\ndata: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}\n\nevent: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Hello\"}}\n\nevent: content_block_stop\ndata: {\"type\":\"content_block_stop\",\"index\":0}\n\nevent: message_delta\ndata: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\"},\"usage\":{\"output_tokens\":5}}\n\nevent: message_stop\ndata: {\"type\":\"message_stop\"}\n\n"
  match messages_sse_to_events(sse) {
    Ok(cr) => {
      let events = cr.value()
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
test "messages_sse_to_events - tool call with thinking" {
  let sse = "event: message_start\ndata: {\"type\":\"message_start\",\"message\":{\"id\":\"msg_2\",\"model\":\"claude-sonnet-4\"}}\n\nevent: content_block_start\ndata: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"thinking\",\"thinking\":\"\"}}\n\nevent: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"thinking_delta\",\"thinking\":\"Let me check\"}}\n\nevent: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"signature_delta\",\"signature\":\"sig_abc\"}}\n\nevent: content_block_stop\ndata: {\"type\":\"content_block_stop\",\"index\":0}\n\nevent: content_block_start\ndata: {\"type\":\"content_block_start\",\"index\":1,\"content_block\":{\"type\":\"tool_use\",\"id\":\"tu_1\",\"name\":\"get_weather\",\"input\":{}}}\n\nevent: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":1,\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\"{\\\"city\\\":\\\"Beijing\\\"}\"}}\n\nevent: content_block_stop\ndata: {\"type\":\"content_block_stop\",\"index\":1}\n\nevent: message_delta\ndata: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"tool_use\"}}\n\nevent: message_stop\ndata: {\"type\":\"message_stop\"}\n\n"
  match messages_sse_to_events(sse) {
    Ok(cr) => {
      let events = cr.value()
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
test "messages_sse_to_events - done event" {
  let sse = "event: message_start\ndata: {\"type\":\"message_start\",\"message\":{\"id\":\"m\",\"model\":\"m\"}}\n\nevent: message_stop\ndata: {\"type\":\"message_stop\"}\n\n"
  match messages_sse_to_events(sse) {
    Ok(cr) => {
      let events = cr.value()
      assert_true(events[events.length() - 1] is Done)
    }
    Err(_) => assert_true(false)
  }
}

///|
/// === 6. 流式编码 ===

///|
test "lux_events_to_messages_sse - text sequence" {
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
  match lux_events_to_messages_sse(events) {
    Ok(cr) => {
      let sse = cr.value()
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
test "lux_events_to_messages_sse - tool call with thinking" {
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
  match lux_events_to_messages_sse(events) {
    Ok(cr) => {
      let sse = cr.value()
      assert_true(sse.contains("thinking_delta"))
      assert_true(sse.contains("signature_delta"))
      assert_true(sse.contains("input_json_delta"))
      assert_true(sse.contains("tool_use"))
    }
    Err(_) => assert_true(false)
  }
}

///|
/// === 保真度：媒体编码诊断 ===

///|
test "encode - native media yields Unsupported diagnostic not empty string" {
  let req = @lux.LucentRequest::new(
    "claude",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [
          @lux.LucentContent::native(
            "vendor-x",
            @json.parse("\"raw\"") catch {
              _ => Json::null()
            },
          ),
        ]),
      ),
    ],
    None,
    None,
    @lux.LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
  match lux_request_to_messages(req) {
    Ok(cr) => {
      // 不得输出空字符串 content 块
      assert_true(!cr.value().contains("\"type\":\"text\",\"text\":\"\""))
      // 必须携带诊断
      let mut has_unsupported = false
      for d in cr.diagnostics() {
        if d.status == Unsupported {
          has_unsupported = true
        }
      }
      assert_true(has_unsupported)
    }
    Err(e) => fail("encode failed: \{e}")
  }
}

///|
test "encode - image url maps to anthropic image block" {
  let req = @lux.LucentRequest::new(
    "claude",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [
          @lux.LucentContent::image("image/png", Url("https://x.com/a.png")),
        ]),
      ),
    ],
    None,
    None,
    @lux.LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
  match lux_request_to_messages(req) {
    Ok(cr) => {
      // 图片应映射为 anthropic image block
      assert_true(cr.value().contains("\"type\":\"image\""))
      assert_true(cr.value().contains("https://x.com/a.png"))
    }
    Err(e) => fail("encode failed: \{e}")
  }
}

///|
test "anthropic store unsupported diagnostic" {
  let opts = @lux.LucentOptions::default().with_store(Some(true))
  let req = @lux.LucentRequest::new(
    "claude-4",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [@lux.LucentContent::text("Hi")]),
      ),
    ],
    None,
    None,
    opts,
    None,
    None,
    None,
    None,
  )
  match lux_request_to_messages(req) {
    Ok(cr) => {
      // 必须携带 Unsupported 诊断
      assert_true(cr.diagnostics().length() > 0)
      // 且编码 JSON 不含 "store"
      assert_false(cr.value().contains("\"store\""))
    }
    Err(e) => fail("encode: \{e}")
  }
}

///|
test "anthropic extras round-trip" {
  let opts = @lux.LucentOptions::default().with_extras(
    Some({ "extra_field": Json::string("v1") }),
  )
  let req = @lux.LucentRequest::new(
    "claude-4",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [@lux.LucentContent::text("Hi")]),
      ),
    ],
    None,
    None,
    opts,
    None,
    None,
    None,
    None,
  )
  match lux_request_to_messages(req) {
    Ok(cr) => {
      assert_true(cr.value().contains("\"extra_field\":\"v1\""))
      match messages_to_lux_request(cr.value()) {
        Ok(cr2) =>
          match cr2.value().options.extras {
            Some(m) => assert_true(m.contains("extra_field"))
            None => fail("extras not decoded")
          }
        Err(e) => fail("decode: \{e}")
      }
    }
    Err(e) => fail("encode: \{e}")
  }
}

///|
test "decode - image url block maps to image multimedia" {
  let json = "{\"model\":\"claude\",\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"image\",\"source\":{\"type\":\"url\",\"url\":\"https://x.com/a.png\"}}]}]}"
  match messages_to_lux_request(json) {
    Ok(cr) =>
      match cr.value().conversation[0] {
        Message(m) =>
          match m.content[0] {
            Image(mm) => {
              assert_eq(mm.media_type, "")
              assert_eq(mm.source, Url("https://x.com/a.png"))
            }
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    Err(e) => fail("decode: \{e}")
  }
}

///|
test "decode - image base64 block maps to inline multimedia" {
  let json = "{\"model\":\"claude\",\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"image\",\"source\":{\"type\":\"base64\",\"media_type\":\"image/jpeg\",\"data\":\"abc123\"}}]}]}"
  match messages_to_lux_request(json) {
    Ok(cr) =>
      match cr.value().conversation[0] {
        Message(m) =>
          match m.content[0] {
            Image(mm) => {
              assert_eq(mm.media_type, "image/jpeg")
              assert_eq(mm.source, Inline("abc123"))
            }
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    Err(e) => fail("decode: \{e}")
  }
}

///|
test "encode - file url maps to anthropic document block" {
  let req = @lux.LucentRequest::new(
    "claude",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [
          @lux.LucentContent::file(
            "application/pdf",
            Url("https://x.com/a.pdf"),
          ),
        ]),
      ),
    ],
    None,
    None,
    @lux.LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
  match lux_request_to_messages(req) {
    Ok(cr) => {
      assert_true(cr.value().contains("\"type\":\"document\""))
      assert_true(cr.value().contains("https://x.com/a.pdf"))
    }
    Err(e) => fail("encode: \{e}")
  }
}

///|
test "decode - document block maps to file multimedia" {
  let json = "{\"model\":\"claude\",\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"document\",\"source\":{\"type\":\"url\",\"url\":\"https://x.com/a.pdf\"},\"media_type\":\"application/pdf\"}]}]}"
  match messages_to_lux_request(json) {
    Ok(cr) =>
      match cr.value().conversation[0] {
        Message(m) =>
          match m.content[0] {
            File(mm) => {
              assert_eq(mm.media_type, "application/pdf")
              assert_eq(mm.source, Url("https://x.com/a.pdf"))
            }
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    Err(e) => fail("decode: \{e}")
  }
}
