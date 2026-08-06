///|
/// OpenAI Responses 适配器白盒测试

///|
/// === 1. 请求解码 ===

///|
test "openai_responses_to_lux_request - simple user message" {
  let json = "{\"model\":\"gpt-5\",\"input\":[{\"type\":\"message\",\"role\":\"user\",\"content\":[{\"type\":\"input_text\",\"text\":\"Hello\"}]}]}"
  match openai_responses_to_lux_request(json) {
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
test "openai_responses_to_lux_request - instructions extracted" {
  let json = "{\"model\":\"gpt-5\",\"instructions\":\"Be helpful\",\"input\":[{\"type\":\"message\",\"role\":\"user\",\"content\":[{\"type\":\"input_text\",\"text\":\"hi\"}]}]}"
  match openai_responses_to_lux_request(json) {
    Ok(cr) =>
      match cr.value().instructions {
        Some(instrs) => assert_eq(instrs.length(), 1)
        None => assert_true(false)
      }
    Err(_) => assert_true(false)
  }
}

///|
test "openai_responses_to_lux_request - function_call and function_call_output" {
  let json = "{\"model\":\"gpt-5\",\"input\":[{\"type\":\"function_call\",\"id\":\"fc_1\",\"call_id\":\"call_1\",\"name\":\"search\",\"arguments\":\"{\\\"q\\\":\\\"x\\\"}\"},{\"type\":\"function_call_output\",\"call_id\":\"call_1\",\"output\":\"result\"}]}"
  match openai_responses_to_lux_request(json) {
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
test "openai_responses_to_lux_request - reasoning item" {
  let json = "{\"model\":\"gpt-5\",\"input\":[{\"type\":\"reasoning\",\"id\":\"rs_1\",\"summary\":[{\"type\":\"summary_text\",\"text\":\"thinking step\"}],\"signature\":\"sig_1\"}]}"
  match openai_responses_to_lux_request(json) {
    Ok(cr) =>
      match cr.value().conversation[0] {
        Reasoning(th) => assert_eq(th.signature, Some("sig_1"))
        _ => assert_true(false)
      }
    Err(_) => assert_true(false)
  }
}

///|
/// === 2. 请求编码 ===

///|
test "lux_request_to_openai_responses - simple user message" {
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
  match lux_request_to_openai_responses(req) {
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
/// === 3. 响应解码 ===

///|
test "openai_responses_to_lux_response - text + usage" {
  let json = "{\"id\":\"resp_1\",\"object\":\"response\",\"status\":\"completed\",\"model\":\"gpt-5\",\"created_at\":1700000000,\"output\":[{\"type\":\"message\",\"id\":\"msg_1\",\"role\":\"assistant\",\"status\":\"completed\",\"content\":[{\"type\":\"output_text\",\"text\":\"Hello!\",\"annotations\":[]}]}],\"usage\":{\"input_tokens\":10,\"output_tokens\":5,\"total_tokens\":15}}"
  match openai_responses_to_lux_response(json) {
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
test "openai_responses_to_lux_response - function_call output" {
  let json = "{\"id\":\"resp_2\",\"model\":\"gpt-5\",\"output\":[{\"type\":\"function_call\",\"id\":\"fc_1\",\"call_id\":\"call_1\",\"name\":\"search\",\"arguments\":\"{}\",\"status\":\"completed\"}],\"usage\":{\"input_tokens\":1,\"output_tokens\":1,\"total_tokens\":2}}"
  match openai_responses_to_lux_response(json) {
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
test "lux_response_to_openai_responses - text response" {
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
  match lux_response_to_openai_responses(resp) {
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
test "lux_response_to_openai_responses - empty choices error" {
  let resp = @lux.LucentResponse::new("r", "m", None, [], None, None)
  match lux_response_to_openai_responses(resp) {
    Ok(_) => assert_true(false)
    Err(e) => assert_eq(e, "response has no choices")
  }
}

///|
/// === 5. 流解码 ===

///|
test "openai_responses_sse_to_events - text stream" {
  let sse = "event: response.created\ndata: {\"type\":\"response.created\",\"response\":{\"id\":\"r_1\",\"model\":\"gpt-5\"}}\n\nevent: response.output_item.added\ndata: {\"type\":\"response.output_item.added\",\"output_index\":0,\"item\":{\"type\":\"message\",\"role\":\"assistant\",\"content\":[{\"type\":\"input_text\",\"text\":\"\"}]}}\n\nevent: response.content_part.added\ndata: {\"type\":\"response.content_part.added\",\"output_index\":0,\"content_index\":0,\"part\":{\"type\":\"output_text\",\"text\":\"\"}}\n\nevent: response.output_text.delta\ndata: {\"type\":\"response.output_text.delta\",\"output_index\":0,\"content_index\":0,\"delta\":\"Hello\"}\n\nevent: response.output_text.done\ndata: {\"type\":\"response.output_text.done\",\"output_index\":0,\"content_index\":0}\n\nevent: response.completed\ndata: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\",\"usage\":{\"input_tokens\":1,\"output_tokens\":1,\"total_tokens\":2}}}\n\n"
  match openai_responses_sse_to_events(sse) {
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
test "openai_responses_sse_to_events - function_call stream" {
  let sse = "event: response.created\ndata: {\"type\":\"response.created\",\"response\":{\"id\":\"r_2\",\"model\":\"gpt-5\"}}\n\nevent: response.output_item.added\ndata: {\"type\":\"response.output_item.added\",\"output_index\":0,\"item\":{\"type\":\"function_call\",\"id\":\"fc_1\",\"name\":\"search\"}}\n\nevent: response.function_call_arguments.delta\ndata: {\"type\":\"response.function_call_arguments.delta\",\"output_index\":0,\"delta\":\"{\\\"q\\\":\\\"x\\\"}\"}\n\nevent: response.function_call_arguments.done\ndata: {\"type\":\"response.function_call_arguments.done\",\"output_index\":0}\n\nevent: response.completed\ndata: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\"}}\n\n"
  match openai_responses_sse_to_events(sse) {
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
test "lux_events_to_openai_responses_sse - text sequence" {
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
  match lux_events_to_openai_responses_sse(events) {
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
  match lux_request_to_openai_responses(req) {
    Ok(cr) => {
      let json = cr.value()
      match openai_responses_to_lux_request(json) {
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
test "decode - input_image yields Degraded diagnostic" {
  let json = "{\"model\":\"gpt-5\",\"input\":[{\"type\":\"message\",\"role\":\"user\",\"content\":[{\"type\":\"input_image\",\"image_url\":\"https://x.com/a.png\"}]}]}"
  match openai_responses_to_lux_request(json) {
    Ok(cr) => {
      let mut has_degraded = false
      for d in cr.diagnostics() {
        if d.status == Degraded {
          has_degraded = true
        }
      }
      assert_true(has_degraded)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "sse - invalid data yields Invalid diagnostic" {
  let sse = "data: {not-valid-json}\n\n"
  match openai_responses_sse_to_events(sse) {
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
  match lux_request_to_openai_responses(req) {
    Ok(cr) => {
      assert_true(cr.value().contains("\"store\":true"))
      assert_true(cr.value().contains("\"extra_field\":\"v1\""))
      match openai_responses_to_lux_request(cr.value()) {
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
test "lux_response_to_openai_responses - message-level reasoning emits reasoning item" {
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
  match lux_response_to_openai_responses(resp) {
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
test "lux_response_to_openai_responses - dual carrier yields Degraded" {
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
  match lux_response_to_openai_responses(resp) {
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
