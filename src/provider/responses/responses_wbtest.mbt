///|
/// OpenAI Responses 适配器白盒测试

///|
/// === 1. 请求解码 ===

///|
test "responses_to_lux_request - simple user message" {
  let json = "{\"model\":\"gpt-5\",\"input\":[{\"type\":\"message\",\"role\":\"user\",\"content\":[{\"type\":\"input_text\",\"text\":\"Hello\"}]}]}"
  match responses_to_lux_request(json) {
    Ok(cr) => {
      let req = cr.value()
      assert_eq(req.model, "gpt-5")
      assert_eq(req.conversation.length(), 1)
      match req.conversation[0] {
        Message(m) => {
          assert_eq(m.role, User)
          match m.content[0] {
            Text(t, _) => assert_eq(t, "Hello")
            _ => assert_true(false)
          }
        }
        _ => assert_true(false)
      }
    }
    Err(e) => fail("unexpected: \{e}")
  }
}

///|
test "responses_to_lux_request - instructions extracted" {
  let json = "{\"model\":\"gpt-5\",\"instructions\":\"Be helpful\",\"input\":[{\"type\":\"message\",\"role\":\"user\",\"content\":[{\"type\":\"input_text\",\"text\":\"hi\"}]}]}"
  match responses_to_lux_request(json) {
    Ok(cr) =>
      match cr.value().instructions {
        Some(instrs) => assert_eq(instrs.length(), 1)
        None => assert_true(false)
      }
    Err(_) => assert_true(false)
  }
}

///|
test "responses_to_lux_request - function_call and function_call_output" {
  let json = "{\"model\":\"gpt-5\",\"input\":[{\"type\":\"function_call\",\"id\":\"fc_1\",\"call_id\":\"call_1\",\"name\":\"search\",\"arguments\":\"{\\\"q\\\":\\\"x\\\"}\"},{\"type\":\"function_call_output\",\"call_id\":\"call_1\",\"output\":\"result\"}]}"
  match responses_to_lux_request(json) {
    Ok(cr) => {
      let req = cr.value()
      assert_eq(req.conversation.length(), 2)
      match req.conversation[0] {
        ToolCall(tu) => {
          assert_eq(tu.id, "fc_1")
          assert_eq(tu.name, "search")
        }
        _ => assert_true(false)
      }
      match req.conversation[1] {
        ToolResult(tr) => assert_eq(tr.tool_use_id, "call_1")
        _ => assert_true(false)
      }
    }
    Err(_) => assert_true(false)
  }
}

///|
test "responses_to_lux_request - reasoning item" {
  let json = "{\"model\":\"gpt-5\",\"input\":[{\"type\":\"reasoning\",\"id\":\"rs_1\",\"summary\":[{\"type\":\"summary_text\",\"text\":\"thinking step\"}],\"signature\":\"sig_1\"}]}"
  match responses_to_lux_request(json) {
    Ok(cr) =>
      match cr.value().conversation[0] {
        Reasoning(th) => assert_eq(th.signature, Some("sig_1"))
        _ => assert_true(false)
      }
    Err(_) => assert_true(false)
  }
}

///|
test "responses_to_lux_request - encrypted_content emits Degraded diagnostic" {
  // include: ["reasoning.encrypted_content"] 的无状态推理延续凭证，
  // lux-ir v1 无载体：不静默丢弃，显式 Degraded（IR 演进项）
  let json = "{\"model\":\"gpt-5\",\"input\":[{\"type\":\"reasoning\",\"id\":\"rs_1\",\"summary\":[],\"encrypted_content\":\"enc-abc\"}]}"
  match responses_to_lux_request(json) {
    Ok(cr) => {
      let ds = cr.diagnostics()
      let mut found = false
      for d in ds {
        if d.field == "input.reasoning.encrypted_content" {
          found = true
        }
      }
      assert_true(found)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "responses_to_lux_request - tool types mapped to kinds" {
  let json = "{\"model\":\"gpt-5\",\"input\":[{\"type\":\"message\",\"role\":\"user\",\"content\":[{\"type\":\"input_text\",\"text\":\"hi\"}]}],\"tools\":[{\"type\":\"function\",\"name\":\"f\",\"description\":\"d\",\"parameters\":{\"type\":\"object\"}},{\"type\":\"web_search\",\"name\":\"ws\"},{\"type\":\"mcp\",\"name\":\"mt\"}]}"
  match responses_to_lux_request(json) {
    Ok(cr) =>
      match cr.value().tools {
        Some(tools) => {
          assert_eq(tools.length(), 3)
          assert_eq(tools[0].kind, Function)
          assert_eq(tools[1].kind, WebSearch)
          assert_eq(tools[2].kind, MCP)
        }
        None => assert_true(false)
      }
    Err(_) => assert_true(false)
  }
}

///|
test "responses_to_lux_request - input items without type field" {
  // 某些客户端（如 OpenCode）省略 type 字段，默认应为 message
  let json = "{\"model\":\"gpt-5\",\"input\":[{\"role\":\"user\",\"content\":[{\"type\":\"input_text\",\"text\":\"Hello\"}]}]}"
  match responses_to_lux_request(json) {
    Ok(cr) => {
      let req = cr.value()
      assert_eq(req.conversation.length(), 1)
      match req.conversation[0] {
        Message(m) => {
          assert_eq(m.role, User)
          match m.content[0] {
            Text(t, _) => assert_eq(t, "Hello")
            _ => assert_true(false)
          }
        }
        _ => assert_true(false)
      }
    }
    Err(e) => fail("unexpected: \{e}")
  }
}

///|
test "responses_to_lux_request - input as string" {
  let json = "{\"model\":\"gpt-5\",\"input\":\"Hello world\"}"
  match responses_to_lux_request(json) {
    Ok(cr) => {
      let req = cr.value()
      assert_eq(req.model, "gpt-5")
      assert_eq(req.conversation.length(), 1)
      match req.conversation[0] {
        Message(m) => {
          assert_eq(m.role, User)
          match m.content[0] {
            Text(t, _) => assert_eq(t, "Hello world")
            _ => assert_true(false)
          }
        }
        _ => assert_true(false)
      }
    }
    Err(e) => fail("unexpected: \{e}")
  }
}

///|
/// === 2. 请求编码 ===

///|
test "lux_request_to_responses - simple user message" {
  let req = @lux.LucentRequest::from_messages(
    "gpt-5",
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
  match lux_request_to_responses(req) {
    Ok(cr) => {
      let s = cr.value()
      assert_true(s.contains("\"model\":\"gpt-5\""))
      assert_true(s.contains("\"input\":"))
      assert_true(s.contains("\"type\":\"message\""))
    }
    Err(_) => assert_true(false)
  }
}

///|
test "lux_request_to_responses - tool kinds encoded" {
  let req = @lux.LucentRequest::from_messages(
    "gpt-5",
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
      @lux.LucentTool::new("ws", None, "{}", None, WebSearch),
      @lux.LucentTool::new("mt", None, "{}", None, MCP),
    ]),
    None,
    @lux.LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
  match lux_request_to_responses(req) {
    Ok(cr) => {
      let s = cr.value()
      assert_true(s.contains("\"type\":\"function\""))
      assert_true(s.contains("\"type\":\"web_search\""))
      assert_true(s.contains("\"type\":\"mcp\""))
      // MCP 的 mcp_server 引用无法从 IR 重建 → 必须携带 Degraded 诊断
      let mut has_degraded = false
      for d in cr.diagnostics() {
        if d.field == "tools.mcp" && d.status == Degraded {
          has_degraded = true
        }
      }
      assert_true(has_degraded)
    }
    Err(_) => assert_true(false)
  }
}

///|
/// === 3. 响应解码 ===

///|
test "responses_to_lux_response - text + usage" {
  let json = "{\"id\":\"resp_1\",\"object\":\"response\",\"status\":\"completed\",\"model\":\"gpt-5\",\"created_at\":1700000000,\"output\":[{\"type\":\"message\",\"id\":\"msg_1\",\"role\":\"assistant\",\"status\":\"completed\",\"content\":[{\"type\":\"output_text\",\"text\":\"Hello!\",\"annotations\":[]}]}],\"usage\":{\"input_tokens\":10,\"output_tokens\":5,\"total_tokens\":15}}"
  match responses_to_lux_response(json) {
    Ok(cr) => {
      let resp = cr.value()
      assert_eq(resp.id, "resp_1")
      assert_eq(resp.model, "gpt-5")
      assert_eq(resp.choices[0].finish_reason, Stop)
      match resp.choices[0].message.content[0] {
        Text(t, _) => assert_eq(t, "Hello!")
        _ => assert_true(false)
      }
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
test "responses_to_lux_response - function_call output" {
  let json = "{\"id\":\"resp_2\",\"model\":\"gpt-5\",\"output\":[{\"type\":\"function_call\",\"id\":\"fc_1\",\"call_id\":\"call_1\",\"name\":\"search\",\"arguments\":\"{}\",\"status\":\"completed\"}],\"usage\":{\"input_tokens\":1,\"output_tokens\":1,\"total_tokens\":2}}"
  match responses_to_lux_response(json) {
    Ok(cr) =>
      match cr.value().choices[0].message.content[0] {
        ToolUse(tu) => assert_eq(tu.name, "search")
        _ => assert_true(false)
      }
    Err(_) => assert_true(false)
  }
}

///|
/// === 4. 响应编码 ===

///|
test "lux_response_to_responses - text response" {
  let msg = @lux.LucentMessage::new(Assistant, [
    @lux.LucentContent::text("Hello"),
  ])
  let choice = @lux.LucentChoice::new(0, msg, Stop, None)
  let resp = @lux.LucentResponse::new(
    "resp_1",
    "gpt-5",
    None,
    [choice],
    Some(@lux.LucentUsage::new(10, 5, 15)),
    None,
  )
  match lux_response_to_responses(resp) {
    Ok(cr) => {
      let s = cr.value()
      assert_true(s.contains("\"id\":\"resp_1\""))
      assert_true(s.contains("\"object\":\"response\""))
      assert_true(s.contains("\"output_tokens\":5"))
    }
    Err(_) => assert_true(false)
  }
}

///|
test "lux_response_to_responses - empty choices error" {
  let resp = @lux.LucentResponse::new("r", "m", None, [], None, None)
  match lux_response_to_responses(resp) {
    Ok(_) => assert_true(false)
    Err(e) => assert_eq(e, "response has no choices")
  }
}

///|
test "lux_events_to_responses_sse - auto-emits output_item.added when ItemStart missing" {
  // 模拟 OpenAI 解码器输出：只有 BlockStart/BlockDelta/BlockEnd，无 ItemStart
  let events : Array[@lux.LucentStreamEvent] = [
    ConversationStart(
      @lux.LucentConversationMeta::new(Some("r_1"), Some("gpt-5"), None),
    ),
    BlockStart(0, Thinking),
    BlockDelta(0, @lux.LucentBlockDelta::thinking_delta("thinking")),
    BlockEnd(0),
    BlockStart(0, Text),
    BlockDelta(0, @lux.LucentBlockDelta::text_delta("Hello")),
    BlockEnd(0),
    Finish(Stop),
    Done,
  ]
  match lux_events_to_responses_sse(events) {
    Ok(cr) => {
      let sse = cr.value()
      // 必须自动补全 response.output_item.added
      assert_true(sse.contains("response.output_item.added"))
      // 必须自动补全 response.content_part.added
      assert_true(sse.contains("response.content_part.added"))
      // 必须包含 thinking 和 text delta（AI SDK 消费 reasoning_summary_text.delta）
      assert_true(sse.contains("response.reasoning_summary_text.delta"))
      assert_true(sse.contains("response.output_text.delta"))
    }
    Err(e) => fail("encode error: \{e}")
  }
}

///|
/// === 5. 流解码 ===

///|
test "responses_sse_to_events - text stream" {
  let sse = "event: response.created\ndata: {\"type\":\"response.created\",\"response\":{\"id\":\"r_1\",\"model\":\"gpt-5\"}}\n\nevent: response.output_item.added\ndata: {\"type\":\"response.output_item.added\",\"output_index\":0,\"item\":{\"type\":\"message\",\"role\":\"assistant\",\"content\":[{\"type\":\"input_text\",\"text\":\"\"}]}}\n\nevent: response.content_part.added\ndata: {\"type\":\"response.content_part.added\",\"output_index\":0,\"content_index\":0,\"part\":{\"type\":\"output_text\",\"text\":\"\"}}\n\nevent: response.output_text.delta\ndata: {\"type\":\"response.output_text.delta\",\"output_index\":0,\"content_index\":0,\"delta\":\"Hello\"}\n\nevent: response.output_text.done\ndata: {\"type\":\"response.output_text.done\",\"output_index\":0,\"content_index\":0}\n\nevent: response.completed\ndata: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\",\"usage\":{\"input_tokens\":1,\"output_tokens\":1,\"total_tokens\":2}}}\n\n"
  match responses_sse_to_events(sse) {
    Ok(cr) => {
      let events = cr.value()
      assert_true(events.length() >= 5)
      match events[0] {
        ConversationStart(_) => ()
        _ => assert_true(false)
      }
    }
    Err(_) => assert_true(false)
  }
}

///|
test "responses_sse_to_events - function_call stream" {
  let sse = "event: response.created\ndata: {\"type\":\"response.created\",\"response\":{\"id\":\"r_2\",\"model\":\"gpt-5\"}}\n\nevent: response.output_item.added\ndata: {\"type\":\"response.output_item.added\",\"output_index\":0,\"item\":{\"type\":\"function_call\",\"id\":\"fc_1\",\"name\":\"search\"}}\n\nevent: response.function_call_arguments.delta\ndata: {\"type\":\"response.function_call_arguments.delta\",\"output_index\":0,\"delta\":\"{\\\"q\\\":\\\"x\\\"}\"}\n\nevent: response.function_call_arguments.done\ndata: {\"type\":\"response.function_call_arguments.done\",\"output_index\":0}\n\nevent: response.completed\ndata: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\"}}\n\n"
  match responses_sse_to_events(sse) {
    Ok(cr) => {
      let events = cr.value()
      assert_true(events.length() >= 3)
      let has_item_start = {
        let mut found = false
        for ev in events {
          match ev {
            ItemStart(_, ToolCall(_)) => found = true
            _ => ()
          }
        }
        found
      }
      assert_true(has_item_start)
    }
    Err(_) => assert_true(false)
  }
}

///|
/// === 6. 流编码 ===

///|
test "lux_events_to_responses_sse - text sequence" {
  let events : Array[@lux.LucentStreamEvent] = [
    ConversationStart(
      @lux.LucentConversationMeta::new(Some("r_1"), Some("gpt-5"), None),
    ),
    ItemStart(
      0,
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(Assistant, [@lux.LucentContent::text("")]),
      ),
    ),
    BlockStart(0, Text),
    BlockDelta(0, @lux.LucentBlockDelta::text_delta("Hello")),
    BlockEnd(0),
    Finish(Stop),
    Done,
  ]
  match lux_events_to_responses_sse(events) {
    Ok(cr) => {
      let sse = cr.value()
      assert_true(sse.contains("event: response.created"))
      assert_true(sse.contains("event: response.output_item.added"))
      assert_true(sse.contains("event: response.content_part.added"))
      assert_true(sse.contains("event: response.output_text.delta"))
      assert_true(sse.contains("event: response.completed"))
    }
    Err(_) => assert_true(false)
  }
}

///|
/// === 保真度：静默分支诊断 ===

///|
test "decode - reasoning config yields Unsupported diagnostic" {
  // 经 IR 构造器编码得到带 reasoning 的 provider JSON，再解码
  let req = @lux.LucentRequest::new(
    "o3",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [@lux.LucentContent::text("Hi")]),
      ),
    ],
    None,
    None,
    @lux.LucentOptions::default(),
    None,
    Some(@lux.LucentReasoningConfig::new(Some(Medium), None)),
    None,
    None,
  )
  match lux_request_to_responses(req) {
    Ok(cr) => {
      let json = cr.value()
      match responses_to_lux_request(json) {
        Ok(cr2) => {
          // reasoning 空实现：必须携带 Unsupported 诊断
          let mut has_unsupported = false
          for d in cr2.diagnostics() {
            if d.status == Unsupported {
              has_unsupported = true
            }
          }
          assert_true(has_unsupported)
        }
        Err(e) => fail("decode failed: \{e}")
      }
    }
    Err(e) => fail("encode failed: \{e}")
  }
}

///|
test "decode - input_image maps to image multimedia (url)" {
  let json = "{\"model\":\"gpt-5\",\"input\":[{\"type\":\"message\",\"role\":\"user\",\"content\":[{\"type\":\"input_image\",\"image_url\":\"https://x.com/a.png\"}]}]}"
  match responses_to_lux_request(json) {
    Ok(cr) => {
      let msg = cr.value().conversation[0]
      match msg {
        Message(m) =>
          match m.content[0] {
            Image(mm) => assert_eq(mm.source, Url("https://x.com/a.png"))
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    }
    Err(_) => assert_true(false)
  }
}

///|
test "decode - input_image data uri maps to inline multimedia" {
  let json = "{\"model\":\"gpt-5\",\"input\":[{\"type\":\"message\",\"role\":\"user\",\"content\":[{\"type\":\"input_image\",\"image_url\":\"data:image/png;base64,iVBORw0KGgo\"}]}]}"
  match responses_to_lux_request(json) {
    Ok(cr) => {
      let msg = cr.value().conversation[0]
      match msg {
        Message(m) =>
          match m.content[0] {
            Image(mm) => {
              assert_eq(mm.media_type, "image/png")
              assert_eq(mm.source, Inline("iVBORw0KGgo"))
            }
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    }
    Err(_) => assert_true(false)
  }
}

///|
test "sse - invalid data yields Invalid diagnostic" {
  let sse = "data: {not-valid-json}\n\n"
  match responses_sse_to_events(sse) {
    Ok(cr) => {
      let mut has_invalid = false
      for d in cr.diagnostics() {
        if d.status == Invalid {
          has_invalid = true
        }
      }
      assert_true(has_invalid)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "responses store/extras round-trip" {
  let opts = @lux.LucentOptions::default()
    .with_store(Some(true))
    .with_extras(Some({ "extra_field": Json::string("v1") }))
  let req = @lux.LucentRequest::new(
    "gpt-4o",
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
  match lux_request_to_responses(req) {
    Ok(cr) => {
      assert_true(cr.value().contains("\"store\":true"))
      assert_true(cr.value().contains("\"extra_field\":\"v1\""))
      match responses_to_lux_request(cr.value()) {
        Ok(cr2) => {
          assert_eq(cr2.value().options.store, Some(true))
          match cr2.value().options.extras {
            Some(m) => assert_true(m.contains("extra_field"))
            None => fail("extras not decoded")
          }
        }
        Err(e) => fail("decode: \{e}")
      }
    }
    Err(e) => fail("encode: \{e}")
  }
}

///|
/// 跨协议链路：vLLM 消息级 reasoning → IR → openai-responses 出站 → reasoning item
test "lux_response_to_responses - message-level reasoning emits reasoning item" {
  let th = @lux.LucentThinking::visible("step by step", None)
  let msg = @lux.LucentMessage::with_reasoning(
    Assistant,
    [@lux.LucentContent::text("answer")],
    Some(th),
  )
  let resp = @lux.LucentResponse::new(
    "resp-1",
    "model",
    None,
    [@lux.LucentChoice::new(0, msg, Stop, None)],
    None,
    None,
  )
  match lux_response_to_responses(resp) {
    Ok(cr) => {
      let s = cr.value()
      // 消息级 reasoning 前置为 reasoning item
      assert_true(s.contains("{\"type\":\"reasoning\",\"id\":\"rs_0\""))
      // 可见文本保留为 message item
      assert_true(s.contains("\"type\":\"message\""))
      assert_true(s.contains("\"text\":\"answer\""))
    }
    Err(_) => assert_true(false)
  }
}

///|
/// 双载体并存：message.reasoning 优先，content Thinking item 跳过 → Degraded
test "lux_response_to_responses - dual carrier yields Degraded" {
  let th = @lux.LucentThinking::visible("msg reasoning", None)
  let msg = @lux.LucentMessage::with_reasoning(
    Assistant,
    [@lux.LucentContent::thinking("block reasoning", None)],
    Some(th),
  )
  let resp = @lux.LucentResponse::new(
    "resp-1",
    "model",
    None,
    [@lux.LucentChoice::new(0, msg, Stop, None)],
    None,
    None,
  )
  match lux_response_to_responses(resp) {
    Ok(cr) => {
      let mut has_dual = false
      for d in cr.diagnostics() {
        if d.field == "reasoning.dual_carrier" && d.status == Degraded {
          has_dual = true
        }
      }
      assert_true(has_dual)
      // message.reasoning 胜出，content Thinking item 被跳过（不重复输出）
      let s = cr.value()
      assert_true(s.contains("\"reasoning\""))
      assert_false(s.contains("block reasoning"))
    }
    Err(_) => assert_true(false)
  }
}

///|
test "encode - image url maps to input_image" {
  let req = @lux.LucentRequest::new(
    "gpt-5",
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
  match lux_request_to_responses(req) {
    Ok(cr) => {
      assert_true(cr.value().contains("\"type\":\"input_image\""))
      assert_true(cr.value().contains("https://x.com/a.png"))
    }
    Err(e) => fail("encode: \{e}")
  }
}

///|
test "encode - image inline maps to data uri input_image" {
  let req = @lux.LucentRequest::new(
    "gpt-5",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [
          @lux.LucentContent::image("image/png", Inline("iVBORw0KGgo")),
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
  match lux_request_to_responses(req) {
    Ok(cr) =>
      assert_true(cr.value().contains("data:image/png;base64,iVBORw0KGgo"))
    Err(e) => fail("encode: \{e}")
  }
}

///|
test "encode - image file_uri yields unsupported diagnostic" {
  let req = @lux.LucentRequest::new(
    "gpt-5",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [
          @lux.LucentContent::image("image/png", FileUri("file:///tmp/a.png")),
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
  match lux_request_to_responses(req) {
    Ok(cr) => {
      let mut has_unsupported = false
      for d in cr.diagnostics() {
        if d.status == Unsupported && d.field == "content.image" {
          has_unsupported = true
        }
      }
      assert_true(has_unsupported)
    }
    Err(e) => fail("encode: \{e}")
  }
}

///|
test "decode - input_file data uri maps to file multimedia" {
  let json = "{\"model\":\"gpt-5\",\"input\":[{\"type\":\"message\",\"role\":\"user\",\"content\":[{\"type\":\"input_file\",\"file_data\":\"data:application/pdf;base64,JVBERi0xLjQ\"}]}]}"
  match responses_to_lux_request(json) {
    Ok(cr) =>
      match cr.value().conversation[0] {
        Message(m) =>
          match m.content[0] {
            File(mm) => {
              assert_eq(mm.media_type, "application/pdf")
              assert_eq(mm.source, Inline("JVBERi0xLjQ"))
            }
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    Err(_) => assert_true(false)
  }
}

///|
test "encode - file inline maps to input_file file_data" {
  let req = @lux.LucentRequest::new(
    "gpt-5",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [
          @lux.LucentContent::file("application/pdf", Inline("JVBERi0xLjQ")),
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
  match lux_request_to_responses(req) {
    Ok(cr) => {
      assert_true(cr.value().contains("\"type\":\"input_file\""))
      assert_true(
        cr.value().contains("data:application/pdf;base64,JVBERi0xLjQ"),
      )
    }
    Err(e) => fail("encode: \{e}")
  }
}

///|
test "responses_sse_to_events - heartbeat merged into JSON payload (\\:)" {
  // 真实场景：SSE data 行内 instructions 字段末尾混入 ": keep-alive."，
  // 被错误合并成 "\: keep-alive."（无效转义），clean_sse_heartbeat 必须剥离
  let sse = "event: response.created\ndata: {\"type\":\"response.created\",\"response\":{\"id\":\"resp_1\",\"created_at\":1787722850,\"instructions\":\"You are opencode.\\n\\nIMPORTANT:\\: keep-alive.\"}}\n\n"
  match responses_sse_to_events(sse) {
    Ok(cr) => {
      let diags = cr.diagnostics()
      assert_eq(diags.length(), 0)
      let events = cr.value()
      assert_true(events.length() >= 1)
      // extra.instructions 不应残留心跳脏文本
      match events[0] {
        ConversationStart(meta) =>
          match meta.extra {
            Some(ex) =>
              match @internal.obj_get(ex, "instructions") {
                Some(String(s)) => assert_true(!s.contains("keep-alive"))
                _ => ()
              }
            None => ()
          }
        _ => ()
      }
    }
    Err(e) => fail("unexpected Err: \{e}")
  }
}

///|
test "responses_sse_to_events - heartbeat line merged as data: : keep-alive row" {
  // 心跳行以 "data: : keep-alive." 形式混入 data 行序列（带句点变体）
  let sse = "event: response.created\ndata: {\"type\":\"response.created\",\"response\":{\"id\":\"resp_1\",\"created_at\":1787722850,\"instructions\":\"You are opencode.\\n\"}}\n\ndata: : keep-alive.\n\ndata: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\"}}\n\n"
  match responses_sse_to_events(sse) {
    Ok(cr) => {
      let diags = cr.diagnostics()
      assert_eq(diags.length(), 0)
      let events = cr.value()
      assert_true(events.length() >= 1)
    }
    Err(e) => fail("unexpected Err: \{e}")
  }
}

///|
/// #10（api-protocol-converter 最小测试矩阵）：解码时 previous_response_id 必须
/// 保留在 extras 中（不再静默丢弃），供 responses → responses 原样透传；
/// 跨端出站（chat/messages）时由目标端编码器拒绝或降级（标准 §3.2）。
test "#10 decode keeps previous_response_id in extras" {
  let json = "{\"model\":\"gpt-5.3\",\"previous_response_id\":\"resp_prev_9\",\"input\":[{\"type\":\"message\",\"role\":\"user\",\"content\":[{\"type\":\"input_text\",\"text\":\"Hi\"}]}]}"
  match responses_to_lux_request(json) {
    Ok(cr) => {
      let req = cr.value()
      let mut found = false
      match req.options.extras {
        Some(m) =>
          match m.get("previous_response_id") {
            Some(String(s)) => found = s == "resp_prev_9"
            _ => ()
          }
        None => ()
      }
      assert_true(found)
    }
    Err(e) => fail("unexpected Err: \{e}")
  }
}

///|
/// #10 responses → responses 往返：extras 中的 previous_response_id 必须原样透传。
test "#10 encode round-trips previous_response_id to responses" {
  let opts = @lux.LucentOptions::default().with_extras(
    Some({ "previous_response_id": Json::string("resp_prev_9") }),
  )
  let req = @lux.LucentRequest::new(
    "gpt-5.3",
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
  match lux_request_to_responses(req) {
    Ok(cr) => {
      assert_true(cr.value().contains("previous_response_id"))
      assert_true(cr.value().contains("resp_prev_9"))
    }
    Err(e) => fail("unexpected Err: \{e}")
  }
}
