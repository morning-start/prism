///|
/// openai_vllm 子协议契约测试

///|
/// 入站：vLLM message.reasoning → LucentMessage.reasoning
test "vllm_to_lux_response - message.reasoning captured" {
  let json = "{\"id\":\"c-1\",\"model\":\"qwen\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"Final answer\",\"reasoning\":\"step by step\"},\"finish_reason\":\"stop\"}]}"
  match vllm_to_lux_response(json) {
    Ok(cr) =>
      match cr.value().choices[0].message.reasoning {
        Some(r) => assert_eq(r.text, "step by step")
        None => assert_true(false)
      }
    Err(_) => assert_true(false)
  }
}

///|
/// 入站：DeepSeek/Fireworks reasoning_content 同样捕获
test "vllm_to_lux_response - reasoning_content captured" {
  let json = "{\"id\":\"c-1\",\"model\":\"deepseek\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"Final\",\"reasoning_content\":\"chain of thought\"},\"finish_reason\":\"stop\"}]}"
  match vllm_to_lux_response(json) {
    Ok(cr) =>
      match cr.value().choices[0].message.reasoning {
        Some(r) => assert_eq(r.text, "chain of thought")
        None => assert_true(false)
      }
    Err(_) => assert_true(false)
  }
}

///|
/// 入站：无 reasoning 字段时 message.reasoning 为 None
test "vllm_to_lux_response - no reasoning field yields None" {
  let json = "{\"id\":\"c-1\",\"model\":\"qwen\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"Final\"},\"finish_reason\":\"stop\"}]}"
  match vllm_to_lux_response(json) {
    Ok(cr) => assert_eq(cr.value().choices[0].message.reasoning, None)
    Err(_) => assert_true(false)
  }
}

///|
/// 出站：LucentMessage.reasoning → message.reasoning（默认 vLLM 字段名）
test "lux_response_to_vllm - reasoning emitted as message.reasoning" {
  let th = @lux.LucentThinking::visible("thought", None)
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
  match lux_response_to_vllm(resp) {
    Ok(cr) => {
      let jv = @json.parse(cr.value())
      match @internal.obj_get(jv, "choices") {
        Some(Array(cs)) =>
          match @internal.obj_get(cs[0], "message") {
            Some(m) => {
              assert_eq(@internal.field_str(m, "reasoning"), Some("thought"))
              assert_eq(@internal.field_str(m, "content"), Some("answer"))
            }
            None => assert_true(false)
          }
        _ => assert_true(false)
      }
    }
    Err(_) => assert_true(false)
  }
}

///|
/// 出站：provider_payload.reasoning_field 声明切换为 reasoning_content
test "lux_response_to_vllm - reasoning_field switches to reasoning_content" {
  let th = @lux.LucentThinking::visible("thought", None)
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
    Some({ "reasoning_field": @json.parse("\"reasoning_content\"") }),
  )
  match lux_response_to_vllm(resp) {
    Ok(cr) => {
      let jv = @json.parse(cr.value())
      match @internal.obj_get(jv, "choices") {
        Some(Array(cs)) =>
          match @internal.obj_get(cs[0], "message") {
            Some(m) =>
              assert_eq(
                @internal.field_str(m, "reasoning_content"),
                Some("thought"),
              )
            None => assert_true(false)
          }
        _ => assert_true(false)
      }
    }
    Err(_) => assert_true(false)
  }
}

///|
/// 出站：无 reasoning 时 message 不含 reasoning 字段
test "lux_response_to_vllm - no reasoning yields plain message" {
  let msg = @lux.LucentMessage::new(Assistant, [
    @lux.LucentContent::text("answer"),
  ])
  let resp = @lux.LucentResponse::new(
    "c-1",
    "model",
    None,
    [@lux.LucentChoice::new(0, msg, Stop, None)],
    None,
    None,
  )
  match lux_response_to_vllm(resp) {
    Ok(cr) => {
      let jv = @json.parse(cr.value())
      match @internal.obj_get(jv, "choices") {
        Some(Array(cs)) =>
          match @internal.obj_get(cs[0], "message") {
            Some(m) => {
              assert_eq(@internal.field_str(m, "reasoning"), None)
              assert_eq(@internal.field_str(m, "content"), Some("answer"))
            }
            None => assert_true(false)
          }
        _ => assert_true(false)
      }
    }
    Err(_) => assert_true(false)
  }
}

///|
/// round-trip：vLLM 入站 → IR → vLLM 出站，reasoning 不丢
test "vllm round-trip preserves reasoning" {
  let inbound = "{\"id\":\"c-1\",\"model\":\"qwen\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"Final\",\"reasoning\":\"thought\"},\"finish_reason\":\"stop\"}]}"
  match vllm_to_lux_response(inbound) {
    Ok(cr) =>
      match lux_response_to_vllm(cr.value()) {
        Ok(enc) => {
          let jv = @json.parse(enc.value())
          match @internal.obj_get(jv, "choices") {
            Some(Array(cs)) =>
              match @internal.obj_get(cs[0], "message") {
                Some(m) =>
                  assert_eq(
                    @internal.field_str(m, "reasoning"),
                    Some("thought"),
                  )
                None => assert_true(false)
              }
            _ => assert_true(false)
          }
        }
        Err(_) => assert_true(false)
      }
    Err(_) => assert_true(false)
  }
}

///|
/// 请求/流式转发：与标准 openai-chat 一致
test "vllm request decode forwards to openai-chat" {
  let json = "{\"model\":\"qwen\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}"
  match vllm_to_lux_request(json) {
    Ok(cr) => assert_eq(cr.value().model, "qwen")
    Err(_) => assert_true(false)
  }
}

///|
/// 请求侧 reasoning 配置：enabled → extra_body.chat_template_kwargs.enable_thinking=true
test "lux_request_to_vllm - reasoning config emits enable_thinking" {
  let req = @lux.LucentRequest::new(
    "qwen3",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [@lux.LucentContent::text("Hello")]),
      ),
    ],
    None,
    None,
    @lux.LucentOptions::default(),
    None,
    Some(@lux.LucentReasoningConfig::new(None, None)),
    None,
    None,
  )
  match lux_request_to_vllm(req) {
    Ok(cr) => {
      let jv = @json.parse(cr.value())
      match @internal.obj_get(jv, "extra_body") {
        Some(Object(m)) =>
          match m.get("chat_template_kwargs") {
            Some(kwargs) =>
              match @internal.obj_get(kwargs, "enable_thinking") {
                Some(True) => ()
                _ => assert_true(false)
              }
            None => assert_true(false)
          }
        _ => assert_true(false)
      }
    }
    Err(_) => assert_true(false)
  }
}

///|
/// 请求侧 reasoning 配置：disabled → enable_thinking=false
test "lux_request_to_vllm - disabled reasoning emits enable_thinking=false" {
  let req = @lux.LucentRequest::new(
    "qwen3",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [@lux.LucentContent::text("Hello")]),
      ),
    ],
    None,
    None,
    @lux.LucentOptions::default(),
    None,
    Some(@lux.LucentReasoningConfig::disabled()),
    None,
    None,
  )
  match lux_request_to_vllm(req) {
    Ok(cr) => {
      let jv = @json.parse(cr.value())
      match @internal.obj_get(jv, "extra_body") {
        Some(Object(m)) =>
          match m.get("chat_template_kwargs") {
            Some(kwargs) =>
              match @internal.obj_get(kwargs, "enable_thinking") {
                Some(False) => ()
                _ => assert_true(false)
              }
            None => assert_true(false)
          }
        _ => assert_true(false)
      }
    }
    Err(_) => assert_true(false)
  }
}

///|
/// capability 声明 provider 名
test "vllm capability declares provider" {
  let cap = capability()
  assert_eq(cap.provider, "openai-chat")
  assert_eq(cap.model_pattern, "gpt-*,o*")
}

///|
/// 流式入站：delta.reasoning → Thinking 块（块索引 1）
test "vllm_sse_to_events - captures delta.reasoning as Thinking block" {
  let sse = "data: {\"choices\":[{\"delta\":{\"role\":\"assistant\",\"reasoning\":\"think hard\"}}]}\n\ndata: {\"choices\":[{\"delta\":{\"content\":\"answer\"}}]}\n\ndata: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n"
  match vllm_sse_to_events(sse) {
    Ok(cr) => {
      let events = cr.value()
      let mut has_thinking = false
      let mut has_text = false
      for ev in events {
        match ev {
          BlockStart(1, Thinking) => has_thinking = true
          BlockDelta(1, ThinkingDelta(s)) =>
            if s == "think hard" {
              has_thinking = true
            }
          BlockDelta(0, TextDelta(s)) => if s == "answer" { has_text = true }
          _ => ()
        }
      }
      assert_true(has_thinking)
      assert_true(has_text)
    }
    Err(_) => assert_true(false)
  }
}

///|
/// 流式入站：delta.reasoning_content（DeepSeek 形态）同样捕获
test "vllm_sse_to_events - captures delta.reasoning_content" {
  let sse = "data: {\"choices\":[{\"delta\":{\"role\":\"assistant\",\"reasoning_content\":\"chain\"}}]}\n\ndata: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n"
  match vllm_sse_to_events(sse) {
    Ok(cr) => {
      let mut has_thinking = false
      for ev in cr.value() {
        match ev {
          BlockDelta(1, ThinkingDelta(s)) =>
            if s == "chain" {
              has_thinking = true
            }
          _ => ()
        }
      }
      assert_true(has_thinking)
    }
    Err(_) => assert_true(false)
  }
}

///|
/// 流式出站：ThinkingDelta → delta.reasoning
test "lux_events_to_vllm_sse - encodes ThinkingDelta as delta.reasoning" {
  let events : Array[@lux.LucentStreamEvent] = [
    ConversationStart(@lux.LucentConversationMeta::new(None, None, None)),
    BlockStart(1, Thinking),
    BlockDelta(1, @lux.LucentBlockDelta::thinking_delta("reasoning text")),
    BlockEnd(1),
    BlockStart(0, Text),
    BlockDelta(0, @lux.LucentBlockDelta::text_delta("answer")),
    BlockEnd(0),
    Finish(Stop),
    Done,
  ]
  match lux_events_to_vllm_sse(events) {
    Ok(cr) => {
      let sse = cr.value()
      assert_true(sse.contains("\"reasoning\":\"reasoning text\""))
      assert_true(sse.contains("\"content\":\"answer\""))
    }
    Err(_) => assert_true(false)
  }
}

///|
/// 流式 round-trip：vLLM SSE（含 reasoning）→ Lux 事件 → vLLM SSE，reasoning 不丢
test "vllm streaming round-trip preserves reasoning" {
  let sse = "data: {\"choices\":[{\"delta\":{\"role\":\"assistant\",\"reasoning\":\"think\"}}]}\n\ndata: {\"choices\":[{\"delta\":{\"content\":\"answer\"}}]}\n\ndata: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n"
  match vllm_sse_to_events(sse) {
    Ok(cr) =>
      match lux_events_to_vllm_sse(cr.value()) {
        Ok(enc) => {
          let s = enc.value()
          assert_true(s.contains("\"reasoning\":\"think\""))
          assert_true(s.contains("\"content\":\"answer\""))
        }
        Err(_) => assert_true(false)
      }
    Err(_) => assert_true(false)
  }
}
