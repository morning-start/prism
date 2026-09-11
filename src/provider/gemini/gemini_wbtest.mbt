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
    Finish(Stop),
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
