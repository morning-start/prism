///|
/// Google Gemini 适配器白盒测试

///|
/// === 1. 请求解码 ===

///|
test "gemini_to_lux_request - simple user message" {
  let json = "{\"model\":\"gemini-2.5-pro\",\"contents\":[{\"role\":\"user\",\"parts\":[{\"text\":\"Hello\"}]}]}"
  match gemini_to_lux_request(json) {
    Ok(req) => {
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
    Ok(req) =>
      match req.instructions {
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
    Ok(req) =>
      match req.conversation[0] {
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
    Ok(req) => {
      assert_eq(req.conversation.length(), 2)
      match req.conversation[1] {
        ToolResult(tr) => assert_eq(tr.tool_use_id, "get_weather_result")
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
    Ok(req) => {
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
    [@lux.LucentMessage::new(@lux.User, [@lux.LucentContent::text("hi")])],
    None,
    None,
    @lux.LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
  match lux_request_to_gemini(req) {
    Ok(s) => {
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
    Ok(resp) => {
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
    Ok(resp) => assert_eq(resp.choices.length(), 2)
    Err(_) => assert_true(false)
  }
}

///|
/// === 4. 响应编码 ===

///|
test "lux_response_to_gemini - text response" {
  let msg = @lux.LucentMessage::new(@lux.Assistant, [
    @lux.LucentContent::text("Hello"),
  ])
  let choice = @lux.LucentChoice::new(0, msg, @lux.Stop, None)
  let resp = @lux.LucentResponse::new(
    "",
    "gemini-2.5-pro",
    None,
    [choice],
    Some(@lux.LucentUsage::new(10, 5, 15)),
    None,
  )
  match lux_response_to_gemini(resp) {
    Ok(s) => {
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
    Ok(events) => assert_true(events.length() >= 3)
    Err(_) => assert_true(false)
  }
}
