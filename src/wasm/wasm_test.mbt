///|
/// WASM 导出层测试 — 6 个通用 IR 函数 + 5 个 SDK API
///
/// 黑盒测试，验证 String 进出的纯函数行为。

///|
/// === wasm_to_lux_request（解码请求）===

///|
test "wasm_to_lux_request - openai decode" {
  let json_str = "{\"model\":\"gpt-4o\",\"messages\":[{\"role\":\"user\",\"content\":\"Hi\"}]}"
  let result = wasm_to_lux_request("openai", json_str)
  // 成功时应返回 LucentRequest JSON
  assert_true(result.contains("model"))
  assert_true(result.contains("conversation"))
}

///|
test "wasm_to_lux_request - unknown provider returns error" {
  let result = wasm_to_lux_request("unknown-provider", "{}")
  assert_true(result.contains("error"))
  assert_true(result.contains("unknown provider"))
}

///|
test "wasm_to_lux_request - invalid JSON returns error" {
  let result = wasm_to_lux_request("openai", "{invalid}")
  assert_true(result.contains("error"))
}

///|
/// === wasm_lux_request_to_provider（编码请求）===

///|
test "wasm_lux_request_to_provider - openai encode" {
  let msg = @lux.LucentMessage::new(User, [@lux.LucentContent::text("Hello")])
  let req = @lux.LucentRequest::from_messages(
    "gpt-4o",
    None,
    [msg],
    None,
    None,
    @lux.LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
  let json_str = req.to_json().stringify()
  let result = wasm_lux_request_to_provider("openai", json_str)
  assert_true(result.contains("model"))
  assert_true(result.contains("messages"))
}

///|
test "wasm_lux_request_to_provider - unknown provider returns error" {
  let msg = @lux.LucentMessage::new(User, [@lux.LucentContent::text("Hi")])
  let req = @lux.LucentRequest::from_messages(
    "test",
    None,
    [msg],
    None,
    None,
    @lux.LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
  let json_str = req.to_json().stringify()
  let result = wasm_lux_request_to_provider("invalid", json_str)
  assert_true(result.contains("error"))
  assert_true(result.contains("unknown provider"))
}

///|
test "wasm_lux_request_to_provider - invalid JSON returns parse error" {
  let result = wasm_lux_request_to_provider("openai", "not json")
  assert_true(result.contains("json parse error"))
}

///|
/// === wasm_to_lux_response（解码响应）===

///|
test "wasm_to_lux_response - openai decode" {
  let resp_json = "{\"id\":\"chatcmpl-1\",\"object\":\"chat.completion\",\"created\":123,\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"Hello!\"},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":5,\"completion_tokens\":3,\"total_tokens\":8}}"
  let result = wasm_to_lux_response("openai", resp_json)
  // 成功时应返回 LucentResponse JSON
  assert_true(result.contains("id"))
}

///|
test "wasm_to_lux_response - unknown provider returns error" {
  let result = wasm_to_lux_response("nobody", "{}")
  assert_true(result.contains("error"))
}

///|
/// === wasm_lux_response_to_provider（编码响应）===

///|
test "wasm_lux_response_to_provider - openai encode" {
  let content = [@lux.LucentContent::text("Hi")]
  let msg = @lux.LucentMessage::new(Assistant, content)
  let choice = @lux.LucentChoice::new(0, msg, Stop, None)
  let resp = @lux.LucentResponse::new(
    "resp-1",
    "gpt-4o",
    None,
    [choice],
    None,
    None,
  )
  let json_str = resp.to_json().stringify()
  let result = wasm_lux_response_to_provider("openai", json_str)
  assert_true(result.contains("choices"))
}

///|
test "wasm_lux_response_to_provider - unknown provider returns error" {
  let content = [@lux.LucentContent::text("Hi")]
  let msg = @lux.LucentMessage::new(Assistant, content)
  let choice = @lux.LucentChoice::new(0, msg, Stop, None)
  let resp = @lux.LucentResponse::new("r", "m", None, [choice], None, None)
  let json_str = resp.to_json().stringify()
  let result = wasm_lux_response_to_provider("nonexistent", json_str)
  assert_true(result.contains("error"))
  assert_true(result.contains("unknown provider"))
}

///|
test "wasm_lux_response_to_provider - invalid JSON" {
  let result = wasm_lux_response_to_provider("openai", "bad")
  assert_true(result.contains("json parse error"))
}

///|
/// === wasm_sse_to_events（解码流式）===

///|
test "wasm_sse_to_events - openai SSE" {
  let sse = "data: {\"id\":\"1\",\"object\":\"chat.completion.chunk\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hello\"},\"finish_reason\":null}]}\n\ndata: [DONE]\n"
  let result = wasm_sse_to_events("openai", sse)
  // 成功时应返回带 value 的信封 JSON
  assert_true(result.contains("\"value\""))
  assert_true(result.contains("\"diagnostics\""))
}

///|
test "wasm_sse_to_events - unknown provider returns error" {
  let result = wasm_sse_to_events("fake", "data: {}")
  assert_true(result.contains("error"))
}

///|
/// === wasm_events_to_sse（编码流式）===

///|
test "wasm_events_to_sse - openai SSE encode" {
  let meta = @lux.LucentConversationMeta::new(Some("r1"), Some("gpt-4o"), None)
  let bt = @lux.LucentBlockType::text()
  let events = [
    @lux.LucentStreamEvent::ConversationStart(meta),
    BlockStart(0, bt),
    BlockDelta(0, @lux.LucentBlockDelta::text_delta("Hello")),
    BlockEnd(0),
    Finish(Stop),
    Done,
  ]
  let json_arr = events.map(fn(ev) { ev.to_json() })
  let json_str = "[" + json_arr.map(fn(j) { j.stringify() }).join(",") + "]"
  let result = wasm_events_to_sse("openai", json_str)
  assert_true(result.contains("data:"))
}

///|
test "wasm_events_to_sse - unknown provider returns error" {
  let events_json = "[{\"Done\":{}}]"
  let result = wasm_events_to_sse("invalid", events_json)
  assert_true(result.contains("error"))
}

///|
test "wasm_events_to_sse - invalid JSON returns parse error" {
  let result = wasm_events_to_sse("openai", "not-array")
  assert_true(result.contains("error"))
}

///|
/// === wasm_sdk_encode_request ===

///|
test "wasm_sdk_encode_request - openai returns JSON" {
  let result = wasm_sdk_encode_request("openai", "Hello")
  assert_true(result.contains("model"))
  assert_true(result.contains("messages"))
}

///|
test "wasm_sdk_encode_request - unknown provider returns error" {
  let result = wasm_sdk_encode_request("bad", "Hello")
  assert_true(result.contains("error"))
}

///|
/// === wasm_sdk_decode_response ===

///|
test "wasm_sdk_decode_response - extracts text" {
  let resp = "{\"id\":\"1\",\"object\":\"chat.completion\",\"created\":0,\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"Hi\"},\"finish_reason\":\"stop\"}],\"usage\":null}"
  let result = wasm_sdk_decode_response("openai", resp)
  // Task 2: 结果必须是信封，value 为纯文本
  let jv = @json.parse(result) catch { _ => Json::null() }
  match jv {
    Object(map) =>
      match map.get("value") {
        Some(String(v)) => assert_eq(v, "Hi")
        _ => fail("expected value string in envelope")
      }
    _ => fail("expected object envelope")
  }
}

///|
test "wasm_sdk_decode_response - unknown provider returns error" {
  let result = wasm_sdk_decode_response("nonexistent", "{}")
  assert_true(result.contains("error"))
}

///|
/// === wasm_sdk_encode_stream ===

///|
test "wasm_sdk_encode_stream - returns JSON with stream" {
  let result = wasm_sdk_encode_stream("openai", "Hi")
  assert_true(result.contains("stream"))
}

///|
test "wasm_sdk_encode_stream - unknown provider returns error" {
  let result = wasm_sdk_encode_stream("invalid", "Hi")
  assert_true(result.contains("error"))
}

///|
/// === wasm_sdk_decode_sse ===

///|
test "wasm_sdk_decode_sse - returns event JSON array" {
  let sse = "data: {\"id\":\"1\",\"object\":\"chat.completion.chunk\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hi\"},\"finish_reason\":null}]}\n\ndata: [DONE]\n"
  let result = wasm_sdk_decode_sse("openai", sse)
  // Task 2: 结果必须是信封，value 为事件数组
  let jv = @json.parse(result) catch { _ => Json::null() }
  match jv {
    Object(map) =>
      match map.get("value") {
        Some(Array(_)) => ()
        _ => fail("expected value array in envelope")
      }
    _ => fail("expected object envelope")
  }
}

///|
/// 事件字段级断言：确认事件对象由结构化字段构成，而非仅信封形状
test "wasm_sdk_decode_sse - event objects carry typed fields" {
  let sse = "data: {\"id\":\"1\",\"object\":\"chat.completion.chunk\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hi\"},\"finish_reason\":null}]}\n\ndata: [DONE]\n"
  let result = wasm_sdk_decode_sse("openai", sse)
  let jv = @json.parse(result) catch { _ => Json::null() }
  let events = match jv {
    Object(map) =>
      match map.get("value") {
        Some(Array(a)) => a
        _ => {
          fail("expected value array in envelope")
          []
        }
      }
    _ => {
      fail("expected object envelope")
      []
    }
  }
  assert_true(events.length() > 0)
  // 首个事件应为 text_delta，且 text 字段为解码出的文本
  match events[0] {
    Object(ev) => {
      match ev.get("type") {
        Some(String("text_delta")) => ()
        _ => fail("expected first event type text_delta")
      }
      match ev.get("text") {
        Some(String("Hi")) => ()
        _ => fail("expected text field to be \"Hi\"")
      }
    }
    _ => fail("expected event to be a JSON object")
  }
}

///|
test "wasm_sdk_decode_sse - unknown provider returns error" {
  let result = wasm_sdk_decode_sse("bad", "data: {}")
  assert_true(result.contains("error"))
}

///|
/// === wasm_sdk_capability ===

///|
test "wasm_sdk_capability - known provider returns JSON" {
  let result = wasm_sdk_capability("responses")
  assert_true(result.contains("provider"))
  assert_true(result.contains("openai"))
  assert_true(result.contains("model_pattern"))
  assert_true(result.contains("capabilities"))
}

///|
test "wasm_sdk_capability - unknown provider returns error" {
  let result = wasm_sdk_capability("unknown")
  assert_true(result.contains("error"))
}

///|
/// === 错误边界 ===

///|
test "empty provider name returns error" {
  let result = wasm_to_lux_request("", "{}")
  assert_true(result.contains("error"))
}

///|
test "empty JSON string for request decode" {
  let result = wasm_to_lux_request("openai", "")
  assert_true(result.contains("error"))
}

///|
/// === wasm_convert_*（中转站协议转发）===

///|
/// 标准请求经 openai 编码得到 source JSON（IR 构造器 → 适配器编码，不手写 JSON）
fn convert_source_req_json() -> Result[String, String] {
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
/// 标准响应经 openai 编码得到 source JSON
fn convert_source_resp_json() -> Result[String, String] {
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
/// 标准事件流经 openai 编码得到 source SSE
fn convert_source_sse() -> Result[String, String] {
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
test "wasm_convert_request - openai to messages" {
  match convert_source_req_json() {
    Ok(json) => {
      let result = wasm_convert_request("openai", json, "messages")
      // 信封：value 为可被 messages 解码的目标 JSON 字符串
      let jv = @json.parse(result) catch { _ => Json::null() }
      match jv {
        Object(map) =>
          match map.get("value") {
            Some(String(target_json)) =>
              match @messages.messages_to_lux_request(target_json) {
                Ok(cr) => {
                  let req = cr.value()
                  assert_eq(req.model, "gpt-4o")
                  assert_eq(req.conversation.length(), 1)
                }
                Err(e) => fail("target decode failed: \{e}")
              }
            _ => fail("expected value string in envelope")
          }
        _ => fail("expected object envelope")
      }
    }
    Err(e) => fail("encode source failed: \{e}")
  }
}

///|
test "wasm_convert_request - unknown provider returns error json" {
  let result = wasm_convert_request("nope", "{}", "messages")
  assert_true(result.contains("error"))
  assert_true(result.contains("unknown provider"))
}

///|
test "wasm_convert_response - openai to messages" {
  match convert_source_resp_json() {
    Ok(json) => {
      let result = wasm_convert_response("openai", json, "messages")
      let jv = @json.parse(result) catch { _ => Json::null() }
      match jv {
        Object(map) =>
          match map.get("value") {
            Some(String(target_json)) =>
              match @messages.messages_to_lux_response(target_json) {
                Ok(cr) => {
                  let resp = cr.value()
                  assert_eq(resp.id, "resp-1")
                  assert_eq(resp.model, "gpt-4o")
                  assert_eq(resp.choices.length(), 1)
                }
                Err(e) => fail("target response decode failed: \{e}")
              }
            _ => fail("expected value string in envelope")
          }
        _ => fail("expected object envelope")
      }
    }
    Err(e) => fail("encode source failed: \{e}")
  }
}

///|
test "wasm_convert_stream - openai to messages" {
  match convert_source_sse() {
    Ok(sse) => {
      let result = wasm_convert_stream("openai", sse, "messages")
      let jv = @json.parse(result) catch { _ => Json::null() }
      match jv {
        Object(map) =>
          match map.get("value") {
            Some(String(target_sse)) =>
              match @messages.messages_sse_to_events(target_sse) {
                Ok(cr) => assert_true(cr.value().length() > 0)
                Err(e) => fail("target sse decode failed: \{e}")
              }
            _ => fail("expected value string in envelope")
          }
        _ => fail("expected object envelope")
      }
    }
    Err(e) => fail("encode source failed: \{e}")
  }
}

///|
/// === wasm_convert_stream_event（单事件流转换）===

///|
test "wasm_convert_stream_event - single openai event to messages" {
  // 单个 OpenAI Chat SSE 事件
  let sse_event = "data: {\"id\":\"1\",\"object\":\"chat.completion.chunk\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hello\"},\"finish_reason\":null}]}\n\n"
  let result = wasm_convert_stream_event("openai", sse_event, "messages")
  // 应返回信封格式
  assert_true(result.contains("\"value\""))
  assert_true(result.contains("\"diagnostics\""))
  // value 应包含 Anthropic 格式的 SSE 事件
  let jv = @json.parse(result) catch { _ => Json::null() }
  match jv {
    Object(map) =>
      match map.get("value") {
        Some(String(target_sse)) =>
          // Anthropic SSE 应包含 content_block_delta
          assert_true(target_sse.contains("content_block_delta"))
        _ => fail("expected value string in envelope")
      }
    _ => fail("expected object envelope")
  }
}

///|
test "wasm_convert_stream_event - [DONE] event to messages" {
  // OpenAI Chat 的流结束事件
  let sse_event = "data: [DONE]\n\n"
  let result = wasm_convert_stream_event("openai", sse_event, "messages")
  // 应返回信封格式
  assert_true(result.contains("\"value\""))
  let jv = @json.parse(result) catch { _ => Json::null() }
  match jv {
    Object(map) =>
      match map.get("value") {
        Some(String(target_sse)) =>
          // Anthropic 的流结束应包含 message_stop
          assert_true(target_sse.contains("message_stop"))
        _ => fail("expected value string in envelope")
      }
    _ => fail("expected object envelope")
  }
}

///|
test "wasm_convert_stream_event - same protocol passthrough" {
  // 同协议转换应返回等价内容
  let sse_event = "data: {\"id\":\"1\",\"object\":\"chat.completion.chunk\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hello\"},\"finish_reason\":null}]}\n\n"
  let result = wasm_convert_stream_event("openai", sse_event, "openai")
  assert_true(result.contains("\"value\""))
  let jv = @json.parse(result) catch { _ => Json::null() }
  match jv {
    Object(map) =>
      match map.get("value") {
        Some(String(target_sse)) =>
          // 同协议应包含相同的 data: 行
          assert_true(target_sse.contains("data:"))
        _ => fail("expected value string in envelope")
      }
    _ => fail("expected object envelope")
  }
}

///|
test "wasm_convert_stream_event - unknown provider returns error" {
  let result = wasm_convert_stream_event("unknown", "data: {}\n\n", "messages")
  assert_true(result.contains("error"))
  assert_true(result.contains("unknown provider"))
}

///|
test "wasm_convert_stream_event - invalid target returns error" {
  let result = wasm_convert_stream_event("openai", "data: {}\n\n", "invalid")
  assert_true(result.contains("error"))
  assert_true(result.contains("unknown provider"))
}

///|
/// === 信封 JSON（value + diagnostics）===

///|
test "wasm_to_lux_request - returns envelope with value and diagnostics" {
  let json_str = "{\"model\":\"gpt-4o\",\"messages\":[{\"role\":\"user\",\"content\":\"Hi\"}]}"
  let result = wasm_to_lux_request("openai", json_str)
  // 信封：{"value":<payload>,"diagnostics":[...]}
  assert_true(result.contains("\"value\""))
  assert_true(result.contains("\"diagnostics\""))
}

///|
test "wasm_to_lux_request - invalid json returns error envelope with diagnostics" {
  let result = wasm_to_lux_request("openai", "{invalid}")
  assert_true(result.contains("\"error\""))
  assert_true(result.contains("\"diagnostics\""))
}

///|
test "wasm_to_lux_response - returns envelope with value and diagnostics" {
  let resp_json = "{\"id\":\"chatcmpl-1\",\"object\":\"chat.completion\",\"created\":123,\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"Hello!\"},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":5,\"completion_tokens\":3,\"total_tokens\":8}}"
  let result = wasm_to_lux_response("openai", resp_json)
  assert_true(result.contains("\"value\""))
  assert_true(result.contains("\"diagnostics\""))
}

///|
test "wasm_sse_to_events - returns envelope with value and diagnostics" {
  let sse = "data: {\"id\":\"1\",\"object\":\"chat.completion.chunk\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hello\"},\"finish_reason\":null}]}\n\ndata: [DONE]\n"
  let result = wasm_sse_to_events("openai", sse)
  assert_true(result.contains("\"value\""))
  assert_true(result.contains("\"diagnostics\""))
}

///|
test "wasm_convert_request - returns envelope with value and diagnostics" {
  match convert_source_req_json() {
    Ok(json) => {
      let result = wasm_convert_request("openai", json, "messages")
      assert_true(result.contains("\"value\""))
      assert_true(result.contains("\"diagnostics\""))
    }
    Err(e) => fail("encode source failed: \{e}")
  }
}

///|
/// === Task 2: wasm_sdk_* 信封化 ===

///|
test "wasm_sdk_encode_request - returns envelope with value and diagnostics" {
  let result = wasm_sdk_encode_request("openai", "Hello")
  assert_true(result.contains("\"value\""))
  assert_true(result.contains("\"diagnostics\""))
}

///|
test "wasm_sdk_decode_response - returns envelope with value and diagnostics" {
  let resp = "{\"id\":\"1\",\"object\":\"chat.completion\",\"created\":0,\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"Hi\"},\"finish_reason\":\"stop\"}],\"usage\":null}"
  let result = wasm_sdk_decode_response("openai", resp)
  assert_true(result.contains("\"value\""))
  assert_true(result.contains("\"diagnostics\""))
}

///|
test "wasm_sdk_encode_stream - returns envelope with value and diagnostics" {
  let result = wasm_sdk_encode_stream("openai", "Hi")
  assert_true(result.contains("\"value\""))
  assert_true(result.contains("\"diagnostics\""))
}

///|
test "wasm_sdk_decode_sse - returns envelope with value and diagnostics" {
  let sse = "data: {\"id\":\"1\",\"object\":\"chat.completion.chunk\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hi\"},\"finish_reason\":null}]}\n\ndata: [DONE]\n"
  let result = wasm_sdk_decode_sse("openai", sse)
  assert_true(result.contains("\"value\""))
  assert_true(result.contains("\"diagnostics\""))
}

///|
test "wasm_sdk_capability - returns envelope with value and diagnostics" {
  let result = wasm_sdk_capability("responses")
  assert_true(result.contains("\"value\""))
  assert_true(result.contains("\"diagnostics\""))
}
