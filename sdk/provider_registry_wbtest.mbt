///|
/// Provider 名称匹配失败时，允许用模型名匹配最具体的注册项。
test "match_provider_name falls back to model pattern" {
  match match_provider_name("gpt-5.3-codex") {
    Some(reg) => assert_eq(reg.name, "openai-codex")
    None => fail("expected model pattern fallback")
  }
}
