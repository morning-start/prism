///|
/// SDK 层测试 — Prism struct、Context、Event、注册表

///|
/// === Prism 构造 ===

///|
test "Prism::new - default provider is openai" {
  let p = Prism::new()
  assert_eq(p.provider, "openai")
  assert_eq(p.api_key, None)
  assert_eq(p.base_url, None)
}

///|
test "Prism::with_provider - sets provider name" {
  let p = Prism::new().with_provider("anthropic")
  assert_eq(p.provider, "anthropic")
}

///|
test "Prism::with_api_key - sets api key" {
  let p = Prism::new().with_api_key("sk-test-123")
  assert_eq(p.api_key, Some("sk-test-123"))
}

///|
test "Prism::with_base_url - sets base url" {
  let p = Prism::new().with_base_url("https://custom.endpoint")
  assert_eq(p.base_url, Some("https://custom.endpoint"))
}

///|
test "Prism::with_provider - chained construction" {
  let p = Prism::new()
    .with_provider("gemini")
    .with_api_key("key-1")
    .with_base_url("https://gemini.api")
  assert_eq(p.provider, "gemini")
  assert_eq(p.api_key, Some("key-1"))
  assert_eq(p.base_url, Some("https://gemini.api"))
}

///|
/// === PrismOptions ===

///|
test "PrismOptions::default - all fields none" {
  let opts = PrismOptions::default()
  assert_eq(opts.model, None)
  assert_eq(opts.temperature, None)
  assert_eq(opts.max_tokens, None)
  assert_eq(opts.store, None)
}

///|
test "PrismOptions::new - sets fields" {
  let opts = PrismOptions::new(
    Some("gpt-4o"),
    Some(0.7),
    Some(2048),
    Some(false),
    None,
  )
  assert_eq(opts.model, Some("gpt-4o"))
  assert_eq(opts.temperature, Some(0.7))
  assert_eq(opts.max_tokens, Some(2048))
  assert_eq(opts.store, Some(false))
}

///|
/// === Context ===

///|
test "Context::new - empty context" {
  let ctx = Context::new()
  assert_eq(ctx.system_prompt, None)
  assert_eq(ctx.messages.length(), 0)
}

///|
test "Context::add_system - sets system prompt" {
  let ctx = Context::new().add_system("You are helpful")
  assert_eq(ctx.system_prompt, Some("You are helpful"))
}

///|
test "Context::add_user - appends user message" {
  let ctx = Context::new().add_user("Hello")
  assert_eq(ctx.messages.length(), 1)
  assert_eq(ctx.messages[0].role, "user")
  assert_eq(ctx.messages[0].content, "Hello")
}

///|
test "Context::add_assistant - appends assistant message" {
  let ctx = Context::new().add_assistant("Hi there!")
  assert_eq(ctx.messages.length(), 1)
  assert_eq(ctx.messages[0].role, "assistant")
  assert_eq(ctx.messages[0].content, "Hi there!")
}

///|
test "Context::add_user - multiple messages" {
  let ctx = Context::new()
    .add_user("Hello")
    .add_assistant("How can I help?")
    .add_user("Tell me a joke")
  assert_eq(ctx.messages.length(), 3)
  assert_eq(ctx.messages[0].role, "user")
  assert_eq(ctx.messages[1].role, "assistant")
  assert_eq(ctx.messages[2].role, "user")
}

///|
/// === context_to_lux_request ===

///|
test "context_to_lux_request - basic user message" {
  let ctx = Context::new().add_user("Hello")
  let req = context_to_lux_request(ctx, "test-model", PrismOptions::default())
  assert_eq(req.model, "test-model")
  assert_eq(req.conversation.length(), 1)
  assert_eq(req.instructions, None)
}

///|
test "context_to_lux_request - with system prompt" {
  let ctx = Context::new().add_system("You are helpful").add_user("Hi")
  let req = context_to_lux_request(ctx, "test-model", PrismOptions::default())
  match req.instructions {
    Some(content) => assert_eq(content.length(), 1)
    None => assert_true(false)
  }
}

///|
test "context_to_lux_request - multiple messages preserved" {
  let ctx = Context::new()
    .add_user("Hello")
    .add_assistant("Hi!")
    .add_user("Weather?")
  let req = context_to_lux_request(ctx, "m1", PrismOptions::default())
  assert_eq(req.conversation.length(), 3)
}

///|
test "context_to_lux_request - with options" {
  let opts = PrismOptions::new(None, Some(0.5), Some(100), None, None)
  let ctx = Context::new().add_user("test")
  let req = context_to_lux_request(ctx, "custom", opts)
  assert_eq(req.options.temperature, Some(0.5))
  assert_eq(req.options.max_output_tokens, Some(100))
}

///|
/// === Prism::encode_request ===

///|
test "encode_request - openai_chat returns valid JSON" {
  let p = Prism::new().with_provider("openai-chat")
  match p.encode_request("Hello", PrismOptions::default()) {
    Ok(json) => {
      assert_true(json.length() > 0)
      assert_true(json.has_prefix("{"))
    }
    Err(e) => fail("encode_request failed: " + e)
  }
}

///|
test "encode_request - anthropic returns valid JSON" {
  let p = Prism::new().with_provider("anthropic")
  match p.encode_request("Hello", PrismOptions::default()) {
    Ok(json) => {
      assert_true(json.contains("model"))
      assert_true(json.contains("messages"))
    }
    Err(e) => fail("anthropic encode failed: " + e)
  }
}

///|
test "encode_request - openai-responses returns valid JSON" {
  let p = Prism::new().with_provider("openai-responses")
  match p.encode_request("Hello", PrismOptions::default()) {
    Ok(json) => assert_true(json.length() > 0)
    Err(e) => fail("responses encode failed: " + e)
  }
}

///|
test "encode_request - gemini returns valid JSON" {
  let p = Prism::new().with_provider("gemini")
  match p.encode_request("Hello", PrismOptions::default()) {
    Ok(json) => assert_true(json.length() > 0)
    Err(e) => fail("gemini encode failed: " + e)
  }
}

///|
test "encode_request - unknown provider returns error" {
  let p = Prism::new().with_provider("nonexistent-provider")
  match p.encode_request("Hello", PrismOptions::default()) {
    Ok(_) => fail("expected error for unknown provider")
    Err(e) => assert_true(e.contains("unknown provider"))
  }
}

///|
/// === Prism::encode_stream_request ===

///|
test "encode_stream_request - openai_chat includes stream field" {
  let p = Prism::new().with_provider("openai-chat")
  match p.encode_stream_request("Hello", PrismOptions::default()) {
    Ok(json) => assert_true(json.contains("stream"))
    Err(e) => fail("stream encode failed: " + e)
  }
}

///|
test "encode_stream_request - unknown provider returns error" {
  let p = Prism::new().with_provider("invalid")
  match p.encode_stream_request("Hi", PrismOptions::default()) {
    Ok(_) => fail("expected error")
    Err(e) => assert_true(e.contains("unknown provider"))
  }
}

///|
/// === Prism::decode_response ===

///|
test "decode_response - openai_chat extracts text" {
  let resp_json = "{\"id\":\"chatcmpl-123\",\"object\":\"chat.completion\",\"created\":123,\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"Hello!\"},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":5,\"completion_tokens\":3,\"total_tokens\":8}}"
  let p = Prism::new().with_provider("openai-chat")
  match p.decode_response(resp_json) {
    Ok(text) => assert_eq(text, "Hello!")
    Err(e) => fail("decode failed: " + e)
  }
}

///|
test "decode_response - unknown provider returns error" {
  let p = Prism::new().with_provider("nonexistent")
  match p.decode_response("{}") {
    Ok(_) => fail("expected error")
    Err(e) => assert_true(e.contains("unknown provider"))
  }
}

///|
/// === Prism::decode_sse ===

///|
test "decode_sse - openai_chat returns events" {
  let p = Prism::new().with_provider("openai-chat")
  let sse = "data: {\"id\":\"1\",\"object\":\"chat.completion.chunk\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hello\"},\"finish_reason\":null}]}\n\ndata: {\"id\":\"1\",\"object\":\"chat.completion.chunk\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n"
  match p.decode_sse(sse) {
    Ok(events) => assert_true(events.length() > 0)
    Err(e) => fail("sse decode failed: " + e)
  }
}

///|
test "decode_sse - unknown provider returns error" {
  let p = Prism::new().with_provider("bad")
  match p.decode_sse("data: {}") {
    Ok(_) => fail("expected error")
    Err(e) => assert_true(e.contains("unknown provider"))
  }
}

///|
/// === Prism::capability ===

///|
test "capability - known provider returns Some" {
  let p = Prism::new()
  match p.capability("openai") {
    Some(_) => assert_true(true)
    None => fail("expected Some for known provider")
  }
}

///|
test "capability - unknown provider returns None" {
  let p = Prism::new()
  match p.capability("nobody") {
    Some(_) => fail("expected None")
    None => assert_true(true)
  }
}

///|
/// === 注册表函数 ===

///|
test "match_provider_name - known provider found" {
  match match_provider_name("openai") {
    Some(r) => assert_eq(r.name, "openai")
    None => fail("expected Some for openai")
  }
}

///|
test "match_provider_name - alias resolves" {
  match match_provider_name("google") {
    Some(_) => assert_true(true)
    None => fail("google alias should resolve")
  }
}

///|
test "match_provider_name - unknown returns None" {
  match match_provider_name("not-a-provider") {
    Some(_) => fail("expected None")
    None => assert_true(true)
  }
}

///|
test "list_provider_names - returns all registered names" {
  let names = list_provider_names()
  assert_true(names.length() >= 4)
  assert_true(names.contains("openai"))
  assert_true(names.contains("anthropic"))
}

///|
/// === PrismEvent 通过 decode_sse 间接验证 ===

///|
test "decode_sse result contains expected event types" {
  let p = Prism::new().with_provider("openai-chat")
  let sse = "data: {\"id\":\"1\",\"object\":\"chat.completion.chunk\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hi\"},\"finish_reason\":null}]}\n\ndata: [DONE]\n"
  match p.decode_sse(sse) {
    Ok(events) => assert_true(events.length() > 0)
    Err(e) => fail("sse: " + e)
  }
}
