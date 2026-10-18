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
      let jv = @internal.parse_json_opt(s).unwrap()
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
      let jv = @internal.parse_json_opt(s).unwrap()
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
      let jv = @internal.parse_json_opt(s).unwrap()
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
      let jv = @internal.parse_json_opt(s).unwrap()
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
      let jv = @internal.parse_json_opt(s).unwrap()
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
test "openai_to_lux_response - detailed usage with reasoning and cached tokens" {
  let json = "{\"id\":\"chatcmpl-1\",\"object\":\"chat.completion\",\"model\":\"o3\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"Hello!\"},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":100,\"completion_tokens\":50,\"total_tokens\":150,\"completion_tokens_details\":{\"reasoning_tokens\":30},\"prompt_tokens_details\":{\"cached_tokens\":40}}}"
  match openai_to_lux_response(json) {
    Ok(cr) => {
      let u = cr.value().usage.unwrap_or(@lux.LucentUsage::new(0, 0, 0))
      assert_eq(u.prompt_tokens, 100)
      assert_eq(u.completion_tokens, 50)
      assert_eq(u.total_tokens, 150)
      assert_eq(u.reasoning_tokens, Some(30))
      assert_eq(u.cached_tokens, Some(40))
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
      let jv = @internal.parse_json_opt(s).unwrap()
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
      let jv = @internal.parse_json_opt(s).unwrap()
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
      let jv = @internal.parse_json_opt(s).unwrap()
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
test "openai_sse_to_events - reasoning_content emits BlockStart(Thinking)" {
  // DeepSeek/vLLM 风格：reasoning_content 出现在 delta 中
  let sse = "data: {\"choices\":[{\"delta\":{\"role\":\"assistant\"}}]}\n\ndata: {\"choices\":[{\"delta\":{\"reasoning_content\":\"Thinking\"}}]}\n\ndata: {\"choices\":[{\"delta\":{\"reasoning_content\":\" step\"}}]}\n\ndata: {\"choices\":[{\"delta\":{\"content\":\"Answer\"}}]}\n\ndata: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n"
  match openai_sse_to_events(sse) {
    Ok(cr) => {
      let events = cr.value()
      // 必须有 BlockStart(thinking_block_idx, Thinking) — 使用索引 1 避免与 text 块冲突
      let has_thinking_start = {
        let mut found = false
        for ev in events {
          match ev {
            BlockStart(1, Thinking) => found = true
            _ => ()
          }
        }
        found
      }
      assert_true(has_thinking_start)
      // 必须有 ThinkingDelta
      let has_thinking_delta = {
        let mut found = false
        for ev in events {
          match ev {
            BlockDelta(1, ThinkingDelta(_)) => found = true
            _ => ()
          }
        }
        found
      }
      assert_true(has_thinking_delta)
      // 必须有 BlockStart(0, Text) 在 content delta 之前
      let has_text_start = {
        let mut found = false
        for ev in events {
          match ev {
            BlockStart(0, Text) => found = true
            _ => ()
          }
        }
        found
      }
      assert_true(has_text_start)
      // 事件序列必须包含 BlockEnd（thinking 用索引 1，text 用索引 0）
      let has_thinking_end = {
        let mut found = false
        for ev in events {
          match ev {
            BlockEnd(1) => found = true
            _ => ()
          }
        }
        found
      }
      assert_true(has_thinking_end)
      let has_text_end = {
        let mut found = false
        for ev in events {
          match ev {
            BlockEnd(0) => found = true
            _ => ()
          }
        }
        found
      }
      assert_true(has_text_end)
      // Finish 必须存在
      let has_finish = {
        let mut found = false
        for ev in events {
          match ev {
            Finish(_) => found = true
            _ => ()
          }
        }
        found
      }
      assert_true(has_finish)
    }
    Err(e) => fail("sse decode error: \{e}")
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

// 注：请求 round-trip 的黑盒契约测试见 test/openai_test.mbt（外部调用者视角，断言更全），
// 此处不再保留同义的白盒拷贝。

///|
test "round trip - response decode then encode preserves id" {
  let json = "{\"id\":\"c-1\",\"object\":\"chat.completion\",\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"hi\"},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":1,\"completion_tokens\":1,\"total_tokens\":2}}"
  match openai_to_lux_response(json) {
    Ok(cr1) =>
      match lux_response_to_openai(cr1.value()) {
        Ok(cr2) => {
          let jv = @internal.parse_json_opt(cr2.value()).unwrap()
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
      let jv = @internal.parse_json_opt(cr.value()).unwrap()
      assert_eq(@internal.field_str(jv, "reasoning_effort"), Some("high"))
    }
    Err(_) => assert_true(false)
  }
}

///|
/// 入站 reasoning_effort → IR reasoning.effort（o-series / gpt-5 推理控制跨端延续）
test "openai_to_lux_request - reasoning_effort parses into IR" {
  let json = "{\"model\":\"o3\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"reasoning_effort\":\"high\"}"
  match openai_to_lux_request(json) {
    Ok(cr) =>
      match cr.value().reasoning {
        Some(rc) => {
          assert_eq(rc.enabled, true)
          assert_eq(rc.effort, Some(High))
        }
        None => assert_true(false)
      }
    Err(_) => assert_true(false)
  }
  // 不在 extras 里重复残留
  match openai_to_lux_request(json) {
    Ok(cr) => {
      let extras = cr.value().options.extras
      let mut leaked = false
      match extras {
        Some(m) => if m.get("reasoning_effort") != None { leaked = true }
        None => ()
      }
      assert_false(leaked)
    }
    Err(_) => assert_true(false)
  }
}

///|
/// minimal 档位在 IR 无对等 → 降级 Low + Degraded 诊断
test "openai_to_lux_request - reasoning_effort minimal degrades to low" {
  let json = "{\"model\":\"gpt-5\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"reasoning_effort\":\"minimal\"}"
  match openai_to_lux_request(json) {
    Ok(cr) => {
      match cr.value().reasoning {
        Some(rc) => assert_eq(rc.effort, Some(Low))
        None => assert_true(false)
      }
      let ds = cr.diagnostics()
      let mut found = false
      for d in ds {
        if d.field == "reasoning_effort" {
          found = true
        }
      }
      assert_true(found)
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
      let jv = @internal.parse_json_opt(cr.value()).unwrap()
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
    Some({
      "reasoning_field": @internal.parse_json_opt("\"reasoning_content\"").unwrap(),
    }),
  )
  match lux_response_to_openai(resp) {
    Ok(cr) => {
      let jv = @internal.parse_json_opt(cr.value()).unwrap()
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
      let jv = @internal.parse_json_opt(cr.value()).unwrap()
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
          let jv = @internal.parse_json_opt(out.value()).unwrap()
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

///|
/// #10（api-protocol-converter 最小测试矩阵）：Responses 只有 previous_response_id
/// 且无会话历史时，跨端出站（chat）必须拒绝转换（标准 §3.2）。
test "#10 previous_response_id standard field without history rejected" {
  let opts = @lux.LucentOptions::default().with_previous_response_id(
    Some("resp_123"),
  )
  let req = @lux.LucentRequest::new(
    "gpt-5.3",
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
  match lux_request_to_openai(req) {
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
  match lux_request_to_openai(req) {
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
/// #6（最小测试矩阵）：多工具调用流式参数增量。
/// OpenAI 流式中 tool_calls index 单调递增（0 → 1），每个 index 连续多帧
/// 累积 arguments；解码端按 index 切换块（BlockEnd 旧块 + BlockStart 新块）。
test "#6 openai_sse_to_events - multi tool call stream with deltas" {
  let sse = "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"c1\",\"type\":\"function\",\"function\":{\"name\":\"get_weather\",\"arguments\":\"{\\\"city\\\":\\\"Bei\"}}]}}]}\n\ndata: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"jing\\\"}\"}}]}}]}\n\ndata: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":1,\"id\":\"c2\",\"type\":\"function\",\"function\":{\"name\":\"send_email\",\"arguments\":\"{\\\"to\\\":\\\"a@b.c\\\"}\"}}]}}]}\n\ndata: {\"choices\":[{\"delta\":{},\"finish_reason\":\"tool_calls\"}]}\n\ndata: [DONE]\n\n"
  match openai_sse_to_events(sse) {
    Ok(cr) => {
      let events = cr.value()
      // 两个 tool 块：index 0（get_weather）+ index 1（send_email）
      let starts : Array[Int32] = []
      for ev in events {
        match ev {
          BlockStart(idx, ToolCall(_, name)) => {
            starts.push(idx)
            ignore(name)
          }
          _ => ()
        }
      }
      assert_eq(starts, [0, 1])
      // 两个工具块各自收到 arguments 增量
      let deltas : Array[Int32] = []
      for ev in events {
        match ev {
          BlockDelta(idx, ToolArgumentsDelta(_)) => deltas.push(idx)
          _ => ()
        }
      }
      assert_true(deltas.contains(0))
      assert_true(deltas.contains(1))
      // 末事件 Done
      assert_true(events[events.length() - 1] is Done)
    }
    Err(_) => assert_true(false)
  }
}

///|
/// === 补充白盒覆盖：请求编码未覆盖分支 ===

///|
/// tool_choice_to_json：None 与 SpecificTool 两个分支
/// （Auto / Required 已由 openai_to_lux_request - tool_choice variants 等覆盖）
test "encode - tool_choice none and specific_tool variants" {
  let cases : Array[(String, @lux.LucentToolChoice, String)] = [
    ("none", None, "\"tool_choice\":\"none\""),
    (
      "specific_tool",
      SpecificTool("get_weather"),
      "\"tool_choice\":{\"type\":\"function\",\"function\":{\"name\":\"get_weather\"}}",
    ),
  ]
  for tc in cases {
    let (label, choice, expect) = tc
    let req = @lux.LucentRequest::from_messages(
      "gpt-4o",
      None,
      [@lux.LucentMessage::new(User, [@lux.LucentContent::text("hi")])],
      None,
      Some(choice),
      @lux.LucentOptions::default(),
      None,
      None,
      None,
      None,
    )
    match lux_request_to_openai(req) {
      Ok(cr) =>
        if !cr.value().contains(expect) {
          fail("tool_choice \{label} not encoded")
        }
      Err(e) => fail("encode \{label} failed: \{e}")
    }
  }
}

///|
/// content_field_to_json / content_part_to_json 的 file / audio / video 分支：
/// openai-chat 无载体 → 显式 Unsupported 诊断，不静默丢弃。
/// 其中 video 同时走进「needs_array」数组分支（content_field_to_json）与
/// 逐 part 分支（content_part_to_json），file / audio 走字符串分支。
test "encode - unsupported content kinds emit explicit diagnostics" {
  let cases : Array[(Array[@lux.LucentContent], String)] = [
    (
      [@lux.LucentContent::file("application/pdf", Url("https://x.com/a.pdf"))],
      "content.file",
    ),
    (
      [@lux.LucentContent::audio("audio/mp3", Url("https://x.com/a.mp3"))],
      "content.audio",
    ),
    (
      [
        @lux.LucentContent::image("image/png", Url("https://x.com/a.png")),
        @lux.LucentContent::video("video/mp4", Url("https://x.com/a.mp4")),
      ],
      "content.video",
    ),
  ]
  for pair in cases {
    let (content, field) = pair
    let req = @lux.LucentRequest::new(
      "gpt-4o",
      None,
      [
        @lux.LucentConversationItem::message(
          @lux.LucentMessage::new(User, content),
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
        let mut found = false
        for d in cr.diagnostics() {
          if d.field == field && d.status == Unsupported {
            found = true
          }
        }
        assert_true(found)
      }
      Err(e) => fail("encode \{field} failed: \{e}")
    }
  }
}

///|
/// content_part_to_json 的 Refusal 分支 + message_to_json 的 refusal 字段拼接：
/// 请求侧 assistant 消息的 refusal 入独立字段，不入 content。
test "encode - refusal content in request message" {
  let req = @lux.LucentRequest::new(
    "gpt-4o",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(Assistant, [
          @lux.LucentContent::text("partial"),
          @lux.LucentContent::refusal("cannot help with that"),
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
      assert_true(cr.value().contains("\"refusal\":\"cannot help with that\""))
    Err(e) => fail("encode: \{e}")
  }
}

///|
/// ToolResult 的两种摆放：
/// - tool 角色消息只取 ToolResult，其余 part 走 message_to_json 的 `_ => ()`
/// - 非 tool 角色消息里的 ToolResult 被 content_part_to_json 丢弃（不入 content）
test "encode - tool_result routed by message role" {
  let tool_role = @lux.LucentRequest::new(
    "gpt-4o",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(Tool, [
          @lux.LucentContent::text("orphan"),
          @lux.LucentContent::tool_result("c1", [@lux.LucentContent::text("r")]),
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
  match lux_request_to_openai(tool_role) {
    Ok(cr) => {
      assert_true(cr.value().contains("\"tool_call_id\":\"c1\""))
      assert_true(cr.value().contains("\"content\":\"r\""))
    }
    Err(e) => fail("encode tool role: \{e}")
  }
  let user_role = @lux.LucentRequest::new(
    "gpt-4o",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [
          @lux.LucentContent::tool_result("c1", [@lux.LucentContent::text("r")]),
          @lux.LucentContent::text("tail"),
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
  match lux_request_to_openai(user_role) {
    Ok(cr) => assert_true(cr.value().contains("\"content\":\"tail\""))
    Err(e) => fail("encode user role: \{e}")
  }
}

///|
/// tools 构造：description 缺省时省略该字段（LucentTool::simple 总带 description）
test "encode - function tool without description omits field" {
  let req = @lux.LucentRequest::new(
    "gpt-4o",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [@lux.LucentContent::text("hi")]),
      ),
    ],
    Some([
      @lux.LucentTool::new("f", None, "{\"type\":\"object\"}", None, Function),
    ]),
    None,
    @lux.LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
  match lux_request_to_openai(req) {
    Ok(cr) => {
      assert_true(cr.value().contains("\"function\":{\"name\":\"f\""))
      assert_false(cr.value().contains("\"description\""))
    }
    Err(e) => fail("encode: \{e}")
  }
}

///|
/// options 分支：top_p / stop 数组 / structured_output=Text
test "encode - options top_p stop and structured output variants" {
  let cases : Array[(String, @lux.LucentOptions, String)] = [
    (
      "top_p",
      @lux.LucentOptions::new(
        None,
        Some(0.9),
        None,
        None,
        None,
        false,
        None,
        None,
        None,
        None,
      ),
      "\"top_p\":0.9",
    ),
    (
      "stop",
      @lux.LucentOptions::new(
        None,
        None,
        None,
        None,
        Some(["END", "STOP"]),
        false,
        None,
        None,
        None,
        None,
      ),
      "\"stop\":[\"END\",\"STOP\"]",
    ),
    (
      "structured_output",
      @lux.LucentOptions::new(
        None,
        None,
        None,
        None,
        None,
        false,
        None,
        Some(Text),
        None,
        None,
      ),
      "\"response_format\":{\"type\":\"text\"}",
    ),
  ]
  for c in cases {
    let (label, opts, expect) = c
    let req = @lux.LucentRequest::new(
      "gpt-4o",
      None,
      [
        @lux.LucentConversationItem::message(
          @lux.LucentMessage::new(User, [@lux.LucentContent::text("hi")]),
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
      Ok(cr) =>
        if !cr.value().contains(expect) {
          fail("option \{label} not encoded")
        }
      Err(e) => fail("encode \{label} failed: \{e}")
    }
  }
}

///|
/// reasoning disabled → 保守省略 reasoning_effort（o-series 无禁用值）
test "encode - reasoning disabled omits reasoning_effort" {
  let req = @lux.LucentRequest::new(
    "o3",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [@lux.LucentContent::text("hi")]),
      ),
    ],
    None,
    None,
    @lux.LucentOptions::default(),
    None,
    Some(@lux.LucentReasoningConfig::disabled()),
    None,
    None,
  )
  match lux_request_to_openai(req) {
    Ok(cr) => assert_false(cr.value().contains("reasoning_effort"))
    Err(e) => fail("encode: \{e}")
  }
}

///|
/// structured_output=JsonSchema：name / strict 从 extras 消费（标准 §6）
test "encode - json_schema consumes name and strict extras" {
  let opts = @lux.LucentOptions::new(
    None,
    None,
    None,
    None,
    None,
    false,
    None,
    Some(JsonSchema("{\"type\":\"object\"}")),
    None,
    Some({
      "json_schema_name": Json::string("answer"),
      "json_schema_strict": Json::boolean(true),
    }),
  )
  let req = @lux.LucentRequest::new(
    "gpt-4o",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [@lux.LucentContent::text("hi")]),
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
    Ok(cr) =>
      assert_true(
        cr
        .value()
        .contains(
          "\"response_format\":{\"type\":\"json_schema\",\"json_schema\":{" +
          "\"name\":\"answer\",\"strict\":true,\"schema\":{\"type\":\"object\"}}}",
        ),
      )
    Err(e) => fail("encode: \{e}")
  }
}

///|
/// extras 的 disable_parallel_tool_use（Anthropic 系）→ parallel_tool_calls（语义反向）
test "encode - extras disable_parallel_tool_use maps to parallel_tool_calls" {
  let cases : Array[(String, Json, String)] = [
    ("true", Json::boolean(true), "\"parallel_tool_calls\":false"),
    ("false", Json::boolean(false), "\"parallel_tool_calls\":true"),
  ]
  for c in cases {
    let (label, value, expect) = c
    let opts = @lux.LucentOptions::new(
      None,
      None,
      None,
      None,
      None,
      false,
      None,
      None,
      None,
      Some({ "disable_parallel_tool_use": value }),
    )
    let req = @lux.LucentRequest::new(
      "gpt-4o",
      None,
      [
        @lux.LucentConversationItem::message(
          @lux.LucentMessage::new(User, [@lux.LucentContent::text("hi")]),
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
        assert_true(cr.value().contains(expect))
        // 被消费，不得残留在输出 JSON
        assert_false(cr.value().contains("disable_parallel_tool_use"))
      }
      Err(e) => fail("encode \{label} failed: \{e}")
    }
  }
}

///|
/// extras 旧载荷回退：previous_response_id 从 extras 读取（标准字段路径已另测）
test "encode - extras previous_response_id degrades to diagnostic" {
  let opts = @lux.LucentOptions::new(
    None,
    None,
    None,
    None,
    None,
    false,
    None,
    None,
    None,
    Some({ "previous_response_id": Json::string("resp_extras") }),
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
  match lux_request_to_openai(req) {
    Ok(cr) => {
      assert_false(cr.value().contains("previous_response_id"))
      let mut found = false
      for d in cr.diagnostics() {
        if d.field == "options.previous_response_id" && d.status == Unsupported {
          found = true
        }
      }
      assert_true(found)
    }
    Err(e) => fail("encode: \{e}")
  }
}

///|
/// === 补充白盒覆盖：流编码未覆盖分支 ===

///|
/// ctx 预填（逐帧转换后续帧无 ConversationStart）：id / model / created 取自 ctx，
/// meta 缺省字段回退 chatcmpl-0 / "" / 0。
test "encode - stream ctx prefills chunk identity" {
  let cases : Array[(String, @lux.LucentConversationMeta, Array[String])] = [
    (
      "full meta",
      @lux.LucentConversationMeta::new_full(
        Some("chatcmpl-ctx"),
        Some("gpt-4o-mini"),
        None,
        Some(1710000000),
        None,
      ),
      [
        "\"id\":\"chatcmpl-ctx\"", "\"model\":\"gpt-4o-mini\"", "\"created\":1710000000",
      ],
    ),
    (
      "defaults",
      @lux.LucentConversationMeta::new(None, None, None),
      ["\"id\":\"chatcmpl-0\"", "\"model\":\"\"", "\"created\":0"],
    ),
  ]
  for c in cases {
    let (label, meta, expects) = c
    let events : Array[@lux.LucentStreamEvent] = [
      BlockDelta(0, @lux.LucentBlockDelta::text_delta("Hello")),
      Finish(Stop),
      Done,
    ]
    match lux_events_to_openai_sse_with_ctx(events, Some(meta)) {
      Ok(cr) => {
        let sse = cr.value()
        for want in expects {
          if !sse.contains(want) {
            fail("ctx \{label} missing \{want}")
          }
        }
      }
      Err(e) => fail("encode \{label} failed: \{e}")
    }
  }
}

///|
/// BlockDelta 的 ThinkingDelta / SignatureDelta / RefusalDelta / NativeDelta 分支，
/// 以及 BlockStart 非 ToolCall 类型的 `_ => ()` 分支。
test "encode - stream thinking/refusal/native deltas" {
  let events : Array[@lux.LucentStreamEvent] = [
    ConversationStart(@lux.LucentConversationMeta::new(None, None, None)),
    BlockStart(1, Thinking),
    BlockDelta(1, @lux.LucentBlockDelta::thinking_delta("reason")),
    BlockDelta(1, @lux.LucentBlockDelta::signature_delta("sig-abc")),
    BlockDelta(1, @lux.LucentBlockDelta::refusal_delta("cannot")),
    BlockDelta(
      1,
      @lux.LucentBlockDelta::native_delta("vendor", Json::string("x")),
    ),
    BlockStart(0, Text),
    BlockEnd(1),
    Finish(Stop),
    Done,
  ]
  match lux_events_to_openai_sse(events) {
    Ok(cr) => {
      let sse = cr.value()
      // thinking → reasoning_content
      assert_true(sse.contains("\"reasoning_content\":\"reason\""))
      // refusal 降级为 content 增量
      assert_true(sse.contains("\"content\":\"cannot\""))
      // signature / native 增量在 chat 端无载体：静默丢弃
      assert_false(sse.contains("sig-abc"))
      assert_false(sse.contains("vendor"))
    }
    Err(e) => fail("encode: \{e}")
  }
}

///|
/// Usage 的 reasoning_tokens / cached_tokens 细化分支
test "encode - stream usage detail tokens" {
  let events : Array[@lux.LucentStreamEvent] = [
    Usage(@lux.LucentUsage::full(100, 50, 150, Some(30), Some(40), None)),
    Done,
  ]
  match lux_events_to_openai_sse(events) {
    Ok(cr) => {
      let sse = cr.value()
      assert_true(
        sse.contains("\"completion_tokens_details\":{\"reasoning_tokens\":30}"),
      )
      assert_true(
        sse.contains("\"prompt_tokens_details\":{\"cached_tokens\":40}"),
      )
    }
    Err(e) => fail("encode: \{e}")
  }
}

///|
/// Error 帧 kind → OpenAI error.type 映射：RateLimit → rate_limit_error
test "encode - stream rate limit error" {
  let events : Array[@lux.LucentStreamEvent] = [
    Error(@lux.LucentError::new(RateLimit, "slow down", Some("429"))),
    Done,
  ]
  match lux_events_to_openai_sse(events) {
    Ok(cr) =>
      assert_true(
        cr
        .value()
        .contains(
          "data: {\"error\":{\"type\":\"rate_limit_error\",\"message\":\"slow down\"}}",
        ),
      )
    Err(e) => fail("encode: \{e}")
  }
}

///|
/// Error 帧 kind → OpenAI error.type 映射：InvalidRequest → invalid_request_error
test "encode - stream invalid request error" {
  let events : Array[@lux.LucentStreamEvent] = [
    Error(@lux.LucentError::new(InvalidRequest, "bad request", Some("400"))),
    Done,
  ]
  match lux_events_to_openai_sse(events) {
    Ok(cr) =>
      assert_true(
        cr
        .value()
        .contains(
          "data: {\"error\":{\"type\":\"invalid_request_error\",\"message\":\"bad request\"}}",
        ),
      )
    Err(e) => fail("encode: \{e}")
  }
}

///|
/// content_field_to_json 数组分支的兜底 `_ => ()`：
/// 消息同时含 Image（触发 needs_array）与非 Text/Image/Audio/Video 的 part
/// （此处 Thinking）——该 part 在数组循环中被跳过、不入 content 元素，
/// 但 content_part_to_json 侧会为它补一条 Unsupported 诊断。
test "encode - mixed image and non-media part takes array content form" {
  let req = @lux.LucentRequest::new(
    "gpt-4o",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [
          @lux.LucentContent::image("image/png", Url("https://x.com/a.png")),
          @lux.LucentContent::thinking("hidden chain", None),
          @lux.LucentContent::text("caption"),
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
      let s = cr.value()
      // needs_array 由 Image 触发 → 数组形式，text 与 image_url 各占一个元素
      // （不依赖元素顺序：Image 在前，Text 在后）
      assert_true(s.contains("\"content\":["))
      assert_true(s.contains("{\"type\":\"text\",\"text\":\"caption\"}"))
      assert_true(s.contains("\"type\":\"image_url\""))
      // 兜底分支跳过的 Thinking 不得成为 content 元素
      assert_false(s.contains("hidden chain"))
      // 但不得静默丢弃：显式 Unsupported 诊断
      let mut has_unsupported = false
      for d in cr.diagnostics() {
        if d.field == "content.thinking" && d.status == Unsupported {
          has_unsupported = true
        }
      }
      assert_true(has_unsupported)
    }
    Err(e) => fail("encode: \{e}")
  }
}

///|
/// Error 帧 kind → OpenAI error.type 全量映射
/// （RateLimit / InvalidRequest 已由上面两个专测覆盖，此处补齐剩余 kind）
test "encode - stream error kind maps to openai error type" {
  let cases : Array[(@lux.LucentErrorKind, String)] = [
    (InvalidRequest, "invalid_request_error"),
    (Authentication, "authentication_error"),
    (ServerError, "server_error"),
    (ContentFilter, "invalid_request_error"),
    (Native("vendor_timeout"), "vendor_timeout"),
  ]
  for c in cases {
    let (kind, error_type) = c
    let events : Array[@lux.LucentStreamEvent] = [
      Error(@lux.LucentError::new(kind, "boom", None)),
      Done,
    ]
    match lux_events_to_openai_sse(events) {
      Ok(cr) =>
        assert_true(
          cr
          .value()
          .contains(
            "data: {\"error\":{\"type\":\"" +
            error_type +
            "\",\"message\":\"boom\"}}",
          ),
        )
      Err(e) => fail("encode \{error_type} failed: \{e}")
    }
  }
}

///|
/// structured_output=JsonSchema 且 extras.json_schema_strict 为 false：
/// 显式下发 "strict":false（缺省/其他值才省略）
test "encode - json_schema strict false emits strict false" {
  let opts = @lux.LucentOptions::new(
    None,
    None,
    None,
    None,
    None,
    false,
    None,
    Some(JsonSchema("{\"type\":\"object\"}")),
    None,
    Some({
      "json_schema_name": Json::string("answer"),
      "json_schema_strict": Json::boolean(false),
    }),
  )
  let req = @lux.LucentRequest::new(
    "gpt-4o",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [@lux.LucentContent::text("hi")]),
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
    Ok(cr) =>
      assert_true(
        cr
        .value()
        .contains(
          "\"response_format\":{\"type\":\"json_schema\",\"json_schema\":{" +
          "\"name\":\"answer\",\"strict\":false,\"schema\":{\"type\":\"object\"}}}",
        ),
      )
    Err(e) => fail("encode: \{e}")
  }
}

///|
/// 出站：LucentUsage.reasoning_tokens / cached_tokens →
/// usage.completion_tokens_details / usage.prompt_tokens_details
/// （encode 方向：IR 有细化用量时必须下发 details 子对象，与 decode 测试对偶）
test "encode - usage details with reasoning and cached tokens emitted" {
  let usage = @lux.LucentUsage::full(100, 50, 150, Some(30), Some(40), None)
  let resp = @lux.LucentResponse::new(
    "c-1",
    "o3",
    None,
    [
      @lux.LucentChoice::new(
        0,
        @lux.LucentMessage::new(Assistant, [@lux.LucentContent::text("Hi")]),
        Stop,
        None,
      ),
    ],
    Some(usage),
    None,
  )
  match lux_response_to_openai(resp) {
    Ok(cr) => {
      let s = cr.value()
      assert_true(s.contains("\"usage\":{\"prompt_tokens\":100"))
      assert_true(s.contains("\"completion_tokens\":50"))
      assert_true(s.contains("\"total_tokens\":150"))
      assert_true(
        s.contains("\"completion_tokens_details\":{\"reasoning_tokens\":30}"),
      )
      assert_true(
        s.contains("\"prompt_tokens_details\":{\"cached_tokens\":40}"),
      )
    }
    Err(e) => fail("encode: \{e}")
  }
}

///|
/// 出站：provider_payload.reasoning_field 是无法识别的值时回落默认字段名 reasoning
/// （match 兜底分支：Some(Object) 但值不是 String("reasoning_content")）
test "encode - reasoning_field unrecognized falls back to reasoning" {
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
    Some({ "reasoning_field": Json::string("thinking") }),
  )
  match lux_response_to_openai(resp) {
    Ok(cr) => {
      let jv = @internal.parse_json_opt(cr.value()).unwrap()
      match @internal.obj_get(jv, "choices") {
        Some(Array(cs)) =>
          match @internal.obj_get(cs[0], "message") {
            Some(m) => {
              assert_eq(@internal.field_str(m, "reasoning"), Some("thought"))
              assert_eq(@internal.field_str(m, "reasoning_content"), None)
            }
            None => assert_true(false)
          }
        _ => assert_true(false)
      }
    }
    Err(e) => fail("encode: \{e}")
  }
}

///|
/// 非 function 的内置工具（web_search_preview 等）在 Chat 无载体，但 IR 能
/// 表达（LucentToolKind）：解码时保留 kind + Unsupported 诊断，不得静默丢弃
/// （契约 #12：不支持的能力必须显式报错）。
test "openai decode - non-function tool kind preserved with Unsupported diagnostic" {
  let json = "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"tools\":[{\"type\":\"function\",\"function\":{\"name\":\"f\",\"parameters\":{}}},{\"type\":\"web_search_preview\"},{\"type\":\"mcp\",\"name\":\"mt\"}]}"
  match openai_to_lux_request(json) {
    Ok(cr) => {
      match cr.value().tools {
        Some(ts) => {
          assert_eq(ts.length(), 3)
          assert_eq(ts[0].kind, Function)
          // web_search_preview → WebSearch，无 name 时用 kind tag 作占位名
          assert_eq(ts[1].kind, WebSearch)
          assert_eq(ts[1].name, "web_search")
          assert_eq(ts[2].kind, MCP)
          assert_eq(ts[2].name, "mt")
        }
        None => fail("expected tools")
      }
      // 两个非 function 工具各产生一条 Unsupported 诊断
      let mut unsupported = 0
      for d in cr.diagnostics() {
        if d.status == Unsupported && d.field == "tools.kind" {
          unsupported = unsupported + 1
        }
      }
      assert_eq(unsupported, 2)
    }
    Err(e) => fail("decode failed: \{e}")
  }
}

///|
/// 完全无 type 的条目不是合法工具定义，维持既有行为跳过（不误判为 Native）
test "openai decode - tool entry without type is skipped" {
  let json = "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"tools\":[{\"name\":\"no_fn\"}]}"
  match openai_to_lux_request(json) {
    Ok(cr) => {
      assert_eq(cr.value().tools, None)
      assert_eq(cr.diagnostics().length(), 0)
    }
    Err(e) => fail("decode failed: \{e}")
  }
}

///|
/// 非 function 工具 kind 的完整映射：file_search / code_interpreter /
/// computer_use / 未知 type（→ Native）
test "openai decode - all non-function tool kinds map correctly" {
  let json = "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"tools\":[{\"type\":\"file_search\"},{\"type\":\"code_interpreter\"},{\"type\":\"computer_use\"},{\"type\":\"vendor_builtin\"}]}"
  match openai_to_lux_request(json) {
    Ok(cr) => {
      match cr.value().tools {
        Some(ts) => {
          assert_eq(ts.length(), 4)
          assert_eq(ts[0].kind, FileSearch)
          assert_eq(ts[1].kind, CodeInterpreter)
          assert_eq(ts[2].kind, ComputerUse)
          // 未知 type 原样保留为 Native（不丢数据）
          assert_eq(ts[3].kind, Native("vendor_builtin"))
          // 无 name 时用 kind tag 作占位名
          assert_eq(ts[0].name, "file_search")
          assert_eq(ts[3].name, "vendor_builtin")
        }
        None => fail("expected tools")
      }
      assert_eq(cr.diagnostics().length(), 4)
    }
    Err(e) => fail("decode failed: \{e}")
  }
}
