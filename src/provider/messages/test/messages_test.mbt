///|
/// Anthropic Messages 适配器黑盒测试 — 仅通过公开 API 验证
///
/// 与白盒测试（_wbtest.mbt）互补：模拟外部调用者视角，
/// 通过 6 函数 + capability 的公开契约验证双向转换与 round-trip 语义。

///|
/// === capability ===

///|
test "capability - declares provider name" {
  assert_eq(@messages.capability().provider, "messages")
}

///|
/// === 请求 round-trip ===

///|
test "round trip - request encode then decode preserves semantics" {
  let original = @lux.LucentRequest::from_messages(
    "claude-sonnet-4",
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
  match @messages.lux_request_to_messages(original) {
    Ok(cr) =>
      match @messages.messages_to_lux_request(cr.value()) {
        Ok(round_cr) => {
          let round = round_cr.value()
          assert_eq(round.model, "claude-sonnet-4")
          assert_eq(round.conversation.length(), 1)
          match round.conversation[0] {
            Message(m) => {
              assert_eq(m.role, User)
              match m.content[0] {
                Text(t, _) => assert_eq(t, "hi")
                _ => assert_true(false)
              }
            }
            _ => assert_true(false)
          }
          match round.instructions {
            Some(instrs) =>
              match instrs[0] {
                Text(t, _) => assert_eq(t, "You are helpful")
                _ => assert_true(false)
              }
            None => assert_true(false)
          }
        }
        Err(_) => assert_true(false)
      }
    Err(_) => assert_true(false)
  }
}

///|
/// === 响应 round-trip ===

///|
test "round trip - response encode then decode preserves text" {
  let resp = @lux.LucentResponse::new(
    "resp-1",
    "claude-sonnet-4",
    None,
    [
      @lux.LucentChoice::new(
        0,
        @lux.LucentMessage::new(Assistant, [@lux.LucentContent::text("hi")]),
        Stop,
        None,
      ),
    ],
    None,
    None,
  )
  match @messages.lux_response_to_messages(resp) {
    Ok(cr) =>
      match @messages.messages_to_lux_response(cr.value()) {
        Ok(round_cr) => assert_eq(round_cr.value().get_text(), "hi")
        Err(_) => assert_true(false)
      }
    Err(_) => assert_true(false)
  }
}

///|
/// === 错误路径 ===

///|
test "invalid input - malformed JSON returns Err" {
  assert_true(@messages.messages_to_lux_request("{invalid}") is Err(_))
  assert_true(@messages.messages_to_lux_response("{invalid}") is Err(_))
}

///|
/// === 解码覆盖矩阵：畸形块 / 罕见特性分支 ===
///
/// 目的：驱动 messages_to_lux_request 内部的错误分支与特性分支
/// （解析失败必须产生 Degraded 诊断而非静默丢弃；合法变异必须落到
/// 正确的 IR 形态）。

///|
/// 断言 ConversionResult 的诊断列表中存在 detail 含 expect 的条目
fn diag_contains(
  cr : @lux.ConversionResult[@lux.LucentRequest],
  expect : String,
) -> Unit raise {
  for d in cr.diagnostics() {
    match d.detail {
      Some(s) => if s.contains(expect) { return }
      None => ()
    }
  }
  fail("expected diagnostic containing: \{expect}")
}

///|
fn decode_ok(json : String) -> @lux.LucentRequest raise {
  match @messages.messages_to_lux_request(json) {
    Ok(cr) => cr.value()
    Err(e) => fail("expected Ok, got Err: \{e}")
  }
}

///|
test "messages decode - malformed content blocks degrade with diagnostics" {
  let cases : Array[(String, String)] = [
    (
      "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"text\"}]}]}",
      "text block missing 'text' field",
    ),
    (
      "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"image\"}]}]}",
      "image block missing 'source' field",
    ),
    (
      "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"image\",\"source\":{\"type\":\"ftp\",\"url\":\"u\"}}]}]}",
      "image block with unknown source type: ftp",
    ),
    (
      "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"document\"}]}]}",
      "document block missing 'source' field",
    ),
    (
      "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"document\",\"source\":{\"type\":\"ftp\"}}]}]}",
      "document block with unknown source type: ftp",
    ),
    (
      "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"video\"}]}]}",
      "unknown content block type: video",
    ),
    (
      "{\"model\":\"m\",\"messages\":[{\"role\":\"user\"}]}", "message missing content",
    ),
    (
      "{\"model\":\"m\",\"messages\":[{\"role\":\"assistant\"}]}", "assistant message missing content",
    ),
    (
      "{\"model\":\"m\",\"messages\":[{\"role\":\"system\",\"content\":\"x\"}]}",
      "unknown message role: system",
    ),
    (
      "{\"model\":\"m\",\"messages\":[{\"content\":\"x\"}]}", "message missing 'role' field",
    ),
  ]
  for c in cases {
    match @messages.messages_to_lux_request(c.0) {
      Ok(cr) => diag_contains(cr, c.1)
      Err(e) => fail("unexpected Err for \{c.0}: \{e}")
    }
  }
}

///|
test "messages decode - string content becomes single text block" {
  let req = decode_ok(
    "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"},{\"role\":\"assistant\",\"content\":\"yo\"}]}",
  )
  match req.conversation[0] {
    Message(m) =>
      match m.content[0] {
        Text(t, _) => assert_eq(t, "hi")
        _ => fail("expected Text block")
      }
    _ => fail("expected Message item")
  }
}

///|
test "messages decode - tool_use without input defaults to empty object args" {
  let req = decode_ok(
    "{\"model\":\"m\",\"messages\":[{\"role\":\"assistant\",\"content\":[{\"type\":\"tool_use\",\"id\":\"t1\",\"name\":\"f\"}]}]}",
  )
  match req.conversation[0] {
    Message(m) =>
      match m.content[0] {
        ToolUse(tu) => assert_eq(tu.arguments_json, "{}")
        _ => fail("expected ToolUse block")
      }
    _ => fail("expected Message item")
  }
}

///|
test "messages decode - tool_result is_error maps to error tool result" {
  let req = decode_ok(
    "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"tool_result\",\"tool_use_id\":\"t1\",\"is_error\":true,\"content\":[{\"type\":\"text\",\"text\":\"boom\"}]}]}]}",
  )
  match req.conversation[0] {
    ToolResult(tr) => assert_true(tr.is_error)
    _ => fail("expected ToolResult item")
  }
}

///|
test "messages decode - mixed tool_result and text preserves blocks with diagnostic" {
  match
    @messages.messages_to_lux_request(
      "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"tool_result\",\"tool_use_id\":\"t1\",\"content\":[{\"type\":\"text\",\"text\":\"ok\"}]},{\"type\":\"text\",\"text\":\"thanks\"}]}]}",
    ) {
    Ok(cr) => {
      diag_contains(cr, "tool_result mixed with other content")
      match cr.value().conversation[0] {
        Message(m) => assert_eq(m.content.length(), 2)
        _ => fail("expected Message item")
      }
    }
    Err(e) => fail("unexpected Err: \{e}")
  }
}

///|
test "messages decode - image and document sources decode to media sources" {
  let req = decode_ok(
    "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"image\",\"source\":{\"type\":\"base64\",\"media_type\":\"image/png\",\"data\":\"AAA\"}},{\"type\":\"image\",\"source\":{\"type\":\"url\",\"url\":\"http://x\"}},{\"type\":\"document\",\"source\":{\"type\":\"base64\",\"media_type\":\"application/pdf\",\"data\":\"BBB\"}},{\"type\":\"document\",\"source\":{\"type\":\"url\",\"url\":\"http://y\"}}]}]}",
  )
  match req.conversation[0] {
    Message(m) => {
      match m.content[0] {
        Image(mm) =>
          match mm.source {
            Inline(d) => assert_eq(d, "AAA")
            _ => fail("expected Inline source")
          }
        _ => fail("expected Image block")
      }
      match m.content[1] {
        Image(mm) =>
          match mm.source {
            Url(u) => assert_eq(u, "http://x")
            _ => fail("expected Url source")
          }
        _ => fail("expected Image block")
      }
      match m.content[2] {
        File(mm) =>
          match mm.source {
            Inline(d) => assert_eq(d, "BBB")
            _ => fail("expected Inline source")
          }
        _ => fail("expected File block")
      }
      match m.content[3] {
        File(mm) =>
          match mm.source {
            Url(u) => assert_eq(u, "http://y")
            _ => fail("expected Url source")
          }
        _ => fail("expected File block")
      }
    }
    _ => fail("expected Message item")
  }
}

///|
test "messages decode - tools type maps to tool kind" {
  let req = decode_ok(
    "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"tools\":[{\"type\":\"custom\",\"name\":\"f\",\"input_schema\":{}},{\"type\":\"code_execution_20250522\",\"name\":\"c\"},{\"type\":\"bash_20250124\",\"name\":\"b\"},{\"type\":\"weird_20260101\",\"name\":\"w\"},{\"name\":\"n\"}]}",
  )
  match req.tools {
    Some(ts) => {
      assert_eq(ts.length(), 5)
      assert_eq(ts[0].kind, Function)
      assert_eq(ts[1].kind, CodeExecution)
      assert_eq(ts[2].kind, Shell)
      assert_eq(ts[3].kind, Native("weird_20260101"))
      assert_eq(ts[4].kind, Function)
      // input_schema 缺失 → "{}"
      assert_eq(ts[1].parameters_json, "{}")
    }
    None => fail("expected tools")
  }
}

///|
/// 包装辅助：把 payload 塞进标准请求的指定字段，避免手数外层大括号
fn msgs_req(field : String, payload : String) -> String {
  "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"" +
  field +
  "\":" +
  payload +
  "}"
}

///|
test "messages decode - tool_choice variants" {
  assert_eq(
    decode_ok(msgs_req("tool_choice", "{\"type\":\"auto\"}")).tool_choice,
    Some(Auto),
  )
  assert_eq(
    decode_ok(msgs_req("tool_choice", "{\"type\":\"any\"}")).tool_choice,
    Some(Required),
  )
  assert_eq(
    decode_ok(msgs_req("tool_choice", "{\"type\":\"tool\",\"name\":\"f\"}")).tool_choice,
    Some(SpecificTool("f")),
  )
  assert_eq(
    decode_ok(msgs_req("tool_choice", "{\"type\":\"tool\"}")).tool_choice,
    None,
  )
  assert_eq(
    decode_ok(msgs_req("tool_choice", "{\"type\":\"bogus\"}")).tool_choice,
    None,
  )
  // tool_choice 非对象 → None
  assert_eq(decode_ok(msgs_req("tool_choice", "\"auto\"")).tool_choice, None)
}

///|
test "messages decode - thinking config variants" {
  match
    decode_ok(
      msgs_req("thinking", "{\"type\":\"enabled\",\"budget_tokens\":1024}"),
    ).reasoning {
    Some(rc) => {
      assert_true(rc.enabled)
      assert_eq(rc.budget_tokens, Some(1024))
    }
    None => fail("expected reasoning config")
  }
  // enabled 但 budget_tokens 非数字 → budget None
  match
    decode_ok(
      msgs_req("thinking", "{\"type\":\"enabled\",\"budget_tokens\":\"big\"}"),
    ).reasoning {
    Some(rc) => assert_eq(rc.budget_tokens, None)
    None => fail("expected reasoning config")
  }
  // adaptive → 启用、无 budget
  match decode_ok(msgs_req("thinking", "{\"type\":\"adaptive\"}")).reasoning {
    Some(rc) => {
      assert_eq(rc.budget_tokens, None)
      assert_eq(rc.effort, None)
    }
    None => fail("expected reasoning config")
  }
  // 未知形态 → disabled（保守）
  match decode_ok(msgs_req("thinking", "{\"type\":\"weird\"}")).reasoning {
    Some(rc) => assert_false(rc.enabled)
    None => fail("expected reasoning config")
  }
  // thinking 非对象 → 无 reasoning
  assert_eq(decode_ok(msgs_req("thinking", "\"enabled\"")).reasoning, None)
}

///|
test "messages decode - output_config effort variants" {
  assert_eq(
    decode_ok(msgs_req("output_config", "{\"effort\":\"low\"}")).reasoning.unwrap().effort,
    Some(Low),
  )
  assert_eq(
    decode_ok(msgs_req("output_config", "{\"effort\":\"medium\"}")).reasoning.unwrap().effort,
    Some(Medium),
  )
  assert_eq(
    decode_ok(msgs_req("output_config", "{\"effort\":\"high\"}")).reasoning.unwrap().effort,
    Some(High),
  )
  assert_eq(
    decode_ok(msgs_req("output_config", "{\"effort\":\"xhigh\"}")).reasoning.unwrap().effort,
    Some(XHigh),
  )
  // 未知 effort → None（不猜）
  assert_eq(
    decode_ok(msgs_req("output_config", "{\"effort\":\"ultra\"}")).reasoning,
    None,
  )
  // max → XHigh + 降级诊断
  match
    @messages.messages_to_lux_request(
      msgs_req("output_config", "{\"effort\":\"max\"}"),
    ) {
    Ok(cr) => diag_contains(cr, "downgraded to xhigh")
    Err(e) => fail("unexpected Err: \{e}")
  }
}

///|
test "messages decode - output_config format variants" {
  match
    decode_ok(
      msgs_req(
        "output_config", "{\"format\":{\"type\":\"json_schema\",\"schema\":{}}}",
      ),
    ).options.structured_output {
    Some(JsonObject) => ()
    _ => fail("expected JsonObject")
  }
  match
    decode_ok(
      msgs_req("output_config", "{\"format\":{\"type\":\"json_schema\"}}"),
    ).options.structured_output {
    Some(JsonObject) => ()
    _ => fail("expected JsonObject")
  }
  match
    decode_ok(
      msgs_req(
        "output_config", "{\"format\":{\"type\":\"json_schema\",\"schema\":{\"type\":\"object\"}}}",
      ),
    ).options.structured_output {
    Some(JsonSchema(s)) => assert_true(s.contains("object"))
    _ => fail("expected JsonSchema")
  }
  match
    decode_ok(msgs_req("output_config", "{\"format\":{\"type\":\"text\"}}")).options.structured_output {
    Some(Text) => ()
    _ => fail("expected Text")
  }
  // 未知 format → None
  assert_eq(
    decode_ok(msgs_req("output_config", "{\"format\":{\"type\":\"yaml\"}}")).options.structured_output,
    None,
  )
  // format 缺失 → None
  assert_eq(
    decode_ok(msgs_req("output_config", "{\"effort\":\"low\"}")).options.structured_output,
    None,
  )
}

///|
test "messages decode - system array parses text blocks and skips others" {
  let req = decode_ok(
    "{\"model\":\"m\",\"system\":[{\"text\":\"a\"},{\"type\":\"text\",\"text\":\"b\"},{\"image\":\"x\"}],\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}",
  )
  match req.instructions {
    Some(instrs) => assert_eq(instrs.length(), 2)
    None => fail("expected instructions")
  }
}

///|
test "messages decode - metadata keeps only string values" {
  let req = decode_ok(
    "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"metadata\":{\"k\":\"v\",\"n\":42}}",
  )
  match req.metadata {
    Some(m) => {
      assert_eq(m["k"], "v")
      assert_false(m.contains("n"))
    }
    None => fail("expected metadata")
  }
}

///|
/// === SSE 解码覆盖补齐：畸形帧 / error 事件 / 未知事件类型 ===
///
/// stream_decode.mbt（messages_sse_to_events）此前只被白盒 SSE 测试覆盖了
/// text / tool / done 的主路径；以下黑盒测试补齐「合法事件类型 + 字段缺失或类型
/// 错误 → 静默跳过」「error 事件（对象无 message / 无 error 键）」「未知 event
/// 类型」三条分支。契约：任何畸形帧都不抛错，只是在事件流中不产生对应事件。

///|
/// 构造单个标准 Anthropic SSE 帧（event + data + 空行分隔），与线上线格式一致。
fn sse_frame(event_type : String, data : String) -> String {
  "event: " + event_type + "\n" + "data: " + data + "\n\n"
}

///|
/// 流解码成功快捷方式（失败即 fail）。
fn sse_events_ok(sse : String) -> Array[@lux.LucentStreamEvent] raise {
  match @messages.messages_sse_to_events(sse) {
    Ok(cr) => cr.value()
    Err(e) => fail("expected Ok, got Err: \{e}")
  }
}

///|
/// 事件类型合法、但缺字段或字段类型不符 → 整帧被安全跳过，不产生任何事件。
test "messages decode - sse frames missing required fields emit no events" {
  let sse = sse_frame("message_start", "{\"type\":\"message_start\"}") +
    sse_frame(
      "content_block_start", "{\"type\":\"content_block_start\",\"index\":0}",
    ) +
    sse_frame(
      "content_block_start", "{\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"image\"}}",
    ) +
    sse_frame(
      "content_block_delta", "{\"type\":\"content_block_delta\",\"index\":0}",
    ) +
    sse_frame(
      "content_block_delta", "{\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\"}}",
    ) +
    sse_frame(
      "content_block_delta", "{\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"thinking_delta\"}}",
    ) +
    sse_frame(
      "content_block_delta", "{\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"signature_delta\"}}",
    ) +
    sse_frame(
      "content_block_delta", "{\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"input_json_delta\"}}",
    ) +
    sse_frame(
      "content_block_delta", "{\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"mystery_delta\"}}",
    ) +
    sse_frame("message_delta", "{\"type\":\"message_delta\"}")
  assert_eq(sse_events_ok(sse).length(), 0)
}

///|
/// error 事件的三种形态：error 对象缺 message → 用 error.type 兜底；
/// error 为字符串 → 该字符串本身就是 message（obj_get 返回键值本身，
/// 字符串值若落进对象分支会退化成 "unknown error" 并丢掉真正的错误文本）；
/// 顶层无 error 键 → 静默跳过。三者都不抛错。
test "messages decode - sse error events without message and without error key" {
  // error 对象有 type 无 message → message 回退为 type
  let type_only = sse_frame(
    "error", "{\"type\":\"error\",\"error\":{\"type\":\"overloaded_error\"}}",
  )
  // error 为字符串 → 字符串本身作为 message（simple 构造）
  let string_error = sse_frame(
    "error", "{\"type\":\"error\",\"error\":\"boom\"}",
  )
  // 顶层无 error 键 → 静默跳过，不产生事件
  let no_error_key = sse_frame("error", "{\"type\":\"error\"}")
  let events = sse_events_ok(type_only + string_error + no_error_key)
  let msgs : Array[String] = []
  for ev in events {
    match ev {
      Error(e) => msgs.push(e.message)
      _ => ()
    }
  }
  // 前两帧各产一个 Error（分别是 type 兜底 / 字符串原文），无 error 键的帧被跳过。
  assert_eq(msgs, ["overloaded_error", "boom"])
}

///|
/// 未知 event 类型（Anthropic 心跳 ping / 未来新事件）→ 顶层 match 默认分支，
/// 不产生任何事件。
test "messages decode - sse unknown event type is ignored" {
  let sse = sse_frame("ping", "{\"type\":\"ping\"}")
  assert_eq(sse_events_ok(sse).length(), 0)
}

///|
/// 响应解码辅助：按 stop_reason 字符串解码（空串 = 省略 stop_reason 字段），
/// 返回 choice.finish_reason。
fn decode_resp_finish(stop_reason : String) -> @lux.LucentFinishReason raise {
  let tail = if stop_reason == "" {
    ""
  } else {
    ",\"stop_reason\":\"" + stop_reason + "\""
  }
  let json = "{\"id\":\"m\",\"model\":\"mm\",\"content\":[{\"type\":\"text\",\"text\":\"hi\"}]" +
    tail +
    "}"
  match @messages.messages_to_lux_response(json) {
    Ok(cr) => cr.value().choices[0].finish_reason
    Err(e) => fail("unexpected Err: \{e}")
  }
}

///|
/// 响应解码：无 content 字段 → 空内容数组；stop_reason 全谱系 → finish_reason
/// （已知映射 / 未知 Native 透传 / 缺失 → Stop）。
test "messages decode - response without content and stop_reason mapping" {
  match
    @messages.messages_to_lux_response(
      "{\"id\":\"m\",\"model\":\"mm\",\"stop_reason\":\"end_turn\"}",
    ) {
    Ok(cr) => {
      let resp = cr.value()
      assert_eq(resp.choices.length(), 1)
      assert_eq(resp.choices[0].message.content.length(), 0)
    }
    Err(e) => fail("unexpected Err: \{e}")
  }
  assert_eq(decode_resp_finish("end_turn"), Stop)
  assert_eq(decode_resp_finish("max_tokens"), Length)
  assert_eq(decode_resp_finish("tool_use"), ToolCalls)
  assert_eq(decode_resp_finish("stop_sequence"), Stop)
  // 未知 stop_reason → Native 透传
  match decode_resp_finish("pause_turn") {
    Native(s) => assert_eq(s, "pause_turn")
    _ => fail("expected Native finish reason")
  }
  // stop_reason 缺失 → Stop
  assert_eq(decode_resp_finish(""), Stop)
}

///|
/// 响应编码辅助：按 finish_reason + usage 组装 LucentResponse，编码为 Anthropic 出站体。
fn encode_resp(
  finish : @lux.LucentFinishReason,
  usage : @lux.LucentUsage?,
) -> String raise {
  let resp = @lux.LucentResponse::new(
    "msg_x",
    "claude-sonnet-4",
    None,
    [
      @lux.LucentChoice::new(
        0,
        @lux.LucentMessage::new(Assistant, [@lux.LucentContent::text("hi")]),
        finish,
        None,
      ),
    ],
    usage,
    None,
  )
  match @messages.lux_response_to_messages(resp) {
    Ok(cr) => cr.value()
    Err(e) => fail("unexpected Err: \{e}")
  }
}

///|
/// 响应编码：finish_reason 全谱系 → Anthropic stop_reason（已知映射 / 无对等值收敛为
/// "end_turn" / Native 合法值透传、非法值收敛）；usage 携带 cache_creation /
/// cached tokens → cache_creation_input_tokens / cache_read_input_tokens。
test "messages encode - response finish reason and cache usage details" {
  let cases : Array[(@lux.LucentFinishReason, String)] = [
    (Stop, "end_turn"),
    (Length, "max_tokens"),
    (ToolCalls, "tool_use"),
    (ContentFilter, "refusal"),
    // Safety → refusal：官方对 refusal 的定义即 "streaming classifiers
    // intervene to handle potential policy violations"，是 stop_reason 枚举里
    // 与「安全拦截」语义对等的唯一值（此前映射 "safety" 不在官方 7 值内，
    // 被收敛 end_turn，把拦截伪装成正常结束 —— 校验系统实测发现）
    (Safety, "refusal"),
    (Recitation, "end_turn"),
    (MalformedToolCall, "end_turn"),
    (Error, "end_turn"),
    // Native 只有落在 Anthropic 合法集合内才透传；pause_turn 是其合法值
    (Native("pause_turn"), "pause_turn"),
    // 非 Anthropic 词汇表的值必须收敛，不得溢出
    (Native("vendor_x"), "end_turn"),
  ]
  for c in cases {
    assert_true(
      encode_resp(c.0, None).contains("\"stop_reason\":\"" + c.1 + "\""),
    )
  }
  let cache_json = encode_resp(
    Stop,
    Some(@lux.LucentUsage::full(100, 20, 120, None, Some(30), Some(50))),
  )
  assert_true(cache_json.contains("\"cache_creation_input_tokens\":50"))
  assert_true(cache_json.contains("\"cache_read_input_tokens\":30"))
}

///|
/// tool_result 的 content 数组内含畸形块 → 该块被静默跳过（Err 分支）；
/// tool_result 缺 content 字段 → 空内容数组。二者均落为独立 ToolResult item。
test "messages decode - tool_result malformed and missing content become empty result" {
  let cases = [
    "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"tool_result\",\"tool_use_id\":\"t1\",\"content\":[{\"type\":\"text\"}]}]}]}",
    "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"tool_result\",\"tool_use_id\":\"t1\"}]}]}",
  ]
  for json in cases {
    let req = decode_ok(json)
    match req.conversation[0] {
      ToolResult(tr) => assert_eq(tr.content.length(), 0)
      _ => fail("expected ToolResult item")
    }
  }
}

///|
/// content 块无 type 字段 → parse_content_block 返回 Err，经 parse_content_blocks
/// 转 Degraded 诊断并跳过，整体仍 Ok 返回。
test "messages decode - content block missing type degrades with diagnostic" {
  match
    @messages.messages_to_lux_request(
      "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":[{\"data\":\"x\"}]}]}",
    ) {
    Ok(cr) => {
      diag_contains(cr, "content block missing 'type' field")
      match cr.value().conversation[0] {
        Message(m) => assert_eq(m.content.length(), 0)
        _ => fail("expected Message item")
      }
    }
    Err(e) => fail("unexpected Err: \{e}")
  }
}

///|
/// 请求无 messages 字段 → field_arr None 分支，conversation 为空。
test "messages decode - request without messages yields empty conversation" {
  assert_eq(decode_ok("{\"model\":\"m\"}").conversation.length(), 0)
}

///|
/// === TASK-4b：request decode 顶层形状守卫（QA P1-1，ACC-004 / TC-7 / TC-8）===

///|
test "decode guard - top-level array request is rejected with Err" {
  // 回退即红：守卫移除后该文档将静默降级为空 IR 请求
  assert_true(@messages.messages_to_lux_request("[1,2,3]") is Err(_))
  assert_true(@messages.messages_to_lux_request("42") is Err(_))
  assert_true(@messages.messages_to_lux_request("\"text\"") is Err(_))
  assert_true(@messages.messages_to_lux_request("null") is Err(_))
}

///|
test "decode guard - messages wrong type yields Invalid diagnostic" {
  // messages: 42 → Invalid 诊断透出，不静默成空请求
  match @messages.messages_to_lux_request("{\"model\":\"m\",\"messages\":42}") {
    Ok(cr) => {
      let diags = cr.diagnostics()
      assert_eq(diags.length(), 1)
      assert_eq(diags[0].status(), Invalid)
      assert_eq(diags[0].field, "messages")
    }
    Err(e) => fail("expected Ok with Invalid diagnostic, got: \{e}")
  }
}

///|
test "decode guard - null and missing messages stay lenient" {
  // null 按缺失宽松处理；缺失同（既有合法行为，回归锚点）
  assert_true(@messages.messages_to_lux_request("{\"messages\":null}") is Ok(_))
  assert_true(@messages.messages_to_lux_request("{\"model\":\"m\"}") is Ok(_))
}
