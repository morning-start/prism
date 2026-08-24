///|
/// SDK 基础示例测试

///|
/// === L1 API 测试 ===

///|
test "L1 - encode request returns valid JSON" {
  let prism = @sdk.Prism::new().with_provider("openai")
  let result = prism.encode_request("Hello", @sdk.PrismOptions::default())
  match result {
    Ok(json) => {
      assert_true(json.length() > 0)
      assert_true(json.contains("model"))
      assert_true(json.contains("input"))
    }
    Err(e) => fail("encode failed: " + e)
  }
}

///|
test "L1 - switch provider changes format" {
  let openai = @sdk.Prism::new().with_provider("openai")
  let anthropic = @sdk.Prism::new().with_provider("anthropic")

  let openai_result = openai.encode_request(
    "Hello",
    @sdk.PrismOptions::default(),
  )
  let anthropic_result = anthropic.encode_request(
    "Hello",
    @sdk.PrismOptions::default(),
  )

  match (openai_result, anthropic_result) {
    (Ok(o), Ok(a)) => {
      // Different providers should produce different JSON formats
      assert_true(o.contains("\"input\"")) // OpenAI Responses uses input
      assert_true(a.contains("\"messages\"")) // Anthropic uses messages
    }
    _ => fail("Both should succeed")
  }
}

///|
test "L1 - complete with mock transport" {
  let prism = @sdk.Prism::new().with_provider("openai-chat")

  fn mock_send(_req : String) -> Result[String, String] {
    Ok(
      "{\"id\":\"resp-1\",\"object\":\"chat.completion\",\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"Hi there!\"},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":5,\"completion_tokens\":3,\"total_tokens\":8}}",
    )
  }

  let result = prism.complete("Hello", @sdk.PrismOptions::default(), mock_send)
  match result {
    Ok(text) => assert_eq(text, "Hi there!")
    Err(e) => fail("complete failed: " + e)
  }
}

///|
/// === L2 API 测试 ===

///|
test "L2 - context with system prompt" {
  let ctx = @sdk.Context::new().add_system("You are helpful").add_user("Hello")

  let req = @sdk.context_to_lux_request(
    ctx,
    "gpt-4o",
    @sdk.PrismOptions::default(),
  )
  match req.instructions {
    Some(content) => assert_eq(content.length(), 1)
    None => fail("Expected system prompt")
  }
}

///|
test "L2 - context with tools" {
  let tools = [
    @sdk.SdkTool::new("test_tool", "A test tool", "{\"type\":\"object\"}"),
  ]

  let ctx = @sdk.Context::new().add_user("Use the tool").add_tools(tools)

  let req = @sdk.context_to_lux_request(
    ctx,
    "gpt-4o",
    @sdk.PrismOptions::default(),
  )
  match req.tools {
    Some(t) => assert_eq(t.length(), 1)
    None => fail("Expected tools")
  }
}

///|
test "L2 - tool result injection" {
  let ctx = @sdk.Context::new()
    .add_user("What's the weather?")
    .add_tool_result("tool_1", "Sunny", false)

  let req = @sdk.context_to_lux_request(
    ctx,
    "gpt-4o",
    @sdk.PrismOptions::default(),
  )
  assert_eq(req.conversation.length(), 2)
  match req.conversation[1] {
    ToolResult(tr) => {
      assert_eq(tr.tool_use_id, "tool_1")
      assert_eq(tr.is_error, false)
    }
    _ => fail("Expected ToolResult")
  }
}

///|
test "L2 - stream decode returns events" {
  let prism = @sdk.Prism::new().with_provider("openai-chat")

  let sse = "data: {\"id\":\"1\",\"object\":\"chat.completion.chunk\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hi\"},\"finish_reason\":null}]}\n\ndata: [DONE]\n"

  let result = prism.decode_sse(sse)
  match result {
    Ok(events) => assert_true(events.length() > 0)
    Err(e) => fail("decode_sse failed: " + e)
  }
}

///|
/// === Error Handling 测试 ===

///|
test "Error - unknown provider returns error" {
  let prism = @sdk.Prism::new().with_provider("nonexistent")
  let result = prism.encode_request("Hello", @sdk.PrismOptions::default())
  match result {
    Ok(_) => fail("Expected error")
    Err(e) => assert_true(e.contains("unknown provider"))
  }
}

///|
test "Error - decode invalid JSON returns error" {
  let prism = @sdk.Prism::new().with_provider("openai")
  let result = prism.decode_response("not json")
  match result {
    Ok(_) => fail("Expected error")
    Err(e) => assert_true(e.length() > 0)
  }
}

///|
/// === Capability 测试 ===

///|
test "Capability - known provider returns Some" {
  let prism = @sdk.Prism::new()
  match prism.capability("openai") {
    Some(_) => assert_true(true)
    None => fail("Expected Some for openai")
  }
}

///|
test "Capability - unknown provider returns None" {
  let prism = @sdk.Prism::new()
  match prism.capability("nonexistent") {
    Some(_) => fail("Expected None")
    None => assert_true(true)
  }
}
