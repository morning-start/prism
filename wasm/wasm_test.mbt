///|
/// WASM 导出层测试 — 6 个通用 IR 函数 + 5 个 SDK API
///
/// 黑盒测试，验证 String 进出的纯函数行为。

///|
/// === wasm_to_lux_request（解码请求）===

///|
test "wasm_to_lux_request - openai_chat decode" {
  let json_str = "{\"model\":\"gpt-4o\",\"messages\":[{\"role\":\"user\",\"content\":\"Hi\"}]}"
  let result = wasm_to_lux_request("openai-chat", json_str)
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
  let result = wasm_to_lux_request("openai-chat", "{invalid}")
  assert_true(result.contains("error"))
}

///|
/// === wasm_lux_request_to_provider（编码请求）===

///|
test "wasm_lux_request_to_provider - openai_chat encode" {
  let msg = @lux.LucentMessage::new(@lux.User, [
    @lux.LucentContent::text("Hello"),
  ])
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
  let result = wasm_lux_request_to_provider("openai-chat", json_str)
  assert_true(result.contains("model"))
  assert_true(result.contains("messages"))
}

///|
test "wasm_lux_request_to_provider - unknown provider returns error" {
  let msg = @lux.LucentMessage::new(@lux.User, [@lux.LucentContent::text("Hi")])
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
  let result = wasm_lux_request_to_provider("openai-chat", "not json")
  assert_true(result.contains("json parse error"))
}

///|
/// === wasm_to_lux_response（解码响应）===

///|
test "wasm_to_lux_response - openai_chat decode" {
  let resp_json = "{\"id\":\"chatcmpl-1\",\"object\":\"chat.completion\",\"created\":123,\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"Hello!\"},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":5,\"completion_tokens\":3,\"total_tokens\":8}}"
  let result = wasm_to_lux_response("openai-chat", resp_json)
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
test "wasm_lux_response_to_provider - openai_chat encode" {
  let content = [@lux.LucentContent::text("Hi")]
  let msg = @lux.LucentMessage::new(@lux.Assistant, content)
  let choice = @lux.LucentChoice::new(0, msg, @lux.Stop, None)
  let resp = @lux.LucentResponse::new(
    "resp-1",
    "gpt-4o",
    None,
    [choice],
    None,
    None,
  )
  let json_str = resp.to_json().stringify()
  let result = wasm_lux_response_to_provider("openai-chat", json_str)
  assert_true(result.contains("choices"))
}

///|
test "wasm_lux_response_to_provider - unknown provider returns error" {
  let content = [@lux.LucentContent::text("Hi")]
  let msg = @lux.LucentMessage::new(@lux.Assistant, content)
  let choice = @lux.LucentChoice::new(0, msg, @lux.Stop, None)
  let resp = @lux.LucentResponse::new("r", "m", None, [choice], None, None)
  let json_str = resp.to_json().stringify()
  let result = wasm_lux_response_to_provider("nonexistent", json_str)
  assert_true(result.contains("error"))
  assert_true(result.contains("unknown provider"))
}

///|
test "wasm_lux_response_to_provider - invalid JSON" {
  let result = wasm_lux_response_to_provider("openai-chat", "bad")
  assert_true(result.contains("json parse error"))
}

///|
/// === wasm_sse_to_events（解码流式）===

///|
test "wasm_sse_to_events - openai_chat SSE" {
  let sse = "data: {\"id\":\"1\",\"object\":\"chat.completion.chunk\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hello\"},\"finish_reason\":null}]}\n\ndata: [DONE]\n"
  let result = wasm_sse_to_events("openai-chat", sse)
  // 成功时应返回 JSON 数组
  assert_true(result.has_prefix("["))
}

///|
test "wasm_sse_to_events - unknown provider returns error" {
  let result = wasm_sse_to_events("fake", "data: {}")
  assert_true(result.contains("error"))
}

///|
/// === wasm_events_to_sse（编码流式）===

///|
test "wasm_events_to_sse - openai_chat SSE encode" {
  let meta = @lux.LucentConversationMeta::new(Some("r1"), Some("gpt-4o"), None)
  let bt = @lux.LucentBlockType::text()
  let events = [
    @lux.LucentStreamEvent::ConversationStart(meta),
    @lux.LucentStreamEvent::BlockStart(0, bt),
    @lux.LucentStreamEvent::BlockDelta(
      0,
      @lux.LucentBlockDelta::text_delta("Hello"),
    ),
    @lux.LucentStreamEvent::BlockEnd(0),
    @lux.LucentStreamEvent::Finish(@lux.Stop),
    @lux.LucentStreamEvent::Done,
  ]
  let json_arr = events.map(fn(ev) { ev.to_json() })
  let json_str = "[" + json_arr.map(fn(j) { j.stringify() }).join(",") + "]"
  let result = wasm_events_to_sse("openai-chat", json_str)
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
  let result = wasm_events_to_sse("openai-chat", "not-array")
  assert_true(result.contains("error"))
}

///|
/// === wasm_sdk_encode_request ===

///|
test "wasm_sdk_encode_request - openai_chat returns JSON" {
  let result = wasm_sdk_encode_request("openai-chat", "Hello")
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
  let result = wasm_sdk_decode_response("openai-chat", resp)
  assert_eq(result, "Hi")
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
  let result = wasm_sdk_encode_stream("openai-chat", "Hi")
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
  let result = wasm_sdk_decode_sse("openai-chat", sse)
  assert_true(result.has_prefix("["))
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
  let result = wasm_sdk_capability("openai")
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
  let result = wasm_to_lux_request("openai-chat", "")
  assert_true(result.contains("error"))
}
