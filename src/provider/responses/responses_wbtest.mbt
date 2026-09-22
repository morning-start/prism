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
/// 保留（T8 起为 IR 标准可选字段，不再落 extras——消除双载体），供
/// responses → responses 原样透传；跨端出站（chat/messages）时由目标端
/// 编码器拒绝或降级（标准 §3.2）。
test "#10 decode keeps previous_response_id as standard field" {
  let json = "{\"model\":\"gpt-5.3\",\"previous_response_id\":\"resp_prev_9\",\"input\":[{\"type\":\"message\",\"role\":\"user\",\"content\":[{\"type\":\"input_text\",\"text\":\"Hi\"}]}]}"
  match responses_to_lux_request(json) {
    Ok(cr) => {
      let req = cr.value()
      // T8：标准可选字段承载
      assert_eq(req.options.previous_response_id, Some("resp_prev_9"))
      // 不再双载体：extras 中不应出现
      match req.options.extras {
        Some(m) => assert_true(m.get("previous_response_id") is None)
        None => ()
      }
    }
    Err(e) => fail("unexpected Err: \{e}")
  }
}

///|
/// #10 兼容门禁：旧 extras 载荷（T8 前的持久化数据）仍被编码识别。
test "#10 encode round-trips previous_response_id from extras (legacy)" {
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

///|
/// #10 responses → responses 往返：标准字段 previous_response_id 原样透传。
test "#10 encode round-trips previous_response_id standard field" {
  let opts = @lux.LucentOptions::default().with_previous_response_id(
    Some("resp_prev_9"),
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

///|
/// 流编码：tool 块自动补 output_item.added（function_call item），
/// arguments 增量与 done 事件按块类型发出（标准 §10.2）。
test "lux_events_to_responses_sse - tool call block" {
  let events : Array[@lux.LucentStreamEvent] = [
    ConversationStart(
      @lux.LucentConversationMeta::new(Some("r_1"), Some("gpt-5"), None),
    ),
    BlockStart(0, @lux.LucentBlockType::tool_call("fc_1", "search")),
    BlockDelta(0, @lux.LucentBlockDelta::tool_arguments_delta("{\"q\":\"x\"}")),
    BlockEnd(0),
    Finish(ToolCalls),
    Done,
  ]
  match lux_events_to_responses_sse(events) {
    Ok(cr) => {
      let sse = cr.value()
      // tool 块必须自动补 output_item.added（function_call）
      assert_true(sse.contains("response.output_item.added"))
      assert_true(sse.contains("\"type\":\"function_call\""))
      assert_true(sse.contains("\"name\":\"search\""))
      // arguments 增量 + done
      assert_true(sse.contains("response.function_call_arguments.delta"))
      assert_true(sse.contains("response.function_call_arguments.done"))
      // 结束状态：tool_calls → completed
      assert_true(sse.contains("\"status\":\"completed\""))
    }
    Err(e) => fail("encode error: \{e}")
  }
}

///|
/// 流编码：thinking 块的结束序列（reasoning_summary_part.done + output_item.done）
/// 与 signature 延续凭证（不丢弃，标准 §10.2 reasoning signature）。
test "lux_events_to_responses_sse - thinking block end and signature" {
  let events : Array[@lux.LucentStreamEvent] = [
    ConversationStart(
      @lux.LucentConversationMeta::new(Some("r_1"), Some("gpt-5"), None),
    ),
    BlockStart(0, Thinking),
    BlockDelta(0, @lux.LucentBlockDelta::thinking_delta("thinking")),
    BlockDelta(0, @lux.LucentBlockDelta::signature_delta("sig_abc")),
    BlockEnd(0),
    Finish(Stop),
    Done,
  ]
  match lux_events_to_responses_sse(events) {
    Ok(cr) => {
      let sse = cr.value()
      // reasoning item 自动补全（BlockStart Thinking 无 ItemStart 时）
      assert_true(sse.contains("\"type\":\"reasoning\""))
      // 摘要 delta（AI SDK 消费 reasoning_summary_text.delta）
      assert_true(sse.contains("response.reasoning_summary_text.delta"))
      // signature 保留在 reasoning_summary_part.done 中
      assert_true(sse.contains("response.reasoning_summary_part.done"))
      assert_true(sse.contains("sig_abc"))
      // 结束序列：output_item.done
      assert_true(sse.contains("response.output_item.done"))
    }
    Err(e) => fail("encode error: \{e}")
  }
}

///|
/// 流编码：Usage 事件合并到 response.completed（含 reasoning/cached 明细）。
test "lux_events_to_responses_sse - usage merged into completed" {
  let events : Array[@lux.LucentStreamEvent] = [
    ConversationStart(
      @lux.LucentConversationMeta::new(Some("r_1"), Some("gpt-5"), None),
    ),
    Finish(Stop),
    Usage(@lux.LucentUsage::full(10, 3, 13, Some(2), Some(4), None)),
    Done,
  ]
  match lux_events_to_responses_sse(events) {
    Ok(cr) => {
      let sse = cr.value()
      assert_true(sse.contains("response.completed"))
      assert_true(sse.contains("\"usage\""))
      assert_true(sse.contains("\"input_tokens\":10"))
      assert_true(sse.contains("\"output_tokens\":3"))
      assert_true(sse.contains("\"total_tokens\":13"))
      // reasoning/cached 明细
      assert_true(sse.contains("\"reasoning_tokens\":2"))
      assert_true(sse.contains("\"cached_tokens\":4"))
    }
    Err(e) => fail("encode error: \{e}")
  }
}

///|
/// 流编码：Error 事件 → 官方错误帧（error 为平铺字段，含 code/message）。
test "lux_events_to_responses_sse - error frame" {
  let events : Array[@lux.LucentStreamEvent] = [
    ConversationStart(
      @lux.LucentConversationMeta::new(Some("r_1"), Some("gpt-5"), None),
    ),
    Error(
      @lux.LucentError::new(
        RateLimit,
        "rate limit hit",
        Some("rate_limit_exceeded"),
      ),
    ),
    Done,
  ]
  match lux_events_to_responses_sse(events) {
    Ok(cr) => {
      let sse = cr.value()
      assert_true(sse.contains("event: error"))
      assert_true(sse.contains("\"code\":\"rate_limit_exceeded\""))
      assert_true(sse.contains("\"message\":\"rate limit hit\""))
    }
    Err(e) => fail("encode error: \{e}")
  }
}

///|
/// request_encode 的私有 helper reasoning_item_json：summary 数组中 Text 片段
/// 的逐个序列化（非 Text 片段跳过）、signature 的追加，以及两者均缺省时
/// None 分支不产出字段；同时覆盖经 Reasoning 会话项的调用点。
test "encode - reasoning item summary and signature" {
  // summary + signature 齐全（中间夹一个非 Text 片段 → 被跳过）
  let full = @lux.LucentThinking::new(
    "hidden",
    Some("sig_full"),
    false,
    Some([
      @lux.LucentContent::text("step one"),
      @lux.LucentContent::thinking("skipped", None),
      @lux.LucentContent::text("step two"),
    ]),
  )
  let s_full = reasoning_item_json(full)
  assert_true(s_full.contains("\"type\":\"reasoning\""))
  assert_true(
    s_full.contains(
      "\"summary\":[{\"type\":\"summary_text\",\"text\":\"step one\"}," +
      "{\"type\":\"summary_text\",\"text\":\"step two\"}]",
    ),
  )
  assert_true(s_full.contains("\"signature\":\"sig_full\""))

  // summary = None 且 signature = None：两个 None 分支
  let bare = @lux.LucentThinking::new("t", None, false, None)
  assert_eq(reasoning_item_json(bare), "{\"type\":\"reasoning\"}")

  // summary 为空数组：summary_parts.length() > 0 不成立 → 无 summary 字段
  let empty_summary = @lux.LucentThinking::new(
    "t",
    Some("sig_only"),
    false,
    Some([]),
  )
  let s_empty = reasoning_item_json(empty_summary)
  assert_false(s_empty.contains("\"summary\""))
  assert_true(s_empty.contains("\"signature\":\"sig_only\""))

  // summary 仅有非 Text 片段：循环体执行但 parts 为空 → 同样无 summary 字段
  let only_non_text = @lux.LucentThinking::new(
    "t",
    None,
    false,
    Some([@lux.LucentContent::thinking("inner", None)]),
  )
  assert_false(reasoning_item_json(only_non_text).contains("\"summary\""))

  // 经 lux_request_to_responses 的 Reasoning 会话项复用同一 helper
  let req = @lux.LucentRequest::new(
    "gpt-5",
    None,
    [@lux.LucentConversationItem::reasoning(full)],
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
      assert_true(s.contains("\"type\":\"reasoning\""))
      assert_true(
        s.contains("{\"type\":\"summary_text\",\"text\":\"step one\"}"),
      )
      assert_true(s.contains("\"signature\":\"sig_full\""))
    }
    Err(e) => fail("encode failed: \{e}")
  }
}

///|
/// request_encode 消息内容分支：Refusal / Video 无 Responses 消息块载体 →
/// 静默跳过；File(Url) / File(FileUri) 无对应载体 → 显式 Unsupported 诊断
/// （不伪装 Exact）。
test "encode - request content kinds refusal video and file url" {
  let req = @lux.LucentRequest::new(
    "gpt-5",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [
          @lux.LucentContent::refusal("no"),
          @lux.LucentContent::video("video/mp4", Url("https://x/v.mp4")),
          @lux.LucentContent::file("application/pdf", Url("https://x/a.pdf")),
          @lux.LucentContent::file(
            "application/pdf",
            FileUri("file:///tmp/a.pdf"),
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
  match lux_request_to_responses(req) {
    Ok(cr) => {
      let s = cr.value()
      // refusal / video 均无 input_text / input_image 载体 → 消息体为空
      assert_false(s.contains("input_text"))
      assert_false(s.contains("input_image"))
      assert_false(s.contains("v.mp4"))
      assert_false(s.contains("a.pdf"))
      // url 与 file_uri 两种来源各自一条 Unsupported 诊断
      let mut unsupported_count = 0
      for d in cr.diagnostics() {
        if d.field == "content.file" && d.status == Unsupported {
          unsupported_count = unsupported_count + 1
        }
      }
      assert_eq(unsupported_count, 2)
    }
    Err(e) => fail("encode failed: \{e}")
  }
}

///|
/// request_encode tools 分支：FileSearch / ComputerUse / Native kind 的 emit，
/// 以及 CodeExecution / Shell / ApplyPatch 无 Responses 原生工具类型 →
/// 显式 Unsupported 诊断（不静默降级为 function）。
test "encode - request tool kinds file_search computer_use native and unsupported" {
  let req = @lux.LucentRequest::new(
    "gpt-5",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [@lux.LucentContent::text("hi")]),
      ),
    ],
    Some([
      @lux.LucentTool::new("fs", Some("find docs"), "{}", None, FileSearch),
      @lux.LucentTool::new("cu", None, "{}", None, ComputerUse),
      @lux.LucentTool::new(
        "vendor_tool",
        None,
        "{}",
        None,
        Native("vendor_tag"),
      ),
      @lux.LucentTool::new("code_run", None, "{}", None, CodeExecution),
      @lux.LucentTool::new("sh", None, "{}", None, Shell),
      @lux.LucentTool::new("apply", None, "{}", None, ApplyPatch),
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
      assert_true(
        s.contains(
          "\"type\":\"file_search\",\"name\":\"fs\",\"description\":\"find docs\"",
        ),
      )
      assert_true(s.contains("\"type\":\"computer_use\",\"name\":\"cu\""))
      assert_true(
        s.contains("\"type\":\"vendor_tag\",\"name\":\"vendor_tool\""),
      )
      let mut unsupported_count = 0
      for d in cr.diagnostics() {
        if d.field == "tools.kind" && d.status == Unsupported {
          unsupported_count = unsupported_count + 1
        }
      }
      assert_eq(unsupported_count, 3)
    }
    Err(e) => fail("encode failed: \{e}")
  }
}

///|
/// request_encode options 分支：top_p、reasoning summary=auto、
/// structured_output（json_object / json_schema），以及 extras 中
/// disable_parallel_tool_use → parallel_tool_calls 的语义反向映射。
test "encode - request options top_p reasoning summary structured output and parallel" {
  let mk = fn(
    so : @lux.LucentStructuredOutput?,
    rc : @lux.LucentReasoningConfig?,
    extras : Map[String, Json]?,
  ) -> @lux.LucentRequest {
    @lux.LucentRequest::new(
      "gpt-5",
      None,
      [
        @lux.LucentConversationItem::message(
          @lux.LucentMessage::new(User, [@lux.LucentContent::text("hi")]),
        ),
      ],
      None,
      None,
      @lux.LucentOptions::new(
        None,
        Some(0.5),
        None,
        None,
        None,
        false,
        None,
        so,
        None,
        extras,
      ),
      None,
      rc,
      None,
      None,
    )
  }
  // top_p + reasoning summary=auto（effort 缺省 → 仅有 summary 字段）
  match
    lux_request_to_responses(
      mk(None, Some(@lux.LucentReasoningConfig::new(None, Some(Auto))), None),
    ) {
    Ok(cr) => {
      let s = cr.value()
      assert_true(s.contains("\"top_p\":0.5"))
      assert_true(s.contains("\"reasoning\":{\"summary\":\"auto\"}"))
    }
    Err(e) => fail("encode failed: \{e}")
  }
  // structured_output = json_object
  match lux_request_to_responses(mk(Some(JsonObject), None, None)) {
    Ok(cr) =>
      assert_true(
        cr.value().contains("\"text\":{\"format\":{\"type\":\"json_object\"}}"),
      )
    Err(e) => fail("encode failed: \{e}")
  }
  // structured_output = text（显式纯文本格式）
  match lux_request_to_responses(mk(Some(Text), None, None)) {
    Ok(cr) =>
      assert_true(
        cr.value().contains("\"text\":{\"format\":{\"type\":\"text\"}}"),
      )
    Err(e) => fail("encode failed: \{e}")
  }
  // structured_output = json_schema
  match
    lux_request_to_responses(
      mk(Some(JsonSchema("{\"type\":\"object\"}")), None, None),
    ) {
    Ok(cr) =>
      assert_true(
        cr
        .value()
        .contains(
          "\"text\":{\"format\":{\"type\":\"json_schema\",\"schema\":{\"type\":\"object\"}}",
        ),
      )
    Err(e) => fail("encode failed: \{e}")
  }
  // extras disable_parallel_tool_use=true → parallel_tool_calls:false（语义反向）
  match
    lux_request_to_responses(
      mk(None, None, Some({ "disable_parallel_tool_use": Json::boolean(true) })),
    ) {
    Ok(cr) => {
      let s = cr.value()
      assert_true(s.contains("\"parallel_tool_calls\":false"))
      assert_false(s.contains("disable_parallel_tool_use"))
    }
    Err(e) => fail("encode failed: \{e}")
  }
  // extras disable_parallel_tool_use=false → parallel_tool_calls:true
  match
    lux_request_to_responses(
      mk(
        None,
        None,
        Some({ "disable_parallel_tool_use": Json::boolean(false) }),
      ),
    ) {
    Ok(cr) => assert_true(cr.value().contains("\"parallel_tool_calls\":true"))
    Err(e) => fail("encode failed: \{e}")
  }
}

///|
/// lux_events_to_responses_sse_with_ctx：ctx 预置 response id（帧内无
/// ConversationStart 时复用），ConversationStart.extra 非标准字段合并进
/// response.created，以及 extra 非 Object 时静默不合并。
test "encode - stream ctx and conversation start extra fields" {
  // ctx Some(meta) 且 meta.id Some(id)：无 ConversationStart → 收尾帧复用该 id
  let ctx = @lux.LucentConversationMeta::new_full(
    Some("resp_ctx_7"),
    Some("gpt-5"),
    None,
    None,
    None,
  )
  let no_start : Array[@lux.LucentStreamEvent] = [Finish(Stop), Done]
  match lux_events_to_responses_sse_with_ctx(no_start, Some(ctx)) {
    Ok(cr) => {
      let sse = cr.value()
      assert_true(sse.contains("event: response.completed"))
      assert_true(sse.contains("\"id\":\"resp_ctx_7\""))
      assert_true(sse.contains("\"status\":\"completed\""))
    }
    Err(e) => fail("encode error: \{e}")
  }

  // ctx Some(meta) 但 meta.id = None：None 分支不改写 resp_id，回落默认 resp_0
  let id_less_ctx = @lux.LucentConversationMeta::new(None, Some("gpt-5"), None)
  match lux_events_to_responses_sse_with_ctx(no_start, Some(id_less_ctx)) {
    Ok(cr) => assert_true(cr.value().contains("\"id\":\"resp_0\""))
    Err(e) => fail("encode error: \{e}")
  }

  // ConversationStart.extra = Object：非标准字段逐条合并进 response.created
  let with_extra : Array[@lux.LucentStreamEvent] = [
    ConversationStart(
      @lux.LucentConversationMeta::new_full(
        Some("resp_x_1"),
        Some("gpt-5"),
        None,
        Some(1700000000),
        Some(
          Json::object({
            "instructions": Json::string("be brief"),
            "service_tier": Json::string("priority"),
            "parallel_tool_calls": Json::boolean(true),
          }),
        ),
      ),
    ),
    Done,
  ]
  match lux_events_to_responses_sse_with_ctx(with_extra, None) {
    Ok(cr) => {
      let sse = cr.value()
      assert_true(sse.contains("\"created_at\":1700000000"))
      assert_true(sse.contains("\"instructions\":\"be brief\""))
      assert_true(sse.contains("\"service_tier\":\"priority\""))
      assert_true(sse.contains("\"parallel_tool_calls\":true"))
    }
    Err(e) => fail("encode error: \{e}")
  }

  // ConversationStart.extra 非 Object（裸字符串）→ _ => () 分支，不合并
  let plain_extra : Array[@lux.LucentStreamEvent] = [
    ConversationStart(
      @lux.LucentConversationMeta::new_full(
        Some("resp_x_2"),
        Some("gpt-5"),
        None,
        None,
        Some(Json::string("not-an-object")),
      ),
    ),
    Done,
  ]
  match lux_events_to_responses_sse_with_ctx(plain_extra, None) {
    Ok(cr) => {
      let sse = cr.value()
      assert_true(sse.contains("event: response.created"))
      assert_false(sse.contains("not-an-object"))
    }
    Err(e) => fail("encode error: \{e}")
  }
}

///|
/// ItemStart 各 item 变体的 output_item.added 序列化：Message（非 Text 内容块
/// 跳过）、ToolCall、ToolResult、Reasoning（summary+signature / 均缺省）、
/// AgentAction。
test "encode - stream output item additions per item kind" {
  let events : Array[@lux.LucentStreamEvent] = [
    ConversationStart(
      @lux.LucentConversationMeta::new(Some("r_items"), Some("gpt-5"), None),
    ),
    // Message：非 Text 内容块被跳过 → content 为空数组
    ItemStart(
      0,
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(Assistant, [@lux.LucentContent::refusal("no")]),
      ),
    ),
    // ToolCall：使用 tu.id 作为 item id
    ItemStart(
      1,
      @lux.LucentConversationItem::tool_call(
        @lux.LucentToolUse::new("fc_1", "search", "{}", None),
      ),
    ),
    // ToolResult
    ItemStart(
      2,
      @lux.LucentConversationItem::tool_result(
        @lux.LucentToolResult::ok("call_1", [@lux.LucentContent::text("result")]),
      ),
    ),
    // Reasoning：summary + signature（中间夹一个非 Text 片段 → 被跳过）
    ItemStart(
      3,
      @lux.LucentConversationItem::reasoning(
        @lux.LucentThinking::new(
          "t",
          Some("sig_it"),
          false,
          Some([
            @lux.LucentContent::text("sum"),
            @lux.LucentContent::thinking("skipped", None),
          ]),
        ),
      ),
    ),
    // Reasoning：summary=None、signature=None → 两个 None 子分支
    ItemStart(
      4,
      @lux.LucentConversationItem::reasoning(
        @lux.LucentThinking::new("t", None, false, None),
      ),
    ),
    // AgentAction → computer_call 占位 item
    ItemStart(
      5,
      @lux.LucentConversationItem::agent_action(
        @lux.LucentAgentAction::new(
          "computer_use",
          "cu_1",
          None,
          None,
          None,
          None,
          None,
        ),
      ),
    ),
    Done,
  ]
  match lux_events_to_responses_sse(events) {
    Ok(cr) => {
      let sse = cr.value()
      assert_true(
        sse.contains(
          "\"output_index\":0,\"item\":{\"id\":\"msg_0\",\"type\":\"message\"" +
          ",\"role\":\"assistant\",\"content\":[]}",
        ),
      )
      assert_true(
        sse.contains(
          "\"output_index\":1,\"item\":{\"id\":\"fc_1\",\"type\":\"function_call\"" +
          ",\"call_id\":\"fc_1\",\"name\":\"search\",\"arguments\":\"\"}",
        ),
      )
      assert_true(
        sse.contains(
          "\"output_index\":2,\"item\":{\"type\":\"function_call_output\"" +
          ",\"call_id\":\"call_1\",\"output\":\"result\"}",
        ),
      )
      assert_true(
        sse.contains(
          "\"output_index\":3,\"item\":{\"id\":\"msg_3\",\"type\":\"reasoning\"" +
          ",\"summary\":[{\"type\":\"summary_text\",\"text\":\"sum\"}]" +
          ",\"signature\":\"sig_it\"}",
        ),
      )
      assert_true(
        sse.contains(
          "\"output_index\":4,\"item\":{\"id\":\"msg_4\",\"type\":\"reasoning\"}",
        ),
      )
      assert_true(
        sse.contains(
          "\"output_index\":5,\"item\":{\"id\":\"cu_1\",\"type\":\"computer_call\"}",
        ),
      )
    }
    Err(e) => fail("encode error: \{e}")
  }
}

///|
/// BlockStart ToolCall 的 id 为空串 → 合成 fc_<counter> id（并递增 item_counter），
/// 后续 arguments delta / done 帧沿用同一合成 id。
test "encode - stream tool call block synthetic id" {
  let events : Array[@lux.LucentStreamEvent] = [
    ConversationStart(
      @lux.LucentConversationMeta::new(Some("r_syn"), Some("gpt-5"), None),
    ),
    BlockStart(0, @lux.LucentBlockType::tool_call("", "auto_tool")),
    BlockDelta(0, @lux.LucentBlockDelta::tool_arguments_delta("{\"a\":1}")),
    BlockEnd(0),
    Finish(ToolCalls),
    Done,
  ]
  match lux_events_to_responses_sse(events) {
    Ok(cr) => {
      let sse = cr.value()
      // tid == "" → 合成 id fc_0（item_counter 自 0 起，ConversationStart 未消耗）
      assert_true(
        sse.contains(
          "\"id\":\"fc_0\",\"type\":\"function_call\",\"call_id\":\"fc_0\"" +
          ",\"name\":\"auto_tool\"",
        ),
      )
      assert_true(
        sse.contains(
          "\"item_id\":\"fc_0\",\"output_index\":0,\"delta\":\"{\\\"a\\\":1}\"",
        ),
      )
      assert_true(
        sse.contains(
          "\"item_id\":\"fc_0\",\"output_index\":0,\"arguments\":\"\"",
        ),
      )
    }
    Err(e) => fail("encode error: \{e}")
  }
}

///|
/// BlockStart Refusal → {"type":"refusal","refusal":""} 内容块；
/// BlockDelta RefusalDelta → response.refusal.delta 帧。
test "encode - stream refusal block and delta" {
  let events : Array[@lux.LucentStreamEvent] = [
    ConversationStart(
      @lux.LucentConversationMeta::new(Some("r_ref"), Some("gpt-5"), None),
    ),
    BlockStart(0, @lux.LucentBlockType::refusal()),
    BlockDelta(0, @lux.LucentBlockDelta::refusal_delta("I cannot comply")),
    BlockEnd(0),
    Finish(Stop),
    Done,
  ]
  match lux_events_to_responses_sse(events) {
    Ok(cr) => {
      let sse = cr.value()
      assert_true(
        sse.contains(
          "\"output_index\":0,\"content_index\":0,\"part\":" +
          "{\"type\":\"refusal\",\"refusal\":\"\"}",
        ),
      )
      assert_true(sse.contains("event: response.refusal.delta"))
      assert_true(
        sse.contains(
          "\"item_id\":\"msg_0\",\"output_index\":0,\"content_index\":0" +
          ",\"delta\":\"I cannot comply\"",
        ),
      )
    }
    Err(e) => fail("encode error: \{e}")
  }
}

///|
/// BlockDelta / BlockEnd 无前置 BlockStart：block_output / block_content /
/// block_item_id 三个映射全部走 None 回退（idx 与 "item_"+out）。
test "encode - stream delta fallbacks without block start" {
  let events : Array[@lux.LucentStreamEvent] = [
    ConversationStart(
      @lux.LucentConversationMeta::new(Some("r_fb"), Some("gpt-5"), None),
    ),
    BlockDelta(3, @lux.LucentBlockDelta::text_delta("orphan")),
    BlockEnd(3),
    Finish(Stop),
    Done,
  ]
  match lux_events_to_responses_sse(events) {
    Ok(cr) => {
      let sse = cr.value()
      // delta 帧：output_index / content_index 均回退为 block 索引 3
      assert_true(
        sse.contains(
          "\"item_id\":\"item_3\",\"output_index\":3,\"content_index\":3" +
          ",\"delta\":\"orphan\"",
        ),
      )
      // 非 tool / 非 thinking → output_text.done（同样走回退索引）
      assert_true(
        sse.contains(
          "\"item_id\":\"item_3\",\"output_index\":3,\"content_index\":3}",
        ),
      )
      assert_true(sse.contains("\"type\":\"message\",\"role\":\"assistant\"}}"))
      // 未注册的块不产出 output_item.added
      assert_false(sse.contains("event: response.output_item.added"))
    }
    Err(e) => fail("encode error: \{e}")
  }
}

///|
/// BlockDelta 的 NativeDelta 落入 catch-all；BlockDiscard / Annotations 均无帧；
/// Finish(Length) → incomplete 状态；Error(InvalidRequest) → invalid_request_error。
test "encode - stream silent events incomplete finish and invalid request error" {
  let silent : Array[@lux.LucentStreamEvent] = [
    ConversationStart(
      @lux.LucentConversationMeta::new(Some("r_silent"), Some("gpt-5"), None),
    ),
    BlockDelta(
      1,
      @lux.LucentBlockDelta::native_delta("vendor_x", Json::string("raw")),
    ),
    BlockDiscard(1),
    Annotations(1, []),
    ItemEnd(1),
    Finish(Length),
    Done,
  ]
  match lux_events_to_responses_sse(silent) {
    Ok(cr) => {
      let sse = cr.value()
      assert_true(sse.contains("event: response.created"))
      // Finish(Length) → incomplete
      assert_true(sse.contains("\"status\":\"incomplete\""))
      // NativeDelta / BlockDiscard / Annotations / ItemEnd 均不产出帧
      assert_false(sse.contains("response.output_text.delta"))
      assert_false(sse.contains("vendor_x"))
    }
    Err(e) => fail("encode error: \{e}")
  }
  let err_events : Array[@lux.LucentStreamEvent] = [
    ConversationStart(
      @lux.LucentConversationMeta::new(Some("r_err"), Some("gpt-5"), None),
    ),
    Error(@lux.LucentError::new(InvalidRequest, "bad request", Some("400"))),
    Done,
  ]
  match lux_events_to_responses_sse(err_events) {
    Ok(cr) => {
      let sse = cr.value()
      assert_true(sse.contains("event: error"))
      assert_true(sse.contains("\"code\":\"invalid_request_error\""))
      assert_true(sse.contains("\"message\":\"bad request\""))
    }
    Err(e) => fail("encode error: \{e}")
  }
  // Authentication → invalid_api_key
  let auth_events : Array[@lux.LucentStreamEvent] = [
    ConversationStart(
      @lux.LucentConversationMeta::new(Some("r_auth"), Some("gpt-5"), None),
    ),
    Error(@lux.LucentError::new(Authentication, "no key", Some("401"))),
    Done,
  ]
  match lux_events_to_responses_sse(auth_events) {
    Ok(cr) => {
      let sse = cr.value()
      assert_true(sse.contains("\"code\":\"invalid_api_key\""))
      assert_true(sse.contains("\"message\":\"no key\""))
    }
    Err(e) => fail("encode error: \{e}")
  }
  // ServerError → server_error
  let server_events : Array[@lux.LucentStreamEvent] = [
    ConversationStart(
      @lux.LucentConversationMeta::new(Some("r_srv"), Some("gpt-5"), None),
    ),
    Error(@lux.LucentError::new(ServerError, "boom", Some("500"))),
    Done,
  ]
  match lux_events_to_responses_sse(server_events) {
    Ok(cr) => {
      let sse = cr.value()
      assert_true(sse.contains("\"code\":\"server_error\""))
      assert_true(sse.contains("\"message\":\"boom\""))
    }
    Err(e) => fail("encode error: \{e}")
  }
  // ContentFilter → content_filter
  let cf_events : Array[@lux.LucentStreamEvent] = [
    ConversationStart(
      @lux.LucentConversationMeta::new(Some("r_cf"), Some("gpt-5"), None),
    ),
    Error(@lux.LucentError::new(ContentFilter, "blocked", None)),
    Done,
  ]
  match lux_events_to_responses_sse(cf_events) {
    Ok(cr) => {
      let sse = cr.value()
      assert_true(sse.contains("\"code\":\"content_filter\""))
      assert_true(sse.contains("\"message\":\"blocked\""))
    }
    Err(e) => fail("encode error: \{e}")
  }
  // Native(tag) → 原样透传厂商 code
  let native_events : Array[@lux.LucentStreamEvent] = [
    ConversationStart(
      @lux.LucentConversationMeta::new(Some("r_nat"), Some("gpt-5"), None),
    ),
    Error(@lux.LucentError::new(Native("vendor_499"), "vendor boom", None)),
    Done,
  ]
  match lux_events_to_responses_sse(native_events) {
    Ok(cr) => {
      let sse = cr.value()
      assert_true(sse.contains("\"code\":\"vendor_499\""))
      assert_true(sse.contains("\"message\":\"vendor boom\""))
    }
    Err(e) => fail("encode error: \{e}")
  }
}

///|
/// BlockStart 的非 Text / 非 Refusal / 非 ToolCall / 非 Thinking 块类型
/// （Image）落到输出文本 part 的兜底分支；Finish(Error) → failed 状态。
test "encode - stream non text block start and error finish" {
  let events : Array[@lux.LucentStreamEvent] = [
    ConversationStart(
      @lux.LucentConversationMeta::new(Some("r_img"), Some("gpt-5"), None),
    ),
    BlockStart(0, Image),
    BlockDelta(0, @lux.LucentBlockDelta::text_delta("img block")),
    BlockEnd(0),
    Finish(Error),
    Done,
  ]
  match lux_events_to_responses_sse(events) {
    Ok(cr) => {
      let sse = cr.value()
      // 块类型既非 Text 也非 Refusal → part 兜底为 output_text
      assert_true(
        sse.contains(
          "\"output_index\":0,\"content_index\":0,\"part\":" +
          "{\"type\":\"output_text\",\"text\":\"\"}",
        ),
      )
      assert_true(
        sse.contains(
          "\"item_id\":\"msg_0\",\"output_index\":0,\"content_index\":0" +
          ",\"delta\":\"img block\"",
        ),
      )
      // Finish(Error) → failed
      assert_true(sse.contains("\"status\":\"failed\""))
    }
    Err(e) => fail("encode error: \{e}")
  }
}
