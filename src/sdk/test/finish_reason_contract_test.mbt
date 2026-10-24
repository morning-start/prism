///|
/// finish_reason 协议枚举契约 —— 流式与非流式编码器的一致性 + 非法值零溢出。
///
/// ## 背景（CR-005 缺陷 B / C）
///
/// IR 的 `LucentFinishReason::to_string()` 输出的是 **IR 自己的词汇表**
/// （`stop` / `length` / `tool_calls` / `safety` / `recitation` /
/// `malformed_tool_call` / `error` / `content_filter`），与任何一家 wire 协议的
/// 枚举都不同。此前**非流式**路径逐协议做了收敛，**流式**路径却直接
/// `fr.to_string()` —— 同一个协议两条路径输出不同词汇表：
///
/// | 目标 | 流式（修复前） | 合法性 |
/// |---|---|---|
/// | messages | `stop` / `length` / `tool_calls` / `safety` / ... | **8/8 非法** |
/// | openai | `safety` / `recitation` / `stop_sequence` / ... | 非法（官方仅 5 值）|
/// | gemini | `Native(v)` 被静默吞成 `STOP` | 数据丢失 |
///
/// 严格校验的对端会拒绝整个响应体或整条流。现三个收敛器集中在
/// `src/provider/meta/finish.mbt`，非流式与流式共用。

///|
/// Anthropic Messages 合法 `stop_reason` 全集（官方枚举）。
let messages_legal : Array[String] = [
  "\"end_turn\"", "\"max_tokens\"", "\"tool_use\"", "\"stop_sequence\"", "\"refusal\"",
  "\"pause_turn\"", "\"model_context_window_exceeded\"",
]

///|
/// OpenAI Chat 合法 `finish_reason` 全集（vendored 官方 OpenAPI）。
let openai_legal : Array[String] = [
  "\"stop\"", "\"length\"", "\"tool_calls\"", "\"content_filter\"", "\"function_call\"",
]

///|
/// 从 SSE 文本里取出某 key 的 JSON 字符串字面量值（含引号）。
/// 用 split 定位（MoonBit 的 `find` 返回子串而非位置）。
fn extract_quoted(sse : String, key : String) -> String {
  let marker = "\"" + key + "\":"
  for line in sse.split("\n") {
    let segs = line.split(marker).to_array()
    if segs.length() >= 2 {
      let rest = segs[1].to_owned().trim_start()
      if rest.length() >= 2 && rest[0] == '"' {
        // 找收尾引号（跳过转义）
        let mut i = 1
        let mut out = "\""
        while i < rest.length() {
          let ch = rest[i]
          out = out + rest[i:i + 1].to_owned()
          if ch == '"' && i > 0 && rest[i - 1] != '\\' {
            break
          }
          i = i + 1
        }
        if out.length() > 1 {
          return out
        }
      }
    }
  }
  ""
}

///|
/// messages 流式编码：所有 IR finish_reason 必须收敛到 Anthropic 合法枚举。
/// 修复前 8/8 非法（直接输出 IR 词汇表）。
test "cr005 - messages stream emits only legal stop_reason" {
  let cases : Array[@lux.LucentFinishReason] = [
    Stop,
    Length,
    ToolCalls,
    Safety,
    Recitation,
    MalformedToolCall,
    Error,
    ContentFilter,
  ]
  for fr in cases {
    let events : Array[@lux.LucentStreamEvent] = [
      ConversationStart(
        @lux.LucentConversationMeta::new(Some("m"), Some("c"), None),
      ),
      Finish(fr),
      Done,
    ]
    match @messages.lux_events_to_messages_sse(events) {
      Err(e) => fail("encode failed: " + e)
      Ok(cr) => {
        let v = extract_quoted(cr.value(), "stop_reason")
        assert_true(v != "")
        assert_true(messages_legal.contains(v))
      }
    }
  }
}

///|
/// `ToolCalls` 必须映射为 Anthropic 的 `tool_use`，**不是** OpenAI 的
/// `tool_calls`。修复前流式输出 `tool_calls`（非法）。
test "cr005 - messages ToolCalls maps to tool_use not tool_calls" {
  let events : Array[@lux.LucentStreamEvent] = [
    ConversationStart(
      @lux.LucentConversationMeta::new(Some("m"), Some("c"), None),
    ),
    Finish(ToolCalls),
    Done,
  ]
  match @messages.lux_events_to_messages_sse(events) {
    Err(e) => fail("encode failed: " + e)
    Ok(cr) =>
      assert_eq(extract_quoted(cr.value(), "stop_reason"), "\"tool_use\"")
  }
}

///|
/// openai 流式编码：所有 IR finish_reason 必须收敛到 OpenAI 合法枚举。
/// 修复前绕过 `openai_finish_reason` 收敛器直接写 IR 词汇表。
test "cr005 - openai stream emits only legal finish_reason" {
  let cases : Array[@lux.LucentFinishReason] = [
    Stop,
    Length,
    ToolCalls,
    Safety,
    Recitation,
    MalformedToolCall,
    Error,
    ContentFilter,
  ]
  for fr in cases {
    let events : Array[@lux.LucentStreamEvent] = [
      ConversationStart(
        @lux.LucentConversationMeta::new(Some("m"), Some("c"), None),
      ),
      Finish(fr),
      Done,
    ]
    match @openai.lux_events_to_openai_sse(events) {
      Err(e) => fail("encode failed: " + e)
      Ok(cr) => {
        let v = extract_quoted(cr.value(), "finish_reason")
        assert_true(v != "")
        assert_true(openai_legal.contains(v))
      }
    }
  }
}

///|
/// 跨协议实测复现：messages 源解出的 `Native("stop_sequence")` 经 openai 流式
/// 出站时曾原样写成 `"finish_reason":"stop_sequence"`（非法）。修复后必须合法。
test "cr005 - messages source stop_sequence does not leak into openai stream" {
  let sse = "event: message_start\n" +
    "data: {\"type\":\"message_start\",\"message\":{\"id\":\"m\",\"model\":\"c\"}}\n\n" +
    "event: message_delta\n" +
    "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"stop_sequence\",\"stop_sequence\":\"END\"}}\n\n" +
    "event: message_stop\ndata: {\"type\":\"message_stop\"}\n\n"
  match @messages.messages_sse_to_events(sse) {
    Err(e) => fail("decode failed: " + e)
    Ok(decoded) =>
      match @openai.lux_events_to_openai_sse(decoded.value()) {
        Err(e) => fail("encode failed: " + e)
        Ok(cr) => {
          let v = extract_quoted(cr.value(), "finish_reason")
          assert_true(v != "")
          assert_true(openai_legal.contains(v))
          assert_false(v.contains("stop_sequence"))
        }
      }
  }
}

///|
/// CR-005 缺陷 B：同源同值在流式与非流式两条路径必须解出**同一** IR 值。
/// 修复前流式 → `Native("stop_sequence")`，非流式 → `Stop`（自相矛盾）。
test "cr005 - stop_sequence decodes identically in stream and non-stream" {
  let stream_sse = "event: message_start\n" +
    "data: {\"type\":\"message_start\",\"message\":{\"id\":\"m\",\"model\":\"c\"}}\n\n" +
    "event: message_delta\n" +
    "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"stop_sequence\"}}\n\n" +
    "event: message_stop\ndata: {\"type\":\"message_stop\"}\n\n"
  let resp_json = "{\"id\":\"m\",\"type\":\"message\",\"role\":\"assistant\",\"model\":\"c\",\"content\":[],\"stop_reason\":\"stop_sequence\",\"stop_sequence\":\"END\"}"
  let stream_finish = match @messages.messages_sse_to_events(stream_sse) {
    Err(e) => fail("stream decode failed: " + e)
    Ok(cr) => {
      let mut found : @lux.LucentFinishReason? = None
      for ev in cr.value() {
        match ev {
          Finish(fr) => found = Some(fr)
          _ => ()
        }
      }
      match found {
        Some(fr) => fr
        None => fail("no Finish event in stream")
      }
    }
  }
  let nonstream_finish = match @messages.messages_to_lux_response(resp_json) {
    Err(e) => fail("response decode failed: " + e)
    Ok(cr) => cr.value().choices[0].finish_reason
  }
  assert_eq(stream_finish, nonstream_finish)
  assert_eq(stream_finish, Stop)
}

///|
/// gemini 流式：厂商自定义 `Native` 值必须**原样透传**，不得静默吞成 STOP。
/// 修复前流式走 `_ => "STOP"` 兜底 —— 那是数据丢失（同协议非流式却是透传）。
test "cr005 - gemini stream passes Native finish reason through" {
  let events : Array[@lux.LucentStreamEvent] = [
    ConversationStart(
      @lux.LucentConversationMeta::new(Some("g"), Some("gm"), None),
    ),
    Finish(Native("LANGUAGE")),
    Done,
  ]
  match @gemini.lux_events_to_gemini_sse(events) {
    Err(e) => fail("encode failed: " + e)
    Ok(cr) => assert_true(cr.value().contains("\"finishReason\":\"LANGUAGE\""))
  }
}

///|
/// 无对等值的收敛必须留诊断（收敛不能静默）。
/// 诊断键使用目标协议的**真实字段名**（stop_reason / finish_reason /
/// finishReason / status），而不是统一叫 finish_reason。
test "cr005 - converged finish_reason is diagnosed" {
  // Safety 在 openai 无对等值；在 messages 用 Recitation（同样无对等值）
  // 验证收敛带诊断。Safety 此前映射 "safety"（非法）收敛 end_turn；
  // 现映射官方对等值 refusal（"streaming classifiers intervene to handle
  // potential policy violations"）直通，不再产生诊断 —— 用 Recitation 保留
  // 「收敛必诊断」的契约覆盖。
  let events : Array[@lux.LucentStreamEvent] = [
    ConversationStart(
      @lux.LucentConversationMeta::new(Some("m"), Some("c"), None),
    ),
    Finish(Recitation),
    Done,
  ]
  // messages：Recitation 无 Anthropic 对等值 → end_turn + 诊断
  match @messages.lux_events_to_messages_sse(events) {
    Err(e) => fail("encode failed: " + e)
    Ok(cr) => {
      let mut found = false
      for d in cr.diagnostics() {
        if d.field.contains("stop_reason") && d.status is Unsupported {
          found = true
        }
      }
      assert_true(found)
    }
  }
  // openai：Safety 无 OpenAI 对等值 → stop + Unsupported
  match @openai.lux_events_to_openai_sse(events) {
    Err(e) => fail("encode failed: " + e)
    Ok(cr) => {
      let mut found = false
      for d in cr.diagnostics() {
        if d.field.contains("finish_reason") && d.status is Unsupported {
          found = true
        }
      }
      assert_true(found)
    }
  }
}
