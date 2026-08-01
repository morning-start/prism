///|
/// convert_* 组合入口测试 — 中转站（场景 2）协议 A → 协议 B 转发
///
/// 原则（遵循项目约定）：
///   1. 测试数据由 IR 类型构造器 + 适配器编码产生，不手写 JSON
///   2. source 侧用 openai_chat 编码，target 侧用 anthropic 解码验证语义保持

///|
/// 标准请求 → openai_chat JSON（source 侧输入）
fn openai_chat_req_json() -> Result[String, String] {
  let req = @lux.LucentRequest::new(
    "gpt-4o",
    Some([@lux.LucentContent::text("You are helpful")]),
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(@lux.User, [@lux.LucentContent::text("Hi")]),
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
  @openai_chat.lux_request_to_openai_chat(req)
}

///|
/// 标准响应 → openai_chat JSON（source 侧输入）
fn openai_chat_resp_json() -> Result[String, String] {
  let resp = @lux.LucentResponse::new(
    "resp-1",
    "gpt-4o",
    None,
    [
      @lux.LucentChoice::new(
        0,
        @lux.LucentMessage::new(@lux.Assistant, [
          @lux.LucentContent::text("Hi back"),
        ]),
        @lux.Stop,
        None,
      ),
    ],
    Some(@lux.LucentUsage::new(10, 5, 15)),
    None,
  )
  @openai_chat.lux_response_to_openai_chat(resp)
}

///|
/// 标准事件流 → openai_chat SSE（source 侧输入）
fn openai_chat_sse() -> Result[String, String] {
  let events : Array[@lux.LucentStreamEvent] = [
    @lux.ConversationStart(@lux.LucentConversationMeta::new(None, None, None)),
    @lux.BlockStart(0, @lux.Text),
    @lux.BlockDelta(0, @lux.LucentBlockDelta::text_delta("Hello")),
    @lux.BlockEnd(0),
    @lux.Finish(@lux.Stop),
    @lux.Done,
  ]
  @openai_chat.lux_events_to_openai_chat_sse(events)
}

///|
/// === convert_request ===

///|
test "convert_request - openai-chat to anthropic" {
  match openai_chat_req_json() {
    Ok(json) =>
      match convert_request("openai-chat", json, "anthropic") {
        Ok(target_json) =>
          match @anthropic.anthropic_to_lux_request(target_json) {
            Ok(req) => {
              assert_eq(req.model, "gpt-4o")
              assert_eq(req.conversation.length(), 1)
            }
            Err(e) => fail("target decode failed: \{e}")
          }
        Err(e) => fail("convert_request failed: \{e}")
      }
    Err(e) => fail("encode source failed: \{e}")
  }
}

///|
test "convert_request - unknown source returns error" {
  match convert_request("no-such-provider", "{}", "anthropic") {
    Err(e) => assert_true(e.contains("unknown provider"))
    Ok(_) => fail("expected error")
  }
}

///|
test "convert_request - unknown target returns error" {
  match openai_chat_req_json() {
    Ok(json) =>
      match convert_request("openai-chat", json, "no-such-provider") {
        Err(e) => assert_true(e.contains("unknown provider"))
        Ok(_) => fail("expected error")
      }
    Err(e) => fail("encode source failed: \{e}")
  }
}

///|
/// === convert_response ===

///|
test "convert_response - openai-chat to anthropic" {
  match openai_chat_resp_json() {
    Ok(json) =>
      match convert_response("openai-chat", json, "anthropic") {
        Ok(target_json) =>
          match @anthropic.anthropic_to_lux_response(target_json) {
            Ok(resp) => {
              assert_eq(resp.id, "resp-1")
              assert_eq(resp.model, "gpt-4o")
              assert_eq(resp.choices.length(), 1)
            }
            Err(e) => fail("target response decode failed: \{e}")
          }
        Err(e) => fail("convert_response failed: \{e}")
      }
    Err(e) => fail("encode response failed: \{e}")
  }
}

///|
test "convert_response - unknown provider returns error" {
  match convert_response("nope", "{}", "anthropic") {
    Err(e) => assert_true(e.contains("unknown provider"))
    Ok(_) => fail("expected error")
  }
}

///|
/// === convert_stream ===

///|
test "convert_stream - openai-chat to anthropic" {
  match openai_chat_sse() {
    Ok(sse) =>
      match convert_stream("openai-chat", sse, "anthropic") {
        Ok(target_sse) =>
          match @anthropic.anthropic_sse_to_events(target_sse) {
            Ok(events) => assert_true(events.length() > 0)
            Err(e) => fail("target sse decode failed: \{e}")
          }
        Err(e) => fail("convert_stream failed: \{e}")
      }
    Err(e) => fail("encode sse failed: \{e}")
  }
}

///|
test "convert_stream - unknown provider returns error" {
  match convert_stream("nope", "data: {}", "anthropic") {
    Err(e) => assert_true(e.contains("unknown provider"))
    Ok(_) => fail("expected error")
  }
}
