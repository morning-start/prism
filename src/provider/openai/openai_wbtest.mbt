///|
/// OpenAI Chat 适配器白盒测试 — 对齐 Lux IR v1 的 6 函数契约
///
/// 依据：docs/lux-ir-design.md §10
/// 覆盖：
///   1. openai_to_lux_request      请求解码
///   2. lux_request_to_openai      请求编码
///   3. openai_to_lux_response     响应解码
///   4. lux_response_to_openai     响应编码
///   5. openai_sse_to_events       流解码
///   6. lux_events_to_openai_sse   流编码

///|
/// === 1. 请求解码 ===

///|
test "openai_to_lux_request - simple user message" {
  let json = "{\"model\":\"gpt-4o\",\"messages\":[{\"role\":\"user\",\"content\":\"Hello\"}],\"stream\":false}"
  match openai_to_lux_request(json) {
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
test "openai_to_lux_request - system instruction extracted" {
  let json = "{\"model\":\"gpt-4o\",\"messages\":[{\"role\":\"system\",\"content\":\"You are helpful\"},{\"role\":\"user\",\"content\":\"hi\"}]}"
  match openai_to_lux_request(json) {
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
test "openai_to_lux_request - assistant with tool_calls" {
  let json = "{\"model\":\"gpt-4o\",\"messages\":[{\"role\":\"user\",\"content\":\"weather?\"},{\"role\":\"assistant\",\"content\":null,\"tool_calls\":[{\"id\":\"call_1\",\"type\":\"function\",\"function\":{\"name\":\"get_weather\",\"arguments\":\"{\\\"city\\\":\\\"Beijing\\\"}\"}}]},{\"role\":\"tool\",\"tool_call_id\":\"call_1\",\"content\":\"{\\\"temp\\\":25}\"}]}"
  match openai_to_lux_request(json) {
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
test "openai_to_lux_request - tools parsed" {
  let json = "{\"model\":\"gpt-4o\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"tools\":[{\"type\":\"function\",\"function\":{\"name\":\"f\",\"description\":\"d\",\"parameters\":{\"type\":\"object\"}}}]}"
  match openai_to_lux_request(json) {
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
test "openai_to_lux_request - tool_choice variants" {
  let json_tc_auto = "{\"model\":\"gpt-4o\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"tool_choice\":\"auto\"}"
  match openai_to_lux_request(json_tc_auto) {
    Ok(cr) => assert_eq(cr.value().tool_choice, Some(Auto))
    Err(_) => assert_true(false)
  }
  let json_tc_req = "{\"model\":\"gpt-4o\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"tool_choice\":{\"type\":\"function\",\"function\":{\"name\":\"f\"}}}"
  match openai_to_lux_request(json_tc_req) {
    Ok(cr) => assert_eq(cr.value().tool_choice, Some(SpecificTool("f")))
    Err(_) => assert_true(false)
  }
}

///|
test "openai_to_lux_request - options mapping" {
  let json = "{\"model\":\"gpt-4o\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"temperature\":0.7,\"max_tokens\":1024,\"stream\":true,\"stop\":\"\\n\\n\",\"seed\":42}"
  match openai_to_lux_request(json) {
    Ok(cr) => {
      let req = cr.value()
      match req.options.temperature {
        Some(t) => assert_true(t > 0.6 && t < 0.8)
        None => assert_true(false)
      }
      assert_eq(req.options.max_output_tokens, Some(1024))
      assert_eq(req.options.stream, true)
      match req.options.extras {
        Some(m) => assert_true(m.contains("seed"))
        None => fail("seed should persist in extras")
      }
      match req.options.stop {
        Some(arr) => assert_eq(arr.length(), 1)
        None => assert_true(false)
      }
    }
    Err(_) => assert_true(false)
  }
}

///|
test "openai_to_lux_request - response_format json_object" {
  let json = "{\"model\":\"gpt-4o\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"response_format\":{\"type\":\"json_object\"}}"
  match openai_to_lux_request(json) {
    Ok(cr) => assert_eq(cr.value().options.structured_output, Some(JsonObject))
    Err(_) => assert_true(false)
  }
}

///|
test "openai_to_lux_request - invalid json returns error" {
  match openai_to_lux_request("not json") {
    Ok(_) => assert_true(false)
    Err(_) => ()
  }
}

///|
test "openai_to_lux_request - empty messages" {
  let json = "{\"model\":\"gpt-4o\",\"messages\":[]}"
  match openai_to_lux_request(json) {
    Ok(cr) => assert_eq(cr.value().conversation.length(), 0)
    Err(_) => assert_true(false)
  }
}

///|
/// === 2. 请求编码 ===

///|
test "lux_request_to_openai - simple user message" {
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
  match lux_request_to_openai(req) {
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
test "lux_request_to_openai - instructions prepended as system message" {
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
  match lux_request_to_openai(req) {
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
test "lux_request_to_openai - tool_use encoded as tool_calls" {
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
  match lux_request_to_openai(req) {
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
test "lux_request_to_openai - tool_result encoded as tool role" {
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
  match lux_request_to_openai(req) {
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
test "lux_request_to_openai - tools encoded" {
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
  match lux_request_to_openai(req) {
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
test "lux_request_to_openai - non-function tool kind unsupported" {
  let req = @lux.LucentRequest::from_messages(
    "gpt-4o",
    None,
    [@lux.LucentMessage::new(User, [@lux.LucentContent::text("hi")])],
    Some([@lux.LucentTool::new("ws", None, "{}", None, WebSearch)]),
    None,
    @lux.LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
  match lux_request_to_openai(req) {
    Ok(cr) => {
      // 必须携带 Unsupported 诊断（不静默降级为 function）
      let mut has_unsupported = false
      for d in cr.diagnostics() {
        if d.field == "tools.kind" && d.status == Unsupported {
          has_unsupported = true
        }
      }
      assert_true(has_unsupported)
      // 且编码 JSON 不含被跳过的工具名
      assert_false(cr.value().contains("ws"))
    }
    Err(_) => assert_true(false)
  }
}

///|
/// === 3. 响应解码 ===

///|
test "openai_to_lux_response - text + usage" {
  let json = "{\"id\":\"chatcmpl-1\",\"object\":\"chat.completion\",\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"Hello!\"},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":5,\"total_tokens\":15}}"
  match openai_to_lux_response(json) {
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
test "openai_to_lux_response - assistant with tool_calls" {
  let json = "{\"id\":\"c-1\",\"object\":\"chat.completion\",\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":null,\"tool_calls\":[{\"id\":\"c1\",\"type\":\"function\",\"function\":{\"name\":\"f\",\"arguments\":\"{}\"}}]},\"finish_reason\":\"tool_calls\"}]}"
  match openai_to_lux_response(json) {
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
  match openai_to_lux_response(json) {
    Ok(cr) =>
      match cr.value().choices[0].message.content[0] {
        Refusal(s) => assert_eq(s, "cannot")
        _ => assert_true(false)
      }
    Err(_) => assert_true(false)
  }
}

///|
test "openai_to_lux_response - invalid json" {
  match openai_to_lux_response("not json") {
    Ok(_) => assert_true(false)
    Err(_) => ()
  }
}

///|
/// === 4. 响应编码 ===

///|
test "lux_response_to_openai - text response" {
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
  match lux_response_to_openai(resp) {
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
test "lux_response_to_openai - tool_calls encoded" {
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
  match lux_response_to_openai(resp) {
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
test "lux_response_to_openai - refusal encoded" {
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
  match lux_response_to_openai(resp) {
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
test "openai_sse_to_events - text chunks" {
  let sse = "data: {\"choices\":[{\"delta\":{\"role\":\"assistant\"}}]}\n\ndata: {\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}\n\ndata: {\"choices\":[{\"delta\":{\"content\":\" world\"}}]}\n\ndata: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n"
  match openai_sse_to_events(sse) {
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
test "openai_sse_to_events - tool call stream" {
  let sse = "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"c1\",\"type\":\"function\",\"function\":{\"name\":\"f\",\"arguments\":\"{\"}}]}}]}\n\ndata: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"\\\"x\\\":\"}}]}}]}\n\ndata: {\"choices\":[{\"delta\":{},\"finish_reason\":\"tool_calls\"}]}\n\ndata: [DONE]\n\n"
  match openai_sse_to_events(sse) {
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
test "openai_sse_to_events - usage frame" {
  let sse = "data: {\"choices\":[{\"delta\":{\"content\":\"ok\"}}]}\n\ndata: {\"choices\":[],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":2,\"total_tokens\":12}}\n\ndata: [DONE]\n\n"
  match openai_sse_to_events(sse) {
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
test "lux_events_to_openai_sse - text sequence" {
  let events : Array[@lux.LucentStreamEvent] = [
    ConversationStart(@lux.LucentConversationMeta::new(None, None, None)),
    BlockStart(0, Text),
    BlockDelta(0, @lux.LucentBlockDelta::text_delta("Hello")),
    BlockEnd(0),
    Finish(Stop),
    Done,
  ]
  match lux_events_to_openai_sse(events) {
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
test "lux_events_to_openai_sse - tool call sequence" {
  let events : Array[@lux.LucentStreamEvent] = [
    BlockStart(0, @lux.LucentBlockType::tool_call("c1", "f")),
    BlockDelta(0, @lux.LucentBlockDelta::tool_arguments_delta("{}")),
    Finish(ToolCalls),
    Done,
  ]
  match lux_events_to_openai_sse(events) {
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
test "lux_events_to_openai_sse - usage frame" {
  let events : Array[@lux.LucentStreamEvent] = [
    Finish(Stop),
    Usage(@lux.LucentUsage::new(10, 2, 12)),
    Done,
  ]
  match lux_events_to_openai_sse(events) {
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
  match lux_request_to_openai(original) {
    Ok(cr1) =>
      match openai_to_lux_request(cr1.value()) {
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
  match openai_to_lux_response(json) {
    Ok(cr1) =>
      match lux_response_to_openai(cr1.value()) {
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
  match lux_request_to_openai(req) {
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
  match lux_request_to_openai(req) {
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
  match lux_request_to_openai(req) {
    Ok(cr) => {
      assert_true(cr.value().contains("\"store\":true"))
      assert_true(cr.value().contains("\"extra_field\":\"v1\""))
      match openai_to_lux_request(cr.value()) {
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
/// 请求侧 reasoning 配置：enabled + effort → reasoning_effort 参数（o-series 标准）
test "lux_request_to_openai - reasoning config emits reasoning_effort" {
  let req = @lux.LucentRequest::new(
    "o3",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [@lux.LucentContent::text("Hello")]),
      ),
    ],
    None,
    None,
    @lux.LucentOptions::default(),
    None,
    Some(@lux.LucentReasoningConfig::new(Some(High), None)),
    None,
    None,
  )
  match lux_request_to_openai(req) {
    Ok(cr) => {
      let jv = @json.parse(cr.value())
      assert_eq(@internal.field_str(jv, "reasoning_effort"), Some("high"))
    }
    Err(_) => assert_true(false)
  }
}

///|
test "encode - image url maps to image_url array content" {
  let req = @lux.LucentRequest::new(
    "gpt-4o",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [
          @lux.LucentContent::text("看图"),
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
  match lux_request_to_openai(req) {
    Ok(cr) => {
      assert_true(cr.value().contains("\"type\":\"image_url\""))
      assert_true(cr.value().contains("https://x.com/a.png"))
      assert_true(cr.value().contains("\"type\":\"text\""))
    }
    Err(e) => fail("encode: \{e}")
  }
}

///|
test "encode - image inline maps to data uri image_url" {
  let req = @lux.LucentRequest::new(
    "gpt-4o",
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
  match lux_request_to_openai(req) {
    Ok(cr) =>
      assert_true(cr.value().contains("data:image/png;base64,iVBORw0KGgo"))
    Err(e) => fail("encode: \{e}")
  }
}

///|
test "encode - image file_uri yields unsupported diagnostic" {
  let req = @lux.LucentRequest::new(
    "gpt-4o",
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
  match lux_request_to_openai(req) {
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
/// === reasoning 契约测试 ===

///|
/// 入站：vLLM message.reasoning → LucentMessage.reasoning
test "openai_to_lux_response - vLLM reasoning captured" {
  let json = "{\"id\":\"c-1\",\"model\":\"qwen\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"Final answer\",\"reasoning\":\"step by step\"},\"finish_reason\":\"stop\"}]}"
  match openai_to_lux_response(json) {
    Ok(cr) =>
      match cr.value().choices[0].message.reasoning {
        Some(r) => assert_eq(r.text, "step by step")
        None => assert_true(false)
      }
    Err(e) => fail("decode: \{e}")
  }
}

///|
/// 入站：DeepSeek reasoning_content → LucentMessage.reasoning
test "openai_to_lux_response - DeepSeek reasoning_content captured" {
  let json = "{\"id\":\"c-1\",\"model\":\"deepseek\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"Final\",\"reasoning_content\":\"chain of thought\"},\"finish_reason\":\"stop\"}]}"
  match openai_to_lux_response(json) {
    Ok(cr) =>
      match cr.value().choices[0].message.reasoning {
        Some(r) => assert_eq(r.text, "chain of thought")
        None => assert_true(false)
      }
    Err(e) => fail("decode: \{e}")
  }
}

///|
/// 入站：无 reasoning 字段 → message.reasoning 为 None
test "openai_to_lux_response - no reasoning yields None" {
  let json = "{\"id\":\"c-1\",\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"Hello\"},\"finish_reason\":\"stop\"}]}"
  match openai_to_lux_response(json) {
    Ok(cr) => assert_eq(cr.value().choices[0].message.reasoning, None)
    Err(e) => fail("decode: \{e}")
  }
}

///|
/// 出站：LucentMessage.reasoning → message.reasoning（默认字段名）
test "lux_response_to_openai - reasoning emitted as message.reasoning" {
  let th = @lux.LucentThinking::visible("thought", None)
  let msg = @lux.LucentMessage::with_reasoning(
    Assistant,
    [@lux.LucentContent::text("answer")],
    Some(th),
  )
  let resp = @lux.LucentResponse::new(
    "c-1",
    "gpt-4o",
    None,
    [@lux.LucentChoice::new(0, msg, Stop, None)],
    None,
    None,
  )
  match lux_response_to_openai(resp) {
    Ok(cr) => {
      let jv = @json.parse(cr.value())
      match @internal.obj_get(jv, "choices") {
        Some(Array(cs)) =>
          match @internal.obj_get(cs[0], "message") {
            Some(m) =>
              assert_eq(@internal.field_str(m, "reasoning"), Some("thought"))
            None => assert_true(false)
          }
        _ => assert_true(false)
      }
    }
    Err(e) => fail("encode: \{e}")
  }
}

///|
/// 出站：provider_payload.reasoning_field 切换为 reasoning_content
test "lux_response_to_openai - reasoning_field switches to reasoning_content" {
  let th = @lux.LucentThinking::visible("thought", None)
  let msg = @lux.LucentMessage::with_reasoning(
    Assistant,
    [@lux.LucentContent::text("answer")],
    Some(th),
  )
  let resp = @lux.LucentResponse::new(
    "c-1",
    "deepseek",
    None,
    [@lux.LucentChoice::new(0, msg, Stop, None)],
    None,
    Some({ "reasoning_field": @json.parse("\"reasoning_content\"") }),
  )
  match lux_response_to_openai(resp) {
    Ok(cr) => {
      let jv = @json.parse(cr.value())
      match @internal.obj_get(jv, "choices") {
        Some(Array(cs)) =>
          match @internal.obj_get(cs[0], "message") {
            Some(m) =>
              assert_eq(
                @internal.field_str(m, "reasoning_content"),
                Some("thought"),
              )
            None => assert_true(false)
          }
        _ => assert_true(false)
      }
    }
    Err(e) => fail("encode: \{e}")
  }
}

///|
/// 出站：无 reasoning 时 message 不含 reasoning 字段
test "lux_response_to_openai - no reasoning yields plain message" {
  let msg = @lux.LucentMessage::new(Assistant, [
    @lux.LucentContent::text("answer"),
  ])
  let resp = @lux.LucentResponse::new(
    "c-1",
    "gpt-4o",
    None,
    [@lux.LucentChoice::new(0, msg, Stop, None)],
    None,
    None,
  )
  match lux_response_to_openai(resp) {
    Ok(cr) => {
      let jv = @json.parse(cr.value())
      match @internal.obj_get(jv, "choices") {
        Some(Array(cs)) =>
          match @internal.obj_get(cs[0], "message") {
            Some(m) => assert_eq(@internal.field_str(m, "reasoning"), None)
            None => assert_true(false)
          }
        _ => assert_true(false)
      }
    }
    Err(e) => fail("encode: \{e}")
  }
}

///|
/// round-trip：vLLM 入站 → IR → openai_chat 出站，reasoning 不丢
test "openai_chat round-trip preserves vLLM reasoning" {
  let inbound = "{\"id\":\"c-1\",\"model\":\"qwen\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"Final\",\"reasoning\":\"thought\"},\"finish_reason\":\"stop\"}]}"
  match openai_to_lux_response(inbound) {
    Ok(cr) =>
      match lux_response_to_openai(cr.value()) {
        Ok(out) => {
          let jv = @json.parse(out.value())
          match @internal.obj_get(jv, "choices") {
            Some(Array(cs)) =>
              match @internal.obj_get(cs[0], "message") {
                Some(m) =>
                  assert_eq(
                    @internal.field_str(m, "reasoning"),
                    Some("thought"),
                  )
                None => assert_true(false)
              }
            _ => assert_true(false)
          }
        }
        Err(e) => fail("encode: \{e}")
      }
    Err(e) => fail("decode: \{e}")
  }
}
