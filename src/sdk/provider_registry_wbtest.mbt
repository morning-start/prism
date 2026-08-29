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
      let req = @lux.LucentRequest::from_messages(
        "claude-3-5",
        None,
        [msg],
        None,
        None,
        @lux.LucentOptions::default(),
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
