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
