///|
/// OpenAI Codex Responses 适配器白盒测试
///
/// Codex 是标准 OpenAI Responses 的薄封装，差异：
///   - JSON 接口与标准 Responses 相同，仅端点 URL 和认证方式不同
///   - 特有字段：phase (commentary/final_answer)、reasoning.effort 支持 xhigh
///   - 所有适配函数直接委托给 openai_responses 包

///|
/// === 1. 请求解码 ===

///|
test "codex_to_lux_request - simple user message" {
  let json = "{\"model\":\"gpt-5.3-codex\",\"input\":[{\"type\":\"message\",\"role\":\"user\",\"content\":[{\"type\":\"input_text\",\"text\":\"Hello\"}]}]}"
  match codex_to_lux_request(json) {
    Ok(cr) => {
      let req = cr.value()
      assert_eq(req.model, "gpt-5.3-codex")
      assert_eq(req.conversation.length(), 1)
    }
    Err(e) => fail("unexpected: \{e}")
  }
}

///|
test "codex_to_lux_request - instructions extracted" {
  let json = "{\"model\":\"gpt-5.3-codex\",\"instructions\":\"Be helpful\",\"input\":[{\"type\":\"message\",\"role\":\"user\",\"content\":[{\"type\":\"input_text\",\"text\":\"hi\"}]}]}"
  match codex_to_lux_request(json) {
    Ok(cr) =>
      match cr.value().instructions {
        Some(instrs) => assert_eq(instrs.length(), 1)
        None => assert_true(false)
      }
    Err(_) => assert_true(false)
  }
}

///|
test "codex_to_lux_request - function_call and function_call_output" {
  let json = "{\"model\":\"gpt-5.3-codex\",\"input\":[{\"type\":\"function_call\",\"id\":\"fc_1\",\"call_id\":\"call_1\",\"name\":\"search\",\"arguments\":\"{\\\"q\\\":\\\"x\\\"}\"},{\"type\":\"function_call_output\",\"call_id\":\"call_1\",\"output\":\"result\"}]}"
  match codex_to_lux_request(json) {
    Ok(cr) => {
      let req = cr.value()
      assert_eq(req.conversation.length(), 2)
      match req.conversation[0] {
        ToolCall(tu) => assert_eq(tu.name, "search")
        _ => assert_true(false)
      }
    }
    Err(_) => assert_true(false)
  }
}

///|
test "codex_to_lux_request - reasoning item" {
  let json = "{\"model\":\"gpt-5.3-codex\",\"input\":[{\"type\":\"reasoning\",\"id\":\"rs_1\",\"summary\":[{\"type\":\"summary_text\",\"text\":\"step 1\"}],\"signature\":\"sig_1\"}]}"
  match codex_to_lux_request(json) {
    Ok(cr) =>
      match cr.value().conversation[0] {
        Reasoning(th) => assert_eq(th.signature, Some("sig_1"))
        _ => assert_true(false)
      }
    Err(_) => assert_true(false)
  }
}

///|
test "codex_to_lux_request - invalid json" {
  match codex_to_lux_request("not json") {
    Ok(_) => assert_true(false)
    Err(_) => ()
  }
}

///|
/// === 2. 请求编码 ===

///|
test "lux_request_to_codex - simple user message" {
  let req = @lux.LucentRequest::from_messages(
    "gpt-5.3-codex",
    None,
    [@lux.LucentMessage::new(@lux.User, [@lux.LucentContent::text("hi")])],
    None,
    None,
    @lux.LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
  match lux_request_to_codex(req) {
    Ok(cr) => {
      let s = cr.value()
      assert_true(s.contains("\"model\":\"gpt-5.3-codex\""))
      assert_true(s.contains("\"input\":"))
    }
    Err(_) => assert_true(false)
  }
}

///|
/// === 3. 响应解码 ===

///|
test "codex_to_lux_response - text + usage" {
  let json = "{\"id\":\"resp_1\",\"object\":\"response\",\"status\":\"completed\",\"model\":\"gpt-5.3-codex\",\"created_at\":1700000000,\"output\":[{\"type\":\"message\",\"id\":\"msg_1\",\"role\":\"assistant\",\"status\":\"completed\",\"content\":[{\"type\":\"output_text\",\"text\":\"Hello!\",\"annotations\":[]}]}],\"usage\":{\"input_tokens\":10,\"output_tokens\":5,\"total_tokens\":15}}"
  match codex_to_lux_response(json) {
    Ok(cr) => {
      let resp = cr.value()
      assert_eq(resp.id, "resp_1")
      assert_eq(resp.model, "gpt-5.3-codex")
      assert_eq(resp.choices.length(), 1)
      assert_eq(resp.choices[0].finish_reason, Stop)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "codex_to_lux_response - function_call output" {
  let json = "{\"id\":\"resp_2\",\"model\":\"gpt-5.3-codex\",\"output\":[{\"type\":\"function_call\",\"id\":\"fc_1\",\"call_id\":\"call_1\",\"name\":\"search\",\"arguments\":\"{}\",\"status\":\"completed\"}],\"usage\":{\"input_tokens\":1,\"output_tokens\":1,\"total_tokens\":2}}"
  match codex_to_lux_response(json) {
    Ok(cr) =>
      match cr.value().choices[0].message.content[0] {
        ToolUse(tu) => assert_eq(tu.name, "search")
        _ => assert_true(false)
      }
    Err(_) => assert_true(false)
  }
}

///|
test "codex_to_lux_response - invalid json" {
  match codex_to_lux_response("not json") {
    Ok(_) => assert_true(false)
    Err(_) => ()
  }
}

///|
/// === 4. 响应编码 ===

///|
test "lux_response_to_codex - text response" {
  let msg = @lux.LucentMessage::new(@lux.Assistant, [
    @lux.LucentContent::text("Hello"),
  ])
  let choice = @lux.LucentChoice::new(0, msg, @lux.Stop, None)
  let resp = @lux.LucentResponse::new(
    "resp_1",
    "gpt-5.3-codex",
    None,
    [choice],
    Some(@lux.LucentUsage::new(10, 5, 15)),
    None,
  )
  match lux_response_to_codex(resp) {
    Ok(cr) => {
      let s = cr.value()
      assert_true(s.contains("\"id\":\"resp_1\""))
      assert_true(s.contains("\"object\":\"response\""))
    }
    Err(_) => assert_true(false)
  }
}

///|
/// === 5. 流解码 ===

///|
test "codex_sse_to_events - text stream" {
  let sse = "event: response.created\ndata: {\"type\":\"response.created\",\"response\":{\"id\":\"r_1\",\"model\":\"gpt-5.3-codex\"}}\n\nevent: response.output_item.added\ndata: {\"type\":\"response.output_item.added\",\"output_index\":0,\"item\":{\"type\":\"message\",\"role\":\"assistant\",\"content\":[{\"type\":\"input_text\",\"text\":\"\"}]}}\n\nevent: response.content_part.added\ndata: {\"type\":\"response.content_part.added\",\"output_index\":0,\"content_index\":0,\"part\":{\"type\":\"output_text\",\"text\":\"\"}}\n\nevent: response.output_text.delta\ndata: {\"type\":\"response.output_text.delta\",\"output_index\":0,\"content_index\":0,\"delta\":\"Hello\"}\n\nevent: response.completed\ndata: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\"}}\n\n"
  match codex_sse_to_events(sse) {
    Ok(cr) => {
      let events = cr.value()
      assert_true(events.length() >= 3)
      match events[0] {
        ConversationStart(_) => ()
        _ => assert_true(false)
      }
    }
    Err(_) => assert_true(false)
  }
}

///|
test "codex_sse_to_events - function_call stream" {
  let sse = "event: response.created\ndata: {\"type\":\"response.created\",\"response\":{\"id\":\"r_2\",\"model\":\"gpt-5.3-codex\"}}\n\nevent: response.output_item.added\ndata: {\"type\":\"response.output_item.added\",\"output_index\":0,\"item\":{\"type\":\"function_call\",\"id\":\"fc_1\",\"name\":\"search\"}}\n\nevent: response.function_call_arguments.delta\ndata: {\"type\":\"response.function_call_arguments.delta\",\"output_index\":0,\"delta\":\"{\\\"q\\\":\\\"x\\\"}\"}\n\nevent: response.function_call_arguments.done\ndata: {\"type\":\"response.function_call_arguments.done\",\"output_index\":0}\n\nevent: response.completed\ndata: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\"}}\n\n"
  match codex_sse_to_events(sse) {
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
test "lux_events_to_codex_sse - text sequence" {
  let events : Array[@lux.LucentStreamEvent] = [
    ConversationStart(
      @lux.LucentConversationMeta::new(Some("r_1"), Some("gpt-5.3-codex"), None),
    ),
    ItemStart(
      0,
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(@lux.Assistant, [@lux.LucentContent::text("")]),
      ),
    ),
    BlockStart(0, Text),
    BlockDelta(0, @lux.LucentBlockDelta::text_delta("Hello")),
    BlockEnd(0),
    Finish(Stop),
    Done,
  ]
  match lux_events_to_codex_sse(events) {
    Ok(cr) => {
      let sse = cr.value()
      assert_true(sse.contains("event: response.created"))
      assert_true(sse.contains("event: response.output_text.delta"))
      assert_true(sse.contains("event: response.completed"))
    }
    Err(_) => assert_true(false)
  }
}

///|
/// === round-trip 一致性 ===

///|
test "round trip - codex request encode then decode" {
  let original = @lux.LucentRequest::from_messages(
    "gpt-5.3-codex",
    Some([@lux.LucentContent::text("Be helpful")]),
    [@lux.LucentMessage::new(@lux.User, [@lux.LucentContent::text("hi")])],
    None,
    None,
    @lux.LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
  match lux_request_to_codex(original) {
    Ok(cr) =>
      match codex_to_lux_request(cr.value()) {
        Ok(cr2) => {
          let round = cr2.value()
          assert_eq(round.model, "gpt-5.3-codex")
          assert_eq(round.conversation.length(), 1)
        }
        Err(_) => assert_true(false)
      }
    Err(_) => assert_true(false)
  }
}
