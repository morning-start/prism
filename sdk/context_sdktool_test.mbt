///|
/// Context 构造 + system prompt + tools 路径测试
///
/// 覆盖：
///   - SdkTool::new / SdkMessage::new 构造
///   - Context::add_system / add_tools
///   - context_to_lux_request instructions 路径
///   - context_to_lux_request tools 路径
///   - Prism encode_request / decode_response / decode_sse

///|
/// === SdkTool / SdkMessage 构造 ===
test "SdkTool::new" {
  let tool = SdkTool::new(
    "get_weather", "Get the weather", "{\"type\":\"object\"}",
  )
  assert_eq(tool.name, "get_weather")
  assert_eq(tool.description, "Get the weather")
  assert_eq(tool.parameters_json, "{\"type\":\"object\"}")
}

///|
/// === Context::add_tools ===
test "Context::add_tools - sets tools array" {
  let tools = [
    SdkTool::new("search", "Search the web", "{}"),
    SdkTool::new("calc", "Calculate", "{}"),
  ]
  let ctx = Context::new().add_tools(tools)
  match ctx.tools {
    Some(t) => assert_eq(t.length(), 2)
    None => assert_true(false)
  }
}

///|
test "Context::add_tools - multiple calls replaces" {
  let tools1 = [SdkTool::new("a", "a", "{}")]
  let tools2 = [SdkTool::new("b", "b", "{}"), SdkTool::new("c", "c", "{}")]
  let ctx = Context::new().add_tools(tools1).add_tools(tools2)
  match ctx.tools {
    Some(t) => assert_eq(t.length(), 2)
    None => assert_true(false)
  }
}

///|
/// === context_to_lux_request — system prompt ===
test "context_to_lux_request - system prompt included" {
  let ctx = Context::new().add_system("You are a bot").add_user("hello")
  let req = context_to_lux_request(ctx, "m", PrismOptions::default())
  // Instructions should have the system prompt
  match req.instructions {
    Some(instr) => {
      assert_eq(instr.length(), 1)
      match instr[0] {
        Text(s, _) => assert_eq(s, "You are a bot")
        _ => assert_true(false)
      }
    }
    None => fail("expected instructions")
  }
}

///|
/// === context_to_lux_request — tools in request ===
test "context_to_lux_request - tools are included in request" {
  let tools = [
    SdkTool::new("get_weather", "Get the weather", "{\"type\":\"object\"}"),
  ]
  let ctx = Context::new().add_user("weather?").add_tools(tools)
  let req = context_to_lux_request(ctx, "m", PrismOptions::default())

  match req.tools {
    Some(t) => {
      assert_eq(t.length(), 1)
      let t0 = t[0]
      assert_eq(t0.name, "get_weather")
      match t0.description {
        Some(d) => assert_eq(d, "Get the weather")
        None => assert_true(false)
      }
      assert_eq(t0.parameters_json, "{\"type\":\"object\"}")
    }
    None => assert_true(false)
  }
}

///|
test "context_to_lux_request - no tools when tools is None" {
  let ctx = Context::new().add_user("hi")
  let req = context_to_lux_request(ctx, "m", PrismOptions::default())
  assert_true(req.tools is None)
}

///|
/// === Prism::encode_request ===
test "encode_request - custom model used" {
  let opts = PrismOptions::new(Some("gpt-4o-mini"), None, None, None, None)
  let p = Prism::new().with_provider("openai-chat")
  match p.encode_request("Hi", opts) {
    Ok(json) => assert_true(json.contains("gpt-4o-mini"))
    Err(e) => fail("encode failed: " + e)
  }
}

///|
test "encode_request - default model gpt-4o used" {
  let p = Prism::new().with_provider("openai-chat")
  match p.encode_request("Hi", PrismOptions::default()) {
    Ok(json) => assert_true(json.contains("gpt-4o"))
    Err(e) => fail("encode failed: " + e)
  }
}

///|
test "encode_stream_request - custom model used" {
  let opts = PrismOptions::new(Some("gpt-4.1"), None, None, None, None)
  let p = Prism::new().with_provider("openai-chat")
  match p.encode_stream_request("Hi", opts) {
    Ok(json) => assert_true(json.contains("gpt-4.1"))
    Err(e) => fail("stream encode failed: " + e)
  }
}

///|
/// === Prism::decode_sse ===
test "decode_sse - gemini with unknown provider errors" {
  let p = Prism::new().with_provider("fake-provider")
  match p.decode_sse("data: {}\n") {
    Err(e) => assert_true(e.contains("unknown"))
    Ok(_) => fail("expected error")
  }
}

///|
/// === Prism::decode_response error paths ===
test "decode_response - gemini error path for malformed json" {
  let p = Prism::new().with_provider("gemini")
  match p.decode_response("not-json-at-all") {
    Err(_) => ()
    Ok(_) => fail("expected decode error for malformed json")
  }
}

///|
test "decode_response - anthropic error path for malformed json" {
  let p = Prism::new().with_provider("anthropic")
  match p.decode_response("not-json-at-all") {
    Err(_) => ()
    Ok(_) => fail("expected decode error")
  }
}
