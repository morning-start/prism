///|
/// Google Gemini 适配器白盒测试

///|
/// === 1. 请求解码 ===

///|
test "gemini_to_lux_request - simple user message" {
  let json = "{\"model\":\"gemini-2.5-pro\",\"contents\":[{\"role\":\"user\",\"parts\":[{\"text\":\"Hello\"}]}]}"
  match gemini_to_lux_request(json) {
    Ok(cr) => {
      let req = cr.value()
      assert_eq(req.model, "gemini-2.5-pro")
      assert_eq(req.conversation.length(), 1)
      match req.conversation[0] {
        Message(m) => {
          assert_eq(m.role, User)
          match m.content[0] {
            Text(t, _) => assert_eq(t, "Hello")
            _ => assert_true(false)
          }
        }
        _ => assert_true(false)
      }
    }
    Err(e) => fail("unexpected: \{e}")
  }
}

///|
test "gemini_to_lux_request - systemInstruction extracted" {
  let json = "{\"model\":\"gemini-2.5-pro\",\"systemInstruction\":{\"role\":\"system\",\"parts\":[{\"text\":\"Be helpful\"}]},\"contents\":[{\"role\":\"user\",\"parts\":[{\"text\":\"hi\"}]}]}"
  match gemini_to_lux_request(json) {
    Ok(cr) =>
      match cr.value().instructions {
        Some(instrs) => assert_eq(instrs.length(), 1)
        None => assert_true(false)
      }
    Err(_) => assert_true(false)
  }
}

///|
test "gemini_to_lux_request - model role mapped to assistant" {
  let json = "{\"model\":\"gemini-2.5-pro\",\"contents\":[{\"role\":\"model\",\"parts\":[{\"text\":\"hello there\"}]}]}"
  match gemini_to_lux_request(json) {
    Ok(cr) =>
      match cr.value().conversation[0] {
        Message(m) => assert_eq(m.role, Assistant)
        _ => assert_true(false)
      }
    Err(_) => assert_true(false)
  }
}

///|
test "gemini_to_lux_request - functionCall and functionResponse" {
  let json = "{\"model\":\"gemini-2.5-pro\",\"contents\":[{\"role\":\"model\",\"parts\":[{\"functionCall\":{\"name\":\"get_weather\",\"args\":{\"city\":\"Beijing\"}}}]},{\"role\":\"tool\",\"parts\":[{\"functionResponse\":{\"name\":\"get_weather\",\"response\":{\"name\":\"get_weather\",\"content\":{\"temp\":25}}}}]}]}"
  match gemini_to_lux_request(json) {
    Ok(cr) => {
      let req = cr.value()
      assert_eq(req.conversation.length(), 2)
      match req.conversation[1] {
        ToolResult(tr) => assert_eq(tr.tool_use_id, "fc_get_weather_0")
        _ => assert_true(false)
      }
    }
    Err(_) => assert_true(false)
  }
}

///|
test "gemini_to_lux_request - generationConfig parsed" {
  let json = "{\"model\":\"gemini-2.5-pro\",\"contents\":[{\"role\":\"user\",\"parts\":[{\"text\":\"hi\"}]}],\"generationConfig\":{\"temperature\":0.5,\"topP\":0.9,\"maxOutputTokens\":1024,\"candidateCount\":2,\"stopSequences\":[\"END\"]}}"
  match gemini_to_lux_request(json) {
    Ok(cr) => {
      let req = cr.value()
      match req.options.temperature {
        Some(t) => assert_true(t > 0.4 && t < 0.6)
        None => assert_true(false)
      }
      match req.options.top_p {
        Some(p) => assert_true(p > 0.8 && p < 1.0)
        None => assert_true(false)
      }
      assert_eq(req.options.max_output_tokens, Some(1024))
      assert_eq(req.options.candidate_count, Some(2))
    }
    Err(_) => assert_true(false)
  }
}

///|
/// === 2. 请求编码 ===

///|
test "lux_request_to_gemini - simple user message" {
  let req = @lux.LucentRequest::from_messages(
    "gemini-2.5-pro",
    None,
    [@lux.LucentMessage::new(User, [@lux.LucentContent::text("hi")])],
    None,
    None,
    @lux.LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
  match lux_request_to_gemini(req) {
    Ok(cr) => {
      let s = cr.value()
      assert_true(s.contains("\"contents\":"))
      assert_true(s.contains("\"role\":\"user\""))
    }
    Err(_) => assert_true(false)
  }
}

///|
/// === 3. 响应解码 ===

///|
test "gemini_to_lux_response - text response" {
  let json = "{\"candidates\":[{\"index\":0,\"content\":{\"role\":\"model\",\"parts\":[{\"text\":\"Hello!\"}]},\"finishReason\":\"STOP\"}],\"usageMetadata\":{\"promptTokenCount\":10,\"candidatesTokenCount\":5,\"totalTokenCount\":15}}"
  match gemini_to_lux_response(json) {
    Ok(cr) => {
      let resp = cr.value()
      assert_eq(resp.choices.length(), 1)
      assert_eq(resp.choices[0].finish_reason, Stop)
      match resp.choices[0].message.content[0] {
        Text(t, _) => assert_eq(t, "Hello!")
        _ => assert_true(false)
      }
      match resp.usage {
        Some(u) => {
          assert_eq(u.prompt_tokens, 10)
          assert_eq(u.completion_tokens, 5)
        }
        None => assert_true(false)
      }
    }
    Err(_) => assert_true(false)
  }
}

///|
test "gemini_to_lux_response - detailed usage with thoughts and cached tokens" {
  let json = "{\"candidates\":[{\"index\":0,\"content\":{\"role\":\"model\",\"parts\":[{\"text\":\"Hello!\"}]},\"finishReason\":\"STOP\"}],\"usageMetadata\":{\"promptTokenCount\":100,\"candidatesTokenCount\":50,\"totalTokenCount\":150,\"thoughtsTokenCount\":30,\"cachedContentTokenCount\":40}}"
  match gemini_to_lux_response(json) {
    Ok(cr) => {
      let u = cr.value().usage.unwrap_or(@lux.LucentUsage::new(0, 0, 0))
      assert_eq(u.prompt_tokens, 100)
      assert_eq(u.completion_tokens, 50)
      assert_eq(u.total_tokens, 150)
      assert_eq(u.reasoning_tokens, Some(30))
      assert_eq(u.cached_tokens, Some(40))
    }
    Err(_) => assert_true(false)
  }
}

///|
test "gemini_to_lux_response - multiple candidates" {
  let json = "{\"candidates\":[{\"index\":0,\"content\":{\"role\":\"model\",\"parts\":[{\"text\":\"answer1\"}]},\"finishReason\":\"STOP\"},{\"index\":1,\"content\":{\"role\":\"model\",\"parts\":[{\"text\":\"answer2\"}]},\"finishReason\":\"STOP\"}],\"usageMetadata\":{\"promptTokenCount\":5,\"candidatesTokenCount\":10,\"totalTokenCount\":15}}"
  match gemini_to_lux_response(json) {
    Ok(cr) => assert_eq(cr.value().choices.length(), 2)
    Err(_) => assert_true(false)
  }
}

///|
/// === 4. 响应编码 ===

///|
test "lux_response_to_gemini - text response" {
  let msg = @lux.LucentMessage::new(Assistant, [
    @lux.LucentContent::text("Hello"),
  ])
  let choice = @lux.LucentChoice::new(0, msg, Stop, None)
  let resp = @lux.LucentResponse::new(
    "",
    "gemini-2.5-pro",
    None,
    [choice],
    Some(@lux.LucentUsage::new(10, 5, 15)),
    None,
  )
  match lux_response_to_gemini(resp) {
    Ok(cr) => {
      let s = cr.value()
      assert_true(s.contains("\"candidates\":"))
      assert_true(s.contains("\"finishReason\":\"STOP\""))
      assert_true(s.contains("\"promptTokenCount\":10"))
    }
    Err(_) => assert_true(false)
  }
}

///|
/// === 5. 流解码 ===

///|
test "gemini_sse_to_events - text chunks" {
  let sse = "data: {\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"text\":\"Hello\"}]}}]}\ndata: {\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"text\":\" world\"}]},\"finishReason\":\"STOP\"}],\"usageMetadata\":{\"promptTokenCount\":10,\"candidatesTokenCount\":5,\"totalTokenCount\":15}}\n"
  match gemini_sse_to_events(sse) {
    Ok(cr) => assert_true(cr.value().length() >= 3)
    Err(_) => assert_true(false)
  }
}

///|
/// 同名工具多次调用时，id 必须唯一且 functionResponse 与 functionCall 配对。
test "gemini_to_lux_request - duplicate tool names pair correctly" {
  let json = "{\"model\":\"gemini-2.5-pro\",\"contents\":[{\"role\":\"model\",\"parts\":[{\"functionCall\":{\"name\":\"search\",\"args\":{\"q\":\"a\"}}},{\"functionCall\":{\"name\":\"search\",\"args\":{\"q\":\"b\"}}}]},{\"role\":\"tool\",\"parts\":[{\"functionResponse\":{\"name\":\"search\",\"response\":{\"content\":{\"r\":1}}}},{\"functionResponse\":{\"name\":\"search\",\"response\":{\"content\":{\"r\":2}}}}]}]}"
  match gemini_to_lux_request(json) {
    Ok(cr) => {
      let req = cr.value()
      assert_eq(req.conversation.length(), 3)
      let ids : Array[String] = []
      for item in req.conversation {
        match item {
          Message(m) =>
            for c in m.content {
              match c {
                ToolUse(tu) => ids.push(tu.id)
                _ => ()
              }
            }
          ToolCall(tu) => ids.push(tu.id)
          ToolResult(tr) => ids.push(tr.tool_use_id)
          _ => ()
        }
      }
      assert_eq(ids.length(), 4)
      // 两个 call + 两个 response，两两配对且互不重复
      assert_eq(ids[0], "fc_search_0")
      assert_eq(ids[1], "fc_search_1")
      assert_eq(ids[2], "fc_search_0")
      assert_eq(ids[3], "fc_search_1")
    }
    Err(_) => assert_true(false)
  }
}

///|
/// === 保真度：媒体占位修复 ===

///|
test "decode - inlineData maps to image multimedia not placeholder" {
  let json = "{\"contents\":[{\"role\":\"user\",\"parts\":[{\"inlineData\":{\"mimeType\":\"image/png\",\"data\":\"AA\"}}]}]}"
  match gemini_to_lux_request(json) {
    Ok(cr) => {
      let req = cr.value()
      // 不得输出文本占位
      assert_true(!req.to_json().stringify().contains("[inline data]"))
      // 应精确映射为 Image（LucentMultimedia）
      match req.conversation[0] {
        Message(m) =>
          match m.content[0] {
            Image(mm) => {
              assert_eq(mm.media_type, "image/png")
              match mm.source {
                Inline(data) => assert_eq(data, "AA")
                _ => assert_true(false)
              }
            }
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
      // 精确映射：无诊断
      assert_eq(cr.diagnostics().length(), 0)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "decode - fileData maps to image multimedia not placeholder" {
  let json = "{\"contents\":[{\"role\":\"user\",\"parts\":[{\"fileData\":{\"mimeType\":\"application/pdf\",\"fileUri\":\"gs://bucket/a.pdf\"}}]}]}"
  match gemini_to_lux_request(json) {
    Ok(cr) => {
      let req = cr.value()
      // 不得输出文本占位
      assert_true(!req.to_json().stringify().contains("[file data]"))
      // 应精确映射为 Image（LucentMultimedia, FileUri source）
      match req.conversation[0] {
        Message(m) =>
          match m.content[0] {
            Image(mm) => {
              assert_eq(mm.media_type, "application/pdf")
              match mm.source {
                FileUri(uri) => assert_eq(uri, "gs://bucket/a.pdf")
                _ => assert_true(false)
              }
            }
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    }
    Err(_) => assert_true(false)
  }
}

///|
test "gemini store unsupported diagnostic" {
  let opts = @lux.LucentOptions::default().with_store(Some(true))
  let req = @lux.LucentRequest::new(
    "gemini-2.0-flash",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [@lux.LucentContent::text("Hi")]),
      ),
    ],
    None,
    None,
    opts,
    None,
    None,
    None,
    None,
  )
  match lux_request_to_gemini(req) {
    Ok(cr) => {
      // 必须携带 Unsupported 诊断
      assert_true(cr.diagnostics().length() > 0)
      // 且编码 JSON 不含 "store"
      assert_false(cr.value().contains("\"store\""))
    }
    Err(e) => fail("encode: \{e}")
  }
}

///|
/// T8：previous_response_id 标准字段——无历史拒绝，有历史剔除+诊断
test "gemini previous_response_id standard field rejected without history" {
  let opts = @lux.LucentOptions::default().with_previous_response_id(
    Some("resp_1"),
  )
  let req = @lux.LucentRequest::new(
    "gemini-2.0-flash",
    None,
    [],
    None,
    None,
    opts,
    None,
    None,
    None,
    None,
  )
  match lux_request_to_gemini(req) {
    Ok(_) => fail("expected rejection without history")
    Err(e) => assert_true(e.contains("previous_response_id"))
  }
}

///|
test "gemini previous_response_id standard field degrades with history" {
  let opts = @lux.LucentOptions::default().with_previous_response_id(
    Some("resp_1"),
  )
  let req = @lux.LucentRequest::new(
    "gemini-2.0-flash",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [@lux.LucentContent::text("Hi")]),
      ),
    ],
    None,
    None,
    opts,
    None,
    None,
    None,
    None,
  )
  match lux_request_to_gemini(req) {
    Ok(cr) => {
      assert_false(cr.value().contains("previous_response_id"))
      let mut has_unsupported = false
      for d in cr.diagnostics() {
        if d.field == "options.previous_response_id" && d.status == Unsupported {
          has_unsupported = true
        }
      }
      assert_true(has_unsupported)
    }
    Err(e) => fail("encode: \{e}")
  }
}

///|
/// T8：extras 旧载荷回退——同样剔除，不落入 generationConfig
test "gemini previous_response_id legacy extras stripped" {
  let opts = @lux.LucentOptions::default().with_extras(
    Some({ "previous_response_id": Json::string("resp_legacy") }),
  )
  let req = @lux.LucentRequest::new(
    "gemini-2.0-flash",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [@lux.LucentContent::text("Hi")]),
      ),
    ],
    None,
    None,
    opts,
    None,
    None,
    None,
    None,
  )
  match lux_request_to_gemini(req) {
    Ok(cr) => assert_false(cr.value().contains("previous_response_id"))
    Err(e) => fail("encode: \{e}")
  }
}

///|
test "gemini non-function tool kind unsupported" {
  let req = @lux.LucentRequest::from_messages(
    "gemini-2.0-flash",
    None,
    [@lux.LucentMessage::new(User, [@lux.LucentContent::text("Hi")])],
    Some([@lux.LucentTool::new("ws", None, "{}", None, WebSearch)]),
    None,
    @lux.LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
  match lux_request_to_gemini(req) {
    Ok(cr) => {
      // 必须携带 Unsupported 诊断（不静默降级为 function）
      let mut has_unsupported = false
      for d in cr.diagnostics() {
        if d.field == "tools.kind" && d.status == Unsupported {
          has_unsupported = true
        }
      }
      assert_true(has_unsupported)
      // 且编码 JSON 不含被跳过的工具名
      assert_false(cr.value().contains("ws"))
    }
    Err(e) => fail("encode: \{e}")
  }
}

///|
test "gemini extras round-trip" {
  let opts = @lux.LucentOptions::default().with_extras(
    Some({ "extra_field": Json::string("v1") }),
  )
  let req = @lux.LucentRequest::new(
    "gemini-2.0-flash",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [@lux.LucentContent::text("Hi")]),
      ),
    ],
    None,
    None,
    opts,
    None,
    None,
    None,
    None,
  )
  match lux_request_to_gemini(req) {
    Ok(cr) => {
      assert_true(cr.value().contains("\"extra_field\":\"v1\""))
      match gemini_to_lux_request(cr.value()) {
        Ok(cr2) =>
          match cr2.value().options.extras {
            Some(m) => assert_true(m.contains("extra_field"))
            None => fail("extras not decoded")
          }
        Err(e) => fail("decode: \{e}")
      }
    }
    Err(e) => fail("encode: \{e}")
  }
}

///|
test "gemini thought part - only Thinking, no text placeholder" {
  // 用 IR 构造器 + 适配器编码产输入（不手写 JSON）
  let resp = @lux.LucentResponse::new(
    "r1",
    "gemini-2.0-flash",
    None,
    [
      @lux.LucentChoice::new(
        0,
        @lux.LucentMessage::new(Assistant, [
          @lux.LucentContent::thinking("think...", None),
        ]),
        Stop,
        None,
      ),
    ],
    None,
    None,
  )
  match lux_response_to_gemini(resp) {
    Ok(cr) =>
      match gemini_to_lux_response(cr.value()) {
        Ok(cr2) => {
          let content = cr2.value().choices[0].message.content
          let mut has_thinking = false
          let mut has_plain_text = false
          for c in content {
            match c {
              Thinking(_) => has_thinking = true
              Text(_, _) => has_plain_text = true
              _ => ()
            }
          }
          assert_true(has_thinking)
          assert_false(has_plain_text) // 不伪装成文本
        }
        Err(e) => fail("decode: \{e}")
      }
    Err(e) => fail("encode: \{e}")
  }
}

///|
/// thoughtSignature 跨轮延续：入站 part.thoughtSignature → IR signature → 出站还原
test "gemini thoughtSignature round-trips through IR" {
  let json = "{\"contents\":[{\"role\":\"model\",\"parts\":[{\"text\":\"internal reasoning\",\"thought\":true,\"thoughtSignature\":\"sig-gemini-1\"}]}]}"
  match gemini_to_lux_request(json) {
    Ok(cr) =>
      match cr.value().conversation[0] {
        Message(m) =>
          match m.content[0] {
            Thinking(th) => assert_eq(th.signature, Some("sig-gemini-1"))
            _ => assert_true(false)
          }
        _ => assert_true(false)
      }
    Err(e) => fail("decode: \{e}")
  }
  // 出站还原
  let req = @lux.LucentRequest::new(
    "gemini-3-pro",
    None,
    [
      @lux.LucentConversationItem::reasoning(
        @lux.LucentThinking::visible("internal reasoning", Some("sig-gemini-1")),
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
  match lux_request_to_gemini(req) {
    Ok(cr) =>
      assert_true(cr.value().contains("\"thoughtSignature\":\"sig-gemini-1\""))
    Err(e) => fail("encode: \{e}")
  }
}

///|
/// 跨协议链路：vLLM 消息级 reasoning → IR → Gemini 出站 → thought:true part
test "lux_response_to_gemini - message-level reasoning emits thought part" {
  let th = @lux.LucentThinking::visible("step by step", None)
  let msg = @lux.LucentMessage::with_reasoning(
    Assistant,
    [@lux.LucentContent::text("answer")],
    Some(th),
  )
  let resp = @lux.LucentResponse::new(
    "c-1",
    "model",
    None,
    [@lux.LucentChoice::new(0, msg, Stop, None)],
    None,
    None,
  )
  match lux_response_to_gemini(resp) {
    Ok(cr) => {
      let s = cr.value()
      // 消息级 reasoning 前置为 thought:true part
      assert_true(s.contains("{\"text\":\"step by step\",\"thought\":true}"))
      // content 保留可见文本 part
      assert_true(s.contains("{\"text\":\"answer\"}"))
    }
    Err(_) => assert_true(false)
  }
}

///|
/// 双载体并存：message.reasoning 优先，content Thinking part 跳过 → Degraded
test "lux_response_to_gemini - dual carrier yields Degraded" {
  let th = @lux.LucentThinking::visible("msg reasoning", None)
  let msg = @lux.LucentMessage::with_reasoning(
    Assistant,
    [@lux.LucentContent::thinking("block reasoning", None)],
    Some(th),
  )
  let resp = @lux.LucentResponse::new(
    "c-1",
    "model",
    None,
    [@lux.LucentChoice::new(0, msg, Stop, None)],
    None,
    None,
  )
  match lux_response_to_gemini(resp) {
    Ok(cr) => {
      let mut has_dual = false
      for d in cr.diagnostics() {
        if d.field == "reasoning.dual_carrier" && d.status == Degraded {
          has_dual = true
        }
      }
      assert_true(has_dual)
      // message.reasoning 胜出，content Thinking part 被跳过（不重复输出）
      let s = cr.value()
      assert_true(s.contains("{\"text\":\"msg reasoning\",\"thought\":true}"))
      assert_false(s.contains("block reasoning"))
    }
    Err(_) => assert_true(false)
  }
}

///|
test "encode - file maps to fileData part" {
  let req = @lux.LucentRequest::new(
    "gemini-2.0-flash",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [
          @lux.LucentContent::file("application/pdf", Url("gs://bucket/a.pdf")),
        ]),
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
  match lux_request_to_gemini(req) {
    Ok(cr) => {
      assert_true(cr.value().contains("\"fileData\""))
      assert_true(cr.value().contains("gs://bucket/a.pdf"))
    }
    Err(e) => fail("encode: \{e}")
  }
}

///|
/// === 官方协议回归（v1beta discovery）===
///
/// 以下用例锁定 8 处协议偏差的修复，防止回归：
///   #1 Content.role 只允许 user/model（工具轮次/系统轮次不得输出 tool/system）
///   #2 systemInstruction 不带 role
///   #3 SpecificTool → mode=ANY + allowedFunctionNames（不得静默丢弃）
///   #4 媒体载体 inlineData / fileData（编码侧）
///   #5 响应字段 responseId / modelVersion（无顶层 model）
///   #7 流式 parts[].text 为增量语义（不得当累计/重发）
///   #8 流式工具参数累积后一次性输出（不得丢失成 args:{}）
///   #C capability parallel_tool_calls 修正为 Full

///|
/// #1 工具结果轮次：官方 Content.role 只能是 user/model，不得输出 "tool"。
test "encode - tool result uses role user and keeps call pairing" {
  let call = @lux.LucentToolUse::new(
    "call_1",
    "get_weather",
    "{\"city\":\"Beijing\"}",
    None,
  )
  let result = @lux.LucentToolResult::ok("call_1", [
    @lux.LucentContent::text("25C"),
  ])
  let req = @lux.LucentRequest::new(
    "gemini-2.0-flash",
    None,
    [
      @lux.LucentConversationItem::tool_call(call),
      @lux.LucentConversationItem::tool_result(result),
    ],
    None,
    None,
    @lux.LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
  match lux_request_to_gemini(req) {
    Ok(cr) => {
      let s = cr.value()
      // 工具结果轮次必须是 user；不存在 "tool" 角色
      assert_true(s.contains("\"role\":\"user\""))
      assert_false(s.contains("\"role\":\"tool\""))
      // functionCall 携带可选 id，functionResponse 回填函数名（非调用 ID）
      assert_true(
        s.contains(
          "\"functionCall\":{\"name\":\"get_weather\",\"id\":\"call_1\"",
        ),
      )
      assert_true(
        s.contains(
          "\"functionResponse\":{\"name\":\"get_weather\",\"id\":\"call_1\"",
        ),
      )
    }
    Err(e) => fail("encode: \{e}")
  }
}

///|
/// #2 systemInstruction 是 Content，官方示例不带 role。
test "encode - systemInstruction emits parts without role" {
  let req = @lux.LucentRequest::new(
    "gemini-2.0-flash",
    Some([@lux.LucentContent::text("You are helpful")]),
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [@lux.LucentContent::text("hi")]),
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
  match lux_request_to_gemini(req) {
    Ok(cr) => {
      let s = cr.value()
      assert_true(
        s.contains(
          "\"systemInstruction\":{\"parts\":[{\"text\":\"You are helpful\"}]}",
        ),
      )
      assert_false(s.contains("\"role\":\"system\""))
    }
    Err(e) => fail("encode: \{e}")
  }
}

///|
/// #1 系统角色消息落在 contents 时无官方载体：降级为 user 且显式 Degraded。
test "encode - system role message degrades to user with diagnostic" {
  let req = @lux.LucentRequest::new(
    "gemini-2.0-flash",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(System, [@lux.LucentContent::text("sys")]),
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
  match lux_request_to_gemini(req) {
    Ok(cr) => {
      assert_false(cr.value().contains("\"role\":\"system\""))
      let mut has_degraded = false
      for d in cr.diagnostics() {
        if d.field == "contents.role" && d.status == Degraded {
          has_degraded = true
        }
      }
      assert_true(has_degraded)
    }
    Err(e) => fail("encode: \{e}")
  }
}

///|
/// #3 限定单一函数：官方无 "specific tool" 模式，用 mode=ANY + allowedFunctionNames。
test "encode - specific tool choice maps to allowedFunctionNames" {
  let req = @lux.LucentRequest::new(
    "gemini-2.0-flash",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [@lux.LucentContent::text("hi")]),
      ),
    ],
    Some([@lux.LucentTool::new("get_weather", None, "{}", None, Function)]),
    Some(SpecificTool("get_weather")),
    @lux.LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
  match lux_request_to_gemini(req) {
    Ok(cr) => {
      let s = cr.value()
      assert_true(s.contains("\"mode\":\"ANY\""))
      assert_true(s.contains("\"allowedFunctionNames\":[\"get_weather\"]"))
    }
    Err(e) => fail("encode: \{e}")
  }
}

///|
/// #4 内联媒体：官方载体是 inlineData{mimeType,data}，不得走 fileData。
test "encode - inline image maps to inlineData not fileData" {
  let req = @lux.LucentRequest::new(
    "gemini-2.0-flash",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [
          @lux.LucentContent::image("image/png", Inline("AA")),
        ]),
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
  match lux_request_to_gemini(req) {
    Ok(cr) => {
      let s = cr.value()
      assert_true(
        s.contains(
          "\"inlineData\":{\"mimeType\":\"image/png\",\"data\":\"AA\"}",
        ),
      )
      assert_false(s.contains("\"fileData\""))
    }
    Err(e) => fail("encode: \{e}")
  }
}

///|
/// #5 GenerateContentResponse 用 responseId / modelVersion，无顶层 model 字段。
test "response - responseId and modelVersion round-trip without model field" {
  let json = "{\"responseId\":\"r-123\",\"modelVersion\":\"gemini-2.5-pro\",\"candidates\":[{\"index\":0,\"content\":{\"role\":\"model\",\"parts\":[{\"text\":\"hi\"}]},\"finishReason\":\"STOP\"}]}"
  match gemini_to_lux_response(json) {
    Ok(cr) => {
      assert_eq(cr.value().id, "r-123")
      assert_eq(cr.value().model, "gemini-2.5-pro")
      match lux_response_to_gemini(cr.value()) {
        Ok(cr2) => {
          let s = cr2.value()
          assert_true(s.contains("\"responseId\":\"r-123\""))
          assert_true(s.contains("\"modelVersion\":\"gemini-2.5-pro\""))
          // 官方 schema 无顶层 model：不得再输出
          assert_false(s.contains("\"model\":"))
        }
        Err(e) => fail("encode: \{e}")
      }
    }
    Err(e) => fail("decode: \{e}")
  }
}

///|
/// #7 官方流式 chunk 的 parts[].text 是增量（"the new text, not the running
/// total. Concatenate; do not replace"）：必须逐帧原样透传，不得当成累计文本，
/// 也不存在需要 BlockDiscard 的整帧覆盖语义。
test "stream decode - incremental text is passed through verbatim" {
  let sse = "data: {\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"text\":\"Hel\"}]}}]}\ndata: {\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"text\":\"lo\"}]}}]}\ndata: {\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"text\":\" world\"}]},\"finishReason\":\"STOP\"}]}\n"
  match gemini_sse_to_events(sse) {
    Ok(cr) => {
      let deltas : Array[String] = []
      let mut has_discard = false
      for ev in cr.value() {
        match ev {
          BlockDelta(_, TextDelta(s)) => deltas.push(s)
          BlockDiscard(_) => has_discard = true
          _ => ()
        }
      }
      assert_eq(deltas.length(), 3)
      assert_eq(deltas[0], "Hel")
      assert_eq(deltas[1], "lo")
      assert_eq(deltas[2], " world")
      assert_false(has_discard)
    }
    Err(e) => fail("decode: \{e}")
  }
}

///|
/// #7 补充：CRLF 分隔的多帧流必须逐帧解析（String::replace 只替换首次出现，
/// 旧实现会残留 CRLF 把第 2 帧起的 JSON 并成一块导致丢帧）。
test "stream decode - CRLF separated frames each parsed" {
  let sse = "data: {\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"text\":\"a\"}]}}]}\r\n\r\ndata: {\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"text\":\"b\"}]}}]}\r\n\r\ndata: {\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"text\":\"c\"}]},\"finishReason\":\"STOP\"}]}\r\n\r\n"
  match gemini_sse_to_events(sse) {
    Ok(cr) => {
      let deltas : Array[String] = []
      for ev in cr.value() {
        match ev {
          BlockDelta(_, TextDelta(s)) => deltas.push(s)
          _ => ()
        }
      }
      assert_eq(deltas.length(), 3)
      assert_eq(deltas[0], "a")
      assert_eq(deltas[1], "b")
      assert_eq(deltas[2], "c")
    }
    Err(e) => fail("decode: \{e}")
  }
}

///|
/// #8 官方 functionCall 是完整块：参数增量必须累积到块结束时一次性输出，
/// 否则会把 args 丢成 {}（旧实现把 functionCall 发在 BlockStart 上）。
test "stream encode - accumulated tool arguments emitted once as complete JSON" {
  let events : Array[@lux.LucentStreamEvent] = [
    BlockStart(0, @lux.LucentBlockType::tool_call("call_1", "get_weather")),
    BlockDelta(0, @lux.LucentBlockDelta::tool_arguments_delta("{\"city\":")),
    BlockDelta(0, @lux.LucentBlockDelta::tool_arguments_delta("\"Beijing\"}")),
    BlockEnd(0),
    Finish(Stop, None),
  ]
  match lux_events_to_gemini_sse(events) {
    Ok(cr) => {
      let s = cr.value()
      assert_true(s.contains("\"args\":{\"city\":\"Beijing\"}"))
      assert_false(s.contains("\"args\":{}"))
      // 无 [DONE] 终止符
      assert_false(s.contains("[DONE]"))
    }
    Err(e) => fail("encode: \{e}")
  }
}

///|
/// #C Gemini 官方支持单条 model 消息内多个 functionCall（并行工具调用），
/// 能力声明须为 Full，与适配器实际解码/编码行为一致（消除声明漂移）。
test "capability - parallel tool calls declared full" {
  let caps = capability().capabilities
  assert_eq(caps.parallel_tool_calls, Full)
  assert_eq(caps.tool_calling, Full)
}

///|
/// === 6. 编码白盒：request_encode 未覆盖分支 ===

///|
/// tool_response_name 的 None 分支：ToolResult 的 tool_use_id 无配对 ToolCall，
/// 无法回查函数名 → Degraded，且 name 回退为 tool_use_id。
test "encode - tool result without matching tool call degrades name" {
  let result = @lux.LucentToolResult::ok("orphan_1", [
    @lux.LucentContent::text("25C"),
  ])
  let req = @lux.LucentRequest::new(
    "gemini-2.0-flash",
    None,
    [@lux.LucentConversationItem::tool_result(result)],
    None,
    None,
    @lux.LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
  match lux_request_to_gemini(req) {
    Ok(cr) => {
      let s = cr.value()
      let mut has_degraded = false
      let mut detail_text = ""
      for d in cr.diagnostics() {
        if d.field == "content.tool_result.name" && d.status == Degraded {
          has_degraded = true
          detail_text = match d.detail {
            Some(m) => m
            None => ""
          }
        }
      }
      assert_true(has_degraded)
      assert_true(detail_text.contains("without matching ToolCall"))
      // name 回退为 tool_use_id，functionResponse 两端都填 orphan_1
      assert_true(
        s.contains(
          "\"functionResponse\":{\"name\":\"orphan_1\",\"id\":\"orphan_1\"",
        ),
      )
    }
    Err(e) => fail("encode: \{e}")
  }
}

///|
/// function_call_part 空 id 分支：tu.id == "" → id_part 为空，
/// functionCall 不带 "id" 键。
test "encode - tool use with empty id omits id field" {
  let call = @lux.LucentToolUse::new("", "no_id_tool", "{\"x\":1}", None)
  let req = @lux.LucentRequest::new(
    "gemini-2.0-flash",
    None,
    [@lux.LucentConversationItem::tool_call(call)],
    None,
    None,
    @lux.LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
  match lux_request_to_gemini(req) {
    Ok(cr) => {
      let s = cr.value()
      assert_true(!s.contains("\"id\""))
      assert_true(
        s.contains(
          "\"functionCall\":{\"name\":\"no_id_tool\",\"args\":{\"x\":1}}",
        ),
      )
    }
    Err(e) => fail("encode: \{e}")
  }
}

///|
/// function_response_part 空 id 分支：tool_use_id == "" → 不输出 "id" 键
/// （name 回退也为空，同时再次覆盖 tool_response_name 的 None 分支）。
test "encode - function response with empty tool id omits id key" {
  let result = @lux.LucentToolResult::ok("", [@lux.LucentContent::text("25C")])
  let req = @lux.LucentRequest::new(
    "gemini-2.0-flash",
    None,
    [@lux.LucentConversationItem::tool_result(result)],
    None,
    None,
    @lux.LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
  match lux_request_to_gemini(req) {
    Ok(cr) => {
      let s = cr.value()
      assert_true(!s.contains("\"id\""))
      assert_true(s.contains("\"functionResponse\""))
    }
    Err(e) => fail("encode: \{e}")
  }
}

///|
/// generationConfig 分支：temperature / top_p / top_k / max_output_tokens /
/// candidate_count / stopSequences / structured_output=JsonObject。
test "encode - generationConfig emits sampling, stop, and structured output" {
  let opts = @lux.LucentOptions::new(
    Some(0.5),
    Some(0.9),
    Some(40),
    Some(1024),
    Some(["STOP", "END"]),
    false,
    Some(2),
    Some(JsonObject),
    None,
    None,
  )
  let req = @lux.LucentRequest::new(
    "gemini-2.0-flash",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [@lux.LucentContent::text("hi")]),
      ),
    ],
    None,
    None,
    opts,
    None,
    None,
    None,
    None,
  )
  match lux_request_to_gemini(req) {
    Ok(cr) => {
      let s = cr.value()
      assert_true(s.contains("\"temperature\":"))
      assert_true(s.contains("\"topP\":"))
      assert_true(s.contains("\"topK\":40"))
      assert_true(s.contains("\"maxOutputTokens\":1024"))
      assert_true(s.contains("\"candidateCount\":2"))
      assert_true(s.contains("\"stopSequences\":[\"STOP\",\"END\"]"))
      assert_true(s.contains("\"responseMimeType\":\"application/json\""))
    }
    Err(e) => fail("encode: \{e}")
  }
}

///|
/// toolConfig 分支：Required → mode=ANY；None → mode=NONE。
test "encode - tool choice required and none map to calling modes" {
  let cases : Array[(@lux.LucentToolChoice, String)] = [
    (Required, "ANY"),
    (None, "NONE"),
  ]
  for c in cases {
    let choice = c.0
    let expect_mode = c.1
    let req = @lux.LucentRequest::new(
      "gemini-2.0-flash",
      None,
      [
        @lux.LucentConversationItem::message(
          @lux.LucentMessage::new(User, [@lux.LucentContent::text("hi")]),
        ),
      ],
      None,
      Some(choice),
      @lux.LucentOptions::default(),
      None,
      None,
      None,
      None,
    )
    match lux_request_to_gemini(req) {
      Ok(cr) =>
        assert_true(
          cr
          .value()
          .contains(
            "\"functionCallingConfig\":{\"mode\":\"" + expect_mode + "\"}",
          ),
        )
      Err(e) => fail("encode: \{e}")
    }
  }
}

///|
/// Thinking 内容块签名分支：content 内 Thinking(th) 且 th.signature 有值 →
/// 输出 thoughtSignature。
test "encode - thinking content block emits thoughtSignature" {
  let req = @lux.LucentRequest::new(
    "gemini-2.0-flash",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(Assistant, [
          @lux.LucentContent::thinking("chain", Some("sig-inline")),
        ]),
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
  match lux_request_to_gemini(req) {
    Ok(cr) => {
      let s = cr.value()
      assert_true(
        s.contains(
          "{\"text\":\"chain\",\"thought\":true,\"thoughtSignature\":\"sig-inline\"}",
        ),
      )
    }
    Err(e) => fail("encode: \{e}")
  }
}

///|
/// Reasoning 独立轮次签名分支：Reasoning(th) 且 th.signature 为 None →
/// thought:true part 但不带 thoughtSignature。
test "encode - reasoning item omits thoughtSignature when unset" {
  let req = @lux.LucentRequest::new(
    "gemini-2.0-flash",
    None,
    [
      @lux.LucentConversationItem::reasoning(
        @lux.LucentThinking::visible("reasoning text", None),
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
  match lux_request_to_gemini(req) {
    Ok(cr) => {
      let s = cr.value()
      assert_true(s.contains("{\"text\":\"reasoning text\",\"thought\":true}"))
      assert_true(!s.contains("thoughtSignature"))
    }
    Err(e) => fail("encode: \{e}")
  }
}

///|
/// thinkingConfig 分支：reasoning.enabled 且无 effort、无 budget →
/// 仅输出 includeThoughts。
test "encode - bare thinkingConfig when reasoning has no effort or budget" {
  let req = @lux.LucentRequest::new(
    "gemini-2.0-flash",
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
    Some(@lux.LucentReasoningConfig::enabled(None)),
    None,
    None,
  )
  match lux_request_to_gemini(req) {
    Ok(cr) => {
      let s = cr.value()
      assert_true(s.contains("\"thinkingConfig\":{\"includeThoughts\":true}"))
    }
    Err(e) => fail("encode: \{e}")
  }
}

///|
/// Video 内容块 + Refusal 内容块分支：video → inlineData part；
/// refusal → Unsupported 诊断。
test "encode - video and refusal content blocks" {
  let req = @lux.LucentRequest::new(
    "gemini-2.0-flash",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(Assistant, [
          @lux.LucentContent::video("video/mp4", Inline("AAAA")),
          @lux.LucentContent::refusal("I cannot"),
        ]),
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
  match lux_request_to_gemini(req) {
    Ok(cr) => {
      let s = cr.value()
      assert_true(
        s.contains(
          "\"inlineData\":{\"mimeType\":\"video/mp4\",\"data\":\"AAAA\"}",
        ),
      )
      let mut has_unsupported = false
      for d in cr.diagnostics() {
        if d.field == "content.refusal" && d.status == Unsupported {
          has_unsupported = true
        }
      }
      assert_true(has_unsupported)
    }
    Err(e) => fail("encode: \{e}")
  }
}

///|
/// systemInstruction 非文本内容分支：指令内容非 Text 时跳过，无文本则不输出 systemInstruction。
test "encode - systemInstruction skips non-text content" {
  let req = @lux.LucentRequest::new(
    "gemini-2.0-flash",
    Some([@lux.LucentContent::image("image/png", Inline("AA"))]),
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [@lux.LucentContent::text("hi")]),
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
  match lux_request_to_gemini(req) {
    Ok(cr) => assert_true(!cr.value().contains("systemInstruction"))
    Err(e) => fail("encode: \{e}")
  }
}

///|
/// === 7. 编码白盒：stream_encode 未覆盖分支 ===

///|
/// normalize_tool_args 三条分支（经 lux_events_to_gemini_sse 触发）：
///   空片段 → {}（无诊断）；解析成功但非 object → Degraded "not a JSON object"；
///   解析失败 → Degraded "not valid JSON"。均回退 args:{}。
test "encode - stream tool arguments normalization branches" {
  let cases : Array[(String, String)] = [
    ("", ""),
    ("5", "not a JSON object"),
    ("[]", "not a JSON object"),
    ("\"str\"", "not a JSON object"),
    ("{oops", "not valid JSON"),
    ("abc", "not valid JSON"),
  ]
  for c in cases {
    let payload = c.0
    let expect_sub = c.1
    let events : Array[@lux.LucentStreamEvent] = [
      BlockStart(0, @lux.LucentBlockType::tool_call("call_1", "search")),
      BlockDelta(0, @lux.LucentBlockDelta::tool_arguments_delta(payload)),
      BlockEnd(0),
      Finish(Stop, None),
    ]
    match lux_events_to_gemini_sse(events) {
      Ok(cr) => {
        let s = cr.value()
        assert_true(s.contains("\"args\":{}"))
        let mut count = 0
        let mut detail_text = ""
        for d in cr.diagnostics() {
          if d.field == "stream.tool_arguments" {
            count = count + 1
            detail_text = match d.detail {
              Some(m) => m
              None => ""
            }
          }
        }
        if expect_sub == "" {
          assert_eq(count, 0)
        } else {
          assert_true(count > 0)
          assert_true(detail_text.contains(expect_sub))
        }
      }
      Err(e) => fail("encode: \{e}")
    }
  }
}

///|
/// ThinkingDelta / SignatureDelta 增量分支：thinking → thought:true part；
/// signature → 累积后带 thoughtSignature。
test "encode - stream thinking and signature deltas pass through" {
  let events : Array[@lux.LucentStreamEvent] = [
    BlockDelta(0, @lux.LucentBlockDelta::thinking_delta("reasoning")),
    BlockDelta(0, @lux.LucentBlockDelta::signature_delta("sig-tok")),
    Finish(Stop, None),
  ]
  match lux_events_to_gemini_sse(events) {
    Ok(cr) => {
      let s = cr.value()
      assert_true(s.contains("{\"text\":\"reasoning\",\"thought\":true}"))
      assert_true(s.contains("\"thoughtSignature\":\"sig-tok\""))
    }
    Err(e) => fail("encode: \{e}")
  }
}

///|
/// ToolArgumentsDelta 无前置 BlockStart 分支：pending 未开 → Degraded
/// "tool arguments delta without a preceding tool_call block start"。
test "encode - stream tool arguments delta without block start degrades" {
  let events : Array[@lux.LucentStreamEvent] = [
    BlockDelta(0, @lux.LucentBlockDelta::tool_arguments_delta("{\"x\":1}")),
    Finish(Stop, None),
  ]
  match lux_events_to_gemini_sse(events) {
    Ok(cr) => {
      let mut has_degraded = false
      let mut detail_text = ""
      for d in cr.diagnostics() {
        if d.field == "stream.tool_arguments" {
          has_degraded = true
          detail_text = match d.detail {
            Some(m) => m
            None => ""
          }
        }
      }
      assert_true(has_degraded)
      assert_true(detail_text.contains("without a preceding"))
    }
    Err(e) => fail("encode: \{e}")
  }
}

///|
/// BlockStart 补发分支：前一工具块未 BlockEnd 又来一个 BlockStart →
/// 先补发前一块（不含 id），再开新块。
test "encode - stream block start flushes previous unclosed tool" {
  let events : Array[@lux.LucentStreamEvent] = [
    BlockStart(0, @lux.LucentBlockType::tool_call("id_a", "fn_a")),
    BlockDelta(0, @lux.LucentBlockDelta::tool_arguments_delta("{\"a\":1}")),
    BlockStart(1, @lux.LucentBlockType::tool_call("id_b", "fn_b")),
    BlockDelta(1, @lux.LucentBlockDelta::tool_arguments_delta("{\"b\":2}")),
    BlockEnd(1),
    Finish(Stop, None),
  ]
  match lux_events_to_gemini_sse(events) {
    Ok(cr) => {
      let s = cr.value()
      // 补发 block 0：无 id，args 为累积值
      assert_true(
        s.contains("\"functionCall\":{\"name\":\"fn_a\",\"args\":{\"a\":1}}"),
      )
      // block 1 正常结束：带 id 与 args
      assert_true(
        s.contains(
          "\"functionCall\":{\"name\":\"fn_b\",\"id\":\"id_b\",\"args\":{\"b\":2}}",
        ),
      )
    }
    Err(e) => fail("encode: \{e}")
  }
}

///|
/// BlockEnd 空 id 分支：pending_tool_id == "" → 输出 functionCall 不带 "id" 键。
test "encode - stream BlockEnd with empty tool id omits id key" {
  let events : Array[@lux.LucentStreamEvent] = [
    BlockStart(0, @lux.LucentBlockType::tool_call("", "search")),
    BlockDelta(0, @lux.LucentBlockDelta::tool_arguments_delta("{\"q\":1}")),
    BlockEnd(0),
    Finish(Stop, None),
  ]
  match lux_events_to_gemini_sse(events) {
    Ok(cr) => {
      let s = cr.value()
      assert_true(!s.contains("\"id\""))
      assert_true(
        s.contains("\"functionCall\":{\"name\":\"search\",\"args\":{\"q\":1}}"),
      )
    }
    Err(e) => fail("encode: \{e}")
  }
}

///|
/// RefusalDelta / NativeDelta / BlockDiscard 分支：refusal、native → Unsupported；
/// block_discard → Degraded（含 index N）。
test "encode - stream refusal native and block discard diagnostics" {
  let events : Array[@lux.LucentStreamEvent] = [
    BlockDelta(0, @lux.LucentBlockDelta::refusal_delta("cannot")),
    BlockDelta(
      1,
      @lux.LucentBlockDelta::native_delta("vendor", Json::string("raw")),
    ),
    BlockDiscard(2),
    Finish(Stop, None),
  ]
  match lux_events_to_gemini_sse(events) {
    Ok(cr) => {
      let mut has_refusal = false
      let mut has_native = false
      let mut has_discard = false
      let mut discard_detail = ""
      for d in cr.diagnostics() {
        if d.field == "stream.refusal" && d.status == Unsupported {
          has_refusal = true
        }
        if d.field == "stream.native" && d.status == Unsupported {
          has_native = true
        }
        if d.field == "stream.block_discard" && d.status == Degraded {
          has_discard = true
          discard_detail = match d.detail {
            Some(m) => m
            None => ""
          }
        }
      }
      assert_true(has_refusal)
      assert_true(has_native)
      assert_true(has_discard)
      assert_true(discard_detail.contains("index 2"))
    }
    Err(e) => fail("encode: \{e}")
  }
}

///|
/// Finish 补发 + finish_reason 分支：未 BlockEnd 的工具块在 Finish 时补发
/// （空 / 非空 id 两条子分支），Length → MAX_TOKENS。
test "encode - stream finish flushes unclosed tool and maps length reason" {
  let ids : Array[String] = ["", "call_flush"]
  for id in ids {
    let events : Array[@lux.LucentStreamEvent] = [
      BlockStart(0, @lux.LucentBlockType::tool_call(id, "search")),
      BlockDelta(0, @lux.LucentBlockDelta::tool_arguments_delta("{\"q\":1}")),
      Finish(Length, None),
    ]
    match lux_events_to_gemini_sse(events) {
      Ok(cr) => {
        let s = cr.value()
        assert_true(s.contains("\"functionCall\":{\"name\":\"search\""))
        assert_true(s.contains("\"args\":{\"q\":1}"))
        assert_true(s.contains("\"finishReason\":\"MAX_TOKENS\""))
        if id == "" {
          assert_true(!s.contains("\"id\""))
        } else {
          assert_true(s.contains("\"id\":\"call_flush\""))
        }
      }
      Err(e) => fail("encode: \{e}")
    }
  }
}

///|
/// Usage 分支：reasoning_tokens / cached_tokens 有值 → thoughtsTokenCount /
/// cachedContentTokenCount。
test "encode - stream usage emits reasoning and cached token counts" {
  let events : Array[@lux.LucentStreamEvent] = [
    Usage(@lux.LucentUsage::full(10, 5, 15, Some(30), Some(40), None)),
    Finish(Stop, None),
  ]
  match lux_events_to_gemini_sse(events) {
    Ok(cr) => {
      let s = cr.value()
      assert_true(s.contains("\"thoughtsTokenCount\":30"))
      assert_true(s.contains("\"cachedContentTokenCount\":40"))
    }
    Err(e) => fail("encode: \{e}")
  }
}

///|
/// 流末兜底分支：无 BlockEnd/Finish 的未闭合工具块在流结束时补发
/// （空 / 非空 id 两条子分支）。
test "encode - stream flushes unclosed tool at end without finish" {
  let ids : Array[String] = ["", "call_end"]
  for id in ids {
    let events : Array[@lux.LucentStreamEvent] = [
      BlockStart(0, @lux.LucentBlockType::tool_call(id, "search")),
      BlockDelta(0, @lux.LucentBlockDelta::tool_arguments_delta("{\"q\":1}")),
    ]
    match lux_events_to_gemini_sse(events) {
      Ok(cr) => {
        let s = cr.value()
        assert_true(s.contains("\"functionCall\":{\"name\":\"search\""))
        assert_true(s.contains("\"args\":{\"q\":1}"))
        if id == "" {
          assert_true(!s.contains("\"id\""))
        } else {
          assert_true(s.contains("\"id\":\"call_end\""))
        }
      }
      Err(e) => fail("encode: \{e}")
    }
  }
}

///|
/// structured_output=JsonSchema 分支：responseMimeType + responseSchema。
test "encode - structured output json schema emits responseSchema" {
  let opts = @lux.LucentOptions::new(
    None,
    None,
    None,
    None,
    None,
    false,
    None,
    Some(JsonSchema("{\"type\":\"object\"}")),
    None,
    None,
  )
  let req = @lux.LucentRequest::new(
    "gemini-2.0-flash",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [@lux.LucentContent::text("hi")]),
      ),
    ],
    None,
    None,
    opts,
    None,
    None,
    None,
    None,
  )
  match lux_request_to_gemini(req) {
    Ok(cr) => {
      let s = cr.value()
      assert_true(s.contains("\"responseMimeType\":\"application/json\""))
      assert_true(s.contains("\"responseSchema\":{\"type\":\"object\"}"))
    }
    Err(e) => fail("encode: \{e}")
  }
}

///|
/// finish_reason 映射全覆盖：每个显式 LucentFinishReason 变体逐一锁定映射字符串。
///
/// `Native` 是**透传**而非收敛：流式旧实现的兜底 `_ => "STOP"` 会把厂商自定义
/// 值（如 gemini 自己解出的 LANGUAGE / BLOCKLIST / SPII）静默吞成 STOP，
/// 与同协议的非流式路径（原样透传）不一致 —— 那正是数据丢失。现已统一为
/// 共用 `@meta.gemini_finish_reason_string`，此处锁定透传行为。
test "encode - stream finish reason mapping covers all variants" {
  let cases : Array[(@lux.LucentFinishReason, String)] = [
    (Stop, "STOP"),
    (Length, "MAX_TOKENS"),
    (ToolCalls, "STOP"),
    (Safety, "SAFETY"),
    (Recitation, "RECITATION"),
    (MalformedToolCall, "MALFORMED_FUNCTION_CALL"),
    (Error, "OTHER"),
    // ContentFilter → SAFETY（内容拦截在 Gemini 的语义载体）
    (ContentFilter, "SAFETY"),
    // Native 合法值透传；非 Gemini 词汇表的值收敛到 OTHER
    (Native("BLOCKLIST"), "BLOCKLIST"),
    (Native("nft"), "OTHER"),
  ]
  for c in cases {
    let reason = c.0
    let expect = c.1
    let events : Array[@lux.LucentStreamEvent] = [Finish(reason, None)]
    match lux_events_to_gemini_sse(events) {
      Ok(cr) =>
        assert_true(cr.value().contains("\"finishReason\":\"" + expect + "\""))
      Err(e) => fail("encode: \{e}")
    }
  }
}

///|
/// functionCall 的 args 必须是合法 JSON 对象：非法 arguments_json 直接内嵌会
/// 产出非法请求体（Gemini 整请求 400）。修复后：回退 {} + Invalid 诊断。
test "encode - invalid tool arguments fall back to empty object with Invalid diagnostic" {
  let req = @lux.LucentRequest::from_messages(
    "gemini-2.0-flash",
    None,
    [
      @lux.LucentMessage::new(Assistant, [
        @lux.LucentContent::tool_use("c1", "f1", "oops-not-json", None),
      ]),
    ],
    None,
    None,
    @lux.LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
  match lux_request_to_gemini(req) {
    Ok(cr) => {
      // 必须打 Invalid 诊断
      let mut has_invalid = false
      for d in cr.diagnostics() {
        if d.status == Invalid && d.field == "content.tool_use.args" {
          has_invalid = true
        }
      }
      assert_true(has_invalid)
      // 不得把非法 JSON 内嵌进请求体（否则上游 400）
      assert_false(cr.value().contains("oops-not-json"))
      assert_true(cr.value().contains("\"args\":{}"))
      // 产出必须是合法 JSON
      match @internal.parse_protocol_json(cr.value()) {
        Ok(_) => ()
        Err(e) => fail("gemini request body is not valid JSON: " + e)
      }
    }
    Err(e) => fail("encode: \{e}")
  }
}

///|
/// 非对象但合法的 JSON（如数组/字符串）同样不是 Gemini 能接受的 args 形态
test "encode - non-object tool arguments fall back with Invalid diagnostic" {
  let req = @lux.LucentRequest::from_messages(
    "gemini-2.0-flash",
    None,
    [
      @lux.LucentMessage::new(Assistant, [
        @lux.LucentContent::tool_use("c1", "f1", "[1,2]", None),
      ]),
    ],
    None,
    None,
    @lux.LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
  match lux_request_to_gemini(req) {
    Ok(cr) => {
      let mut has_invalid = false
      for d in cr.diagnostics() {
        if d.status == Invalid && d.field == "content.tool_use.args" {
          has_invalid = true
        }
      }
      assert_true(has_invalid)
      assert_true(cr.value().contains("\"args\":{}"))
    }
    Err(e) => fail("encode: \{e}")
  }
}
