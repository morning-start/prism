///|
/// @sdk.Context 构造 + system prompt + tools 路径测试
///
/// 覆盖：
///   - @sdk.SdkTool::new / @sdk.SdkMessage::new 构造
///   - @sdk.Context::add_system / add_tools
///   - @sdk.context_to_lux_request instructions 路径
///   - @sdk.context_to_lux_request tools 路径
///   - @sdk.Prism encode_request / decode_response / decode_sse

///|
/// === @sdk.SdkTool / @sdk.SdkMessage 构造 ===
test "@sdk.SdkTool::new" {
  let tool = @sdk.SdkTool::new(
    "get_weather", "Get the weather", "{\"type\":\"object\"}",
  )
  assert_eq(tool.name, "get_weather")
  assert_eq(tool.description, "Get the weather")
  assert_eq(tool.parameters_json, "{\"type\":\"object\"}")
}

///|
/// === @sdk.Context::add_tools ===
test "@sdk.Context::add_tools - sets tools array" {
  let tools = [
    @sdk.SdkTool::new("search", "Search the web", "{}"),
    @sdk.SdkTool::new("calc", "Calculate", "{}"),
  ]
  let ctx = @sdk.Context::new().add_tools(tools)
  match ctx.tools {
    Some(t) => assert_eq(t.length(), 2)
    None => assert_true(false)
  }
}

///|
test "@sdk.Context::add_tools - multiple calls replaces" {
  let tools1 = [@sdk.SdkTool::new("a", "a", "{}")]
  let tools2 = [
    @sdk.SdkTool::new("b", "b", "{}"),
    @sdk.SdkTool::new("c", "c", "{}"),
  ]
  let ctx = @sdk.Context::new().add_tools(tools1).add_tools(tools2)
  match ctx.tools {
    Some(t) => assert_eq(t.length(), 2)
    None => assert_true(false)
  }
}

///|
/// === @sdk.context_to_lux_request — system prompt ===
test "@sdk.context_to_lux_request - system prompt included" {
  let ctx = @sdk.Context::new().add_system("You are a bot").add_user("hello")
  let req = @sdk.context_to_lux_request(ctx, "m", @sdk.PrismOptions::default())
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
/// === @sdk.context_to_lux_request — tools in request ===
test "@sdk.context_to_lux_request - tools are included in request" {
  let tools = [
    @sdk.SdkTool::new("get_weather", "Get the weather", "{\"type\":\"object\"}"),
  ]
  let ctx = @sdk.Context::new().add_user("weather?").add_tools(tools)
  let req = @sdk.context_to_lux_request(ctx, "m", @sdk.PrismOptions::default())

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
test "@sdk.context_to_lux_request - no tools when tools is None" {
  let ctx = @sdk.Context::new().add_user("hi")
  let req = @sdk.context_to_lux_request(ctx, "m", @sdk.PrismOptions::default())
  assert_true(req.tools is None)
}

///|
/// === @sdk.Prism::encode_request ===
test "encode_request - custom model used" {
  let opts = @sdk.PrismOptions::new(Some("gpt-4o-mini"), None, None, None, None)
  let p = @sdk.Prism::new().with_provider("openai")
  match p.encode_request("Hi", opts) {
    Ok(json) => assert_true(json.contains("gpt-4o-mini"))
    Err(e) => fail("encode failed: " + e)
  }
}

///|
test "encode_request - default model gpt-4o used" {
  let p = @sdk.Prism::new().with_provider("openai")
  match p.encode_request("Hi", @sdk.PrismOptions::default()) {
    Ok(json) => assert_true(json.contains("gpt-4o"))
    Err(e) => fail("encode failed: " + e)
  }
}

///|
test "encode_stream_request - custom model used" {
  let opts = @sdk.PrismOptions::new(Some("gpt-4.1"), None, None, None, None)
  let p = @sdk.Prism::new().with_provider("openai-chat")
  match p.encode_stream_request("Hi", opts) {
    Ok(json) => assert_true(json.contains("gpt-4.1"))
    Err(e) => fail("stream encode failed: " + e)
  }
}

///|
/// === @sdk.Prism::decode_sse ===
test "decode_sse - gemini with unknown provider errors" {
  let p = @sdk.Prism::new().with_provider("fake-provider")
  match p.decode_sse("data: {}\n") {
    Err(e) => assert_true(e.contains("unknown"))
    Ok(_) => fail("expected error")
  }
}

///|
/// === @sdk.Prism::decode_response error paths ===
test "decode_response - gemini error path for malformed json" {
  let p = @sdk.Prism::new().with_provider("gemini")
  match p.decode_response("not-json-at-all") {
    Err(_) => ()
    Ok(_) => fail("expected decode error for malformed json")
  }
}

///|
test "decode_response - anthropic error path for malformed json" {
  let p = @sdk.Prism::new().with_provider("anthropic")
  match p.decode_response("not-json-at-all") {
    Err(_) => ()
    Ok(_) => fail("expected decode error")
  }
}
