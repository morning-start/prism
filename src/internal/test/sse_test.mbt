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

///|
/// 回归：CRLF 归一化必须替换**全部**出现（String::replace 只替换首次出现）。
/// 若误用 replace，第 2 个及以后的 `\r\n` 会残留，导致多帧被并进一个块。
test "parse_sse_messages - three CRLF frames stay three messages" {
  let messages = @internal.parse_sse_messages(
    "data: {\"x\":1}\r\n\r\ndata: {\"x\":2}\r\n\r\ndata: {\"x\":3}\r\n\r\n",
  )
  assert_eq(messages.length(), 3)
  assert_eq(messages[0].data, "{\"x\":1}")
  assert_eq(messages[1].data, "{\"x\":2}")
  assert_eq(messages[2].data, "{\"x\":3}")
}

///|
/// 回归：LF 分隔的三帧也必须各自成块（不得两帧并块）。
test "parse_sse_messages - multiple LF frames do not merge" {
  let messages = @internal.parse_sse_messages(
    "data: a\n\ndata: b\n\ndata: c\n\n",
  )
  assert_eq(messages.length(), 3)
  assert_eq(messages[2].data, "c")
}

///|
/// ═══ SseFrameSplitter — 增量帧分割（T5）═══

///|
test "SseFrameSplitter - whole buffer yields all frames" {
  let splitter = @internal.SseFrameSplitter::new()
  let frames = splitter.feed("data: a\n\ndata: b\n\ndata: c\n\n")
  assert_eq(frames.length(), 3)
  assert_eq(frames[0], "data: a")
  assert_eq(frames[1], "data: b")
  assert_eq(frames[2], "data: c")
}

///|
/// 核心：1 字节 chunk 切分喂入，帧序列与整缓冲一致（半帧跨 chunk 缓冲）
test "SseFrameSplitter - one byte chunks yield same frames" {
  let sse = "event: message_start\ndata: {\"a\":1}\n\ndata: {\"b\":2}\n\ndata: [DONE]\n\n"
  let whole = @internal.SseFrameSplitter::new().feed(sse)
  let splitter = @internal.SseFrameSplitter::new()
  let collected : Array[String] = []
  let mut i = 0
  while i < sse.length() {
    let ch = sse[i:i + 1].to_owned()
    for f in splitter.feed(ch) {
      collected.push(f)
    }
    i = i + 1
  }
  assert_eq(collected.length(), whole.length())
  assert_eq(collected, whole)
}

///|
/// 随机边界切分（非 1 字节）同样保持帧序列一致
test "SseFrameSplitter - arbitrary chunk boundaries preserve frames" {
  let sse = "data: {\"x\":1}\n\ndata: {\"y\":2}\n\ndata: {\"z\":3}\n\n"
  let whole = @internal.SseFrameSplitter::new().feed(sse)
  let splitter = @internal.SseFrameSplitter::new()
  let collected : Array[String] = []
  let mut i = 0
  while i < sse.length() {
    let end = if i + 7 <= sse.length() { i + 7 } else { sse.length() }
    for f in splitter.feed(sse[i:end].to_owned()) {
      collected.push(f)
    }
    i = end
  }
  assert_eq(collected, whole)
}

///|
/// CRLF 流：帧边界为 \r\n\r\n
test "SseFrameSplitter - CRLF frames split correctly" {
  let splitter = @internal.SseFrameSplitter::new()
  let frames = splitter.feed("data: a\r\n\r\ndata: b\r\n\r\n")
  assert_eq(frames.length(), 2)
  assert_eq(frames[0], "data: a")
  assert_eq(frames[1], "data: b")
}

///|
/// \r|\n 边界切分：chunk1 尾部 \r 挂起，chunk2 首字符 \n 配对消费
test "SseFrameSplitter - CR split across chunk boundary pairs correctly" {
  let splitter = @internal.SseFrameSplitter::new()
  // 第一 chunk 以 \r 结尾（半帧 + 半个行尾）
  let f1 = splitter.feed("data: a\r")
  assert_eq(f1.length(), 0)
  // 第二 chunk 以 \n 开头：与挂起的 \r 配对成 CRLF，不得变成两个行尾
  let f2 = splitter.feed("\n\r")
  assert_eq(f2.length(), 0)
  let f3 = splitter.feed("\ndata: b\n\n")
  assert_eq(f3.length(), 2)
  assert_eq(f3[0], "data: a")
  assert_eq(f3[1], "data: b")
}

///|
/// 独立 \r 行尾（非 CRLF）：挂起后下一 chunk 非 \n → 补独立行尾
test "SseFrameSplitter - lone CR line ending is preserved" {
  let splitter = @internal.SseFrameSplitter::new()
  let f1 = splitter.feed("data: a\r")
  assert_eq(f1.length(), 0)
  let f2 = splitter.feed("data: b\r\r")
  assert_eq(f2.length(), 0)
  // 收尾挂起的 \r 是行尾：flush 补 \n 后切出完整帧
  let tail = splitter.flush()
  assert_eq(tail.length(), 1)
  assert_eq(tail[0], "data: a\ndata: b")
}

///|
/// flush：无尾部空行的流，半帧在 finish 时产出
test "SseFrameSplitter - flush yields trailing frame" {
  let splitter = @internal.SseFrameSplitter::new()
  let f1 = splitter.feed("data: a\n\ndata: b")
  assert_eq(f1.length(), 1)
  let tail = splitter.flush()
  assert_eq(tail.length(), 1)
  assert_eq(tail[0], "data: b")
}

///|
/// 空帧/纯注释帧不产出
test "SseFrameSplitter - empty and comment frames skipped" {
  let splitter = @internal.SseFrameSplitter::new()
  let frames = splitter.feed(": keep-alive\n\n\n\ndata: real\n\n")
  assert_eq(frames.length(), 1)
  assert_eq(frames[0], "data: real")
}
