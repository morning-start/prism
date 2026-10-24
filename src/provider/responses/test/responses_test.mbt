///|
/// OpenAI Responses 适配器黑盒测试 — 仅通过公开 API 验证
///
/// 与白盒测试（_wbtest.mbt）互补：模拟外部调用者视角，
/// 通过 6 函数 + capability 的公开契约验证双向转换与 round-trip 语义。

///|
/// === capability ===

///|
test "capability - declares provider name" {
  assert_eq(@responses.capability().provider, "openai")
}

///|
/// === 请求 round-trip ===

///|
test "round trip - request encode then decode preserves semantics" {
  let original = @lux.LucentRequest::from_messages(
    "gpt-4o",
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
  match @responses.lux_request_to_responses(original) {
    Ok(cr1) =>
      match @responses.responses_to_lux_request(cr1.value()) {
        Ok(cr2) => {
          let round = cr2.value()
          assert_eq(round.model, "gpt-4o")
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
    "gpt-4o",
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
  match @responses.lux_response_to_responses(resp) {
    Ok(cr1) =>
      match @responses.responses_to_lux_response(cr1.value()) {
        Ok(cr2) => assert_eq(cr2.value().get_text(), "hi")
        Err(_) => assert_true(false)
      }
    Err(_) => assert_true(false)
  }
}

///|
/// === 错误路径 ===

///|
test "invalid input - malformed JSON returns Err" {
  assert_true(@responses.responses_to_lux_request("{invalid}") is Err(_))
  assert_true(@responses.responses_to_lux_response("{invalid}") is Err(_))
}

///|
/// === 解码覆盖矩阵：畸形块 / 罕见特性分支 ===
///
/// 目的：驱动 responses_to_lux_request / responses_to_lux_response /
/// responses_sse_to_events 内部的错误分支与特性分支（解析失败必须产生
/// Degraded / Unsupported / Invalid 诊断而非静默丢弃；合法变异必须落到
/// 正确的 IR 形态）。

///|
/// 断言请求 ConversionResult 的诊断列表中存在 detail 含 expect 的条目
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
/// 断言响应 ConversionResult 的诊断列表中存在 detail 含 expect 的条目
fn resp_diag_contains(
  cr : @lux.ConversionResult[@lux.LucentResponse],
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
  match @responses.responses_to_lux_request(json) {
    Ok(cr) => cr.value()
    Err(e) => fail("expected Ok, got Err: \{e}")
  }
}

///|
fn decode_resp_ok(json : String) -> @lux.LucentResponse raise {
  match @responses.responses_to_lux_response(json) {
    Ok(cr) => cr.value()
    Err(e) => fail("expected Ok, got Err: \{e}")
  }
}

///|
fn sse_ok(sse : String) -> Array[@lux.LucentStreamEvent] raise {
  match @responses.responses_sse_to_events(sse) {
    Ok(cr) => cr.value()
    Err(e) => fail("expected Ok, got Err: \{e}")
  }
}

///|
/// 包装辅助：把 payload 塞进标准请求的指定顶层字段，避免手数外层大括号
fn resp_req(field : String, payload : String) -> String {
  "{\"model\":\"m\",\"input\":[{\"type\":\"message\",\"role\":\"user\"," +
  "\"content\":[{\"type\":\"input_text\",\"text\":\"hi\"}]}]," +
  "\"" +
  field +
  "\":" +
  payload +
  "}"
}

///|
test "responses decode - malformed input parts skip or degrade silently" {
  // input_text 缺 text / input_image 空 URL / 畸形 data URI（media_type 与
  // payload 均回退默认值）/ input_file 空 file_data / input_image 缺
  // image_url / 未知 part 类型：一律跳过，不得 Err、不得静默产生半成品块
  let req = decode_ok(
    "{\"model\":\"m\",\"input\":[{\"type\":\"message\",\"role\":\"user\",\"content\":[" +
    "{\"type\":\"input_text\"}," +
    "{\"type\":\"input_image\",\"image_url\":\"\"}," +
    "{\"type\":\"input_image\",\"image_url\":\"d;ta:image/png;base64,AAA\"}," +
    "{\"type\":\"input_image\",\"image_url\":\"data:image/png;base64,\"}," +
    "{\"type\":\"input_image\"}," +
    "{\"type\":\"input_file\",\"file_data\":\"\"}," +
    "{\"type\":\"input_file\",\"file_data\":\"d;ta:application/pdf;base64,BBB\"}," +
    "{\"type\":\"input_file\",\"file_data\":\"data:application/pdf;base64,\"}," +
    "{\"type\":\"input_audio\",\"data\":\"x\"}" +
    "]}]}",
  )
  assert_eq(req.conversation.length(), 1)
  match req.conversation[0] {
    Message(m) => assert_eq(m.content.length(), 0)
    _ => fail("expected Message item")
  }
}

///|
test "responses decode - input_file non data uri and file_id only degrade" {
  // 非 data URI 的 file_data 与仅 file_id（服务器端引用）必须显式 Degraded
  let json = "{\"model\":\"m\",\"input\":[{\"type\":\"message\",\"role\":\"user\",\"content\":[" +
    "{\"type\":\"input_file\",\"file_data\":\"https://x.com/a.pdf\"}," +
    "{\"type\":\"input_file\",\"file_id\":\"file-abc\"}" +
    "]}]}"
  match @responses.responses_to_lux_request(json) {
    Ok(cr) => {
      diag_contains(cr, "file_data must be a data URI")
      diag_contains(cr, "file_id not mapped to multimedia")
      match cr.value().conversation[0] {
        Message(m) => assert_eq(m.content.length(), 0)
        _ => fail("expected Message item")
      }
    }
    Err(e) => fail("unexpected Err: \{e}")
  }
}

///|
test "responses decode - message without content array yields empty content" {
  // content 字段缺失 → 空内容消息（而不是丢弃整条 item）
  let req = decode_ok(
    "{\"model\":\"m\",\"input\":[{\"type\":\"message\",\"role\":\"user\"}]}",
  )
  assert_eq(req.conversation.length(), 1)
  match req.conversation[0] {
    Message(m) => assert_eq(m.content.length(), 0)
    _ => fail("expected Message item")
  }
}

///|
test "responses decode - assistant and developer roles map to roles" {
  // "assistant" / "developer" 显式映射；未知 role 保守回退 User
  let req = decode_ok(
    "{\"model\":\"m\",\"input\":[" +
    "{\"type\":\"message\",\"role\":\"assistant\",\"content\":[{\"type\":\"input_text\",\"text\":\"a\"}]}," +
    "{\"type\":\"message\",\"role\":\"developer\",\"content\":[{\"type\":\"input_text\",\"text\":\"d\"}]}," +
    "{\"type\":\"message\",\"role\":\"weird\",\"content\":[{\"type\":\"input_text\",\"text\":\"w\"}]}" +
    "]}",
  )
  assert_eq(req.conversation.length(), 3)
  match req.conversation[0] {
    Message(m) => assert_eq(m.role, Assistant)
    _ => fail("expected Message item 0")
  }
  match req.conversation[1] {
    Message(m) => assert_eq(m.role, Developer)
    _ => fail("expected Message item 1")
  }
  match req.conversation[2] {
    Message(m) => assert_eq(m.role, User)
    _ => fail("expected Message item 2")
  }
}

///|
test "responses decode - reasoning input item summary parts and signature" {
  // summary 数组中缺 text 的条目跳过；reasoning 无 summary 时 text 为空串
  let req = decode_ok(
    "{\"model\":\"m\",\"input\":[" +
    "{\"type\":\"reasoning\",\"summary\":[{\"type\":\"summary_text\",\"text\":\"step1\"},{\"type\":\"summary_text\"}],\"signature\":\"sig_1\"}," +
    "{\"type\":\"reasoning\"}" +
    "]}",
  )
  assert_eq(req.conversation.length(), 2)
  match req.conversation[0] {
    Reasoning(th) => {
      assert_eq(th.text, "step1")
      assert_eq(th.signature, Some("sig_1"))
      match th.summary {
        Some(arr) => assert_eq(arr.length(), 1)
        None => fail("expected summary array")
      }
    }
    _ => fail("expected Reasoning item")
  }
  match req.conversation[1] {
    Reasoning(th) => {
      assert_eq(th.text, "")
      assert_eq(th.signature, None)
      assert_eq(th.summary, None)
    }
    _ => fail("expected Reasoning item without summary")
  }
}

///|
test "responses decode - function_call and output items use defaults" {
  // function_call / function_call_output 各字段缺失时走默认值
  let req = decode_ok(
    "{\"model\":\"m\",\"input\":[" +
    "{\"type\":\"function_call\"}," +
    "{\"type\":\"function_call_output\"}" +
    "]}",
  )
  assert_eq(req.conversation.length(), 2)
  match req.conversation[0] {
    ToolCall(tu) => {
      assert_eq(tu.id, "")
      assert_eq(tu.name, "")
      assert_eq(tu.arguments_json, "{}")
    }
    _ => fail("expected ToolCall item")
  }
  match req.conversation[1] {
    ToolResult(tr) => {
      assert_eq(tr.tool_use_id, "")
      match tr.content[0] {
        Text(t, _) => assert_eq(t, "")
        _ => fail("expected Text content")
      }
    }
    _ => fail("expected ToolResult item")
  }
}

///|
test "responses decode - typeless item role and content fallbacks" {
  // 无 type 的 item：role 决定角色（含 developer）；content 可为数组（未知
  // part 跳过）、字符串，或既非数组也非字符串（回退空数组）；既无 type 又无
  // role 的 item 被整体跳过
  let req = decode_ok(
    "{\"model\":\"m\",\"input\":[" +
    "{\"role\":\"assistant\",\"content\":[{\"type\":\"input_text\",\"text\":\"a\"},{\"type\":\"input_text\"},{\"type\":\"input_image\",\"image_url\":\"u\"}]}," +
    "{\"role\":\"developer\",\"content\":\"dev string\"}," +
    "{\"role\":\"user\",\"content\":42}," +
    "{\"role\":\"user\",\"content\":\"plain string\"}," +
    "{\"role\":\"weird\",\"content\":\"unknown role\"}," +
    "{\"foo\":\"bar\"}" +
    "]}",
  )
  assert_eq(req.conversation.length(), 5)
  match req.conversation[0] {
    Message(m) => {
      assert_eq(m.role, Assistant)
      assert_eq(m.content.length(), 1)
    }
    _ => fail("expected Message item 0")
  }
  match req.conversation[1] {
    Message(m) => {
      assert_eq(m.role, Developer)
      assert_eq(m.content.length(), 1)
    }
    _ => fail("expected Message item 1")
  }
  // content 既非数组也非字符串 → 空内容
  match req.conversation[2] {
    Message(m) => assert_eq(m.content.length(), 0)
    _ => fail("expected Message item 2")
  }
  match req.conversation[3] {
    Message(m) =>
      match m.content[0] {
        Text(t, _) => assert_eq(t, "plain string")
        _ => fail("expected Text content")
      }
    _ => fail("expected Message item 3")
  }
  // 未知 role（无 type）→ 保守回退 User
  match req.conversation[4] {
    Message(m) => {
      assert_eq(m.role, User)
      match m.content[0] {
        Text(t, _) => assert_eq(t, "unknown role")
        _ => fail("expected Text content")
      }
    }
    _ => fail("expected Message item 4")
  }
}

///|
test "responses decode - input missing or non array yields empty conversation" {
  // input 缺失或既非 string 也非 array → 空会话
  assert_eq(decode_ok("{\"model\":\"m\"}").conversation.length(), 0)
  assert_eq(
    decode_ok("{\"model\":\"m\",\"input\":42}").conversation.length(),
    0,
  )
}

///|
test "responses decode - tool kinds cover server tools and native fallback" {
  // file_search / code_interpreter / computer_use 精确映射；未知 type 落
  // Native；无 type 的 tool 回退 Function；parameters 缺失 → "{}"
  let req = decode_ok(
    "{\"model\":\"m\",\"input\":[{\"type\":\"message\",\"role\":\"user\",\"content\":[{\"type\":\"input_text\",\"text\":\"hi\"}]}]," +
    "\"tools\":[" +
    "{\"type\":\"file_search\",\"name\":\"fs\"}," +
    "{\"type\":\"code_interpreter\",\"name\":\"ci\"}," +
    "{\"type\":\"computer_use\",\"name\":\"cu\"}," +
    "{\"type\":\"mystery_tool_v9\",\"name\":\"mx\"}," +
    "{\"name\":\"no_type\"}" +
    "]}",
  )
  match req.tools {
    Some(ts) => {
      assert_eq(ts.length(), 5)
      assert_eq(ts[0].kind, FileSearch)
      assert_eq(ts[1].kind, CodeInterpreter)
      assert_eq(ts[2].kind, ComputerUse)
      assert_eq(ts[3].kind, Native("mystery_tool_v9"))
      assert_eq(ts[4].kind, Function)
      assert_eq(ts[0].parameters_json, "{}")
    }
    None => fail("expected tools")
  }
}

///|
test "responses decode - tool_choice variants" {
  assert_eq(
    decode_ok(resp_req("tool_choice", "\"auto\"")).tool_choice,
    Some(Auto),
  )
  assert_eq(
    decode_ok(resp_req("tool_choice", "\"none\"")).tool_choice,
    Some(None),
  )
  assert_eq(
    decode_ok(resp_req("tool_choice", "\"required\"")).tool_choice,
    Some(Required),
  )
  // 未知字符串 / 非字符串 → None
  assert_eq(decode_ok(resp_req("tool_choice", "\"bogus\"")).tool_choice, None)
  assert_eq(decode_ok(resp_req("tool_choice", "42")).tool_choice, None)
}

///|
test "responses decode - text format variants" {
  match
    decode_ok(resp_req("text", "{\"format\":{\"type\":\"text\"}}")).options.structured_output {
    Some(Text) => ()
    _ => fail("expected Text structured output")
  }
  match
    decode_ok(resp_req("text", "{\"format\":{\"type\":\"json_object\"}}")).options.structured_output {
    Some(JsonObject) => ()
    _ => fail("expected JsonObject structured output")
  }
  match
    decode_ok(
      resp_req(
        "text", "{\"format\":{\"type\":\"json_schema\",\"schema\":{\"type\":\"object\",\"properties\":{\"a\":{\"type\":\"string\"}}}}}",
      ),
    ).options.structured_output {
    Some(JsonSchema(s)) => assert_true(s.contains("properties"))
    _ => fail("expected JsonSchema structured output")
  }
  // json_schema 缺 schema → None
  assert_eq(
    decode_ok(resp_req("text", "{\"format\":{\"type\":\"json_schema\"}}")).options.structured_output,
    None,
  )
  // 未知 format 类型 / format 非对象 / format 缺失 → None
  assert_eq(
    decode_ok(resp_req("text", "{\"format\":{\"type\":\"yaml\"}}")).options.structured_output,
    None,
  )
  assert_eq(
    decode_ok(resp_req("text", "{\"format\":\"flat\"}")).options.structured_output,
    None,
  )
  assert_eq(decode_ok(resp_req("text", "{}")).options.structured_output, None)
}

///|
test "responses decode - numeric and boolean options round trip" {
  let req = decode_ok(
    "{\"model\":\"m\",\"temperature\":0.5,\"top_p\":0.9,\"max_output_tokens\":256," +
    "\"stream\":true,\"store\":false,\"input\":\"hi\",\"vendor_flag\":\"on\"}",
  )
  assert_eq(req.options.temperature, Some(0.5))
  assert_eq(req.options.top_p, Some(0.9))
  assert_eq(req.options.max_output_tokens, Some(256))
  assert_eq(req.options.stream, true)
  assert_eq(req.options.store, Some(false))
  match req.options.extras {
    Some(m) => assert_true(m.contains("vendor_flag"))
    None => fail("expected extras")
  }
}

///|
/// request_decode.mbt 的 append_field：reasoning 编码时 summary 前的逗号拼接
/// （effort + summary 同时存在 → base != ""；仅 summary → base == ""）
test "responses decode - append_field exercised by reasoning summary encode" {
  let mk = fn(rc : @lux.LucentReasoningConfig) -> @lux.LucentRequest {
    @lux.LucentRequest::new(
      "gpt-5",
      None,
      [
        @lux.LucentConversationItem::message(
          @lux.LucentMessage::new(User, [@lux.LucentContent::text("hi")]),
        ),
      ],
      None,
      None,
      @lux.LucentOptions::default(),
      None,
      Some(rc),
      None,
      None,
    )
  }
  match
    @responses.lux_request_to_responses(
      mk(@lux.LucentReasoningConfig::new(Some(Medium), Some(Concise))),
    ) {
    Ok(cr) =>
      assert_true(
        cr
        .value()
        .contains(
          "\"reasoning\":{\"effort\":\"medium\",\"summary\":\"concise\"}",
        ),
      )
    Err(e) => fail("encode failed: \{e}")
  }
  match
    @responses.lux_request_to_responses(
      mk(@lux.LucentReasoningConfig::new(None, Some(Detailed))),
    ) {
    Ok(cr) =>
      assert_true(
        cr.value().contains("\"reasoning\":{\"summary\":\"detailed\"}"),
      )
    Err(e) => fail("encode failed: \{e}")
  }
}

///|
test "responses decode - reasoning output item with summary and signature" {
  // reasoning output item：summary 数组（缺 text 的条目跳过）、signature 保留；
  // 无 summary 时 text 为空串
  let resp = decode_resp_ok(
    "{\"id\":\"r\",\"model\":\"m\",\"output\":[" +
    "{\"type\":\"reasoning\",\"summary\":[{\"text\":\"think a\"},{\"type\":\"summary_text\"}],\"signature\":\"sig_9\"}," +
    "{\"type\":\"reasoning\"}" +
    "]}",
  )
  assert_eq(resp.choices[0].message.content.length(), 2)
  match resp.choices[0].message.content[0] {
    Thinking(th) => {
      assert_eq(th.text, "think a")
      assert_eq(th.signature, Some("sig_9"))
      // LucentContent::thinking 不携带 summary 载体（summary 已折进 text）
      assert_eq(th.summary, None)
    }
    _ => fail("expected Thinking block")
  }
  match resp.choices[0].message.content[1] {
    Thinking(th) => {
      assert_eq(th.text, "")
      assert_eq(th.signature, None)
      assert_eq(th.summary, None)
    }
    _ => fail("expected Thinking block without summary")
  }
}

///|
test "responses decode - refusal and malformed output parts" {
  // refusal 块（读 text 字段）、refusal 缺 text、output_text 缺 text、
  // 未知 part 类型、message 无 content 数组、未知 output item 类型
  let resp = decode_resp_ok(
    "{\"id\":\"r\",\"model\":\"m\",\"output\":[" +
    "{\"type\":\"message\",\"content\":[{\"type\":\"output_text\"},{\"type\":\"refusal\",\"text\":\"I cannot\"},{\"type\":\"refusal\"},{\"type\":\"output_audio\"}]}," +
    "{\"type\":\"message\"}," +
    "{\"type\":\"web_search_call\",\"id\":\"ws_1\"}" +
    "]}",
  )
  assert_eq(resp.choices[0].message.content.length(), 1)
  match resp.choices[0].message.content[0] {
    Refusal(s) => assert_eq(s, "I cannot")
    _ => fail("expected Refusal block")
  }
}

///|
test "responses decode - status variants map to finish reasons" {
  let base = "{\"id\":\"r\",\"model\":\"m\",\"output\":[],\"status\":"
  assert_eq(
    decode_resp_ok(base + "\"completed\"}").choices[0].finish_reason,
    Stop,
  )
  assert_eq(
    decode_resp_ok(base + "\"incomplete\"}").choices[0].finish_reason,
    Length,
  )
  assert_eq(
    decode_resp_ok(base + "\"failed\"}").choices[0].finish_reason,
    Error,
  )
  // 其他字符串 → LucentFinishReason::from_string
  assert_eq(
    decode_resp_ok(base + "\"content_filter\"}").choices[0].finish_reason,
    ContentFilter,
  )
  assert_eq(
    decode_resp_ok(base + "\"weird_status\"}").choices[0].finish_reason,
    Native("weird_status"),
  )
  // status 缺失 → Stop；output 缺失 → 空内容
  let no_status = decode_resp_ok("{\"id\":\"r\",\"model\":\"m\"}")
  assert_eq(no_status.choices[0].finish_reason, Stop)
  assert_eq(no_status.choices[0].message.content.length(), 0)
}

///|
test "responses decode - server side output items yield Unsupported diagnostic" {
  // web_search_call 等 server-side item → Unsupported 诊断而非静默丢弃；
  // 无 type 的 output item 不发诊断
  let json = "{\"id\":\"r\",\"model\":\"m\",\"output\":[" +
    "{\"type\":\"web_search_call\",\"id\":\"ws_1\"}," +
    "{\"id\":\"no_type\"}," +
    "{\"type\":\"message\",\"content\":[{\"type\":\"output_text\",\"text\":\"ok\"}]}" +
    "]}"
  match @responses.responses_to_lux_response(json) {
    Ok(cr) => {
      resp_diag_contains(cr, "server-side output item")
      let mut has_ws = false
      for d in cr.diagnostics() {
        if d.field == "response.output.web_search_call" &&
          d.status == Unsupported {
          has_ws = true
        }
      }
      assert_true(has_ws)
      assert_eq(cr.value().get_text(), "ok")
    }
    Err(e) => fail("unexpected Err: \{e}")
  }
}

///|
test "responses decode - usage detail tokens" {
  let resp = decode_resp_ok(
    "{\"id\":\"r\",\"model\":\"m\",\"created_at\":1700000000,\"output\":[],\"usage\":{\"input_tokens\":10,\"output_tokens\":5,\"total_tokens\":15,\"output_tokens_details\":{\"reasoning_tokens\":3},\"input_tokens_details\":{\"cached_tokens\":7}}}",
  )
  assert_eq(resp.created_at, Some(1700000000))
  match resp.usage {
    Some(u) => {
      assert_eq(u.prompt_tokens, 10)
      assert_eq(u.completion_tokens, 5)
      assert_eq(u.total_tokens, 15)
      assert_eq(u.reasoning_tokens, Some(3))
      assert_eq(u.cached_tokens, Some(7))
    }
    None => fail("expected usage")
  }
}

///|
test "responses decode - function_call output uses defaults" {
  // function_call output item：id / name 缺失走默认值，arguments 保留
  let resp = decode_resp_ok(
    "{\"id\":\"r\",\"model\":\"m\",\"output\":[{\"type\":\"function_call\",\"arguments\":\"{\\\"q\\\":1}\"}]}",
  )
  match resp.choices[0].message.content[0] {
    ToolUse(tu) => {
      assert_eq(tu.id, "")
      assert_eq(tu.name, "")
      assert_eq(tu.arguments_json, "{\"q\":1}")
    }
    _ => fail("expected ToolUse block")
  }
}

///|
test "responses decode - stream refusal delta and done events" {
  // content_part.added 的 refusal 分支、未知 part 类型、part 缺失；
  // refusal.delta / refusal.done；refusal.delta 缺 delta 字段时静默跳过
  let sse = "event: response.content_part.added\n" +
    "data: {\"type\":\"response.content_part.added\",\"output_index\":0,\"content_index\":1,\"part\":{\"type\":\"refusal\",\"text\":\"\"}}\n\n" +
    "event: response.content_part.added\n" +
    "data: {\"type\":\"response.content_part.added\",\"content_index\":2,\"part\":{\"type\":\"output_audio\",\"data\":\"x\"}}\n\n" +
    "event: response.content_part.added\n" +
    "data: {\"type\":\"response.content_part.added\",\"content_index\":3}\n\n" +
    "event: response.refusal.delta\n" +
    "data: {\"type\":\"response.refusal.delta\",\"content_index\":1,\"delta\":\"no can do\"}\n\n" +
    "event: response.refusal.delta\n" +
    "data: {\"type\":\"response.refusal.delta\",\"content_index\":4}\n\n" +
    "event: response.refusal.done\n" +
    "data: {\"type\":\"response.refusal.done\",\"content_index\":1}\n\n"
  let events = sse_ok(sse)
  assert_eq(events.length(), 3)
  assert_eq(events[0], BlockStart(1, Refusal))
  assert_eq(
    events[1],
    BlockDelta(1, @lux.LucentBlockDelta::refusal_delta("no can do")),
  )
  assert_eq(events[2], BlockEnd(1))
}

///|
test "responses decode - stream reasoning delta done and thinking block start" {
  // reasoning item 额外发出 BlockStart(Thinking)；reasoning_summary_text /
  // reasoning_text 的 delta 与 done 事件；delta 缺字段时静默跳过
  let sse = "event: response.output_item.added\n" +
    "data: {\"type\":\"response.output_item.added\",\"output_index\":0,\"item\":{\"type\":\"reasoning\",\"summary\":[]}}\n\n" +
    "event: response.reasoning_summary_text.delta\n" +
    "data: {\"type\":\"response.reasoning_summary_text.delta\",\"content_index\":0,\"delta\":\"s1\"}\n\n" +
    "event: response.reasoning_text.delta\n" +
    "data: {\"type\":\"response.reasoning_text.delta\",\"content_index\":1,\"delta\":\"t1\"}\n\n" +
    "event: response.reasoning_text.delta\n" +
    "data: {\"type\":\"response.reasoning_text.delta\",\"content_index\":2}\n\n" +
    "event: response.reasoning_summary_text.done\n" +
    "data: {\"type\":\"response.reasoning_summary_text.done\",\"content_index\":0}\n\n" +
    "event: response.reasoning_text.done\n" +
    "data: {\"type\":\"response.reasoning_text.done\",\"content_index\":1}\n\n"
  let events = sse_ok(sse)
  assert_eq(events.length(), 6)
  match events[0] {
    ItemStart(0, Reasoning(_)) => ()
    _ => fail("expected ItemStart reasoning")
  }
  assert_eq(events[1], BlockStart(0, Thinking))
  assert_eq(
    events[2],
    BlockDelta(0, @lux.LucentBlockDelta::thinking_delta("s1")),
  )
  assert_eq(
    events[3],
    BlockDelta(1, @lux.LucentBlockDelta::thinking_delta("t1")),
  )
  assert_eq(events[4], BlockEnd(0))
  assert_eq(events[5], BlockEnd(1))
}

///|
test "responses decode - stream error event and event type fallback" {
  // event: 行缺失时从 JSON 的 type 字段回退推断事件类型；error 事件 →
  // Error(LucentError)；error 字段缺失时静默跳过
  let sse = "data: {\"type\":\"error\",\"error\":\"upstream exploded\"}\n\n" +
    "event: error\n" +
    "data: {\"type\":\"error\",\"error\":\"second failure\"}\n\n" +
    "event: error\n" +
    "data: {\"type\":\"error\"}\n\n"
  let events = sse_ok(sse)
  assert_eq(events.length(), 2)
  assert_eq(events[0], Error(@lux.LucentError::simple("upstream exploded")))
  assert_eq(events[1], Error(@lux.LucentError::simple("second failure")))
}

///|
test "responses decode - stream silent skip and degraded frames" {
  // 空 data 帧（无诊断）、response.created 的 response 非对象（extra
  // 回退 None）/ 缺失、output_item.added 的 item 无法解析 / 缺失、
  // delta 缺字段、response.completed 缺 status / usage / response
  let sse = "data: \n\n" +
    "event: response.created\n" +
    "data: {\"type\":\"response.created\",\"response\":\"not-an-object\"}\n\n" +
    "event: response.created\n" +
    "data: {\"type\":\"response.created\"}\n\n" +
    "event: response.output_item.added\n" +
    "data: {\"type\":\"response.output_item.added\",\"output_index\":0,\"item\":{\"foo\":1}}\n\n" +
    "event: response.output_item.added\n" +
    "data: {\"type\":\"response.output_item.added\",\"output_index\":1}\n\n" +
    "event: response.output_text.delta\n" +
    "data: {\"type\":\"response.output_text.delta\",\"content_index\":0}\n\n" +
    "event: response.function_call_arguments.delta\n" +
    "data: {\"type\":\"response.function_call_arguments.delta\",\"output_index\":0}\n\n" +
    "event: response.completed\n" +
    "data: {\"type\":\"response.completed\"}\n\n" +
    "event: response.completed\n" +
    "data: {\"type\":\"response.completed\",\"response\":{\"id\":\"r_1\"}}\n\n"
  match @responses.responses_sse_to_events(sse) {
    Ok(cr) => {
      // 全部静默跳过：无诊断
      assert_eq(cr.diagnostics().length(), 0)
      let events = cr.value()
      // ConversationStart（extra 因非对象而回退 None）+ 两个 Done
      assert_eq(events.length(), 3)
      match events[0] {
        ConversationStart(meta) => assert_eq(meta.extra, None)
        _ => fail("expected ConversationStart")
      }
      assert_eq(events[1], Done)
      assert_eq(events[2], Done)
    }
    Err(e) => fail("unexpected Err: \{e}")
  }
}

///|
/// response.created 的 extra 捕获口径：与非流式 response.mbt 一致，只捕获
/// Response 顶层 IR 未建模字段（moderation）。status / output / usage 等
/// 建模字段不得进 extra（否则出站时拼进 response.created 顶层产出非法 JSON，
/// 管线校验实测）；moderation 缺失时 extra 为 None。
test "responses decode - stream captures only unmodeled top-level fields" {
  let sse = "event: response.created\n" +
    "data: {\"type\":\"response.created\",\"response\":{\"id\":\"r_m\",\"model\":\"gpt-4o\",\"created_at\":7,\"status\":\"in_progress\",\"output\":[],\"usage\":{\"input_tokens\":1},\"incomplete_details\":null,\"moderation\":{\"category\":\"harassment\"}}}\n\n" +
    "event: response.completed\n" +
    "data: {\"type\":\"response.completed\",\"response\":{\"id\":\"r_m\",\"model\":\"gpt-4o\",\"created_at\":7,\"status\":\"completed\",\"output\":[]}}\n\n"
  let events = sse_ok(sse)
  // ConversationStart + Finish + Done（completed 的终止分支）
  assert_eq(events.length(), 3)
  match events[0] {
    ConversationStart(meta) => {
      let extra = match meta.extra {
        Some(e) => e
        None => fail("expected moderation extra")
      }
      // 只含 moderation，建模字段（status/output/usage…）一律不进 extra
      assert_eq(
        extra.stringify(),
        "{\"moderation\":{\"category\":\"harassment\"}}",
      )
    }
    _ => fail("expected ConversationStart")
  }
  // moderation 缺失 → extra 为 None
  let no_mod = sse_ok(
    "event: response.created\n" +
    "data: {\"type\":\"response.created\",\"response\":{\"id\":\"r_n\",\"model\":\"m\",\"created_at\":1,\"status\":\"in_progress\",\"output\":[]}}\n\n",
  )
  match no_mod[0] {
    ConversationStart(meta) => assert_eq(meta.extra, None)
    _ => fail("expected ConversationStart")
  }
}

///|
/// response.mbt 编码侧分支：Thinking（summary + signature）、ToolUse、Refusal、
/// 未知内容块跳过、incomplete 状态与 reasoning/cached 用量明细
test "responses decode - response encode covers thinking tool refusal and usage" {
  let th = @lux.LucentThinking::new(
    "reasoned",
    Some("sig_enc"),
    false,
    Some([
      @lux.LucentContent::text("part1"),
      // 非 Text 块在 reasoning summary 序列化时被跳过
      @lux.LucentContent::image(
        "image/png",
        @lux.LucentMediaSource::url("https://x/skip.png"),
      ),
    ]),
  )
  let msg = @lux.LucentMessage::new(Assistant, [
    Thinking(th),
    @lux.LucentContent::tool_use("fc_9", "search", "{\"q\":\"x\"}", None),
    @lux.LucentContent::refusal("cannot comply"),
    @lux.LucentContent::image(
      "image/png",
      @lux.LucentMediaSource::url("https://x/a.png"),
    ),
  ])
  let resp = @lux.LucentResponse::new(
    "resp_9",
    "gpt-5",
    None,
    [@lux.LucentChoice::new(0, msg, Length, None)],
    Some(@lux.LucentUsage::full(10, 5, 15, Some(3), Some(7), None)),
    None,
  )
  match @responses.lux_response_to_responses(resp) {
    Ok(cr) => {
      let s = cr.value()
      // incomplete 状态
      assert_true(s.contains("\"status\":\"incomplete\""))
      // reasoning item（summary_text 条目 + signature 字段）
      assert_true(s.contains("\"type\":\"reasoning\""))
      assert_true(s.contains("{\"type\":\"summary_text\",\"text\":\"part1\"}"))
      assert_true(s.contains("\"signature\":\"sig_enc\""))
      // function_call output item
      assert_true(s.contains("\"type\":\"function_call\""))
      assert_true(s.contains("\"call_id\":\"call_fc_9\""))
      assert_true(s.contains("\"name\":\"search\""))
      // refusal output item
      assert_true(
        s.contains("\"type\":\"refusal\",\"refusal\":\"cannot comply\""),
      )
      // image 内容块无对应 output item → 静默跳过
      assert_false(s.contains("https://x/a.png"))
      // usage 明细
      assert_true(s.contains("\"reasoning_tokens\":3"))
      assert_true(s.contains("\"cached_tokens\":7"))
    }
    Err(e) => fail("encode failed: \{e}")
  }
  // Error finish reason → failed 状态
  let err_resp = @lux.LucentResponse::new(
    "resp_10",
    "gpt-5",
    None,
    [
      @lux.LucentChoice::new(
        0,
        @lux.LucentMessage::new(Assistant, [@lux.LucentContent::text("boom")]),
        Error,
        None,
      ),
    ],
    None,
    None,
  )
  match @responses.lux_response_to_responses(err_resp) {
    Ok(cr) => assert_true(cr.value().contains("\"status\":\"failed\""))
    Err(e) => fail("encode failed: \{e}")
  }
  // 其他 finish reason（非 stop / length / error）→ completed
  let tc_resp = @lux.LucentResponse::new(
    "resp_11",
    "gpt-5",
    None,
    [
      @lux.LucentChoice::new(
        0,
        @lux.LucentMessage::new(Assistant, [@lux.LucentContent::text("call")]),
        ToolCalls,
        None,
      ),
    ],
    None,
    None,
  )
  match @responses.lux_response_to_responses(tc_resp) {
    Ok(cr) => assert_true(cr.value().contains("\"status\":\"completed\""))
    Err(e) => fail("encode failed: \{e}")
  }
}
