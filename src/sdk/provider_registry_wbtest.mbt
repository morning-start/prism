///|
/// Provider 名称匹配失败时，允许用模型名匹配最具体的注册项。
test "match_provider_name falls back to model pattern" {
  match match_provider_name("gpt-5.3-codex") {
    Some(reg) => assert_eq(reg.name, "responses")
    None => fail("expected model pattern fallback")
  }
}

///|
/// === 六函数契约切换：注册表返回带诊断的 ConversionResult ===

///|
test "registry - request_decode returns ConversionResult" {
  match match_provider_name("openai") {
    Some(reg) =>
      match
        (reg.request_decode)(
          "{\"model\":\"gpt-4o\",\"messages\":[{\"role\":\"user\",\"content\":\"Hi\"}]}",
        ) {
        Ok(cr) => {
          assert_eq(cr.diagnostics().length(), 0)
          assert_eq(cr.value().model, "gpt-4o")
        }
        Err(e) => fail("decode failed: \{e}")
      }
    None => fail("provider not found")
  }
}

///|
test "registry - request_encode returns ConversionResult" {
  match match_provider_name("anthropic") {
    Some(reg) => {
      let msg = @lux.LucentMessage::new(User, [@lux.LucentContent::text("Hi")])
      let opts = @lux.LucentOptions::new(
        None,
        None,
        None,
        Some(1024),
        None,
        false,
        None,
        None,
        None,
        None,
      )
      let req = @lux.LucentRequest::from_messages(
        "claude-3-5",
        None,
        [msg],
        None,
        None,
        opts,
        None,
        None,
        None,
        None,
      )
      match (reg.request_encode)(req) {
        Ok(cr) => {
          assert_true(cr.value().contains("model"))
          assert_eq(cr.diagnostics().length(), 0)
        }
        Err(e) => fail("encode failed: \{e}")
      }
    }
    None => fail("provider not found")
  }
}

///|
test "match_provider_name normalizes aliases" {
  match match_provider_name("  google  ") {
    Some(reg) => assert_eq(reg.name, "gemini")
    None => fail("expected alias resolution")
  }
}

///|
test "match_provider_name returns None for unknown provider" {
  match match_provider_name("  not-a-provider  ") {
    None => assert_true(true)
    Some(_) => fail("expected unknown provider to be None")
  }
}

///|
/// === capability 消费一致性（iteration-008 方向 A/C）===

///|
/// 请求使用声明支持的能力时，check_capability 不得产生 Unsupported 诊断。
/// 四 provider 均声明 tool_calling/reasoning/structured_output=Full，
/// 带工具的请求应通过能力校验（声明与实际行为一致，防声明漂移）。
test "check_capability - supported tools yield no diagnostics" {
  let tools_req : @lux.LucentRequest = @lux.LucentRequest::new(
    "test-model",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [@lux.LucentContent::text("Hi")]),
      ),
    ],
    Some([
      @lux.LucentTool::simple(
        "get_weather", "Get weather", "{\"type\":\"object\"}",
      ),
    ]),
    None,
    @lux.LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
  for name in ["openai", "messages", "responses", "gemini"] {
    let prism = Prism::new().with_provider(name)
    let diags = prism.check_capability(tools_req)
    assert_eq(diags.length(), 0)
  }
}

///|
/// check_capability 与能力声明一致：capability() 查询返回的声明
/// 中 tool_calling 必须为 Full（与 adapter 实际支持工具的行为一致）。
test "check_capability - declaration matches tool support" {
  for name in ["openai", "messages", "responses", "gemini"] {
    match Prism::new().capability(name) {
      Some(cap) => assert_true(cap.capabilities.tool_calling is Full)
      None => fail("capability for " + name + " not found")
    }
  }
}
