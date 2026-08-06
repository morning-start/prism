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
/// capability 声明 provider 名
test "vllm capability declares provider" {
  let cap = capability()
  assert_eq(cap.provider, "openai-chat")
  assert_eq(cap.model_pattern, "gpt-*,o*")
}
