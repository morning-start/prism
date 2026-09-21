///|
/// Agent 循环回填闭环测试（T2）
///
/// 覆盖：
///   - @sdk.Prism::events_to_context：TextDelta 合并 + ToolCall 累积回填
///   - lucent_events_to_prism 工具块累积修复：openai/messages 的
///     BlockStart(ToolCall)+BlockDelta(ToolArgumentsDelta) 路径此前被
///     完全丢弃（只认 ItemStart），默认 provider 流式 tool call 静默丢失
///   - 端到端：SSE 解码 → 回填 Context → 第二轮编码（两 provider）

///|
/// === events_to_context：文本回合 ===
test "events_to_context - text deltas merge into one assistant message" {
  let events : Array[@sdk.PrismEvent] = [
    TextDelta("Hello"),
    TextDelta(" world"),
    Finish(Stop),
  ]
  let ctx = @sdk.Prism::new().events_to_context(
    @sdk.Context::new().add_user("hi"),
    events,
  )
  assert_eq(ctx.messages.length(), 2)
  assert_eq(ctx.messages[1].role, "assistant")
  assert_eq(ctx.messages[1].content, "Hello world")
  assert_eq(ctx.messages[1].tool_calls.length(), 0)
}

///|
/// === events_to_context：工具调用回合 ===
test "events_to_context - tool call events backfill as ToolUse" {
  let events : Array[@sdk.PrismEvent] = [
    TextDelta("checking"),
    ToolCall(
      @sdk.PrismToolCall::new("call_1", "get_weather", "{\"city\":\"SH\"}"),
    ),
    Finish(ToolCalls),
  ]
  let ctx = @sdk.Prism::new().events_to_context(
    @sdk.Context::new().add_user("weather?"),
    events,
  )
  assert_eq(ctx.messages.length(), 2)
  let turn = ctx.messages[1]
  assert_eq(turn.content, "checking")
  assert_eq(turn.tool_calls.length(), 1)
  assert_eq(turn.tool_calls[0].id, "call_1")
  assert_eq(turn.tool_calls[0].name, "get_weather")
  assert_eq(turn.tool_calls[0].arguments_json, "{\"city\":\"SH\"}")
  // 回填后 IR 形态：assistant Message 含 Text + ToolUse
  let req = @sdk.context_to_lux_request(ctx, "m", @sdk.PrismOptions::default())
  match req.conversation[1] {
    Message(m) => {
      assert_eq(m.content.length(), 2)
      match m.content[1] {
        ToolUse(tu) => assert_eq(tu.name, "get_weather")
        _ => fail("expected ToolUse content")
      }
    }
    _ => fail("expected assistant Message")
  }
}

///|
test "events_to_context - multiple tool calls in one turn" {
  let events : Array[@sdk.PrismEvent] = [
    ToolCall(@sdk.PrismToolCall::new("c1", "f1", "{}")),
    ToolCall(@sdk.PrismToolCall::new("c2", "f2", "{\"a\":1}")),
    Finish(ToolCalls),
  ]
  let ctx = @sdk.Prism::new().events_to_context(
    @sdk.Context::new().add_user("go"),
    events,
  )
  assert_eq(ctx.messages[1].tool_calls.length(), 2)
  let req = @sdk.context_to_lux_request(ctx, "m", @sdk.PrismOptions::default())
  match req.conversation[1] {
    Message(m) => assert_eq(m.content.length(), 2)
    _ => fail("expected assistant Message with 2 ToolUse blocks")
  }
}

///|
test "events_to_context - empty turn appends nothing" {
  let events : Array[@sdk.PrismEvent] = [Finish(Stop)]
  let ctx = @sdk.Prism::new().events_to_context(
    @sdk.Context::new().add_user("hi"),
    events,
  )
  assert_eq(ctx.messages.length(), 1)
}

///|
/// === 核心修复回归：openai 流式 tool call 不再被丢弃 ===
/// 真实 OpenAI Chat Completions SSE 线格式（首帧 id+name，后续帧 arguments 增量）
test "decode_sse - openai streaming tool call accumulates arguments" {
  let sse = "data: {\"id\":\"cc1\",\"object\":\"chat.completion.chunk\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\"}}]}\n\n" +
    "data: {\"id\":\"cc1\",\"object\":\"chat.completion.chunk\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"call_1\",\"type\":\"function\",\"function\":{\"name\":\"get_weather\",\"arguments\":\"\"}}]}}]}\n\n" +
    "data: {\"id\":\"cc1\",\"object\":\"chat.completion.chunk\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"{\\\"city\\\"\"}}]}}]}\n\n" +
    "data: {\"id\":\"cc1\",\"object\":\"chat.completion.chunk\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\":\\\"SH\\\"}\"}}]}}]}\n\n" +
    "data: {\"id\":\"cc1\",\"object\":\"chat.completion.chunk\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"tool_calls\"}]}\n\n" +
    "data: [DONE]\n\n"
  let p = @sdk.Prism::new().with_provider("openai")
  match p.decode_sse(sse) {
    Ok(events) => {
      let mut tool_call : @sdk.PrismToolCall? = None
      for ev in events {
        match ev {
          ToolCall(tc) => tool_call = Some(tc)
          _ => ()
        }
      }
      match tool_call {
        Some(tc) => {
          assert_eq(tc.id, "call_1")
          assert_eq(tc.name, "get_weather")
          assert_eq(tc.arguments_json, "{\"city\":\"SH\"}")
        }
        None => fail("openai streaming tool call was dropped")
      }
    }
    Err(e) => fail("decode_sse failed: " + e)
  }
}

///|
/// messages（Anthropic）流式 tool call：content_block_start + input_json_delta
test "decode_sse - messages streaming tool call accumulates arguments" {
  let sse = "event: message_start\ndata: {\"type\":\"message_start\",\"message\":{\"id\":\"msg_1\",\"type\":\"message\",\"role\":\"assistant\",\"content\":[],\"model\":\"claude-sonnet-4-5\",\"stop_reason\":null,\"usage\":{\"input_tokens\":10,\"output_tokens\":1}}}\n\n" +
    "event: content_block_start\ndata: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"tool_use\",\"id\":\"toolu_1\",\"name\":\"get_weather\",\"input\":{}}}\n\n" +
    "event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\"{\\\"city\\\"\"}}\n\n" +
    "event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\":\\\"SH\\\"}\"}}\n\n" +
    "event: content_block_stop\ndata: {\"type\":\"content_block_stop\",\"index\":0}\n\n" +
    "event: message_delta\ndata: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"tool_use\"},\"usage\":{\"output_tokens\":20}}\n\n" +
    "event: message_stop\ndata: {\"type\":\"message_stop\"}\n\n"
  let p = @sdk.Prism::new().with_provider("messages")
  match p.decode_sse(sse) {
    Ok(events) => {
      let mut tool_call : @sdk.PrismToolCall? = None
      for ev in events {
        match ev {
          ToolCall(tc) => tool_call = Some(tc)
          _ => ()
        }
      }
      match tool_call {
        Some(tc) => {
          assert_eq(tc.id, "toolu_1")
          assert_eq(tc.name, "get_weather")
          assert_eq(tc.arguments_json, "{\"city\":\"SH\"}")
        }
        None => fail("messages streaming tool call was dropped")
      }
    }
    Err(e) => fail("decode_sse failed: " + e)
  }
}

///|
/// === 端到端：SSE → 回填 → 第二轮编码（T1+T2 闭环验收）===
test "agent loop round 2 - openai events backfill then re-encode" {
  let sse = "data: {\"id\":\"cc1\",\"object\":\"chat.completion.chunk\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"call_1\",\"type\":\"function\",\"function\":{\"name\":\"get_weather\",\"arguments\":\"{\\\"city\\\":\\\"SH\\\"}\"}}]}}]}\n\n" +
    "data: {\"id\":\"cc1\",\"object\":\"chat.completion.chunk\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"tool_calls\"}]}\n\n" +
    "data: [DONE]\n\n"
  let p = @sdk.Prism::new().with_provider("openai")
  let ctx0 = @sdk.Context::new().add_user("weather?")
  match p.decode_sse(sse) {
    Ok(events) => {
      let ctx1 = p.events_to_context(ctx0, events)
      let ctx2 = ctx1.add_tool_result("call_1", "{\"temp\":26}", false)
      assert_eq(ctx2.messages.length(), 3)
      let req = @sdk.context_to_lux_request(
        ctx2,
        "gpt-4o",
        @sdk.PrismOptions::default(),
      )
      match @openai.lux_request_to_openai(req) {
        Ok(cr) => {
          let json = cr.value()
          assert_true(json.contains("\"tool_calls\""))
          assert_true(json.contains("\"role\":\"tool\""))
          let tc_pos = json.split("\"tool_calls\"").to_array()[0].length()
          let tool_pos = json.split("\"role\":\"tool\"").to_array()[0].length()
          assert_true(tc_pos < tool_pos)
        }
        Err(e) => fail("round 2 encode failed: " + e)
      }
    }
    Err(e) => fail("decode_sse failed: " + e)
  }
}

///|
test "agent loop round 2 - messages events backfill then re-encode" {
  let sse = "event: content_block_start\ndata: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"tool_use\",\"id\":\"toolu_1\",\"name\":\"get_weather\",\"input\":{}}}\n\n" +
    "event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\"{\\\"city\\\":\\\"SH\\\"}\"}}\n\n" +
    "event: content_block_stop\ndata: {\"type\":\"content_block_stop\",\"index\":0}\n\n" +
    "event: message_delta\ndata: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"tool_use\"}}}\n\n"
  let p = @sdk.Prism::new().with_provider("messages")
  let ctx0 = @sdk.Context::new().add_user("weather?")
  match p.decode_sse(sse) {
    Ok(events) => {
      let ctx1 = p.events_to_context(ctx0, events)
      let ctx2 = ctx1.add_tool_result("toolu_1", "{\"temp\":26}", false)
      let req = @sdk.context_to_lux_request(
        ctx2,
        "claude-sonnet-4-5",
        @sdk.PrismOptions::default(),
      )
      match @messages.lux_request_to_messages(req) {
        Ok(cr) => {
          let json = cr.value()
          assert_true(json.contains("\"type\":\"tool_use\""))
          assert_true(json.contains("\"type\":\"tool_result\""))
          let use_pos = json.split("\"type\":\"tool_use\"").to_array()[0].length()
          let res_pos = json.split("\"type\":\"tool_result\"").to_array()[0].length()
          assert_true(use_pos < res_pos)
        }
        Err(e) => fail("round 2 encode failed: " + e)
      }
    }
    Err(e) => fail("decode_sse failed: " + e)
  }
}
