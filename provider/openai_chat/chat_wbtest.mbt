///|
/// OpenAI Chat 适配器白盒测试 — 对齐 Lux IR v1 的 6 函数契约
///
/// 依据：docs/lux-ir-design.md §10
/// 覆盖：
///   1. openai_chat_to_lux_request      请求解码
///   2. lux_request_to_openai_chat      请求编码
///   3. openai_chat_to_lux_response     响应解码
///   4. lux_response_to_openai_chat     响应编码
///   5. openai_chat_sse_to_events       流解码
///   6. lux_events_to_openai_chat_sse   流编码

///|
/// === 1. 请求解码 ===

///|
test "openai_chat_to_lux_request - simple user message" {
  let json = "{\"model\":\"gpt-4o\",\"messages\":[{\"role\":\"user\",\"content\":\"Hello\"}],\"stream\":false}"
  match openai_chat_to_lux_request(json) {
    Ok(cr) => {
      let req = cr.value()
      assert_eq(req.model, "gpt-4o")
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
      assert_eq(req.options.stream, false)
      assert_eq(req.instructions, None)
    }
    Err(e) => fail("unexpected error: \{e}")
  }
}

///|
test "openai_chat_to_lux_request - system instruction extracted" {
  let json = "{\"model\":\"gpt-4o\",\"messages\":[{\"role\":\"system\",\"content\":\"You are helpful\"},{\"role\":\"user\",\"content\":\"hi\"}]}"
  match openai_chat_to_lux_request(json) {
    Ok(cr) => {
      let req = cr.value()
      // system 抽出为 instructions，不入 conversation
      assert_eq(req.conversation.length(), 1)
      match req.instructions {
        Some(instrs) => assert_eq(instrs.length(), 1)
        None => assert_true(false)
      }
    }
    Err(_) => assert_true(false)
  }
}

///|
test "openai_chat_to_lux_request - assistant with tool_calls" {
  let json = "{\"model\":\"gpt-4o\",\"messages\":[{\"role\":\"user\",\"content\":\"weather?\"},{\"role\":\"assistant\",\"content\":null,\"tool_calls\":[{\"id\":\"call_1\",\"type\":\"function\",\"function\":{\"name\":\"get_weather\",\"arguments\":\"{\\\"city\\\":\\\"Beijing\\\"}\"}}]},{\"role\":\"tool\",\"tool_call_id\":\"call_1\",\"content\":\"{\\\"temp\\\":25}\"}]}"
  match openai_chat_to_lux_request(json) {
    Ok(cr) => {
      let req = cr.value()
      assert_eq(req.conversation.length(), 3)
      // assistant 消息含 ToolUse content
      match req.conversation[1] {
        Message(m) =>
          match m.content[0] {
            ToolUse(tu) => {
              assert_eq(tu.id, "call_1")
              assert_eq(tu.name, "get_weather")
            }
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
      // tool 角色消息含 ToolResult
      match req.conversation[2] {
        Message(m) =>
          match m.content[0] {
            ToolResult(tr) => assert_eq(tr.tool_use_id, "call_1")
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    }
    Err(_) => assert_true(false)
  }
}

///|
test "openai_chat_to_lux_request - tools parsed" {
  let json = "{\"model\":\"gpt-4o\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"tools\":[{\"type\":\"function\",\"function\":{\"name\":\"f\",\"description\":\"d\",\"parameters\":{\"type\":\"object\"}}}]}"
  match openai_chat_to_lux_request(json) {
    Ok(cr) =>
      match cr.value().tools {
        Some(tools) => {
          assert_eq(tools.length(), 1)
          assert_eq(tools[0].name, "f")
        }
        None => assert_true(false)
      }
    Err(_) => assert_true(false)
  }
}

///|
test "openai_chat_to_lux_request - tool_choice variants" {
  let json_tc_auto = "{\"model\":\"gpt-4o\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"tool_choice\":\"auto\"}"
  match openai_chat_to_lux_request(json_tc_auto) {
    Ok(cr) => assert_eq(cr.value().tool_choice, Some(Auto))
    Err(_) => assert_true(false)
  }
  let json_tc_req = "{\"model\":\"gpt-4o\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"tool_choice\":{\"type\":\"function\",\"function\":{\"name\":\"f\"}}}"
  match openai_chat_to_lux_request(json_tc_req) {
    Ok(cr) => assert_eq(cr.value().tool_choice, Some(SpecificTool("f")))
    Err(_) => assert_true(false)
  }
}

///|
test "openai_chat_to_lux_request - options mapping" {
  let json = "{\"model\":\"gpt-4o\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"temperature\":0.7,\"max_tokens\":1024,\"stream\":true,\"stop\":\"\\n\\n\",\"seed\":42}"
  match openai_chat_to_lux_request(json) {
    Ok(cr) => {
      let req = cr.value()
      match req.options.temperature {
        Some(t) => assert_true(t > 0.6 && t < 0.8)
        None => assert_true(false)
      }
      assert_eq(req.options.max_output_tokens, Some(1024))
      assert_eq(req.options.stream, true)
      assert_eq(req.options.seed, Some(42))
      match req.options.stop {
        Some(arr) => assert_eq(arr.length(), 1)
        None => assert_true(false)
      }
    }
    Err(_) => assert_true(false)
  }
}

///|
test "openai_chat_to_lux_request - response_format json_object" {
  let json = "{\"model\":\"gpt-4o\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"response_format\":{\"type\":\"json_object\"}}"
  match openai_chat_to_lux_request(json) {
    Ok(cr) => assert_eq(cr.value().options.structured_output, Some(JsonObject))
    Err(_) => assert_true(false)
  }
}

///|
test "openai_chat_to_lux_request - invalid json returns error" {
  match openai_chat_to_lux_request("not json") {
    Ok(_) => assert_true(false)
    Err(_) => ()
  }
}

///|
test "openai_chat_to_lux_request - empty messages" {
  let json = "{\"model\":\"gpt-4o\",\"messages\":[]}"
  match openai_chat_to_lux_request(json) {
    Ok(cr) => assert_eq(cr.value().conversation.length(), 0)
    Err(_) => assert_true(false)
  }
}

///|
/// === 2. 请求编码 ===

///|
test "lux_request_to_openai_chat - simple user message" {
  let req = @lux.LucentRequest::from_messages(
    "gpt-4o",
    None,
    [@lux.LucentMessage::new(User, [@lux.LucentContent::text("Hello")])],
    None,
    None,
    @lux.LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
  match lux_request_to_openai_chat(req) {
    Ok(cr) => {
      let s = cr.value()
      let jv = @json.parse(s)
      match @internal.obj_get(jv, "model") {
        Some(String("gpt-4o")) => ()
        _ => assert_true(false)
      }
      match @internal.field_arr(jv, "messages") {
        Some(arr) => assert_eq(arr.length(), 1)
        None => assert_true(false)
      }
    }
    Err(_) => assert_true(false)
  }
}

///|
test "lux_request_to_openai_chat - instructions prepended as system message" {
  let req = @lux.LucentRequest::from_messages(
    "gpt-4o",
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
  match lux_request_to_openai_chat(req) {
    Ok(cr) => {
      let s = cr.value()
      let jv = @json.parse(s)
      match @internal.field_arr(jv, "messages") {
        Some(arr) => {
          assert_eq(arr.length(), 2)
          match @internal.field_str(arr[0], "role") {
            Some("system") => ()
            _ => assert_true(false)
          }
        }
        None => assert_true(false)
      }
    }
    Err(_) => assert_true(false)
  }
}

///|
test "lux_request_to_openai_chat - tool_use encoded as tool_calls" {
  let req = @lux.LucentRequest::from_messages(
    "gpt-4o",
    None,
    [
      @lux.LucentMessage::new(Assistant, [
        @lux.LucentContent::text("Let me check"),
        @lux.LucentContent::tool_use("c1", "f", "{}", None),
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
  match lux_request_to_openai_chat(req) {
    Ok(cr) => {
      let s = cr.value()
      let jv = @json.parse(s)
      match @internal.field_arr(jv, "messages") {
        Some(arr) =>
          match @internal.obj_get(arr[0], "tool_calls") {
            Some(Array(tc)) => assert_eq(tc.length(), 1)
            _ => assert_true(false)
          }
        None => assert_true(false)
      }
    }
    Err(_) => assert_true(false)
  }
}

///|
test "lux_request_to_openai_chat - tool_result encoded as tool role" {
  let req = @lux.LucentRequest::from_messages(
    "gpt-4o",
    None,
    [
      @lux.LucentMessage::new(Tool, [
        @lux.LucentContent::tool_result("c1", [
          @lux.LucentContent::text("result"),
        ]),
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
  match lux_request_to_openai_chat(req) {
    Ok(cr) => {
      let s = cr.value()
      let jv = @json.parse(s)
      match @internal.field_arr(jv, "messages") {
        Some(arr) =>
          match @internal.field_str(arr[0], "role") {
            Some("tool") => ()
            _ => assert_true(false)
          }
        None => assert_true(false)
      }
    }
    Err(_) => assert_true(false)
  }
}

///|
test "lux_request_to_openai_chat - tools encoded" {
  let req = @lux.LucentRequest::from_messages(
    "gpt-4o",
    None,
    [@lux.LucentMessage::new(User, [@lux.LucentContent::text("hi")])],
    Some([@lux.LucentTool::simple("f", "desc", "{\"type\":\"object\"}")]),
    None,
    @lux.LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
  match lux_request_to_openai_chat(req) {
    Ok(cr) => {
      let s = cr.value()
      let jv = @json.parse(s)
      match @internal.field_arr(jv, "tools") {
        Some(arr) => assert_eq(arr.length(), 1)
        None => assert_true(false)
      }
    }
    Err(_) => assert_true(false)
  }
}

///|
/// === 3. 响应解码 ===

///|
test "openai_chat_to_lux_response - text + usage" {
  let json = "{\"id\":\"chatcmpl-1\",\"object\":\"chat.completion\",\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"Hello!\"},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":5,\"total_tokens\":15}}"
  match openai_chat_to_lux_response(json) {
    Ok(cr) => {
      let resp = cr.value()
      assert_eq(resp.id, "chatcmpl-1")
      assert_eq(resp.model, "gpt-4o")
      assert_eq(resp.choices.length(), 1)
      match resp.choices[0].message.content[0] {
        Text(t, _) => assert_eq(t, "Hello!")
        _ => assert_true(false)
      }
      assert_eq(resp.choices[0].finish_reason, Stop)
      match resp.usage {
        Some(u) => assert_eq(u.prompt_tokens, 10)
        None => assert_true(false)
      }
    }
    Err(_) => assert_true(false)
  }
}

///|
test "openai_chat_to_lux_response - assistant with tool_calls" {
  let json = "{\"id\":\"c-1\",\"object\":\"chat.completion\",\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":null,\"tool_calls\":[{\"id\":\"c1\",\"type\":\"function\",\"function\":{\"name\":\"f\",\"arguments\":\"{}\"}}]},\"finish_reason\":\"tool_calls\"}]}"
  match openai_chat_to_lux_response(json) {
    Ok(cr) => {
      let resp = cr.value()
      assert_eq(resp.choices[0].finish_reason, ToolCalls)
      match resp.choices[0].message.content[0] {
        ToolUse(tu) => assert_eq(tu.name, "f")
        _ => assert_true(false)
      }
    }
    Err(_) => assert_true(false)
  }
}

///|
test "ai_chat_to_lux_response - refusal decoded" {
  let json = "{\"id\":\"c-1\",\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":null,\"refusal\":\"cannot\"},\"finish_reason\":\"stop\"}]}"
  match openai_chat_to_lux_response(json) {
    Ok(cr) =>
      match cr.value().choices[0].message.content[0] {
        Refusal(s) => assert_eq(s, "cannot")
        _ => assert_true(false)
      }
    Err(_) => assert_true(false)
  }
}

///|
test "openai_chat_to_lux_response - invalid json" {
  match openai_chat_to_lux_response("not json") {
    Ok(_) => assert_true(false)
    Err(_) => ()
  }
}

///|
/// === 4. 响应编码 ===

///|
test "lux_response_to_openai_chat - text response" {
  let resp = @lux.LucentResponse::new(
    "r-1",
    "gpt-4o",
    None,
    [
      @lux.LucentChoice::new(
        0,
        @lux.LucentMessage::new(Assistant, [@lux.LucentContent::text("Hello")]),
        Stop,
        None,
      ),
    ],
    Some(@lux.LucentUsage::new(10, 5, 15)),
    None,
  )
  match lux_response_to_openai_chat(resp) {
    Ok(cr) => {
      let s = cr.value()
      let jv = @json.parse(s)
      match @internal.field_str(jv, "object") {
        Some("chat.completion") => ()
        _ => assert_true(false)
      }
      match @internal.field_arr(jv, "choices") {
        Some(arr) => assert_eq(arr.length(), 1)
        None => assert_true(false)
      }
      match @internal.obj_get(jv, "usage") {
        Some(_) => ()
        None => assert_true(false)
      }
    }
    Err(_) => assert_true(false)
  }
}

///|
test "lux_response_to_openai_chat - tool_calls encoded" {
  let resp = @lux.LucentResponse::new(
    "r-1",
    "gpt-4o",
    None,
    [
      @lux.LucentChoice::new(
        0,
        @lux.LucentMessage::new(Assistant, [
          @lux.LucentContent::tool_use("c1", "f", "{}", None),
        ]),
        ToolCalls,
        None,
      ),
    ],
    None,
    None,
  )
  match lux_response_to_openai_chat(resp) {
    Ok(cr) => {
      let s = cr.value()
      let jv = @json.parse(s)
      match @internal.field_arr(jv, "choices") {
        Some(arr) =>
          match @internal.obj_get(arr[0], "message") {
            Some(m) =>
              match @internal.obj_get(m, "tool_calls") {
                Some(Array(tc)) => assert_eq(tc.length(), 1)
                _ => assert_true(false)
              }
            None => assert_true(false)
          }
        None => assert_true(false)
      }
    }
    Err(_) => assert_true(false)
  }
}

///|
test "lux_response_to_openai_chat - refusal encoded" {
  let resp = @lux.LucentResponse::new(
    "r-1",
    "gpt-4o",
    None,
    [
      @lux.LucentChoice::new(
        0,
        @lux.LucentMessage::new(Assistant, [@lux.LucentContent::refusal("no")]),
        Stop,
        None,
      ),
    ],
    None,
    None,
  )
  match lux_response_to_openai_chat(resp) {
    Ok(cr) => {
      let s = cr.value()
      let jv = @json.parse(s)
      match @internal.field_arr(jv, "choices") {
        Some(arr) =>
          match @internal.obj_get(arr[0], "message") {
            Some(m) =>
              match @internal.field_str(m, "refusal") {
                Some("no") => ()
                _ => assert_true(false)
              }
            None => assert_true(false)
          }
        None => assert_true(false)
      }
    }
    Err(_) => assert_true(false)
  }
}

///|
/// === 5. 流解码 ===

///|
test "openai_chat_sse_to_events - text chunks" {
  let sse = "data: {\"choices\":[{\"delta\":{\"role\":\"assistant\"}}]}\n\ndata: {\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}\n\ndata: {\"choices\":[{\"delta\":{\"content\":\" world\"}}]}\n\ndata: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n"
  match openai_chat_sse_to_events(sse) {
    Ok(cr) => {
      let events = cr.value()
      // 应有：ConversationStart + BlockStart + BlockDelta×2 + BlockEnd + Finish + Done
      assert_true(events.length() >= 5)
      // ConversationStart 首个事件
      assert_true(events[0] is ConversationStart(_))
      // Done 末事件
      assert_true(events[events.length() - 1] is Done)
    }
    Err(e) => fail("sse decode error: \{e}")
  }
}

///|
test "openai_chat_sse_to_events - tool call stream" {
  let sse = "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"c1\",\"type\":\"function\",\"function\":{\"name\":\"f\",\"arguments\":\"{\"}}]}}]}\n\ndata: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"\\\"x\\\":\"}}]}}]}\n\ndata: {\"choices\":[{\"delta\":{},\"finish_reason\":\"tool_calls\"}]}\n\ndata: [DONE]\n\n"
  match openai_chat_sse_to_events(sse) {
    Ok(cr) => {
      let events = cr.value()
      // 应有 BlockStart(0, ToolCall) + BlockDelta(ToolArgumentsDelta)×2 + BlockEnd + Finish(ToolCalls) + Done
      let has_tool_block_start = {
        let mut found = false
        for ev in events {
          match ev {
            BlockStart(0, ToolCall(_, _)) => found = true
            _ => ()
          }
        }
        found
      }
      assert_true(has_tool_block_start)
      // 末事件 Done
      assert_true(events[events.length() - 1] is Done)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "openai_chat_sse_to_events - usage frame" {
  let sse = "data: {\"choices\":[{\"delta\":{\"content\":\"ok\"}}]}\n\ndata: {\"choices\":[],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":2,\"total_tokens\":12}}\n\ndata: [DONE]\n\n"
  match openai_chat_sse_to_events(sse) {
    Ok(cr) => {
      let events = cr.value()
      let has_usage = {
        let mut found = false
        for ev in events {
          match ev {
            Usage(_) => found = true
            _ => ()
          }
        }
        found
      }
      assert_true(has_usage)
    }
    Err(_) => assert_true(false)
  }
}

///|
/// === 6. 流编码 ===

///|
test "lux_events_to_openai_chat_sse - text sequence" {
  let events : Array[@lux.LucentStreamEvent] = [
    ConversationStart(@lux.LucentConversationMeta::new(None, None, None)),
    BlockStart(0, Text),
    BlockDelta(0, @lux.LucentBlockDelta::text_delta("Hello")),
    BlockEnd(0),
    Finish(Stop),
    Done,
  ]
  match lux_events_to_openai_chat_sse(events) {
    Ok(cr) => {
      let sse = cr.value()
      // 应含 role:assistant、content:Hello、finish_reason:stop、[DONE]
      assert_true(sse.contains("\"role\":\"assistant\""))
      assert_true(sse.contains("\"content\":\"Hello\""))
      assert_true(sse.contains("\"finish_reason\":\"stop\""))
      assert_true(sse.contains("data: [DONE]"))
    }
    Err(_) => assert_true(false)
  }
}

///|
test "lux_events_to_openai_chat_sse - tool call sequence" {
  let events : Array[@lux.LucentStreamEvent] = [
    BlockStart(0, @lux.LucentBlockType::tool_call("c1", "f")),
    BlockDelta(0, @lux.LucentBlockDelta::tool_arguments_delta("{}")),
    Finish(ToolCalls),
    Done,
  ]
  match lux_events_to_openai_chat_sse(events) {
    Ok(cr) => {
      let sse = cr.value()
      // 应含 tool_calls 首帧（id + name）和 arguments 增量
      assert_true(sse.contains("\"id\":\"c1\""))
      assert_true(sse.contains("\"name\":\"f\""))
      assert_true(sse.contains("\"arguments\":\"{}\""))
    }
    Err(_) => assert_true(false)
  }
}

///|
test "lux_events_to_openai_chat_sse - usage frame" {
  let events : Array[@lux.LucentStreamEvent] = [
    Finish(Stop),
    Usage(@lux.LucentUsage::new(10, 2, 12)),
    Done,
  ]
  match lux_events_to_openai_chat_sse(events) {
    Ok(cr) => assert_true(cr.value().contains("\"total_tokens\":12"))
    Err(_) => assert_true(false)
  }
}

///|
/// === round-trip 一致性 ===

///|
test "round trip - request encode then decode preserves semantics" {
  let original = @lux.LucentRequest::from_messages(
    "gpt-4o",
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
  match lux_request_to_openai_chat(original) {
    Ok(cr1) =>
      match openai_chat_to_lux_request(cr1.value()) {
        Ok(cr2) => {
          let round = cr2.value()
          assert_eq(round.model, "gpt-4o")
          assert_eq(round.conversation.length(), 1)
          // instructions 应被还原（system 消息抽出）
          match round.instructions {
            Some(_) => ()
            None => assert_true(false)
          }
        }
        Err(_) => assert_true(false)
      }
    Err(_) => assert_true(false)
  }
}

///|
test "round trip - response decode then encode preserves id" {
  let json = "{\"id\":\"c-1\",\"object\":\"chat.completion\",\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"hi\"},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":1,\"completion_tokens\":1,\"total_tokens\":2}}"
  match openai_chat_to_lux_response(json) {
    Ok(cr1) =>
      match lux_response_to_openai_chat(cr1.value()) {
        Ok(cr2) => {
          let jv = @json.parse(cr2.value())
          match @internal.field_str(jv, "id") {
            Some("c-1") => ()
            _ => assert_true(false)
          }
        }
        Err(_) => assert_true(false)
      }
    Err(_) => assert_true(false)
  }
}

///|
/// === 保真度：Reasoning / AgentAction 编码产生 Unsupported 诊断 ===

///|
test "encode - Reasoning item yields Unsupported diagnostic" {
  let req = @lux.LucentRequest::new(
    "gpt-4o",
    None,
    [
      @lux.LucentConversationItem::reasoning(
        @lux.LucentThinking::new("think", None, false, None),
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
  match lux_request_to_openai_chat(req) {
    Ok(cr) => {
      // 不阻断成功
      assert_true(cr.value().contains("model"))
      // 但必须携带诊断
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
test "encode - AgentAction item yields Unsupported diagnostic" {
  let req = @lux.LucentRequest::new(
    "gpt-4o",
    None,
    [
      @lux.LucentConversationItem::agent_action(
        @lux.LucentAgentAction::new(
          "computer_call",
          "aa1",
          None,
          None,
          None,
          None,
          None,
        ),
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
  match lux_request_to_openai_chat(req) {
    Ok(cr) => {
      assert_true(cr.value().contains("model"))
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
test "chat store/extras round-trip" {
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
  match lux_request_to_openai_chat(req) {
    Ok(cr) => {
      assert_true(cr.value().contains("\"store\":true"))
      assert_true(cr.value().contains("\"extra_field\":\"v1\""))
      match openai_chat_to_lux_request(cr.value()) {
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
/// === Reasoning 契约测试 ===

///|
test "openai_chat_to_lux_response - vLLM message.reasoning captured" {
  let json = "{\"id\":\"c-1\",\"model\":\"qwen\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"Final answer\",\"reasoning\":\"step by step\"},\"finish_reason\":\"stop\"}]}"
  match openai_chat_to_lux_response(json) {
    Ok(cr) =>
      match cr.value().choices[0].message.reasoning {
        Some(r) => assert_eq(r.text, "step by step")
        None => assert_true(false)
      }
    Err(_) => assert_true(false)
  }
}

///|
test "openai_chat_to_lux_response - DeepSeek reasoning_content captured" {
  let json = "{\"id\":\"c-1\",\"model\":\"deepseek\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"Final answer\",\"reasoning_content\":\"chain of thought\"},\"finish_reason\":\"stop\"}]}"
  match openai_chat_to_lux_response(json) {
    Ok(cr) =>
      match cr.value().choices[0].message.reasoning {
        Some(r) => assert_eq(r.text, "chain of thought")
        None => assert_true(false)
      }
    Err(_) => assert_true(false)
  }
}

///|
test "lux_response_to_openai_chat - reasoning encoded as reasoning field" {
  let resp = @lux.LucentResponse::new(
    "r-1",
    "qwen",
    None,
    [
      @lux.LucentChoice::new(
        0,
        @lux.LucentMessage::with_reasoning(
          Assistant,
          [@lux.LucentContent::text("Final answer")],
          Some(@lux.LucentThinking::visible("step by step", None)),
        ),
        Stop,
        None,
      ),
    ],
    None,
    None,
  )
  match lux_response_to_openai_chat(resp) {
    Ok(cr) => {
      let jv = @json.parse(cr.value())
      match @internal.field_arr(jv, "choices") {
        Some(arr) =>
          match @internal.obj_get(arr[0], "message") {
            Some(msg) =>
              match @internal.field_str(msg, "reasoning") {
                Some(r) => assert_eq(r, "step by step")
                None => assert_true(false)
              }
            None => assert_true(false)
          }
        None => assert_true(false)
      }
    }
    Err(_) => assert_true(false)
  }
}

///|
test "openai-chat reasoning round-trip - vLLM format" {
  let inbound = "{\"id\":\"c-1\",\"model\":\"qwen\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"Final\",\"reasoning\":\"thought\"},\"finish_reason\":\"stop\"}]}"
  match openai_chat_to_lux_response(inbound) {
    Ok(cr) =>
      match lux_response_to_openai_chat(cr.value()) {
        Ok(enc) => {
          let jv = @json.parse(enc.value())
          match @internal.field_arr(jv, "choices") {
            Some(arr) =>
              match @internal.obj_get(arr[0], "message") {
                Some(msg) =>
                  match @internal.field_str(msg, "reasoning") {
                    Some(r) => assert_eq(r, "thought")
                    None => assert_true(false)
                  }
                None => assert_true(false)
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
/// === C1/C2/C4：流式 reasoning + 保真度诊断 ===

///|
test "C1 openai_chat_sse_to_events - captures delta.reasoning_content" {
  let sse = "data: {\"choices\":[{\"delta\":{\"role\":\"assistant\",\"reasoning_content\":\"think hard\"}}]}\n\ndata: {\"choices\":[{\"delta\":{\"content\":\"answer\"}}]}\n\ndata: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n"
  match openai_chat_sse_to_events(sse) {
    Ok(cr) => {
      let events = cr.value()
      let has_thinking_block = {
        let mut found = false
        for ev in events {
          match ev {
            BlockStart(1, Thinking) => found = true
            _ => ()
          }
        }
        found
      }
      assert_true(has_thinking_block)
      let has_thinking_delta = {
        let mut found = false
        for ev in events {
          match ev {
            BlockDelta(1, ThinkingDelta(s)) =>
              if s == "think hard" {
                found = true
              }
            _ => ()
          }
        }
        found
      }
      assert_true(has_thinking_delta)
      // Reasoning 块在 finish_reason 被闭合
      let has_block_end_1 = {
        let mut found = false
        for ev in events {
          match ev {
            BlockEnd(1) => found = true
            _ => ()
          }
        }
        found
      }
      assert_true(has_block_end_1)
    }
    Err(e) => fail("sse decode error: \{e}")
  }
}

///|
test "C2 lux_events_to_openai_chat_sse - encodes delta.reasoning" {
  let events : Array[@lux.LucentStreamEvent] = [
    ConversationStart(@lux.LucentConversationMeta::new(None, None, None)),
    BlockStart(1, @lux.LucentBlockType::thinking()),
    BlockDelta(1, @lux.LucentBlockDelta::thinking_delta("reasoning text")),
    BlockEnd(1),
    BlockStart(0, Text),
    BlockDelta(0, @lux.LucentBlockDelta::text_delta("answer")),
    BlockEnd(0),
    Finish(Stop),
    Done,
  ]
  match lux_events_to_openai_chat_sse(events) {
    Ok(cr) => {
      let sse = cr.value()
      assert_true(sse.contains("\"reasoning\":\"reasoning text\""))
      assert_true(sse.contains("\"content\":\"answer\""))
    }
    Err(_) => assert_true(false)
  }
}

///|
test "C4 lux_response_to_openai_chat - signature loss yields Degraded diagnostic" {
  let th = @lux.LucentThinking::visible("thought", Some("sig-abc"))
  let msg = @lux.LucentMessage::with_reasoning(
    Assistant,
    [@lux.LucentContent::text("answer")],
    Some(th),
  )
  let resp = @lux.LucentResponse::new(
    "r-1",
    "model",
    None,
    [@lux.LucentChoice::new(0, msg, Stop, None)],
    None,
    None,
  )
  match lux_response_to_openai_chat(resp) {
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
/// (a) reasoning_field 切换：provider_payload.reasoning_field = "reasoning_content"
/// 时出站字段名切换为 reasoning_content（DeepSeek/Fireworks 形态）。
test "(a) lux_response_to_openai_chat - reasoning_field switches to reasoning_content" {
  let th = @lux.LucentThinking::visible("thought", None)
  let msg = @lux.LucentMessage::with_reasoning(
    Assistant,
    [@lux.LucentContent::text("answer")],
    Some(th),
  )
  let resp = @lux.LucentResponse::new(
    "r-1",
    "model",
    None,
    [@lux.LucentChoice::new(0, msg, Stop, None)],
    None,
    Some({ "reasoning_field": @json.parse("\"reasoning_content\"") }),
  )
  match lux_response_to_openai_chat(resp) {
    Ok(cr) => {
      let s = cr.value()
      assert_true(s.contains("\"reasoning_content\":\"thought\""))
      assert_false(s.contains("\"reasoning\":\"thought\""))
      // 字段名合法，不产生诊断
      assert_eq(cr.diagnostics().length(), 0)
    }
    Err(_) => assert_true(false)
  }
}

///|
/// (a) reasoning_field 非法值 → Unsupported 诊断，不静默回退。
test "(a) lux_response_to_openai_chat - unsupported reasoning_field yields Unsupported" {
  let th = @lux.LucentThinking::visible("thought", None)
  let msg = @lux.LucentMessage::with_reasoning(
    Assistant,
    [@lux.LucentContent::text("answer")],
    Some(th),
  )
  let resp = @lux.LucentResponse::new(
    "r-1",
    "model",
    None,
    [@lux.LucentChoice::new(0, msg, Stop, None)],
    None,
    Some({ "reasoning_field": @json.parse("\"thought\"") }),
  )
  match lux_response_to_openai_chat(resp) {
    Ok(cr) => {
      let mut has_unsupported = false
      for d in cr.diagnostics() {
        if d.field == "reasoning.reasoning_field" && d.status == Unsupported {
          has_unsupported = true
        }
      }
      assert_true(has_unsupported)
      // 仍输出默认字段名 reasoning（不静默丢弃内容）
      assert_true(cr.value().contains("\"reasoning\":\"thought\""))
    }
    Err(_) => assert_true(false)
  }
}

///|
/// (b) 双载体回退：content 中的 Thinking block 作为 message.reasoning 的回退载体。
test "(b) lux_response_to_openai_chat - content Thinking falls back to reasoning" {
  let msg = @lux.LucentMessage::new(Assistant, [
    @lux.LucentContent::text("answer"),
    @lux.LucentContent::thinking("thought in block", None),
  ])
  let resp = @lux.LucentResponse::new(
    "r-1",
    "model",
    None,
    [@lux.LucentChoice::new(0, msg, Stop, None)],
    None,
    None,
  )
  match lux_response_to_openai_chat(resp) {
    Ok(cr) => {
      let s = cr.value()
      // content Thinking 回退为 reasoning 字段
      assert_true(s.contains("\"reasoning\":\"thought in block\""))
      // content 字符串不含 thinking 文本（Thinking 不入 content）
      assert_true(s.contains("\"content\":\"answer\""))
      assert_false(s.contains("\"content\":\"answerthought in block\""))
    }
    Err(_) => assert_true(false)
  }
}

///|
/// (b) 双载体并存：message.reasoning 与 content Thinking 同时存在 → Degraded 诊断，
/// 且以 message.reasoning 为准。
test "(b) lux_response_to_openai_chat - dual carrier yields Degraded" {
  let th = @lux.LucentThinking::visible("msg reasoning", None)
  let msg = @lux.LucentMessage::with_reasoning(
    Assistant,
    [@lux.LucentContent::thinking("block reasoning", None)],
    Some(th),
  )
  let resp = @lux.LucentResponse::new(
    "r-1",
    "model",
    None,
    [@lux.LucentChoice::new(0, msg, Stop, None)],
    None,
    None,
  )
  match lux_response_to_openai_chat(resp) {
    Ok(cr) => {
      let mut has_dual = false
      for d in cr.diagnostics() {
        if d.field == "reasoning.dual_carrier" && d.status == Degraded {
          has_dual = true
        }
      }
      assert_true(has_dual)
      // message.reasoning 优先
      assert_true(cr.value().contains("\"reasoning\":\"msg reasoning\""))
    }
    Err(_) => assert_true(false)
  }
}
