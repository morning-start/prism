///|
/// convert_* 组合入口测试 — 中转站（场景 2）协议 A → 协议 B 转发
///
/// 原则（遵循项目约定）：
///   1. 测试数据由 IR 类型构造器 + 适配器编码产生，不手写 JSON
///   2. source 侧用 openai 编码，target 侧用 messages 解码验证语义保持

///|
test "openai stream to responses stream - full event sequence" {
  // 模拟 OpenAI Chat Completions 流式响应（包含 reasoning_content）
  let openai_sse = "data: {\"id\":\"c1\",\"object\":\"chat.completion.chunk\",\"created\":1000,\"model\":\"gpt-4\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\"}}]}\n\ndata: {\"id\":\"c1\",\"object\":\"chat.completion.chunk\",\"created\":1000,\"model\":\"gpt-4\",\"choices\":[{\"index\":0,\"delta\":{\"reasoning_content\":\"thinking\"}}]}\n\ndata: {\"id\":\"c1\",\"object\":\"chat.completion.chunk\",\"created\":1000,\"model\":\"gpt-4\",\"choices\":[{\"index\":0,\"delta\":{\"reasoning_content\":\" step\"}}]}\n\ndata: {\"id\":\"c1\",\"object\":\"chat.completion.chunk\",\"created\":1000,\"model\":\"gpt-4\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"\\n\\n\"}}]}\n\ndata: {\"id\":\"c1\",\"object\":\"chat.completion.chunk\",\"created\":1000,\"model\":\"gpt-4\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hello\"}}]}\n\ndata: {\"id\":\"c1\",\"object\":\"chat.completion.chunk\",\"created\":1000,\"model\":\"gpt-4\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}]}\n\ndata: {\"id\":\"c1\",\"object\":\"chat.completion.chunk\",\"created\":1000,\"model\":\"gpt-4\",\"choices\":[],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":5,\"total_tokens\":15}}\n\ndata: [DONE]\n\n"

  match @sdk.convert_stream("openai", openai_sse, "responses") {
    Ok(cr) => {
      let sse = cr.value()
      // 必须包含 response.created
      assert_true(sse.contains("event: response.created"))
      // 必须包含 response.output_item.added（reasoning item）
      assert_true(sse.contains("response.output_item.added"))
      // 必须包含 reasoning_summary_text.delta（AI SDK 消费该事件，reasoning_text.delta 会被忽略）
      assert_true(sse.contains("response.reasoning_summary_text.delta"))
      // 必须包含 content_part.added
      assert_true(sse.contains("response.content_part.added"))
      // 必须包含 output_text.delta
      assert_true(sse.contains("response.output_text.delta"))
      // 必须包含 output_text.done
      assert_true(sse.contains("response.output_text.done"))
      // 必须包含 response.completed（只出现一次）
      let completed_count = sse.split("event: response.completed").length() - 1
      assert_eq(completed_count, 1)
      // 不应包含 [DONE]
      assert_false(sse.contains("[DONE]"))
      // 输出每个事件行用于调试
      let lines = sse.split("\n").to_array()
      let mut j = 0
      while j < lines.length() {
        let line = lines[j]
        if line.has_prefix("event: ") {
          // 打印事件类型
          let _ = line.length() // 确保不 panic
        }
        j = j + 1
      }
      // 调试：统计所有事件类型
      let event_type_counts : Map[String, Int] = Map([])
      let all_lines = sse.split("\n").to_array()
      let mut j = 0
      while j < all_lines.length() {
        let line = all_lines[j]
        if line.has_prefix("event: ") {
          let etype = line[7:].to_owned()
          match event_type_counts.get(etype) {
            Some(n) => event_type_counts[etype] = n + 1
            None => event_type_counts[etype] = 1
          }
        }
        j = j + 1
      }
      // 检查关键事件是否存在
      let has_output_text_done = sse.contains("response.output_text.done")
      let has_reasoning_done = sse.contains(
        "response.reasoning_summary_part.done",
      )
      let has_completed = sse.contains("response.completed")
      let has_hello = sse.contains("Hello")
      // 断言：output_text.done 必须存在
      assert_true(has_output_text_done)
      // 断言：reasoning_summary_part.done 应只出现一次
      if has_reasoning_done {
        let reasoning_done_count = sse
          .split("event: response.reasoning_summary_part.done")
          .length() -
          1
        assert_eq(reasoning_done_count, 1)
      }
      // 断言：response.completed 只出现一次
      let completed_count = sse.split("event: response.completed").length() - 1
      assert_eq(completed_count, 1)
      // 断言：不应包含 [DONE]
      assert_false(sse.contains("[DONE]"))
      // 断言：应包含文本内容
      assert_true(has_hello)
    }
    Err(e) => fail("convert_stream error: \{e}")
  }
}

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
