///|
/// 测试 internal/sse.mbt — SSE 行解析

///|
/// === parse_sse_line - event 行 ===
test "parse_sse_line - event type extracted" {
  match @internal.parse_sse_line("event: message_start") {
    Some(line) => assert_eq(line.event, Some("message_start"))
    None => fail("expected Some")
  }
}

///|
test "parse_sse_line - event with trailing space" {
  match @internal.parse_sse_line("event: done ") {
    Some(line) => assert_eq(line.event, Some("done "))
    None => fail("expected Some")
  }
}

///|
test "parse_sse_line - event with no data" {
  match @internal.parse_sse_line("event: ping") {
    Some(line) => {
      assert_eq(line.event, Some("ping"))
      assert_eq(line.data, None)
    }
    None => fail("expected Some")
  }
}

///|
/// === parse_sse_line - data 行 ===
test "parse_sse_line - data with space after colon" {
  match @internal.parse_sse_line("data: {\"key\":\"val\"}") {
    Some(line) => assert_eq(line.data, Some("{\"key\":\"val\"}"))
    None => fail("expected Some")
  }
}

///|
test "parse_sse_line - data without space after colon" {
  match @internal.parse_sse_line("data:hello") {
    Some(line) => assert_eq(line.data, Some("hello"))
    None => fail("expected Some")
  }
}

///|
test "parse_sse_line - data [DONE] sentinel" {
  match @internal.parse_sse_line("data: [DONE]") {
    Some(line) => assert_eq(line.data, Some("[DONE]"))
    None => fail("expected Some")
  }
}

///|
test "parse_sse_line - data with no event" {
  match @internal.parse_sse_line("data: {\"a\":1}") {
    Some(line) => {
      assert_eq(line.event, None)
      assert_eq(line.data, Some("{\"a\":1}"))
    }
    None => fail("expected Some")
  }
}

///|
/// === parse_sse_line - 空行/注释 ===
test "parse_sse_line - empty line returns None" {
  assert_true(@internal.parse_sse_line("") is None)
}

///|
test "parse_sse_line - comment line returns None" {
  assert_true(@internal.parse_sse_line(":comment") is None)
}

///|
/// === parse_sse_line - 非 SSE 行 ===
test "parse_sse_line - unknown line returns None" {
  assert_true(@internal.parse_sse_line("random text") is None)
  assert_true(@internal.parse_sse_line("x") is None)
}

///|
/// === parse_sse_line - event + data 两次调用（模拟双行流） ===
test "parse_sse_line - event then data sequenced" {
  let event_line = @internal.parse_sse_line("event: response.created").unwrap()
  let data_line = @internal.parse_sse_line("data: {\"id\":\"rsp_1\"}").unwrap()
  assert_eq(event_line.event, Some("response.created"))
  assert_eq(data_line.data, Some("{\"id\":\"rsp_1\"}"))
}

///|
/// === parse_sse_line - 边界场景 ===
test "parse_sse_line - data with empty content" {
  // "data: " → data 之后无内容，返回空字符串
  match @internal.parse_sse_line("data: ") {
    Some(line) => assert_eq(line.data, Some(""))
    None => fail("expected Some")
  }
}

///|
test "parse_sse_line - data: with nothing after" {
  // "data:" 无空格 → 经短路径解析，内容为空字符串
  match @internal.parse_sse_line("data:") {
    Some(line) => assert_eq(line.data, Some(""))
    None => fail("expected Some")
  }
}

///|
test "parse_sse_line - event with very long name" {
  let _long_name : String = "x"
  let mut long_event = "event: "
  let mut i = 0
  while i < 100 {
    long_event = long_event + "x"
    i = i + 1
  }
  match @internal.parse_sse_line(long_event) {
    Some(line) => assert_true(line.event is Some(_))
    None => fail("expected Some for long event")
  }
}

///|
test "parse_sse_line - event without data content" {
  // "event: " → event 后无内容，返回空字符串
  match @internal.parse_sse_line("event: ") {
    Some(line) => assert_eq(line.event, Some(""))
    None => fail("expected Some")
  }
}

///|
/// === extract_sse_events ===

///|
test "extract_sse_events - single event" {
  let sse = "data: {\"key\":\"value\"}\n\n"
  let events = @internal.extract_sse_events(sse)
  assert_eq(events.length(), 1)
  assert_eq(events[0], "{\"key\":\"value\"}")
}

///|
test "extract_sse_events - multiple events" {
  let sse = "data: {\"id\":1}\n\ndata: {\"id\":2}\n\n"
  let events = @internal.extract_sse_events(sse)
  assert_eq(events.length(), 2)
  assert_eq(events[0], "{\"id\":1}")
  assert_eq(events[1], "{\"id\":2}")
}

///|
test "extract_sse_events - filters heartbeat comments" {
  // 心跳注释行应被过滤
  let sse = "data: {\"key\":\"value\"}\n: keep-alive\n\n"
  let events = @internal.extract_sse_events(sse)
  assert_eq(events.length(), 1)
  assert_eq(events[0], "{\"key\":\"value\"}")
}

///|
test "extract_sse_events - filters heartbeat between events" {
  // 心跳在两个事件之间
  let sse = "data: {\"id\":1}\n\n: keep-alive\ndata: {\"id\":2}\n\n"
  let events = @internal.extract_sse_events(sse)
  assert_eq(events.length(), 2)
  assert_eq(events[0], "{\"id\":1}")
  assert_eq(events[1], "{\"id\":2}")
}

///|
test "extract_sse_events - multi-line data" {
  // 多个 data: 行应合并
  let sse = "data: line1\ndata: line2\n\n"
  let events = @internal.extract_sse_events(sse)
  assert_eq(events.length(), 1)
  assert_eq(events[0], "line1\nline2")
}

///|
test "extract_sse_events - [DONE] sentinel" {
  let sse = "data: [DONE]\n\n"
  let events = @internal.extract_sse_events(sse)
  assert_eq(events.length(), 1)
  assert_eq(events[0], "[DONE]")
}

///|
test "extract_sse_events - empty stream" {
  let sse = ""
  let events = @internal.extract_sse_events(sse)
  assert_eq(events.length(), 0)
}

///|
test "extract_sse_events - only heartbeats" {
  let sse = ": keep-alive\n: heartbeat\n\n"
  let events = @internal.extract_sse_events(sse)
  assert_eq(events.length(), 0)
}

///|
test "extract_sse_events - event type ignored" {
  // event: 行应被忽略，只提取 data:
  let sse = "event: message_start\ndata: {\"type\":\"start\"}\n\n"
  let events = @internal.extract_sse_events(sse)
  assert_eq(events.length(), 1)
  assert_eq(events[0], "{\"type\":\"start\"}")
}

///|
test "extract_sse_events - real world OpenAI SSE with heartbeat" {
  // 模拟实际 OpenAI SSE 流，包含心跳
  let sse = "data: {\"type\":\"response.created\",\"response\":{\"id\":\"resp_123\"}}\n\n: keep-alive\ndata: {\"type\":\"response.output_item.added\"}\n\n"
  let events = @internal.extract_sse_events(sse)
  assert_eq(events.length(), 2)
  assert_true(events[0].contains("response.created"))
  assert_true(events[1].contains("output_item.added"))
}

///|
test "extract_sse_events - multi-line data concatenation" {
  // SSE 规范：多个 data: 行应合并
  let sse = "data: line1\ndata: line2\ndata: line3\n\n"
  let events = @internal.extract_sse_events(sse)
  assert_eq(events.length(), 1)
  assert_eq(events[0], "line1\nline2\nline3")
}

///|
test "extract_sse_events - multi-line data with heartbeat" {
  // 多行 data 中间有心跳
  let sse = "data: line1\n: keep-alive\ndata: line2\n\n"
  let events = @internal.extract_sse_events(sse)
  assert_eq(events.length(), 1)
  assert_eq(events[0], "line1\nline2")
}

///|
test "parse_sse_messages - accepts CRLF boundaries" {
  let messages = @internal.parse_sse_messages(
    "data: {\"x\":1}\r\n\r\ndata: {\"x\":2}\r\n\r\n",
  )
  assert_eq(messages.length(), 2)
  assert_eq(messages[0].data, "{\"x\":1}")
  assert_eq(messages[1].data, "{\"x\":2}")
}

///|
test "parse_sse_message - strips CR from event and data" {
  match @internal.parse_sse_message("event: done\r\ndata: ok\r\n") {
    Some(message) => {
      assert_eq(message.event_type, Some("done"))
      assert_eq(message.data, "ok")
    }
    None => fail("expected SSE message")
  }
}
