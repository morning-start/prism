///|
/// Google Gemini 适配器黑盒测试 — 仅通过公开 API 验证
///
/// 与白盒测试（_wbtest.mbt）互补：模拟外部调用者视角，
/// 通过 6 函数 + capability 的公开契约验证双向转换与 round-trip 语义。

///|
/// === capability ===

///|
test "capability - declares provider name" {
  assert_eq(@gemini.capability().provider, "google")
}

///|
/// === 请求 round-trip ===

///|
test "round trip - request encode then decode preserves semantics" {
  let original = @lux.LucentRequest::from_messages(
    "gemini-1.5-pro",
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
  match @gemini.lux_request_to_gemini(original) {
    Ok(cr1) =>
      match @gemini.gemini_to_lux_request(cr1.value()) {
        Ok(cr) => {
          let round = cr.value()
          assert_eq(round.model, "gemini-1.5-pro")
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
    "gemini-1.5-pro",
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
  match @gemini.lux_response_to_gemini(resp) {
    Ok(cr1) =>
      match @gemini.gemini_to_lux_response(cr1.value()) {
        Ok(cr) => assert_eq(cr.value().get_text(), "hi")
        Err(_) => assert_true(false)
      }
    Err(_) => assert_true(false)
  }
}

///|
/// === 错误路径 ===

///|
test "invalid input - malformed JSON returns Err" {
  assert_true(@gemini.gemini_to_lux_request("{invalid}") is Err(_))
  assert_true(@gemini.gemini_to_lux_response("{invalid}") is Err(_))
}

///|
/// === 解码覆盖矩阵：畸形 part / 罕见特性分支 ===
///
/// 目的：驱动 gemini_to_lux_request / gemini_to_lux_response /
/// gemini_sse_to_events 内部的降级分支与特性分支：
///   - 解析失败必须产生 Degraded / Unsupported 诊断而非静默丢弃
///   - 合法变异必须落到正确的 IR 形态（角色回退、合成 tool 调用 id、
///     thinkingLevel → effort、safetyRatings、finishReason、流事件序列）

///|
/// 断言 ConversionResult 的诊断列表中存在 detail 含 expect 的条目
fn[T] diag_contains(
  cr : @lux.ConversionResult[T],
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
fn req_ok(json : String) -> @lux.LucentRequest raise {
  match @gemini.gemini_to_lux_request(json) {
    Ok(cr) => cr.value()
    Err(e) => fail("expected Ok, got Err: \{e}")
  }
}

///|
fn resp_ok(json : String) -> @lux.LucentResponse raise {
  match @gemini.gemini_to_lux_response(json) {
    Ok(cr) => cr.value()
    Err(e) => fail("expected Ok, got Err: \{e}")
  }
}

///|
fn sse_ok(sse : String) -> Array[@lux.LucentStreamEvent] raise {
  match @gemini.gemini_sse_to_events(sse) {
    Ok(cr) => cr.value()
    Err(e) => fail("expected Ok, got Err: \{e}")
  }
}

///|
/// 流事件序列摘要：S/D/E + block_index，F/U/X = Finish/Usage/Done，? = 其他
fn event_summary(events : Array[@lux.LucentStreamEvent]) -> String {
  let names : Array[String] = []
  for ev in events {
    names.push(
      match ev {
        BlockStart(idx, _) => "S" + idx.to_string()
        BlockEnd(idx) => "E" + idx.to_string()
        BlockDelta(idx, _) => "D" + idx.to_string()
        Finish(_) => "F"
        Usage(_) => "U"
        Done => "X"
        _ => "?"
      },
    )
  }
  names.join("")
}

///|
/// 包装辅助：把 payload 塞进标准 Gemini 请求的指定顶层字段，避免手数外层大括号
fn gemini_req(field : String, payload : String) -> String {
  "{\"model\":\"gemini-2.5-pro\",\"contents\":[{\"role\":\"user\",\"parts\":[{\"text\":\"hi\"}]}],\"" +
  field +
  "\":" +
  payload +
  "}"
}

///|
/// 包装辅助：构造带 generationConfig.thinkingConfig 的标准请求
fn gemini_thinking(payload : String) -> String {
  gemini_req("generationConfig", "{\"thinkingConfig\":" + payload + "}")
}

///|
test "gemini decode - malformed parts degrade with diagnostics" {
  let cases : Array[(String, String)] = [
    (
      "{\"model\":\"m\",\"contents\":[{\"role\":\"user\",\"parts\":[{\"inlineData\":{\"mimeType\":\"image/png\"}}]}]}",
      "inlineData missing data field",
    ),
    (
      "{\"model\":\"m\",\"contents\":[{\"role\":\"user\",\"parts\":[{\"fileData\":{\"mimeType\":\"application/pdf\"}}]}]}",
      "fileData missing fileUri field",
    ),
    (
      "{\"model\":\"m\",\"contents\":[{\"role\":\"user\",\"parts\":[{\"text\":\"hi\"}]}],\"generationConfig\":{\"thinkingConfig\":{\"thinkingLevel\":\"minimal\"}}}",
      "gemini thinkingLevel \"minimal\" 降级映射为 LucentReasoningEffort",
    ),
    (
      "{\"model\":\"m\",\"contents\":[{\"role\":\"user\",\"parts\":[{\"text\":\"hi\"}]}],\"generationConfig\":{\"thinkingConfig\":{\"thinkingLevel\":\"ULTRA\"}}}",
      "降级映射为 LucentReasoningEffort",
    ),
  ]
  for c in cases {
    match @gemini.gemini_to_lux_request(c.0) {
      Ok(cr) => diag_contains(cr, c.1)
      Err(e) => fail("unexpected Err for \{c.0}: \{e}")
    }
  }
}

///|
test "gemini decode - thought marker variants produce thinking blocks" {
  let req = req_ok(
    "{\"model\":\"m\",\"contents\":[{\"role\":\"model\",\"parts\":[{\"text\":\"a\",\"thought\":true},{\"text\":\"b\",\"thought\":\"yes\"},{\"text\":\"c\",\"thought\":false},{\"text\":\"d\",\"thought\":true,\"thoughtSignature\":\"sig-1\"}]}]}",
  )
  match req.conversation[0] {
    Message(m) => {
      assert_eq(m.content.length(), 4)
      // thought:true → 仅 Thinking，不伪装成文本
      match m.content[0] {
        Thinking(th) => assert_eq(th.text, "a")
        _ => fail("expected Thinking block")
      }
      // thought 为非布尔真值（字符串）同样视为思考块
      match m.content[1] {
        Thinking(th) => assert_eq(th.text, "b")
        _ => fail("expected Thinking block for string thought")
      }
      // thought:false → 普通文本
      match m.content[2] {
        Text(t, _) => assert_eq(t, "c")
        _ => fail("expected Text block")
      }
      // thoughtSignature 保留进 IR signature
      match m.content[3] {
        Thinking(th) => {
          assert_eq(th.text, "d")
          assert_eq(th.signature, Some("sig-1"))
        }
        _ => fail("expected Thinking block with signature")
      }
    }
    _ => fail("expected Message item")
  }
}

///|
test "gemini decode - functionCall without args defaults to empty object" {
  let req = req_ok(
    "{\"model\":\"m\",\"contents\":[{\"role\":\"model\",\"parts\":[{\"functionCall\":{\"name\":\"f\"}}]}]}",
  )
  match req.conversation[0] {
    Message(m) =>
      match m.content[0] {
        ToolUse(tu) => {
          assert_eq(tu.id, "fc_f_0")
          assert_eq(tu.name, "f")
          assert_eq(tu.arguments_json, "{}")
        }
        _ => fail("expected ToolUse block")
      }
    _ => fail("expected Message item")
  }
}

///|
test "gemini decode - functionCall synthetic ids increment per name" {
  let req = req_ok(
    "{\"model\":\"m\",\"contents\":[{\"role\":\"model\",\"parts\":[{\"functionCall\":{\"name\":\"f\",\"args\":{\"a\":1}}},{\"functionCall\":{\"name\":\"f\"}},{\"functionCall\":{\"name\":\"g\"}},{\"functionCall\":{\"name\":\"\",\"args\":{\"z\":1}}}]}]}",
  )
  let ids : Array[String] = []
  match req.conversation[0] {
    Message(m) => {
      assert_eq(m.content.length(), 4)
      for c in m.content {
        match c {
          ToolUse(tu) => ids.push(tu.id)
          _ => ()
        }
      }
    }
    _ => fail("expected Message item")
  }
  assert_eq(ids.length(), 4)
  // 函数名缺失 → 空名，序号按函数名独立计数
  assert_eq(ids[0], "fc_f_0")
  assert_eq(ids[1], "fc_f_1")
  assert_eq(ids[2], "fc_g_0")
  assert_eq(ids[3], "fc__0")
}

///|
test "gemini decode - unknown role falls back to user" {
  let cases : Array[String] = [
    "{\"model\":\"m\",\"contents\":[{\"role\":\"system\",\"parts\":[{\"text\":\"x\"}]}]}",
    "{\"model\":\"m\",\"contents\":[{\"role\":\"assistant\",\"parts\":[{\"text\":\"x\"}]}]}",
    "{\"model\":\"m\",\"contents\":[{\"parts\":[{\"text\":\"x\"}]}]}",
  ]
  for json in cases {
    let req = req_ok(json)
    assert_eq(req.conversation.length(), 1)
    match req.conversation[0] {
      Message(m) => assert_eq(m.role, User)
      _ => fail("expected Message item")
    }
  }
  // 已知角色原样映射：model → Assistant，tool → Tool
  let known = req_ok(
    "{\"model\":\"m\",\"contents\":[{\"role\":\"model\",\"parts\":[{\"text\":\"x\"}]},{\"role\":\"tool\",\"parts\":[{\"text\":\"y\"}]}]}",
  )
  assert_eq(known.conversation.length(), 2)
  match known.conversation[0] {
    Message(m) => assert_eq(m.role, Assistant)
    _ => fail("expected Message item")
  }
  match known.conversation[1] {
    Message(m) => assert_eq(m.role, Tool)
    _ => fail("expected Message item")
  }
}

///|
test "gemini decode - content without parts yields empty message" {
  let req = req_ok("{\"model\":\"m\",\"contents\":[{\"role\":\"user\"}]}")
  assert_eq(req.conversation.length(), 1)
  match req.conversation[0] {
    Message(m) => assert_eq(m.content.length(), 0)
    _ => fail("expected Message item")
  }
}

///|
test "gemini decode - missing contents and systemInstruction fallbacks" {
  // contents 缺失 / 空数组 / 非数组 → 空会话
  let cases : Array[String] = [
    "{\"model\":\"m\"}", "{\"model\":\"m\",\"contents\":[]}", "{\"model\":\"m\",\"contents\":{}}",
  ]
  for json in cases {
    assert_eq(req_ok(json).conversation.length(), 0)
  }
  // systemInstruction 只取 text part，其他 part 跳过
  let with_sys = req_ok(
    "{\"model\":\"m\",\"systemInstruction\":{\"role\":\"system\",\"parts\":[{\"text\":\"a\"},{\"inlineData\":{\"data\":\"AA\"}},{\"text\":\"b\"}]},\"contents\":[{\"role\":\"user\",\"parts\":[{\"text\":\"hi\"}]}]}",
  )
  assert_true(with_sys.instructions is Some(_))
  match with_sys.instructions {
    Some(instrs) => assert_eq(instrs.length(), 2)
    None => fail("expected instructions")
  }
  // parts 缺失 / systemInstruction 非对象 / 整体缺失 → 无 instructions
  let empty_sys : Array[String] = [
    "{\"model\":\"m\",\"systemInstruction\":{\"role\":\"system\"}}", "{\"model\":\"m\",\"systemInstruction\":\"be nice\"}",
    "{\"model\":\"m\",\"contents\":[{\"role\":\"user\",\"parts\":[{\"text\":\"hi\"}]}]}",
  ]
  for json in empty_sys {
    assert_true(req_ok(json).instructions is None)
  }
}

///|
test "gemini decode - functionResponse pairing and empty object fallbacks" {
  let req = req_ok(
    "{\"model\":\"m\",\"contents\":[{\"role\":\"model\",\"parts\":[{\"functionCall\":{\"name\":\"f\",\"args\":{\"a\":1}}},{\"functionCall\":{\"name\":\"f\"}}]},{\"role\":\"tool\",\"parts\":[{\"functionResponse\":{\"name\":\"f\",\"response\":{\"content\":\"ok\"}}},{\"functionResponse\":{\"name\":\"f\"}},{\"functionResponse\":{\"name\":\"f\",\"response\":{}}},{\"functionResponse\":{\"name\":\"other\"}}]}]}",
  )
  assert_eq(req.conversation.length(), 5)
  // 第一轮 functionCall → Message（含两个 ToolUse 块）
  match req.conversation[0] {
    Message(m) => assert_eq(m.content.length(), 2)
    _ => fail("expected Message item")
  }
  // 后续轮次一律变成 ToolResult item，按函数名消费配对游标
  let expected : Array[String] = ["fc_f_0", "fc_f_1", "fc_f_2", "fc_other_0"]
  let mut i = 0
  while i < 4 {
    match req.conversation[i + 1] {
      ToolResult(tr) => assert_eq(tr.tool_use_id, expected[i])
      _ => fail("expected ToolResult item")
    }
    i = i + 1
  }
  // response 存在但 content 缺失 → "{}"
  match req.conversation[3] {
    ToolResult(tr) =>
      match tr.content[0] {
        Text(t, _) => assert_eq(t, "{}")
        _ => fail("expected Text content")
      }
    _ => fail("expected ToolResult item")
  }
  // response 整体缺失 → "{}"
  match req.conversation[2] {
    ToolResult(tr) =>
      match tr.content[0] {
        Text(t, _) => assert_eq(t, "{}")
        _ => fail("expected Text content")
      }
    _ => fail("expected ToolResult item")
  }
  // response.content 是字符串 → 原样 stringify
  match req.conversation[1] {
    ToolResult(tr) =>
      match tr.content[0] {
        Text(t, _) => assert_true(t.contains("ok"))
        _ => fail("expected Text content")
      }
    _ => fail("expected ToolResult item")
  }
}

///|
test "gemini decode - mixed functionResponse and text keeps only tool result" {
  let req = req_ok(
    "{\"model\":\"m\",\"contents\":[{\"role\":\"tool\",\"parts\":[{\"text\":\"dropped\"},{\"functionResponse\":{\"name\":\"f\",\"response\":{\"content\":\"ok\"}}},{\"inlineData\":{\"mimeType\":\"image/png\",\"data\":\"AA\"}}]}]}",
  )
  // 同轮次混合 part 时只保留 functionResponse → 单个 ToolResult item
  assert_eq(req.conversation.length(), 1)
  match req.conversation[0] {
    ToolResult(tr) => assert_eq(tr.tool_use_id, "fc_f_0")
    _ => fail("expected ToolResult item")
  }
}

///|
test "gemini decode - thought-only marker part is skipped" {
  let req = req_ok(
    "{\"model\":\"m\",\"contents\":[{\"role\":\"model\",\"parts\":[{\"thoughtSignature\":\"sig\"},{},\"plain\",{\"text\":\"hi\"}]}]}",
  )
  // thought-only marker / 空对象 / 裸字符串均无对应 IR 块 → 跳过
  match req.conversation[0] {
    Message(m) => {
      assert_eq(m.content.length(), 1)
      match m.content[0] {
        Text(t, _) => assert_eq(t, "hi")
        _ => fail("expected Text block")
      }
    }
    _ => fail("expected Message item")
  }
}

///|
test "gemini decode - tools functionDeclarations parse with fallbacks" {
  let req = req_ok(
    "{\"model\":\"m\",\"contents\":[{\"role\":\"user\",\"parts\":[{\"text\":\"hi\"}]}],\"tools\":[{\"functionDeclarations\":[{\"name\":\"f\",\"description\":\"desc\",\"parameters\":{\"type\":\"object\",\"properties\":{\"a\":{\"type\":\"string\"}}}},{\"name\":\"g\"}]},{\"googleSearch\":{}},{\"functionDeclarations\":[]}]}",
  )
  match req.tools {
    Some(ts) => {
      assert_eq(ts.length(), 2)
      assert_eq(ts[0].name, "f")
      assert_eq(ts[0].kind, Function)
      assert_eq(ts[0].description, Some("desc"))
      assert_true(ts[0].parameters_json.contains("\"properties\""))
      // parameters 缺失 → "{}"；description 缺失 → None
      assert_eq(ts[1].name, "g")
      assert_eq(ts[1].description, None)
      assert_eq(ts[1].parameters_json, "{}")
    }
    None => fail("expected tools")
  }
  // 无 functionDeclarations 的工具项 → 空列表 → None
  assert_true(
    req_ok(
      "{\"model\":\"m\",\"contents\":[{\"role\":\"user\",\"parts\":[{\"text\":\"hi\"}]}],\"tools\":[{\"googleSearch\":{}}]}",
    ).tools
    is None,
  )
  // tools 非数组 → None
  assert_true(
    req_ok(
      "{\"model\":\"m\",\"contents\":[{\"role\":\"user\",\"parts\":[{\"text\":\"hi\"}]}],\"tools\":{}}",
    ).tools
    is None,
  )
}

///|
test "gemini decode - tool choice functionCallingConfig modes" {
  assert_eq(
    req_ok(
      gemini_req(
        "toolConfig", "{\"functionCallingConfig\":{\"mode\":\"AUTO\"}}",
      ),
    ).tool_choice,
    Some(Auto),
  )
  assert_eq(
    req_ok(
      gemini_req("toolConfig", "{\"functionCallingConfig\":{\"mode\":\"ANY\"}}"),
    ).tool_choice,
    Some(Required),
  )
  assert_eq(
    req_ok(
      gemini_req(
        "toolConfig", "{\"functionCallingConfig\":{\"mode\":\"NONE\"}}",
      ),
    ).tool_choice,
    Some(None),
  )
  // 未知 mode / mode 缺失 / mode 非字符串 → None
  let bad_modes : Array[String] = [
    "{\"functionCallingConfig\":{\"mode\":\"WHATEVER\"}}", "{\"functionCallingConfig\":{}}",
    "{\"functionCallingConfig\":{\"mode\":7}}", "{\"functionCallingConfig\":\"AUTO\"}",
    "{}", "\"AUTO\"",
  ]
  for payload in bad_modes {
    assert_true(req_ok(gemini_req("toolConfig", payload)).tool_choice is None)
  }
  // 整个 toolConfig 缺失 → None
  assert_true(
    req_ok(
      "{\"model\":\"m\",\"contents\":[{\"role\":\"user\",\"parts\":[{\"text\":\"hi\"}]}]}",
    ).tool_choice
    is None,
  )
}

///|
test "gemini decode - thinkingLevel maps to reasoning effort" {
  assert_eq(
    req_ok(gemini_thinking("{\"thinkingLevel\":\"low\"}")).reasoning.unwrap().effort,
    Some(Low),
  )
  assert_eq(
    req_ok(gemini_thinking("{\"thinkingLevel\":\"medium\"}")).reasoning.unwrap().effort,
    Some(Medium),
  )
  assert_eq(
    req_ok(gemini_thinking("{\"thinkingLevel\":\"high\"}")).reasoning.unwrap().effort,
    Some(High),
  )
  // thinkingLevel 启用推理（enabled=true）
  assert_true(
    req_ok(gemini_thinking("{\"thinkingLevel\":\"low\"}")).reasoning.unwrap().enabled,
  )
  // 未知档位（含大小写变体）→ Low + Degraded 诊断
  let degraded : Array[String] = ["minimal", "MINIMAL", "ultra", ""]
  for level in degraded {
    let json = gemini_thinking("{\"thinkingLevel\":\"" + level + "\"}")
    match @gemini.gemini_to_lux_request(json) {
      Ok(cr) => {
        diag_contains(cr, "降级映射为 LucentReasoningEffort")
        assert_eq(cr.value().reasoning.unwrap().effort, Some(Low))
      }
      Err(e) => fail("unexpected Err: \{e}")
    }
  }
  // thinkingLevel 非字符串 → 落到 includeThoughts 分支（默认 disabled）
  match req_ok(gemini_thinking("{\"thinkingLevel\":3}")).reasoning {
    Some(rc) => assert_false(rc.enabled)
    None => fail("expected reasoning config")
  }
}

///|
test "gemini decode - includeThoughts and thinkingBudget fallbacks" {
  match req_ok(gemini_thinking("{\"includeThoughts\":true}")).reasoning {
    Some(rc) => {
      assert_true(rc.enabled)
      assert_true(rc.budget_tokens is None)
    }
    None => fail("expected reasoning config")
  }
  match
    req_ok(
      gemini_thinking("{\"includeThoughts\":true,\"thinkingBudget\":2048}"),
    ).reasoning {
    Some(rc) => {
      assert_true(rc.enabled)
      assert_eq(rc.budget_tokens, Some(2048))
    }
    None => fail("expected reasoning config")
  }
  // includeThoughts 缺失 / false / 非布尔 → disabled
  let payloads : Array[String] = [
    "{}", "{\"includeThoughts\":false}", "{\"includeThoughts\":\"yes\"}", "{\"thinkingBudget\":1024}",
  ]
  for payload in payloads {
    match req_ok(gemini_thinking(payload)).reasoning {
      Some(rc) => assert_false(rc.enabled)
      None => fail("expected reasoning config")
    }
  }
  // thinkingConfig 缺失 → 无 reasoning
  assert_true(
    req_ok(gemini_req("generationConfig", "{\"temperature\":0.5}")).reasoning
    is None,
  )
  // generationConfig 缺失 → 无 reasoning
  assert_true(
    req_ok(
      "{\"model\":\"m\",\"contents\":[{\"role\":\"user\",\"parts\":[{\"text\":\"hi\"}]}]}",
    ).reasoning
    is None,
  )
}

///|
test "gemini decode - generationConfig options and extras" {
  let req = req_ok(
    gemini_req(
      "generationConfig", "{\"temperature\":0.5,\"topP\":0.9,\"topK\":40,\"maxOutputTokens\":1024,\"candidateCount\":2,\"stopSequences\":[\"END\",\"STOP\"],\"responseMimeType\":\"application/json\"}",
    ),
  )
  match req.options.temperature {
    Some(t) => assert_true(t > 0.4 && t < 0.6)
    None => fail("expected temperature")
  }
  match req.options.top_p {
    Some(p) => assert_true(p > 0.8 && p < 1.0)
    None => fail("expected top_p")
  }
  assert_eq(req.options.top_k, Some(40))
  assert_eq(req.options.max_output_tokens, Some(1024))
  assert_eq(req.options.candidate_count, Some(2))
  assert_eq(req.options.stream, false)
  match req.options.stop {
    Some(arr) => assert_eq(arr.length(), 2)
    None => fail("expected stop sequences")
  }
  // 未知字段 → extras
  assert_true(req.options.extras is Some(_))
  match req.options.extras {
    Some(m) => assert_true(m.contains("responseMimeType"))
    None => fail("expected extras")
  }
  // generationConfig 缺失 → 默认值
  let bare = req_ok(
    "{\"model\":\"m\",\"contents\":[{\"role\":\"user\",\"parts\":[{\"text\":\"hi\"}]}]}",
  )
  assert_true(bare.options.temperature is None)
  assert_true(bare.options.stop is None)
  assert_true(bare.options.extras is None)
  assert_true(bare.options.top_k is None)
}

///|
test "gemini decode - reasoning effort encode level variants" {
  let levels : Array[(@lux.LucentReasoningEffort, String)] = [
    (Low, "\"thinkingLevel\":\"low\""),
    (Medium, "\"thinkingLevel\":\"medium\""),
    (High, "\"thinkingLevel\":\"high\""),
  ]
  for pair in levels {
    let req = @lux.LucentRequest::new(
      "gemini-3-pro",
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
      Some(@lux.LucentReasoningConfig::new(Some(pair.0), None)),
      None,
      None,
    )
    match @gemini.lux_request_to_gemini(req) {
      Ok(cr) => assert_true(cr.value().contains(pair.1))
      Err(e) => fail("unexpected Err: \{e}")
    }
  }
  // XHigh 在 gemini 无对等档位 → 降级为 high + Degraded 诊断
  let xhigh = @lux.LucentRequest::new(
    "gemini-3-pro",
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
    Some(@lux.LucentReasoningConfig::new(Some(XHigh), None)),
    None,
    None,
  )
  match @gemini.lux_request_to_gemini(xhigh) {
    Ok(cr) => {
      assert_true(cr.value().contains("\"thinkingLevel\":\"high\""))
      diag_contains(cr, "无 gemini thinkingLevel 对等档位")
    }
    Err(e) => fail("unexpected Err: \{e}")
  }
}

///|
test "gemini decode - response finish reason mapping" {
  let cases : Array[(String, @lux.LucentFinishReason)] = [
    ("STOP", Stop),
    ("MAX_TOKENS", Length),
    ("SAFETY", Safety),
    ("RECITATION", Recitation),
    ("MALFORMED_FUNCTION_CALL", MalformedToolCall),
    ("OTHER", Native("OTHER")),
    ("length", Length),
  ]
  for c in cases {
    let json = "{\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"text\":\"x\"}]},\"finishReason\":\"" +
      c.0 +
      "\"}]}"
    let resp = resp_ok(json)
    assert_eq(resp.choices.length(), 1)
    // index 缺失 → 回落为数组下标
    assert_eq(resp.choices[0].index, 0)
    assert_eq(resp.choices[0].finish_reason, c.1)
  }
  // finishReason 缺失 → Stop
  let resp = resp_ok(
    "{\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"text\":\"x\"}]}}]}",
  )
  assert_eq(resp.choices[0].finish_reason, Stop)
}

///|
test "gemini decode - response without candidates returns Err" {
  let cases : Array[String] = [
    "{\"candidates\":[]}", "{}", "{\"candidates\":\"none\"}", "{\"candidates\":[{\"index\":0}]}",
  ]
  for json in cases {
    match @gemini.gemini_to_lux_response(json) {
      Ok(_) => fail("expected Err for \{json}")
      Err(_) => ()
    }
  }
}

///|
test "gemini decode - response safety ratings parsed" {
  let resp = resp_ok(
    "{\"candidates\":[{\"index\":2,\"content\":{\"role\":\"model\",\"parts\":[{\"text\":\"x\"}]},\"finishReason\":\"SAFETY\",\"safetyRatings\":[{\"category\":\"HARM_CATEGORY_HATE_SPEECH\",\"probability\":\"LOW\"},{\"category\":\"HARM_CATEGORY_DANGEROUS\"},{\"probability\":\"HIGH\"}]}]}",
  )
  assert_eq(resp.choices[0].index, 2)
  assert_eq(resp.choices[0].finish_reason, Safety)
  match resp.choices[0].safety_ratings {
    Some(ratings) => {
      assert_eq(ratings.length(), 3)
      assert_eq(ratings[0].category, "HARM_CATEGORY_HATE_SPEECH")
      assert_eq(ratings[0].probability, "LOW")
      // category / probability 缺失 → 空串（不失败）
      assert_eq(ratings[1].category, "HARM_CATEGORY_DANGEROUS")
      assert_eq(ratings[1].probability, "")
      assert_eq(ratings[2].category, "")
      assert_eq(ratings[2].probability, "HIGH")
    }
    None => fail("expected safety ratings")
  }
  // safetyRatings 缺失 / 非数组 → None
  let no_ratings = resp_ok(
    "{\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"x\"}]},\"finishReason\":\"STOP\"}]}",
  )
  assert_true(no_ratings.choices[0].safety_ratings is None)
  let bad_ratings = resp_ok(
    "{\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"x\"}]},\"safetyRatings\":\"LOW\"}]}",
  )
  assert_true(bad_ratings.choices[0].safety_ratings is None)
  // safetyRatings 空数组 → Some([])
  let empty_ratings = resp_ok(
    "{\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"x\"}]},\"safetyRatings\":[]}]}",
  )
  match empty_ratings.choices[0].safety_ratings {
    Some(r) => assert_eq(r.length(), 0)
    None => fail("expected empty safety ratings array")
  }
}

///|
test "gemini decode - response thought and tool result parts" {
  let resp = resp_ok(
    "{\"responseId\":\"r-1\",\"modelVersion\":\"gemini-2.5-pro\",\"candidates\":[{\"index\":0,\"content\":{\"role\":\"model\",\"parts\":[{\"text\":\"reasoning\",\"thought\":true,\"thoughtSignature\":\"sig-1\"},{\"functionResponse\":{\"name\":\"f\",\"response\":{\"content\":\"tool output\"}}},{\"functionResponse\":{\"name\":\"f\"}},{\"text\":\"answer\"}]},\"finishReason\":\"STOP\"}],\"usageMetadata\":{\"promptTokenCount\":3,\"candidatesTokenCount\":4,\"totalTokenCount\":7}}",
  )
  assert_eq(resp.id, "r-1")
  assert_eq(resp.model, "gemini-2.5-pro")
  let parts = resp.choices[0].message.content
  assert_eq(parts.length(), 4)
  // thoughtSignature 入 IR signature
  match parts[0] {
    Thinking(th) => {
      assert_eq(th.text, "reasoning")
      assert_eq(th.signature, Some("sig-1"))
    }
    _ => fail("expected Thinking part")
  }
  // candidate 中的 functionResponse → tool_result（合成 id）
  match parts[1] {
    ToolResult(tr) => {
      assert_eq(tr.tool_use_id, "fc_f_0")
      match tr.content[0] {
        Text(t, _) => assert_true(t.contains("tool output"))
        _ => fail("expected Text content")
      }
    }
    _ => fail("expected ToolResult part")
  }
  // response 缺失 → "{}"
  match parts[2] {
    ToolResult(tr) => assert_eq(tr.tool_use_id, "fc_f_1")
    _ => fail("expected ToolResult part")
  }
  match parts[3] {
    Text(t, _) => assert_eq(t, "answer")
    _ => fail("expected Text part")
  }
  match resp.usage {
    Some(u) => assert_eq(u.total_tokens, 7)
    None => fail("expected usage")
  }
}

///|
test "gemini decode - response candidate functionCall and empty response fallbacks" {
  let resp = resp_ok(
    "{\"candidates\":[{\"index\":0,\"content\":{\"role\":\"model\",\"parts\":[{\"functionCall\":{\"name\":\"g\",\"id\":\"call_1\",\"args\":{\"a\":1}}},{\"functionResponse\":{\"name\":\"g\",\"response\":{}}},{\"text\":\"x\"}]},\"finishReason\":\"STOP\"},{\"index\":1,\"content\":{\"role\":\"model\"},\"finishReason\":\"STOP\"}]}",
  )
  assert_eq(resp.choices.length(), 2)
  let parts = resp.choices[0].message.content
  assert_eq(parts.length(), 3)
  // candidate 中的 functionCall → ToolUse（响应侧忽略显式 id，按 fc_<name>_<n> 合成）
  match parts[0] {
    ToolUse(tu) => {
      assert_eq(tu.id, "fc_g_0")
      assert_eq(tu.name, "g")
      assert_true(tu.arguments_json.contains("1"))
    }
    _ => fail("expected ToolUse part")
  }
  // response 存在但 content 缺失 → "{}"
  match parts[1] {
    ToolResult(tr) => {
      assert_eq(tr.tool_use_id, "fc_g_0")
      match tr.content[0] {
        Text(t, _) => assert_eq(t, "{}")
        _ => fail("expected Text content")
      }
    }
    _ => fail("expected ToolResult part")
  }
  // content 存在但 parts 缺失 → 空内容数组（不失败）
  assert_eq(resp.choices[1].message.content.length(), 0)
  assert_eq(resp.choices[1].message.role, Assistant)
}

///|
test "gemini decode - response encode finish reasons" {
  let cases : Array[(@lux.LucentFinishReason, String)] = [
    (Stop, "\"finishReason\":\"STOP\""),
    (Length, "\"finishReason\":\"MAX_TOKENS\""),
    (ToolCalls, "\"finishReason\":\"STOP\""),
    (Safety, "\"finishReason\":\"SAFETY\""),
    (Recitation, "\"finishReason\":\"RECITATION\""),
    (MalformedToolCall, "\"finishReason\":\"MALFORMED_FUNCTION_CALL\""),
    (Error, "\"finishReason\":\"OTHER\""),
    (ContentFilter, "\"finishReason\":\"STOP\""),
  ]
  for c in cases {
    let resp = @lux.LucentResponse::new(
      "",
      "gemini-2.5-pro",
      None,
      [
        @lux.LucentChoice::new(
          0,
          @lux.LucentMessage::new(Assistant, [@lux.LucentContent::text("hi")]),
          c.0,
          None,
        ),
      ],
      None,
      None,
    )
    match @gemini.lux_response_to_gemini(resp) {
      Ok(cr) => assert_true(cr.value().contains(c.1))
      Err(e) => fail("unexpected Err: \{e}")
    }
  }
  // 无 choices → Err
  let empty = @lux.LucentResponse::new("r", "m", None, [], None, None)
  assert_true(@gemini.lux_response_to_gemini(empty) is Err(_))
}

///|
test "gemini decode - response encode safety ratings usage and id" {
  let resp = @lux.LucentResponse::new(
    "resp-9",
    "gemini-2.5-pro",
    None,
    [
      @lux.LucentChoice::new(
        0,
        @lux.LucentMessage::new(Assistant, [@lux.LucentContent::text("hi")]),
        Stop,
        Some([
          @lux.LucentSafetyRating::new("HARM_CATEGORY_HATE_SPEECH", "LOW"),
          @lux.LucentSafetyRating::new("HARM_CATEGORY_SEXUAL", "NEGLIGIBLE"),
        ]),
      ),
    ],
    Some(@lux.LucentUsage::new(3, 4, 7)),
    None,
  )
  match @gemini.lux_response_to_gemini(resp) {
    Ok(cr) => {
      let s = cr.value()
      assert_true(s.contains("\"responseId\":\"resp-9\""))
      assert_true(s.contains("\"safetyRatings\":["))
      assert_true(s.contains("\"HARM_CATEGORY_HATE_SPEECH\""))
      assert_true(s.contains("\"usageMetadata\":{\"promptTokenCount\":3"))
      // 官方 GenerateContentResponse 无顶层 model 字段
      assert_false(s.contains("\"model\":"))
    }
    Err(e) => fail("unexpected Err: \{e}")
  }
  // usage 缺失 → 不输出 usageMetadata；id 为空串 → 不输出 responseId
  let no_usage = @lux.LucentResponse::new(
    "",
    "gemini-2.5-pro",
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
  match @gemini.lux_response_to_gemini(no_usage) {
    Ok(cr) => {
      assert_false(cr.value().contains("\"usageMetadata\""))
      assert_false(cr.value().contains("\"responseId\""))
    }
    Err(e) => fail("unexpected Err: \{e}")
  }
}

///|
test "gemini decode - response encode assistant tool result refusal and media" {
  let msg = @lux.LucentMessage::new(Assistant, [
    @lux.LucentContent::thinking("reasoning", Some("sig-x")),
    @lux.LucentContent::text("answer"),
    @lux.LucentContent::tool_use(
      "call_1",
      "get_weather",
      "{\"city\":\"Beijing\"}",
      None,
    ),
    @lux.LucentContent::tool_result("fc_f_0", [@lux.LucentContent::text("ok")]),
    @lux.LucentContent::refusal("I cannot help"),
    @lux.LucentContent::native("vendor_tag", Json::string("raw")),
    @lux.LucentContent::image("image/png", Inline("AA")),
    @lux.LucentContent::audio("audio/mp3", Url("http://x/y.mp3")),
    @lux.LucentContent::file("application/pdf", FileUri("gs://b/a.pdf")),
    @lux.LucentContent::video("video/mp4", Inline("BB")),
  ])
  let resp = @lux.LucentResponse::new(
    "c-1",
    "gemini-2.5-pro",
    None,
    [@lux.LucentChoice::new(0, msg, Stop, None)],
    None,
    None,
  )
  match @gemini.lux_response_to_gemini(resp) {
    Ok(cr) => {
      let s = cr.value()
      // Thinking + thoughtSignature
      assert_true(
        s.contains(
          "{\"text\":\"reasoning\",\"thought\":true,\"thoughtSignature\":\"sig-x\"}",
        ),
      )
      assert_true(s.contains("{\"text\":\"answer\"}"))
      // assistant 轮次的 tool_use → functionCall part（带官方可选 id）
      assert_true(
        s.contains(
          "\"functionCall\":{\"name\":\"get_weather\",\"id\":\"call_1\"",
        ),
      )
      // assistant 轮次的 tool_result → functionResponse + Degraded
      assert_true(s.contains("\"functionResponse\":{\"name\":\"fc_f_0\""))
      diag_contains(
        cr, "tool_result inside an assistant candidate is re-encoded as functionResponse",
      )
      // refusal / native → Unsupported 诊断，且内容不出现在输出中
      diag_contains(cr, "refusal text dropped")
      assert_false(s.contains("I cannot help"))
      diag_contains(cr, "native content (vendor_tag) not supported by gemini")
      assert_false(s.contains("vendor_tag"))
      // 媒体三态：inlineData / fileUri（http URL 也按 fileUri 透传）
      assert_true(
        s.contains(
          "\"inlineData\":{\"mimeType\":\"image/png\",\"data\":\"AA\"}",
        ),
      )
      assert_true(
        s.contains(
          "\"fileData\":{\"mimeType\":\"audio/mp3\",\"fileUri\":\"http://x/y.mp3\"}",
        ),
      )
      assert_true(
        s.contains(
          "\"fileData\":{\"mimeType\":\"application/pdf\",\"fileUri\":\"gs://b/a.pdf\"}",
        ),
      )
      assert_true(
        s.contains(
          "\"inlineData\":{\"mimeType\":\"video/mp4\",\"data\":\"BB\"}",
        ),
      )
    }
    Err(e) => fail("unexpected Err: \{e}")
  }
}

///|
test "gemini decode - response encode message reasoning and dual carrier" {
  let msg = @lux.LucentMessage::with_reasoning(
    Assistant,
    [
      @lux.LucentContent::thinking("block reasoning", Some("sig-b")),
      @lux.LucentContent::text("answer"),
    ],
    Some(@lux.LucentThinking::visible("msg reasoning", Some("sig-m"))),
  )
  let resp = @lux.LucentResponse::new(
    "c-2",
    "gemini-2.5-pro",
    None,
    [@lux.LucentChoice::new(0, msg, Stop, None)],
    None,
    None,
  )
  match @gemini.lux_response_to_gemini(resp) {
    Ok(cr) => {
      let s = cr.value()
      // 消息级 reasoning 前置为 thought part（含 thoughtSignature）
      assert_true(
        s.contains(
          "{\"text\":\"msg reasoning\",\"thought\":true,\"thoughtSignature\":\"sig-m\"}",
        ),
      )
      assert_true(s.contains("{\"text\":\"answer\"}"))
      // content Thinking 被跳过（不重复输出）+ Degraded
      assert_false(s.contains("block reasoning"))
      diag_contains(cr, "both message.reasoning and content Thinking present")
    }
    Err(e) => fail("unexpected Err: \{e}")
  }
}

///|
test "gemini decode - stream thinking and text block lifecycle" {
  let sse = "data: {\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"text\":\"a\",\"thought\":true}]}}]}\n" +
    "data: {\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"text\":\"b\"}]}}]}\n" +
    "data: {\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"text\":\"c\",\"thought\":\"yes\"}]}}]}\n" +
    "data: {\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"text\":\"c2\",\"thought\":true}]}}]}\n" +
    "data: {\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"text\":\"d\"}]}}]}\n" +
    "data: {\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"text\":\"e\"}]}}]}\n" +
    "data: {\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"functionCall\":{\"name\":\"f\"}}]},\"finishReason\":\"STOP\"}]}\n"
  let events = sse_ok(sse)
  // CR-002 A1：首个可解析帧发 ConversationStart（摘要记 "?"），其后事件整体后移一位
  assert_eq(event_summary(events), "?S0D0E0S1D1E1S2D2D2E2S3D3D3E3S4D4E4FX")
  assert_eq(events.length(), 20)
  match events[0] {
    ConversationStart(_) => ()
    _ => fail("expected ConversationStart first")
  }
  // 思考块与文本块互斥开闭；同类型的后续增量复用已打开的块序号
  assert_eq(events[1], BlockStart(0, Thinking))
  assert_eq(
    events[2],
    BlockDelta(0, @lux.LucentBlockDelta::thinking_delta("a")),
  )
  assert_eq(events[3], BlockEnd(0))
  assert_eq(events[4], BlockStart(1, Text))
  assert_eq(events[5], BlockDelta(1, @lux.LucentBlockDelta::text_delta("b")))
  // 字符串 thought 也走思考分支；第二个 thought part 复用思考块 2
  assert_eq(events[7], BlockStart(2, Thinking))
  assert_eq(
    events[8],
    BlockDelta(2, @lux.LucentBlockDelta::thinking_delta("c")),
  )
  assert_eq(
    events[9],
    BlockDelta(2, @lux.LucentBlockDelta::thinking_delta("c2")),
  )
  // 第二个文本 part 复用文本块 3
  assert_eq(events[11], BlockStart(3, Text))
  assert_eq(events[12], BlockDelta(3, @lux.LucentBlockDelta::text_delta("d")))
  assert_eq(events[13], BlockDelta(3, @lux.LucentBlockDelta::text_delta("e")))
  // functionCall 之前先由 close_gemini_blocks 闭合文本块
  assert_eq(events[14], BlockEnd(3))
  assert_eq(events[15], BlockStart(4, ToolCall("fc_f_0", "f")))
  assert_eq(events[17], BlockEnd(4))
  assert_eq(events[18], Finish(Stop))
  assert_eq(events[19], Done)
}

///|
test "gemini decode - stream signature delta closes open blocks" {
  let sse = "data: {\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"text\":\"a\",\"thought\":true}]}}]}\n" +
    "data: {\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"text\":\"b\"}]}}]}\n" +
    "data: {\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"thoughtSignature\":\"sig-1\"}]}}]}\n" +
    "data: {\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"text\":\"c\",\"thought\":true}]}}]}\n" +
    "data: {\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"thoughtSignature\":\"sig-2\"}]}}]}\n"
  let events = sse_ok(sse)
  // 无 text 的 thoughtSignature 帧：先闭合当前打开的块（文本一次、思考一次），
  // 再开一个签名 Thinking 块并立即闭合
  // CR-002 A1：首帧为 ConversationStart，其后事件整体后移一位
  assert_eq(event_summary(events), "?S0D0E0S1D1E1S2D2E2S3D3E3S4D4E4X")
  assert_eq(events.length(), 17)
  assert_eq(
    events[8],
    BlockDelta(2, @lux.LucentBlockDelta::signature_delta("sig-1")),
  )
  assert_eq(events[9], BlockEnd(2))
  // 思考块打开时收到签名帧 → close_gemini_blocks 闭合思考块
  assert_eq(events[12], BlockEnd(3))
  assert_eq(
    events[14],
    BlockDelta(4, @lux.LucentBlockDelta::signature_delta("sig-2")),
  )
  assert_eq(events[15], BlockEnd(4))
  assert_eq(events[16], Done)
}

///|
test "gemini decode - stream functionCall synthetic ids" {
  let sse = "data: {\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"functionCall\":{\"name\":\"f\",\"args\":{\"a\":1}}}]}}]}\n" +
    "data: {\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"functionCall\":{\"name\":\"f\",\"args\":{\"b\":2}}}]}}]}\n" +
    "data: {\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"functionCall\":{\"name\":\"f\",\"id\":\"call_explicit\"}}]}}]}\n" +
    "data: {\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"functionCall\":{\"name\":\"f\",\"id\":\"\"}}]},\"finishReason\":\"STOP\"}]}\n"
  let events = sse_ok(sse)
  assert_eq(event_summary(events), "?S0D0E0S1D1E1S2D2E2S3D3E3FX")
  let ids : Array[String] = []
  let names : Array[String] = []
  for ev in events {
    match ev {
      BlockStart(_, ToolCall(id, name)) => {
        ids.push(id)
        names.push(name)
      }
      _ => ()
    }
  }
  assert_eq(ids.length(), 4)
  // 显式 id 优先；空串 id 回落为合成 id（序号按函数名独立计数）
  assert_eq(ids[0], "fc_f_0")
  assert_eq(ids[1], "fc_f_1")
  assert_eq(ids[2], "call_explicit")
  assert_eq(ids[3], "fc_f_2")
  assert_eq(names[0], "f")
  assert_eq(names[3], "f")
}

///|
test "gemini decode - stream usage and done emitted once" {
  let sse = "data: {\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"text\":\"x\"}]},\"finishReason\":\"MAX_TOKENS\"}]}\n" +
    "data: {\"usageMetadata\":{\"promptTokenCount\":3,\"candidatesTokenCount\":4,\"totalTokenCount\":7,\"thoughtsTokenCount\":5,\"cachedContentTokenCount\":2}}\n"
  let events = sse_ok(sse)
  // CR-001 D3：Done 不再贴在 finishReason 上，而是排在本段输入的 usage 之后
  // （否则 OpenAI 目标的 usage 帧会落到 [DONE] 之后而被客户端丢弃）。
  // CR-002 A1：首帧为 ConversationStart，其后事件整体后移一位。
  assert_eq(event_summary(events), "?S0D0E0FUX")
  assert_eq(events[4], Finish(Length))
  match events[5] {
    Usage(u) => {
      assert_eq(u.prompt_tokens, 3)
      assert_eq(u.completion_tokens, 4)
      assert_eq(u.total_tokens, 7)
      assert_eq(u.reasoning_tokens, Some(5))
      assert_eq(u.cached_tokens, Some(2))
    }
    _ => fail("expected Usage event")
  }
  // Usage 帧单独出现时补发 Done
  let usage_only = sse_ok(
    "data: {\"usageMetadata\":{\"promptTokenCount\":1,\"candidatesTokenCount\":2,\"totalTokenCount\":3}}\n",
  )
  assert_eq(event_summary(usage_only), "?UX")
}

///|
test "gemini decode - stream fallback done and skipped frames" {
  // 空流 / 无 data 行 → 无任何可解析帧：CR-003 R2 起仍补一个会话元信息（"?"），
  // 保证退化流也有协议首帧；其后仅兜底 Done。
  assert_eq(event_summary(sse_ok("")), "?X")
  assert_eq(event_summary(sse_ok("event: ping\n\n")), "?X")
  // CR-002 A1：只要存在可解析帧就会先发 ConversationStart（"?"），
  // 因此下列用例由 "X" 变为 "?X"；非法 JSON 帧被跳过后仍以首帧元信息开头。
  assert_eq(
    event_summary(
      sse_ok(
        "data: {oops\ndata: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"x\"}]}}]}\n",
      ),
    ),
    "?S0D0E0X",
  )
  // candidates 空数组 → 无内容事件（仅元信息 + 兜底 Done）
  assert_eq(event_summary(sse_ok("data: {\"candidates\":[]}\n")), "?X")
  // content 缺失 / parts 缺失 / part 无 text → 无内容事件
  assert_eq(
    event_summary(sse_ok("data: {\"candidates\":[{\"index\":0}]}\n")),
    "?X",
  )
  assert_eq(
    event_summary(
      sse_ok("data: {\"candidates\":[{\"content\":{\"role\":\"model\"}}]}\n"),
    ),
    "?X",
  )
  assert_eq(
    event_summary(
      sse_ok(
        "data: {\"candidates\":[{\"content\":{\"parts\":[{\"inlineData\":{\"mimeType\":\"image/png\",\"data\":\"AA\"}}]}}]}\n",
      ),
    ),
    "?X",
  )
  // parts 为空数组 → 无内容事件
  assert_eq(
    event_summary(
      sse_ok("data: {\"candidates\":[{\"content\":{\"parts\":[]}}]}\n"),
    ),
    "?X",
  )
}
