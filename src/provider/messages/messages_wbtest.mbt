///|
/// Anthropic Messages 适配器白盒测试

///|
/// 统计子串出现次数（用于「usage 不被重复发射」这类不变量）。
/// 用 split 段数 -1 实现（MoonBit 的 `find` 返回子串而非位置）。
fn count_occurrences(haystack : String, needle : String) -> Int32 {
  haystack.split(needle).to_array().length() - 1
}

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
test "messages_to_lux_request - adaptive thinking maps to enabled not disabled" {
  let json = "{\"model\":\"claude-sonnet-4\",\"max_tokens\":1024,\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"hi\"}]}],\"thinking\":{\"type\":\"adaptive\"},\"output_config\":{\"effort\":\"high\"}}"
  match messages_to_lux_request(json) {
    Ok(cr) =>
      match cr.value().reasoning {
        Some(rc) => {
          // adaptive 语义上是"开"：映射为 enabled，禁止落入 disabled
          assert_eq(rc.enabled, true)
          assert_eq(rc.budget_tokens, None)
          assert_eq(rc.effort, Some(High))
        }
        None => assert_true(false)
      }
    Err(_) => assert_true(false)
  }
}

///|
test "messages_to_lux_request - output_config effort max downgrades to xhigh with diagnostic" {
  let json = "{\"model\":\"claude-sonnet-4\",\"max_tokens\":1024,\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"hi\"}]}],\"thinking\":{\"type\":\"adaptive\"},\"output_config\":{\"effort\":\"max\"}}"
  match messages_to_lux_request(json) {
    Ok(cr) => {
      match cr.value().reasoning {
        Some(rc) => assert_eq(rc.effort, Some(XHigh))
        None => assert_true(false)
      }
      let ds = cr.diagnostics()
      let mut found = false
      for d in ds {
        if d.field == "output_config.effort" {
          found = true
        }
      }
      assert_true(found)
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
test "lux_request_to_messages - effort-based reasoning emits adaptive thinking with output_config" {
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
    Some(@lux.LucentReasoningConfig::new(Some(High), None)),
    None,
    None,
  )
  match lux_request_to_messages(req) {
    Ok(cr) => {
      let s = cr.value()
      // adaptive 形态：thinking.type=adaptive + effort 落 output_config
      assert_true(s.contains("\"thinking\":{\"type\":\"adaptive\"}"))
      assert_true(s.contains("\"output_config\":{\"effort\":\"high\"}"))
    }
    Err(_) => assert_true(false)
  }
}

///|
test "lux_request_to_messages - effort reasoning with structured output merges single output_config" {
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
      Some(JsonSchema("{\"type\":\"object\"}")),
      None,
      None,
    ),
    None,
    Some(@lux.LucentReasoningConfig::new(Some(Medium), None)),
    None,
    None,
  )
  match lux_request_to_messages(req) {
    Ok(cr) => {
      let s = cr.value()
      // effort 与 format 合并为单个 output_config 对象，不产生两个 output_config
      assert_true(
        s.contains(
          "\"output_config\":{\"effort\":\"medium\",\"format\":{\"type\":\"json_schema\"",
        ),
      )
      assert_false(s.contains("\"thinking\":{\"type\":\"enabled\"}"))
    }
    Err(_) => assert_true(false)
  }
}

///|
/// === 3. 响应解码 ===

///|
test "messages_to_lux_response - usage with cache read and creation tokens" {
  let json = "{\"id\":\"msg_1\",\"type\":\"message\",\"role\":\"assistant\",\"model\":\"claude-sonnet-4\",\"content\":[{\"type\":\"text\",\"text\":\"Hello!\"}],\"stop_reason\":\"end_turn\",\"usage\":{\"input_tokens\":100,\"output_tokens\":20,\"cache_creation_input_tokens\":50,\"cache_read_input_tokens\":30}}"
  match messages_to_lux_response(json) {
    Ok(cr) => {
      let u = cr.value().usage.unwrap_or(@lux.LucentUsage::new(0, 0, 0))
      assert_eq(u.prompt_tokens, 100)
      assert_eq(u.completion_tokens, 20)
      assert_eq(u.cache_creation_tokens, Some(50))
      assert_eq(u.cached_tokens, Some(30))
    }
    Err(_) => assert_true(false)
  }
}

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
      // caller 是官方 ToolUseBlock required（模型直接发起 → "direct"）。
      // 2026-10-24 [5] 组首次纳入工具调用样本时实测发现缺失会被官方 schema 拒绝。
      assert_true(s.contains("\"caller\":{\"type\":\"direct\"}"))
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
            Finish(ToolCalls, None) => found = true
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
    Finish(Stop, None),
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
    Finish(ToolCalls, None),
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
            @internal.parse_json_opt("\"raw\"").unwrap_or(Json::null()),
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
test "encode - image url maps to messages image block" {
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
      // 图片应映射为 messages image block
      assert_true(cr.value().contains("\"type\":\"image\""))
      assert_true(cr.value().contains("https://x.com/a.png"))
    }
    Err(e) => fail("encode failed: \{e}")
  }
}

///|
test "messages store unsupported diagnostic" {
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
test "messages extras round-trip" {
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

///|
/// #11（api-protocol-converter 最小测试矩阵）：非法 JSON arguments 不能发给 Claude，
/// 编码端必须产生 Invalid 诊断且不输出非法 input 请求体（标准 §11.2）。
test "#11 invalid JSON tool arguments produce Invalid diagnostic and no broken input" {
  let req = @lux.LucentRequest::new(
    "claude-sonnet-4",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(Assistant, [
          @lux.LucentContent::tool_use(
            "tu_bad",
            "get_weather",
            "not-valid-json{",
            None,
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
      // 非法 tool_use 块被跳过，不落入输出 JSON
      assert_false(cr.value().contains("not-valid-json{"))
      // 必须携带 Invalid 诊断（field = content.tool_use.input）
      let mut has_invalid = false
      for d in cr.diagnostics() {
        if d.field == "content.tool_use.input" && d.status == Invalid {
          has_invalid = true
        }
      }
      assert_true(has_invalid)
    }
    Err(e) => fail("encode: \{e}")
  }
}

///|
/// #11 独立 ToolCall conversation item 同样受 arguments JSON 校验约束。
test "#11 standalone invalid tool call item is not emitted" {
  let req = @lux.LucentRequest::new(
    "claude-sonnet-4",
    None,
    [
      @lux.LucentConversationItem::tool_call(
        @lux.LucentToolUse::new("tu_bad", "get_weather", "{oops", None),
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
      assert_false(cr.value().contains("get_weather"))
      let mut has_invalid = false
      for d in cr.diagnostics() {
        if d.field == "content.tool_use.input" && d.status == Invalid {
          has_invalid = true
        }
      }
      assert_true(has_invalid)
    }
    Err(e) => fail("encode: \{e}")
  }
}

///|
/// #9（最小测试矩阵）：Claude 无 tool 角色，Tool 角色消息必须包装为
/// role:"user" + tool_result block，禁止输出 "role":"tool"（标准 §3.3-D/§11.3）。
test "#9 tool-role message is wrapped as user with tool_result block" {
  let req = @lux.LucentRequest::new(
    "claude-sonnet-4",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(Tool, [
          @lux.LucentContent::tool_result("tu_1", [
            @lux.LucentContent::text("{\"temp\":25}"),
          ]),
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
      let s = cr.value()
      assert_true(s.contains("\"role\":\"user\""))
      assert_true(s.contains("\"type\":\"tool_result\""))
      assert_true(s.contains("\"tool_use_id\":\"tu_1\""))
      // Claude 协议没有 tool 角色，绝不能输出 role:"tool"
      assert_false(s.contains("\"role\":\"tool\""))
    }
    Err(e) => fail("encode: \{e}")
  }
}

///|
/// #9：同一 user 消息内 tool_result 必须排在文本前面（Claude 顺序硬规则，标准 §11.4）。
/// 入站混合内容被保留为 Message item（#3 修复），出站时工具结果前置。
test "#9 tool_result block is emitted before text in the same user message" {
  let req = @lux.LucentRequest::new(
    "claude-sonnet-4",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [
          @lux.LucentContent::tool_result("tu_1", [
            @lux.LucentContent::text("sunny"),
          ]),
          @lux.LucentContent::text("please use the tool result"),
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
      let s = cr.value()
      // 文本块位于 tool_result 块之前时会违反 Claude 顺序要求；
      // 编码端必须把 tool_result 前置（用 split 求相对位置，避免依赖 index_of API）。
      let before_tool = s.split("\"type\":\"tool_result\"").to_array()[0].length()
      let before_text = s.split("\"please use the tool result\"").to_array()[0].length()
      assert_true(s.contains("\"type\":\"tool_result\""))
      assert_true(s.contains("\"please use the tool result\""))
      assert_true(before_tool < before_text)
    }
    Err(e) => fail("encode: \{e}")
  }
}

///|
/// #9 入站：user 消息中 tool_result 与文本混合时不得静默丢弃文本（#3 修复），
/// 且应产生 Degraded 诊断；往返编码后文本与 tool_result 均保留。
test "#9 decode preserves mixed text + tool_result user message" {
  let json = "{\"model\":\"claude-sonnet-4\",\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"tool_result\",\"tool_use_id\":\"tu_1\",\"content\":[{\"type\":\"text\",\"text\":\"sunny\"}]},{\"type\":\"text\",\"text\":\"context note\"}]}]}"
  match messages_to_lux_request(json) {
    Ok(cr) => {
      let req = cr.value()
      assert_eq(req.conversation.length(), 1)
      match req.conversation[0] {
        Message(m) => {
          // 混合内容被保留为 Message item，文本与 tool_result 都在
          assert_true(m.content.length() >= 2)
          let mut has_tool = false
          let mut has_text = false
          for c in m.content {
            match c {
              ToolResult(_) => has_tool = true
              Text(t, _) => if t.contains("context note") { has_text = true }
              _ => ()
            }
          }
          assert_true(has_tool)
          assert_true(has_text)
        }
        _ => assert_true(false)
      }
      // 应产生 Degraded 诊断（tool_result 与其他内容混合）
      let mut has_degraded = false
      for d in cr.diagnostics() {
        if d.status == Degraded && d.field == "message.tool_result" {
          has_degraded = true
        }
      }
      assert_true(has_degraded)
    }
    Err(e) => fail("decode: \{e}")
  }
}

///|

///|
/// #10（api-protocol-converter 最小测试矩阵）：Responses 只有 previous_response_id
/// 且无会话历史时，跨端出站（messages）必须拒绝转换（标准 §3.2）。
test "#10 previous_response_id standard field without history rejected" {
  let opts = @lux.LucentOptions::default().with_previous_response_id(
    Some("resp_123"),
  )
  let req = @lux.LucentRequest::new(
    "claude-sonnet-4",
    None,
    [],
    None,
    None,
    opts,
    None,
    None,
    None,
    None,
  )
  match lux_request_to_messages(req) {
    Ok(_) => fail("expected rejection for previous_response_id without history")
    Err(e) => assert_true(e.contains("previous_response_id"))
  }
}

///|
/// T8：标准字段路径——有历史时剔除并打 Unsupported 诊断。
test "#10 previous_response_id standard field with history degrades" {
  let opts = @lux.LucentOptions::default().with_previous_response_id(
    Some("resp_123"),
  )
  let req = @lux.LucentRequest::new(
    "claude-sonnet-4",
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
      assert_false(cr.value().contains("previous_response_id"))
      let mut has_unsupported = false
      for d in cr.diagnostics() {
        if d.field == "options.previous_response_id" && d.status == Unsupported {
          has_unsupported = true
        }
      }
      assert_true(has_unsupported)
    }
    Err(e) => fail("encode: \{e}")
  }
}

///|
/// thinking_to_block 的 th.redacted == true 分支（request_encode.mbt 此前整段未覆盖）：
/// signature 有值 / 无值两种子情况都要命中。
test "encode - redacted_thinking with and without signature" {
  let with_sig = thinking_to_block(
    @lux.LucentThinking::redacted(Some("sig-redacted")),
  )
  assert_eq(
    with_sig, "{\"type\":\"redacted_thinking\",\"signature\":\"sig-redacted\"}",
  )
  let without_sig = thinking_to_block(@lux.LucentThinking::redacted(None))
  assert_eq(without_sig, "{\"type\":\"redacted_thinking\",\"signature\":null}")
}

///|
/// stream_encode：双 Finish 的 usage 配对 —— 第二个 Finish 的窗口下界必须
/// 由「上一个 Finish」确定（messages_pair_usages 的回扫分支）。
///
/// 事件序 [Usage1, Finish1, Usage2, Finish2] 的配对语义：Usage2 落在
/// Finish1 的窗口内（上界是下一个 Finish），故归 Finish1；Finish2 窗口内
/// 无 Usage → output_tokens:0。Usage1 未被任何 Finish 消费 → 独立发一帧。
/// 关键不变量：**同一个 Usage 不得被两个 Finish 重复发射**（此前 consumed[]
/// 不防重配对，Usage2 会跟着两个 Finish 各发一遍）。
test "encode - stream double finish pairs usages with lower bound" {
  let events : Array[@lux.LucentStreamEvent] = [
    ConversationStart(
      @lux.LucentConversationMeta::new(Some("msg_df"), Some("claude"), None),
    ),
    Usage(@lux.LucentUsage::new(11, 22, 33)),
    Finish(Stop, None),
    Usage(@lux.LucentUsage::new(44, 55, 99)),
    Finish(Stop, None),
    Done,
  ]
  match lux_events_to_messages_sse(events) {
    Ok(cr) => {
      let sse = cr.value()
      // Usage1 独立发射（未被 Finish 配对）
      assert_true(sse.contains("\"input_tokens\":11,\"output_tokens\":22"))
      // Usage2 归 Finish1，且只出现一次
      assert_true(sse.contains("\"input_tokens\":44,\"output_tokens\":55"))
      assert_eq(count_occurrences(sse, "\"input_tokens\":44"), 1)
      // 三帧 message_delta：Usage1 独立 + Finish1 + Finish2
      let mut delta_count = 0
      for line in sse.split("\n") {
        if line.has_prefix("data: {\"type\":\"message_delta\"") {
          delta_count = delta_count + 1
        }
      }
      assert_eq(delta_count, 3)
    }
    Err(e) => fail("encode error: \{e}")
  }
}

///|
/// stream_encode：Finish 在 Usage **之前** 的配对（IR 事件序 [Finish, Usage]）
/// —— 回退分支「Finish 之前窗口内最后一个 Usage」。此时 Finish 自身窗口内
/// （下一个 Finish 之前）的 Usage 应归它。
test "encode - stream finish before usage pairs forward" {
  let events : Array[@lux.LucentStreamEvent] = [
    ConversationStart(
      @lux.LucentConversationMeta::new(Some("msg_fb"), Some("claude"), None),
    ),
    Finish(Stop, None),
    Usage(@lux.LucentUsage::new(7, 8, 15)),
    Done,
  ]
  match lux_events_to_messages_sse(events) {
    Ok(cr) => {
      let sse = cr.value()
      // Usage 归 Finish 合并发射（不重复独立发）
      assert_true(sse.contains("\"input_tokens\":7,\"output_tokens\":8"))
      assert_eq(count_occurrences(sse, "\"input_tokens\":7"), 1)
      let mut delta_count = 0
      for line in sse.split("\n") {
        if line.has_prefix("data: {\"type\":\"message_delta\"") {
          delta_count = delta_count + 1
        }
      }
      assert_eq(delta_count, 1)
    }
    Err(e) => fail("encode error: \{e}")
  }
}

///|
/// stream_encode：ConversationStart 的 meta.usage_input = Some(n) → message_start 帧
/// 携带 "usage":{"input_tokens":n}（None => 0 分支已由既有用例覆盖）。
test "encode - stream conversation start emits input usage" {
  let events : Array[@lux.LucentStreamEvent] = [
    ConversationStart(
      @lux.LucentConversationMeta::new(
        Some("msg_usage"),
        Some("claude-sonnet-4"),
        Some(1234),
      ),
    ),
    Done,
  ]
  match lux_events_to_messages_sse(events) {
    Ok(cr) =>
      // CR-003 R1：message_start.usage 现在同时给出 output_tokens（首帧语义为 1）
      assert_true(
        cr
        .value()
        .contains("\"usage\":{\"input_tokens\":1234,\"output_tokens\":1}"),
      )
    Err(e) => fail("encode error: \{e}")
  }
}

///|
/// stream_encode：BlockStart 的 Refusal 分支、BlockDelta 的 RefusalDelta 与 NativeDelta
/// 分支（此前均未覆盖）。Native 块类型 + NativeDelta 一并纳入。
test "encode - stream refusal and native block waves" {
  let events : Array[@lux.LucentStreamEvent] = [
    ConversationStart(
      @lux.LucentConversationMeta::new(
        Some("msg_r"),
        Some("claude-sonnet-4"),
        None,
      ),
    ),
    BlockStart(0, Refusal),
    BlockDelta(0, @lux.LucentBlockDelta::refusal_delta("I cannot help")),
    BlockEnd(0),
    BlockStart(1, @lux.LucentBlockType::native("my_native_block")),
    BlockDelta(
      1,
      @lux.LucentBlockDelta::native_delta("my_native_delta", Json::null()),
    ),
    BlockEnd(1),
    // BlockStart Image → 命中 Image | Audio | Video 合并分支（空 text 块）
    BlockStart(2, Image),
    BlockEnd(2),
    Done,
  ]
  match lux_events_to_messages_sse(events) {
    Ok(cr) => {
      let sse = cr.value()
      // BlockStart Refusal → content_block_start 携带空 text 块
      assert_true(
        sse.contains("\"content_block\":{\"type\":\"text\",\"text\":\"\"}"),
      )
      // BlockDelta RefusalDelta → text_delta
      assert_true(
        sse.contains("\"type\":\"text_delta\",\"text\":\"I cannot help\""),
      )
      // BlockStart Native → content_block_start 携带原生类型
      assert_true(
        sse.contains("\"content_block\":{\"type\":\"my_native_block\"}"),
      )
      // BlockDelta NativeDelta → delta 仅保留 type 标签
      assert_true(sse.contains("\"delta\":{\"type\":\"my_native_delta\"}"))
    }
    Err(e) => fail("encode error: \{e}")
  }
}

///|
/// stream_encode：整个 Error(e) 分支 —— error.type 由 e.kind 派生，六种 kind 全覆盖：
/// RateLimit→rate_limit_error、InvalidRequest→invalid_request_error、
/// Authentication→authentication_error、ServerError→api_error、
/// ContentFilter→invalid_request_error、Native(tag)→tag。
test "encode - stream error event maps kind to anthropic error type" {
  let cases : Array[(@lux.LucentErrorKind, String)] = [
    (RateLimit, "rate_limit_error"),
    (InvalidRequest, "invalid_request_error"),
    (Authentication, "authentication_error"),
    (ServerError, "api_error"),
    (ContentFilter, "invalid_request_error"),
    (Native("vendor_error"), "vendor_error"),
  ]
  for kv in cases {
    let (kind, expected) = kv
    let events : Array[@lux.LucentStreamEvent] = [
      Error(@lux.LucentError::new(kind, "boom", None)),
      Done,
    ]
    match lux_events_to_messages_sse(events) {
      Ok(cr) =>
        assert_true(
          cr.value().contains("\"error\":{\"type\":\"" + expected + "\""),
        )
      Err(e) => fail("encode error: \{e}")
    }
  }
}

///|
/// request_encode：content_to_block 的多内容类型分支 —— Refusal、媒体 base64（image/file
/// Inline）、Video/FileUri Unsupported。合并覆盖以压降 request_encode.mbt 未覆盖行。
test "encode - content block variety covers refusal media and unsupported kinds" {
  let req = @lux.LucentRequest::from_messages(
    "claude-sonnet-4",
    None,
    [
      @lux.LucentMessage::new(Assistant, [
        @lux.LucentContent::refusal("I cannot assist"),
        @lux.LucentContent::video("video/mp4", Url("https://x.com/v.mp4")),
        @lux.LucentContent::image("image/png", Inline("YmFzZTY0ZGF0YQ==")),
        @lux.LucentContent::file("application/pdf", Inline("cGRmZGF0YQ==")),
        @lux.LucentContent::file(
          "application/pdf",
          FileUri("file:///tmp/a.pdf"),
        ),
      ]),
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
      let s = cr.value()
      // Refusal → text 块（保留文本）
      assert_true(s.contains("\"type\":\"text\",\"text\":\"I cannot assist\""))
      // image Inline(base64) → base64 image block
      assert_true(
        s.contains("\"type\":\"image\",\"source\":{\"type\":\"base64\""),
      )
      // file Inline(base64) → base64 document block
      assert_true(
        s.contains("\"type\":\"document\",\"source\":{\"type\":\"base64\""),
      )
      // Video / FileUri → Unsupported 诊断（不得产出空/泄漏块）
      assert_false(s.contains("\"text\":\"video/mp4\""))
      let mut unsupported_count = 0
      for d in cr.diagnostics() {
        if d.status == Unsupported {
          unsupported_count = unsupported_count + 1
        }
      }
      assert_true(unsupported_count >= 2)
    }
    Err(e) => fail("encode error: \{e}")
  }
}

///|
/// request_encode：options 的 top_p / top_k / stop_sequences / stream=true 分支
/// （四处此前未覆盖）。单个请求同时携带四个字段。
test "encode - options map top_p top_k stop sequences and stream" {
  let opts = @lux.LucentOptions::new(
    None,
    Some(0.9),
    Some(40),
    Some(1024),
    Some(["STOP", "HALT"]),
    true,
    None,
    None,
    None,
    None,
  )
  let req = @lux.LucentRequest::from_messages(
    "claude-sonnet-4",
    None,
    [@lux.LucentMessage::new(User, [@lux.LucentContent::text("hi")])],
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
      let s = cr.value()
      assert_true(s.contains("\"top_p\":"))
      assert_true(s.contains("\"top_k\":40"))
      assert_true(s.contains("\"stop_sequences\":[\"STOP\",\"HALT\"]"))
      assert_true(s.contains("\"stream\":true"))
    }
    Err(e) => fail("encode error: \{e}")
  }
}

///|
/// request_encode：structured_output 的 JsonObject 与 Text 两分支（并入单个 output_config）。
/// 断言形状相同，用 Array 循环展开为两个用例。
///
/// JsonObject：Anthropic json_schema 必须携带具体 schema，此前伪造的空
/// `"schema":{}` 不是合法 JSON Schema，已改为最宽合法形式
/// `"schema":{"type":"object"}` 并打 Degraded 诊断。
test "encode - structured output emits output_config format" {
  let cases : Array[(@lux.LucentStructuredOutput, String)] = [
    (JsonObject, "\"schema\":{\"type\":\"object\"}"),
    (Text, "\"format\":{\"type\":\"text\"}"),
  ]
  for kv in cases {
    let (variant, expected) = kv
    let opts = @lux.LucentOptions::new(
      None,
      None,
      None,
      Some(1024),
      None,
      false,
      None,
      Some(variant),
      None,
      None,
    )
    let req = @lux.LucentRequest::from_messages(
      "claude-sonnet-4",
      None,
      [@lux.LucentMessage::new(User, [@lux.LucentContent::text("hi")])],
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
        let s = cr.value()
        assert_true(s.contains("\"output_config\":{"))
        assert_true(s.contains(expected))
      }
      Err(e) => fail("encode error: \{e}")
    }
  }
}

///|
/// request_encode：tools 的 Native kind 分支 → {"type":"<tag>","name":...}。
test "encode - native tool kind emits vendor type tag" {
  let req = @lux.LucentRequest::from_messages(
    "claude-sonnet-4",
    None,
    [@lux.LucentMessage::new(User, [@lux.LucentContent::text("hi")])],
    Some([
      @lux.LucentTool::new(
        "vendor_tool",
        Some("a vendor tool"),
        "{\"type\":\"object\"}",
        None,
        Native("vendor_kind"),
      ),
    ]),
    None,
    @lux.LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
  match lux_request_to_messages(req) {
    Ok(cr) =>
      assert_true(
        cr.value().contains("\"type\":\"vendor_kind\",\"name\":\"vendor_tool\""),
      )
    Err(e) => fail("encode error: \{e}")
  }
}

///|
/// request_encode：reasoning.enabled 但 budget_tokens=None 且 effort=None →
/// adaptive thinking 分支内的 effort None 子分支。
test "encode - adaptive reasoning without effort still emits adaptive thinking" {
  let req = @lux.LucentRequest::from_messages(
    "claude-sonnet-4",
    None,
    [@lux.LucentMessage::new(User, [@lux.LucentContent::text("hi")])],
    None,
    None,
    @lux.LucentOptions::default(),
    None,
    Some(@lux.LucentReasoningConfig::enabled(None)),
    None,
    None,
  )
  match lux_request_to_messages(req) {
    Ok(cr) =>
      assert_true(cr.value().contains("\"thinking\":{\"type\":\"adaptive\"}"))
    Err(e) => fail("encode error: \{e}")
  }
}

///|
/// request_encode：instructions 含非 Text 内容（image）→ 系统抽取循环的 _ 分支
/// （不产 system 字段，也不报错）。
test "encode - instructions with non-text block is skipped for system" {
  let req = @lux.LucentRequest::from_messages(
    "claude-sonnet-4",
    Some([@lux.LucentContent::image("image/png", Url("https://x.com/i.png"))]),
    [@lux.LucentMessage::new(User, [@lux.LucentContent::text("hi")])],
    None,
    None,
    @lux.LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
  match lux_request_to_messages(req) {
    Ok(cr) => assert_false(cr.value().contains("\"system\":"))
    Err(e) => fail("encode error: \{e}")
  }
}

///|
/// request_encode：legacy 路径 —— extras 中的 previous_response_id（String）在有历史时
/// 命中 prev_id_extras 的 Some(String(id)) 分支，随后剔除并打 Unsupported 诊断。
test "encode - previous_response_id in extras with history degrades and strips" {
  let opts = @lux.LucentOptions::default().with_extras(
    Some({ "previous_response_id": Json::string("resp_legacy") }),
  )
  let req = @lux.LucentRequest::from_messages(
    "claude-sonnet-4",
    None,
    [@lux.LucentMessage::new(User, [@lux.LucentContent::text("Hi")])],
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
      assert_false(cr.value().contains("resp_legacy"))
      let mut has_unsupported = false
      for d in cr.diagnostics() {
        if d.field == "options.previous_response_id" && d.status == Unsupported {
          has_unsupported = true
        }
      }
      assert_true(has_unsupported)
    }
    Err(e) => fail("encode error: \{e}")
  }
}

///|
/// tool_result 的 content 官方允许**字符串**简写或 block 数组。
/// 字符串形态此前被 field_arr 判为 None → 内容整体丢失且无诊断（契约 §3）。
test "decode - tool_result with string content is preserved" {
  let json = "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"tool_result\",\"tool_use_id\":\"t1\",\"content\":\"plain result text\"}]}]}"
  match messages_to_lux_request(json) {
    Ok(cr) => {
      match cr.value().conversation[0] {
        ToolResult(tr) => {
          assert_eq(tr.tool_use_id, "t1")
          assert_eq(tr.content.length(), 1)
          match tr.content[0] {
            Text(t, _) => assert_eq(t, "plain result text")
            _ => fail("expected text block from string content")
          }
        }
        _ => fail("expected ToolResult item")
      }
      // 字符串形态是合法的，不应产生诊断
      assert_eq(cr.diagnostics().length(), 0)
    }
    Err(e) => fail("decode failed: \{e}")
  }
}

///|
/// tool_result 的 content 既非字符串也非数组（如数字）→ 显式 Invalid 诊断，
/// 不静默丢弃。
test "decode - tool_result with non-string non-array content reports Invalid" {
  let json = "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"tool_result\",\"tool_use_id\":\"t1\",\"content\":42}]}]}"
  match messages_to_lux_request(json) {
    Ok(cr) => {
      let mut has_invalid = false
      for d in cr.diagnostics() {
        if d.status == Invalid && d.field == "content.tool_result.content" {
          has_invalid = true
        }
      }
      assert_true(has_invalid)
    }
    Err(e) => fail("decode failed: \{e}")
  }
}
