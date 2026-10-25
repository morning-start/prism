///|
/// OpenAI Chat 适配器黑盒测试 — 仅通过公开 API 验证
///
/// 与白盒测试（_wbtest.mbt）互补：模拟外部调用者视角，
/// 通过 6 函数 + capability 的公开契约验证双向转换与 round-trip 语义。

///|
/// === capability ===

///|
test "capability - declares provider name" {
  assert_eq(@openai.capability().provider, "openai")
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
  match @openai.lux_request_to_openai(original) {
    Ok(cr1) =>
      match @openai.openai_to_lux_request(cr1.value()) {
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
test "round trip - response encode then decode preserves id" {
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
  match @openai.lux_response_to_openai(resp) {
    Ok(cr1) =>
      match @openai.openai_to_lux_response(cr1.value()) {
        Ok(cr2) => assert_eq(cr2.value().id, "resp-1")
        Err(_) => assert_true(false)
      }
    Err(_) => assert_true(false)
  }
}

///|
/// === 错误路径 ===

///|
test "invalid input - malformed JSON returns Err" {
  assert_true(@openai.openai_to_lux_request("{invalid}") is Err(_))
  assert_true(@openai.openai_to_lux_response("{invalid}") is Err(_))
}

///|
/// === 解码覆盖矩阵：畸形块 / 罕见特性分支 ===
///
/// 目的：驱动 openai_to_lux_request / openai_to_lux_response /
/// openai_sse_to_events 内部的跳过分支与特性分支。契约：畸形输入必须被
/// 安全跳过（Ok + 裁剪后的 IR，不抛错），合法变异必须落到正确的 IR 形态，
/// 需要调用方知晓的语义损失必须带 Degraded 诊断。

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
  match @openai.openai_to_lux_request(json) {
    Ok(cr) => cr.value()
    Err(e) => fail("expected Ok, got Err: \{e}")
  }
}

///|
/// 响应解码成功快捷方式
fn decode_resp_ok(json : String) -> @lux.LucentResponse raise {
  match @openai.openai_to_lux_response(json) {
    Ok(cr) => cr.value()
    Err(e) => fail("expected Ok, got Err: \{e}")
  }
}

///|
/// 流解码成功快捷方式
fn decode_events_ok(sse : String) -> Array[@lux.LucentStreamEvent] raise {
  match @openai.openai_sse_to_events(sse) {
    Ok(cr) => cr.value()
    Err(e) => fail("expected Ok, got Err: \{e}")
  }
}

///|
/// 包装辅助：把 payload 塞进标准请求的指定字段，避免手数外层大括号
fn oa_req(field : String, payload : String) -> String {
  "{\"model\":\"gpt-4o\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"" +
  field +
  "\":" +
  payload +
  "}"
}

///|
/// 解码请求并取出唯一消息的内容块数量
fn content_len(json : String) -> Int32 raise {
  let req = decode_ok(json)
  if req.conversation.length() != 1 {
    fail(
      "expected exactly 1 conversation item, got \{req.conversation.length()}",
    )
  }
  match req.conversation[0] {
    Message(m) => m.content.length()
    _ => fail("expected Message item")
  }
}

///|
/// 取出唯一消息的第 idx 个内容块
fn block_at(json : String, idx : Int32) -> @lux.LucentContent raise {
  let req = decode_ok(json)
  if req.conversation.length() != 1 {
    fail("expected exactly 1 conversation item")
  }
  match req.conversation[0] {
    Message(m) =>
      if idx < m.content.length() {
        m.content[idx]
      } else {
        fail("no content block at index \{idx}")
      }
    _ => fail("expected Message item")
  }
}

///|
/// 取出唯一消息的第 idx 个内容块并要求它是 Image
fn image_at(json : String, idx : Int32) -> @lux.LucentMultimedia raise {
  match block_at(json, idx) {
    Image(mm) => mm
    _ => fail("expected Image block at index \{idx}")
  }
}

///|
/// 收集流事件里所有 ToolCall 块启动的 "id|name" 标签
fn tool_start_labels(sse : String) -> Array[String] raise {
  let events = decode_events_ok(sse)
  let labels : Array[String] = []
  for ev in events {
    match ev {
      BlockStart(_, ToolCall(id, name)) => labels.push(id + "|" + name)
      _ => ()
    }
  }
  labels
}

///|
/// 统计流事件里 ToolArgumentsDelta 的数量
fn tool_arg_deltas(sse : String) -> Int32 raise {
  let events = decode_events_ok(sse)
  let mut n = 0
  for ev in events {
    match ev {
      BlockDelta(_, ToolArgumentsDelta(_)) => n = n + 1
      _ => ()
    }
  }
  n
}

///|
test "openai decode - malformed content parts are skipped, valid parts kept" {
  let cases : Array[(String, Int32)] = [
    (
      "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"text\"}]}]}",
      0,
    ),
    (
      "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"input_audio\",\"input_audio\":{\"data\":\"x\"}}]}]}",
      0,
    ),
    (
      "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"image_url\",\"image_url\":{\"url\":\"\"}}]}]}",
      0,
    ),
    (
      "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"image_url\"}]}]}",
      0,
    ),
    (
      "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"image_url\",\"image_url\":{\"url\":42}}]}]}",
      0,
    ),
    (
      "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"a\"},{\"type\":\"text\"},{\"type\":\"weird\"}]}]}",
      1,
    ),
    ("{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":123}]}", 0),
    ("{\"model\":\"m\",\"messages\":[{\"role\":\"user\"}]}", 0),
    ("{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":[]}]}", 0),
  ]
  for c in cases {
    assert_eq(content_len(c.0), c.1)
  }
}

///|
test "openai decode - unknown roles and missing role skip messages" {
  assert_eq(
    decode_ok(
      "{\"model\":\"m\",\"messages\":[{\"role\":\"banana\",\"content\":\"x\"}]}",
    ).conversation.length(),
    0,
  )
  assert_eq(
    decode_ok("{\"model\":\"m\",\"messages\":[{\"content\":\"x\"}]}").conversation.length(),
    0,
  )
  assert_eq(
    decode_ok("{\"model\":\"m\",\"messages\":\"hi\"}").conversation.length(),
    0,
  )
  assert_eq(decode_ok("{\"model\":\"m\"}").conversation.length(), 0)
  assert_eq(
    decode_ok(
      "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":\"a\"},{\"role\":\"weird\",\"content\":\"b\"},{\"role\":\"user\",\"content\":\"c\"}]}",
    ).conversation.length(),
    2,
  )
}

///|
test "openai decode - assistant tool_calls skip malformed entries and default fields" {
  let req = decode_ok(
    "{\"model\":\"m\",\"messages\":[{\"role\":\"assistant\",\"content\":null,\"tool_calls\":[{\"id\":\"c1\",\"function\":{\"name\":\"f\",\"arguments\":\"{\\\"a\\\":1}\"}},{\"id\":\"c2\"},{\"function\":{\"name\":\"g\"}},{\"id\":\"c4\",\"function\":{}}]}]}",
  )
  match req.conversation[0] {
    Message(m) => {
      // 无 function 的条目被跳过，其余三条保留
      assert_eq(m.content.length(), 3)
      match m.content[0] {
        ToolUse(tu) => {
          assert_eq(tu.id, "c1")
          assert_eq(tu.name, "f")
          assert_eq(tu.arguments_json, "{\"a\":1}")
        }
        _ => fail("expected ToolUse")
      }
      match m.content[1] {
        ToolUse(tu) => {
          // id 缺失 → ""，arguments 缺失 → "{}"
          assert_eq(tu.id, "")
          assert_eq(tu.name, "g")
          assert_eq(tu.arguments_json, "{}")
        }
        _ => fail("expected ToolUse")
      }
      match m.content[2] {
        ToolUse(tu) => {
          assert_eq(tu.id, "c4")
          assert_eq(tu.name, "")
        }
        _ => fail("expected ToolUse")
      }
    }
    _ => fail("expected Message item")
  }
}

///|
test "openai decode - tool role message decodes to ToolResult content" {
  let req = decode_ok(
    "{\"model\":\"m\",\"messages\":[{\"role\":\"tool\",\"tool_call_id\":\"call_1\",\"content\":\"25\"},{\"role\":\"tool\",\"tool_call_id\":\"call_2\"}]}",
  )
  match req.conversation[0] {
    Message(m) => {
      assert_eq(m.role, Tool)
      match m.content[0] {
        ToolResult(tr) => {
          assert_eq(tr.tool_use_id, "call_1")
          match tr.content[0] {
            Text(t, _) => assert_eq(t, "25")
            _ => fail("expected Text")
          }
        }
        _ => fail("expected ToolResult")
      }
    }
    _ => fail("expected Message item")
  }
  // tool 消息缺 content → 空文本
  match req.conversation[1] {
    Message(m) =>
      match m.content[0] {
        ToolResult(tr) =>
          match tr.content[0] {
            Text(t, _) => assert_eq(t, "")
            _ => fail("expected Text")
          }
        _ => fail("expected ToolResult")
      }
    _ => fail("expected Message item")
  }
}

///|
test "openai decode - tools skip entries without function and default parameters" {
  let req = decode_ok(
    "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"tools\":[{\"type\":\"function\",\"function\":{\"name\":\"f\",\"description\":\"d\",\"parameters\":{\"type\":\"object\"},\"strict\":true}},{\"function\":{\"name\":\"g\"}},{\"name\":\"no_fn\"}]}",
  )
  match req.tools {
    Some(ts) => {
      assert_eq(ts.length(), 2)
      assert_eq(ts[0].name, "f")
      match ts[0].description {
        Some(d) => assert_eq(d, "d")
        None => fail("expected description")
      }
      assert_true(ts[0].parameters_json.contains("object"))
      assert_eq(ts[0].strict, Some(true))
      assert_eq(ts[0].kind, Function)
      // 缺 parameters → "{}"；缺 description/strict → None
      assert_eq(ts[1].name, "g")
      assert_eq(ts[1].description, None)
      assert_eq(ts[1].parameters_json, "{}")
      assert_eq(ts[1].strict, None)
    }
    None => fail("expected tools")
  }
}

///|
test "openai decode - tool_choice variants map to IR tool choices" {
  assert_eq(
    decode_ok(oa_req("tool_choice", "\"auto\"")).tool_choice,
    Some(Auto),
  )
  // LucentToolChoice::None（与 Option::None 靠类型推导区分）
  assert_eq(
    decode_ok(oa_req("tool_choice", "\"none\"")).tool_choice,
    Some(None),
  )
  assert_eq(
    decode_ok(oa_req("tool_choice", "\"required\"")).tool_choice,
    Some(Required),
  )
  assert_eq(
    decode_ok(
      oa_req(
        "tool_choice", "{\"type\":\"function\",\"function\":{\"name\":\"f\"}}",
      ),
    ).tool_choice,
    Some(SpecificTool("f")),
  )
  // function 缺 name / 缺 function / 未知 type → None
  assert_eq(
    decode_ok(oa_req("tool_choice", "{\"type\":\"function\",\"function\":{}}")).tool_choice,
    None,
  )
  assert_eq(
    decode_ok(oa_req("tool_choice", "{\"type\":\"function\"}")).tool_choice,
    None,
  )
  assert_eq(
    decode_ok(oa_req("tool_choice", "{\"type\":\"custom\"}")).tool_choice,
    None,
  )
  // 非字符串/非对象形态 → None
  assert_eq(decode_ok(oa_req("tool_choice", "42")).tool_choice, None)
  assert_eq(decode_ok(oa_req("tool_choice", "\"weird\"")).tool_choice, None)
  // 字段缺失 → None
  assert_eq(
    decode_ok(
      "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}",
    ).tool_choice,
    None,
  )
}

///|
test "openai decode - image_url data URIs, media type defaults and url fallbacks" {
  let json = "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"image_url\",\"image_url\":{\"url\":\"data:image/png;base64,AAA\"}},{\"type\":\"image_url\",\"image_url\":{\"url\":\"data:image/jpeg;base64,BBB\"}},{\"type\":\"image_url\",\"image_url\":{\"url\":\"dat;:x,CCC\"}},{\"type\":\"image_url\",\"image_url\":{\"url\":\"https://x.com/a.png\"}},{\"type\":\"image_url\",\"image_url\":{\"url\":\"http://x.com/b.png\"}},{\"type\":\"image_url\",\"image_url\":{\"url\":\"data:image/png;base64,\"}},{\"type\":\"image_url\",\"image_url\":{\"url\":\"dat;:x\"}},{\"type\":\"image_url\",\"image_url\":{\"url\":\"data:image/png\"}}]}]}"
  assert_eq(content_len(json), 8)
  // data URI → inline 源，media_type 取自 URL
  assert_eq(image_at(json, 0).media_type, "image/png")
  match image_at(json, 0).source {
    Inline(d) => assert_eq(d, "AAA")
    _ => fail("expected Inline source")
  }
  assert_eq(image_at(json, 1).media_type, "image/jpeg")
  match image_at(json, 1).source {
    Inline(d) => assert_eq(d, "BBB")
    _ => fail("expected Inline source")
  }
  // 无 media_type 段 → 回退 "image/png"
  assert_eq(image_at(json, 2).media_type, "image/png")
  match image_at(json, 2).source {
    Inline(d) => assert_eq(d, "CCC")
    _ => fail("expected Inline source")
  }
  // 非 data: scheme → url 源
  assert_eq(image_at(json, 3).media_type, "image/png")
  match image_at(json, 3).source {
    Url(u) => assert_eq(u, "https://x.com/a.png")
    _ => fail("expected Url source")
  }
  assert_eq(image_at(json, 4).media_type, "image/png")
  match image_at(json, 4).source {
    Url(u) => assert_eq(u, "http://x.com/b.png")
    _ => fail("expected Url source")
  }
  // data URI 但 data 为空 / 无逗号 → 回退 url 源（inline 不可构造）
  assert_eq(image_at(json, 5).media_type, "image/png")
  match image_at(json, 5).source {
    Url(u) => assert_eq(u, "data:image/png;base64,")
    _ => fail("expected Url source")
  }
  assert_eq(image_at(json, 6).media_type, "image/png")
  match image_at(json, 6).source {
    Url(u) => assert_eq(u, "dat;:x")
    _ => fail("expected Url source")
  }
  // data: 前缀但无 ";" 分隔 → 直接回退 url 源
  assert_eq(image_at(json, 7).media_type, "image/png")
  match image_at(json, 7).source {
    Url(u) => assert_eq(u, "data:image/png")
    _ => fail("expected Url source")
  }
}

///|
test "openai decode - reasoning_effort variants and degradation diagnostics" {
  assert_eq(
    decode_ok(oa_req("reasoning_effort", "\"low\"")).reasoning.unwrap().effort,
    Some(Low),
  )
  assert_eq(
    decode_ok(oa_req("reasoning_effort", "\"medium\"")).reasoning.unwrap().effort,
    Some(Medium),
  )
  assert_eq(
    decode_ok(oa_req("reasoning_effort", "\"high\"")).reasoning.unwrap().effort,
    Some(High),
  )
  assert_eq(
    decode_ok(oa_req("reasoning_effort", "\"xhigh\"")).reasoning.unwrap().effort,
    Some(XHigh),
  )
  // minimal → Low + Degraded 诊断
  match
    @openai.openai_to_lux_request(oa_req("reasoning_effort", "\"minimal\"")) {
    Ok(cr) => {
      diag_contains(cr, "reasoning_effort \"minimal\" downgraded to Low")
      assert_eq(cr.value().reasoning.unwrap().effort, Some(Low))
    }
    Err(e) => fail("unexpected Err: \{e}")
  }
  // 未知档位 → 忽略 + Degraded 诊断
  match @openai.openai_to_lux_request(oa_req("reasoning_effort", "\"turbo\"")) {
    Ok(cr) => {
      diag_contains(cr, "unknown reasoning_effort \"turbo\" ignored")
      assert_eq(cr.value().reasoning, None)
    }
    Err(e) => fail("unexpected Err: \{e}")
  }
  // 非字符串值 / 缺失 → 无 reasoning
  assert_eq(decode_ok(oa_req("reasoning_effort", "5")).reasoning, None)
  assert_eq(
    decode_ok(
      "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}",
    ).reasoning,
    None,
  )
}

///|
test "openai decode - response_format variants map to structured output" {
  assert_eq(
    decode_ok(oa_req("response_format", "{\"type\":\"json_object\"}")).options.structured_output,
    Some(JsonObject),
  )
  assert_eq(
    decode_ok(oa_req("response_format", "{\"type\":\"text\"}")).options.structured_output,
    Some(Text),
  )
  match
    decode_ok(
      oa_req(
        "response_format", "{\"type\":\"json_schema\",\"json_schema\":{\"schema\":{\"type\":\"object\"}}}",
      ),
    ).options.structured_output {
    Some(JsonSchema(s)) => assert_true(s.contains("object"))
    _ => fail("expected JsonSchema")
  }
  // json_schema 缺 json_schema 对象 / 缺 schema → None
  assert_eq(
    decode_ok(oa_req("response_format", "{\"type\":\"json_schema\"}")).options.structured_output,
    None,
  )
  assert_eq(
    decode_ok(
      oa_req("response_format", "{\"type\":\"json_schema\",\"json_schema\":{}}"),
    ).options.structured_output,
    None,
  )
  // 未知 type / 非对象 / 缺失 → None
  assert_eq(
    decode_ok(oa_req("response_format", "{\"type\":\"yaml\"}")).options.structured_output,
    None,
  )
  assert_eq(
    decode_ok(oa_req("response_format", "\"text\"")).options.structured_output,
    None,
  )
  assert_eq(
    decode_ok(oa_req("response_format", "42")).options.structured_output,
    None,
  )
}

///|
test "openai decode - max_completion_tokens takes precedence over max_tokens" {
  assert_eq(
    decode_ok(
      "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"max_completion_tokens\":512,\"max_tokens\":999}",
    ).options.max_output_tokens,
    Some(512),
  )
  assert_eq(
    decode_ok(
      "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"max_tokens\":256}",
    ).options.max_output_tokens,
    Some(256),
  )
  assert_eq(
    decode_ok(
      "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}",
    ).options.max_output_tokens,
    None,
  )
}

///|
test "openai decode - system and developer messages become instructions" {
  let req = decode_ok(
    "{\"model\":\"m\",\"messages\":[{\"role\":\"system\",\"content\":\"sys\"},{\"role\":\"developer\",\"content\":[{\"type\":\"text\",\"text\":\"dev\"},{\"type\":\"weird\"}]},{\"role\":\"user\",\"content\":\"hi\"}]}",
  )
  assert_eq(req.conversation.length(), 1)
  match req.instructions {
    Some(instrs) => {
      assert_eq(instrs.length(), 2)
      match instrs[0] {
        Text(t, _) => assert_eq(t, "sys")
        _ => fail("expected Text")
      }
      match instrs[1] {
        Text(t, _) => assert_eq(t, "dev")
        _ => fail("expected Text")
      }
    }
    None => fail("expected instructions")
  }
  // 系统消息内容全被跳过 → instructions 保持 None
  assert_eq(
    decode_ok(
      "{\"model\":\"m\",\"messages\":[{\"role\":\"system\",\"content\":[{\"type\":\"weird\"}]},{\"role\":\"user\",\"content\":\"hi\"}]}",
    ).instructions,
    None,
  )
}

///|
test "openai decode - response keeps provider_payload metadata and skips malformed choices" {
  let resp = decode_resp_ok(
    "{\"id\":\"c-1\",\"model\":\"gpt-4o\",\"created\":1700000000,\"system_fingerprint\":\"fp_1\",\"service_tier\":\"scale\",\"choices\":[{\"index\":3},{\"index\":0,\"message\":{\"role\":\"tool\",\"content\":\"x\"}}]}",
  )
  assert_eq(resp.id, "c-1")
  assert_eq(resp.model, "gpt-4o")
  assert_eq(resp.created_at, Some(1700000000))
  // 响应级元数据 → provider_payload（不静默丢弃）
  match resp.provider_payload {
    Some(p) => {
      let s = p.stringify()
      assert_true(s.contains("system_fingerprint"))
      assert_true(s.contains("fp_1"))
      assert_true(s.contains("service_tier"))
      assert_true(s.contains("scale"))
    }
    None => fail("expected provider_payload")
  }
  // 无 message 的 choice 被跳过
  assert_eq(resp.choices.length(), 1)
  assert_eq(resp.choices[0].index, 0)
  // role 非 assistant → 回退 Assistant；finish_reason 缺失 → Stop
  assert_eq(resp.choices[0].message.role, Assistant)
  assert_eq(resp.choices[0].finish_reason, Stop)
  assert_eq(resp.choices[0].message.reasoning, None)
  match resp.choices[0].message.content[0] {
    Text(t, _) => assert_eq(t, "x")
    _ => fail("expected Text")
  }
  // 无 choices / 无 id 的响应
  let bare = decode_resp_ok("{\"model\":\"m\"}")
  assert_eq(bare.choices.length(), 0)
  assert_eq(bare.id, "")
  assert_eq(bare.created_at, None)
  assert_eq(bare.provider_payload, None)
}

///|
test "openai decode - response tool_calls skip malformed entries and default fields" {
  let resp = decode_resp_ok(
    "{\"id\":\"c-2\",\"model\":\"m\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":null,\"tool_calls\":[{\"id\":\"c1\",\"function\":{\"name\":\"f\",\"arguments\":\"{}\"}},{\"id\":\"c2\"},{\"function\":{\"name\":\"g\"}},{\"id\":\"c4\",\"function\":{}}]},\"finish_reason\":\"tool_calls\"}]}",
  )
  assert_eq(resp.choices[0].finish_reason, ToolCalls)
  let content = resp.choices[0].message.content
  assert_eq(content.length(), 3)
  match content[1] {
    ToolUse(tu) => {
      assert_eq(tu.id, "")
      assert_eq(tu.name, "g")
      assert_eq(tu.arguments_json, "{}")
    }
    _ => fail("expected ToolUse")
  }
  match content[2] {
    ToolUse(tu) => {
      assert_eq(tu.id, "c4")
      assert_eq(tu.name, "")
    }
    _ => fail("expected ToolUse")
  }
}

///|
test "openai decode - sse skips invalid and truncated frames" {
  let events = decode_events_ok(
    "data: {\"choices\":[{\"delta\":{\"role\":\"assistant\"}}]}\n\ndata: not-json\n\ndata: {\"choices\":[{\"delta\":{\"content\":\"hi\"}}]}\n\ndata: {\"choices\":[{\"delta\"\n\ndata: [DONE]\n\n",
  )
  // ConversationStart + BlockStart(Text) + BlockDelta + BlockEnd + Done
  assert_eq(events.length(), 5)
  assert_true(events[0] is ConversationStart(_))
  assert_true(events[events.length() - 1] is Done)
}

///|
test "openai decode - sse delta.reasoning emits a thinking block" {
  let events = decode_events_ok(
    "data: {\"choices\":[{\"delta\":{\"role\":\"assistant\"}}]}\n\ndata: {\"choices\":[{\"delta\":{\"reasoning\":\"think\"}}]}\n\ndata: {\"choices\":[{\"delta\":{\"reasoning\":\" more\"}}]}\n\ndata: {\"choices\":[{\"delta\":{\"content\":\"answer\"}}]}\n\ndata: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n",
  )
  let mut thinking_starts = 0
  let mut thinking_deltas = 0
  let mut thinking_ends = 0
  for ev in events {
    match ev {
      BlockStart(1, Thinking) => thinking_starts = thinking_starts + 1
      BlockDelta(1, ThinkingDelta(_)) => thinking_deltas = thinking_deltas + 1
      BlockEnd(1) => thinking_ends = thinking_ends + 1
      _ => ()
    }
  }
  assert_eq(thinking_starts, 1)
  assert_eq(thinking_deltas, 2)
  assert_eq(thinking_ends, 1)
  assert_true(events[events.length() - 1] is Done)
}

///|
test "openai decode - sse closes an open thinking block at done without finish reason" {
  // 无 finish_reason 帧，[DONE] 负责闭合未结束的 thinking 块
  let events = decode_events_ok(
    "data: {\"choices\":[{\"delta\":{\"reasoning\":\"think\"}}]}\n\ndata: [DONE]\n\n",
  )
  // BlockStart(Thinking) + BlockDelta + BlockEnd(1) + Done
  assert_eq(events.length(), 4)
  let mut thinking_ends = 0
  for ev in events {
    match ev {
      BlockEnd(1) => thinking_ends = thinking_ends + 1
      _ => ()
    }
  }
  assert_eq(thinking_ends, 1)
  assert_true(events[events.length() - 1] is Done)
}

///|
test "openai decode - sse frames without delta or choices are skipped" {
  let events = decode_events_ok(
    "data: {\"id\":\"x\"}\n\ndata: {\"choices\":[]}\n\ndata: {\"choices\":[{\"index\":0}]}\n\ndata: {\"choices\":[{\"delta\":{\"content\":\"ok\"}}]}\n\ndata: [DONE]\n\n",
  )
  // 只有带 delta.content 的帧产生事件：BlockStart + BlockDelta + BlockEnd + Done
  assert_eq(events.length(), 4)
  let mut text_starts = 0
  for ev in events {
    match ev {
      BlockStart(0, Text) => text_starts = text_starts + 1
      _ => ()
    }
  }
  assert_eq(text_starts, 1)
}

///|
test "openai decode - sse tool_calls without function or id emit bare blocks" {
  // 无 function → name 为空；function 无 arguments → 无增量
  let sse_bare = "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"c1\"}]}}]}\n\ndata: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{}}]}}]}\n\ndata: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0}]}}]}\n\ndata: {\"choices\":[{\"delta\":{},\"finish_reason\":\"tool_calls\"}]}\n\ndata: [DONE]\n\n"
  assert_eq(tool_start_labels(sse_bare), ["c1|"])
  assert_eq(tool_arg_deltas(sse_bare), 0)
  // 无 id → BlockStart 携带空 id
  let sse_no_id = "data: {\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"name\":\"f\"}}]}}]}\n\ndata: [DONE]\n\n"
  assert_eq(tool_start_labels(sse_no_id), ["|f"])
  assert_eq(tool_arg_deltas(sse_no_id), 0)
}

///|
test "openai decode - sse empty stream and done-only stream" {
  assert_eq(decode_events_ok("").length(), 0)
  let done_only = decode_events_ok("data: [DONE]\n\n")
  assert_eq(done_only.length(), 1)
  assert_true(done_only[0] is Done)
  // 未闭合的文本块在 [DONE] 前被闭合
  let events = decode_events_ok(
    "data: {\"choices\":[{\"delta\":{\"content\":\"hi\"}}]}\n\ndata: [DONE]\n\n",
  )
  let mut text_ends = 0
  for ev in events {
    match ev {
      BlockEnd(0) => text_ends = text_ends + 1
      _ => ()
    }
  }
  assert_eq(text_ends, 1)
  assert_true(events[events.length() - 1] is Done)
}

///|
/// === TASK-4b：request decode 顶层形状守卫（QA P1-1，ACC-004 / TC-7 / TC-8）===

///|
test "decode guard - top-level array request is rejected with Err" {
  // 回退即红：守卫移除后该文档将静默降级为空 IR 请求
  assert_true(@openai.openai_to_lux_request("[1,2,3]") is Err(_))
  assert_true(@openai.openai_to_lux_request("42") is Err(_))
  assert_true(@openai.openai_to_lux_request("\"text\"") is Err(_))
  assert_true(@openai.openai_to_lux_request("null") is Err(_))
}

///|
test "decode guard - messages wrong type yields Invalid diagnostic" {
  // messages: 42 → Invalid 诊断透出，不静默成空请求
  let doc = "{\"model\":\"gpt-4o\",\"messages\":42}"
  match @openai.openai_to_lux_request(doc) {
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
  assert_true(@openai.openai_to_lux_request("{\"messages\":null}") is Ok(_))
  assert_true(@openai.openai_to_lux_request("{\"model\":\"gpt-4o\"}") is Ok(_))
}
