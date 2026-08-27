///|
/// convert_* 组合入口测试 — 中转站（场景 2）协议 A → 协议 B 转发
///
/// 原则（遵循项目约定）：
///   1. 测试数据由 IR 类型构造器 + 适配器编码产生，不手写 JSON
///   2. source 侧用 openai 编码，target 侧用 messages 解码验证语义保持

///|
/// 标准请求 → openai JSON（source 侧输入）
fn openai_req_json() -> Result[String, String] {
  let req = @lux.LucentRequest::new(
    "gpt-4o",
    Some([@lux.LucentContent::text("You are helpful")]),
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [@lux.LucentContent::text("Hi")]),
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
  match @openai.lux_request_to_openai(req) {
    Ok(cr) => Ok(cr.value())
    Err(e) => Err(e)
  }
}

///|
/// 标准响应 → openai JSON（source 侧输入）
fn openai_resp_json() -> Result[String, String] {
  let resp = @lux.LucentResponse::new(
    "resp-1",
    "gpt-4o",
    None,
    [
      @lux.LucentChoice::new(
        0,
        @lux.LucentMessage::new(Assistant, [@lux.LucentContent::text("Hi back")]),
        Stop,
        None,
      ),
    ],
    Some(@lux.LucentUsage::new(10, 5, 15)),
    None,
  )
  match @openai.lux_response_to_openai(resp) {
    Ok(cr) => Ok(cr.value())
    Err(e) => Err(e)
  }
}

///|
/// 标准事件流 → openai SSE（source 侧输入）
fn openai_sse() -> Result[String, String] {
  let events : Array[@lux.LucentStreamEvent] = [
    ConversationStart(@lux.LucentConversationMeta::new(None, None, None)),
    BlockStart(0, Text),
    BlockDelta(0, @lux.LucentBlockDelta::text_delta("Hello")),
    BlockEnd(0),
    Finish(Stop),
    Done,
  ]
  match @openai.lux_events_to_openai_sse(events) {
    Ok(cr) => Ok(cr.value())
    Err(e) => Err(e)
  }
}

///|
/// === convert_request ===

///|
test "convert_request - openai to messages" {
  match openai_req_json() {
    Ok(json) =>
      match convert_request("openai", json, "messages") {
        Ok(cr) => {
          let target_json = cr.value()
          match @messages.messages_to_lux_request(target_json) {
            Ok(cr2) => {
              let req = cr2.value()
              assert_eq(req.model, "gpt-4o")
              assert_eq(req.conversation.length(), 1)
            }
            Err(e) => fail("target decode failed: \{e}")
          }
        }
        Err(e) => fail("convert_request failed: \{e}")
      }
    Err(e) => fail("encode source failed: \{e}")
  }
}

///|
test "convert_request - unknown source returns error" {
  match convert_request("no-such-provider", "{}", "messages") {
    Err(e) => assert_true(e.contains("unknown provider"))
    Ok(_) => fail("expected error")
  }
}

///|
test "convert_request - unknown target returns error" {
  match openai_req_json() {
    Ok(json) =>
      match convert_request("openai", json, "no-such-provider") {
        Err(e) => assert_true(e.contains("unknown provider"))
        Ok(_) => fail("expected error")
      }
    Err(e) => fail("encode source failed: \{e}")
  }
}

///|
/// === convert_response ===

///|
test "convert_response - openai to messages" {
  match openai_resp_json() {
    Ok(json) =>
      match convert_response("openai", json, "messages") {
        Ok(cr) => {
          let target_json = cr.value()
          match @messages.messages_to_lux_response(target_json) {
            Ok(cr2) => {
              let resp = cr2.value()
              assert_eq(resp.id, "resp-1")
              assert_eq(resp.model, "gpt-4o")
              assert_eq(resp.choices.length(), 1)
            }
            Err(e) => fail("target response decode failed: \{e}")
          }
        }
        Err(e) => fail("convert_response failed: \{e}")
      }
    Err(e) => fail("encode response failed: \{e}")
  }
}

///|
test "convert_response - unknown provider returns error" {
  match convert_response("nope", "{}", "messages") {
    Err(e) => assert_true(e.contains("unknown provider"))
    Ok(_) => fail("expected error")
  }
}

///|
/// === convert_stream ===

///|
test "convert_stream - openai to messages" {
  match openai_sse() {
    Ok(sse) =>
      match convert_stream("openai", sse, "messages") {
        Ok(cr) => {
          let target_sse = cr.value()
          match @messages.messages_sse_to_events(target_sse) {
            Ok(cr2) => assert_true(cr2.value().length() > 0)
            Err(e) => fail("target sse decode failed: \{e}")
          }
        }
        Err(e) => fail("convert_stream failed: \{e}")
      }
    Err(e) => fail("encode sse failed: \{e}")
  }
}

///|
test "convert_stream - unknown provider returns error" {
  match convert_stream("nope", "data: {}", "messages") {
    Err(e) => assert_true(e.contains("unknown provider"))
    Ok(_) => fail("expected error")
  }
}

///|
/// === convert_response_with_meta（D8 信封透出）===

///|
test "convert_response_with_meta - carries source" {
  match openai_resp_json() {
    Ok(json) =>
      match convert_response_with_meta("openai", json, "messages") {
        Ok(cr) => {
          // value 可解析为 target JSON
          let target_json = cr.value()
          match @messages.messages_to_lux_response(target_json) {
            Ok(cr2) => {
              let resp = cr2.value()
              assert_eq(resp.id, "resp-1")
              assert_eq(resp.model, "gpt-4o")
            }
            Err(e) => fail("target response decode failed: \{e}")
          }
          // meta 信封含 source_provider
          assert_eq(cr.meta.source_provider, "openai")
        }
        Err(e) => fail("convert_response_with_meta failed: \{e}")
      }
    Err(e) => fail("encode response failed: \{e}")
  }
}

///|
test "convert_response_with_meta - unknown provider returns error" {
  match convert_response_with_meta("nope", "{}", "messages") {
    Err(e) => assert_true(e.contains("unknown provider"))
    Ok(_) => fail("expected error")
  }
}
