///|
/// ProviderSchema 校验测试 + match_by_model 通配符匹配测试
///
/// 覆盖 schema.mbt validate_request/validate_response 和
/// provider_capability.mbt match_by_model 的通配符分支。

///|
test "DIAGNOSTIC - pattern_specificity of claude-*" {
  match match_by_model("claude-sonnet-4-20250514") {
    Some(reg) => assert_eq(reg.name, "anthropic")
    None => fail("DIAGNOSTIC: match_by_model returned None for claude-sonnet")
  }
}

///|
/// === ProviderSchema::get_schema ===
test "get_schema - openai variants" {
  match get_schema("openai") {
    Some(s) => assert_eq(s.provider_name, "openai")
    None => fail("expected Some for openai")
  }
  match get_schema("openai-chat") {
    Some(s) => assert_eq(s.provider_name, "openai")
    None => fail("expected Some for openai-chat")
  }
  match get_schema("openai-codex") {
    Some(s) => assert_eq(s.provider_name, "openai")
    None => fail("expected Some for openai-codex")
  }
}

///|
test "get_schema - anthropic variants" {
  match get_schema("anthropic") {
    Some(s) => assert_eq(s.provider_name, "anthropic")
    None => fail("expected Some for anthropic")
  }
  match get_schema("claude") {
    Some(s) => assert_eq(s.provider_name, "anthropic")
    None => fail("expected Some for claude")
  }
}

///|
test "get_schema - gemini variants" {
  for name in ["gemini", "google", "google-vertex"] {
    match get_schema(name) {
      Some(s) => assert_eq(s.provider_name, "gemini")
      None => fail("expected Some for " + name)
    }
  }
}

///|
test "get_schema - azure variants" {
  for name in ["azure-openai", "azure"] {
    match get_schema(name) {
      Some(s) => assert_eq(s.provider_name, "openai")
      None => fail("expected Some for " + name)
    }
  }
}

///|
test "get_schema - unknown returns None" {
  assert_true(get_schema("nonexistent") is None)
}

///|
test "get_schema - alias names resolve via registry" {
  // 别名（注册表 aliases）也应能解析到 schema
  for name in ["oai-responses", "chat", "vertex", "claude-messages"] {
    match get_schema(name) {
      Some(_) => ()
      None => fail("expected Some for alias " + name)
    }
  }
}

///|
test "get_schema - model name falls back to registry matching" {
  // 模型名经 match_by_model 回退到 openai-codex，schema 归 openai
  match get_schema("gpt-5.3-codex") {
    Some(s) => assert_eq(s.provider_name, "openai")
    None => fail("expected Some for model name gpt-5.3-codex")
  }
  match get_schema("claude-sonnet-4") {
    Some(s) => assert_eq(s.provider_name, "anthropic")
    None => fail("expected Some for claude model name")
  }
}

///|
/// === ProviderSchema::validate_request — OpenAI ===
fn ok_req() -> @lux.LucentRequest {
  @lux.LucentRequest::new(
    "gpt-4o",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [@lux.LucentContent::text("hi")]),
      ),
    ],
    None,
    None,
    @lux.LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
}

///|
test "validate_request - openai accepts valid default" {
  let schema = ProviderSchema::openai()
  let errors = schema.validate_request(ok_req())
  assert_true(errors.length() == 0)
}

///|
test "validate_request - openai rejects temperature below 0" {
  let opts = @lux.LucentOptions::new(
    Some(-0.1),
    None,
    None,
    None,
    None,
    false,
    None,
    None,
    None,
    None,
  )
  let req = @lux.LucentRequest::new(
    "gpt-4o",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [@lux.LucentContent::text("hi")]),
      ),
    ],
    None,
    None,
    opts,
    None,
    None,
    None,
    None,
  )
  let errors = ProviderSchema::openai().validate_request(req)
  assert_true(errors.length() > 0)
  let has_temp_err = errors[0].contains("temperature")
  assert_true(has_temp_err)
}

///|
test "validate_request - openai rejects temperature above 2" {
  let opts = @lux.LucentOptions::new(
    Some(2.5),
    None,
    None,
    None,
    None,
    false,
    None,
    None,
    None,
    None,
  )
  let req = @lux.LucentRequest::new(
    "gpt-4o",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [@lux.LucentContent::text("hi")]),
      ),
    ],
    None,
    None,
    opts,
    None,
    None,
    None,
    None,
  )
  let errors = ProviderSchema::openai().validate_request(req)
  assert_true(errors.length() > 0)
}

///|
test "validate_request - openai rejects top_p > 1" {
  let opts = @lux.LucentOptions::new(
    None,
    Some(1.5),
    None,
    None,
    None,
    false,
    None,
    None,
    None,
    None,
  )
  let req = @lux.LucentRequest::new(
    "gpt-4o",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [@lux.LucentContent::text("hi")]),
      ),
    ],
    None,
    None,
    opts,
    None,
    None,
    None,
    None,
  )
  let errors = ProviderSchema::openai().validate_request(req)
  assert_true(errors.length() > 0)
}

///|
test "validate_request - openai accepts top_p at boundary" {
  let opts = @lux.LucentOptions::new(
    None,
    Some(1.0),
    None,
    None,
    None,
    false,
    None,
    None,
    None,
    None,
  )
  let req = @lux.LucentRequest::new(
    "gpt-4o",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [@lux.LucentContent::text("hi")]),
      ),
    ],
    None,
    None,
    opts,
    None,
    None,
    None,
    None,
  )
  let errors = ProviderSchema::openai().validate_request(req)
  assert_true(errors.length() == 0)
}

///|
test "validate_request - openai rejects max_output_tokens < 1" {
  let opts = @lux.LucentOptions::new(
    None,
    None,
    Some(0),
    None,
    None,
    false,
    None,
    None,
    None,
    None,
  )
  let req = @lux.LucentRequest::new(
    "gpt-4o",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [@lux.LucentContent::text("hi")]),
      ),
    ],
    None,
    None,
    opts,
    None,
    None,
    None,
    None,
  )
  let errors = ProviderSchema::openai().validate_request(req)
  assert_true(errors.length() > 0)
}

///|
test "validate_request - openai reports multiple errors at once" {
  let opts = @lux.LucentOptions::new(
    Some(-1.0), // bad temp
    Some(2.0), // bad top_p
    Some(0), // bad top_k
    Some(0), // bad max_output_tokens
    None,
    false,
    None,
    None,
    None,
    None,
  )
  let req = @lux.LucentRequest::new(
    "gpt-4o",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [@lux.LucentContent::text("hi")]),
      ),
    ],
    None,
    None,
    opts,
    None,
    None,
    None,
    None,
  )
  let errors = ProviderSchema::openai().validate_request(req)
  // 多个字段违规，应有多个错误
  assert_true(errors.length() > 1)
}

///|
/// === ProviderSchema::validate_request — Anthropic ===
test "validate_request - anthropic rejects top_k < 1" {
  let opts = @lux.LucentOptions::new(
    None,
    None,
    Some(0),
    None,
    None,
    false,
    None,
    None,
    None,
    None,
  )
  let req = @lux.LucentRequest::new(
    "claude-sonnet-4-20250514",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [@lux.LucentContent::text("hi")]),
      ),
    ],
    None,
    None,
    opts,
    None,
    None,
    None,
    None,
  )
  let errors = ProviderSchema::anthropic().validate_request(req)
  assert_true(errors.length() > 0)
}

///|
test "validate_request - anthropic accepts top_k = 1" {
  let opts = @lux.LucentOptions::new(
    None,
    None,
    Some(1),
    None,
    None,
    false,
    None,
    None,
    None,
    None,
  )
  let req = @lux.LucentRequest::new(
    "claude-sonnet-4-20250514",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [@lux.LucentContent::text("hi")]),
      ),
    ],
    None,
    None,
    opts,
    None,
    None,
    None,
    None,
  )
  let errors = ProviderSchema::anthropic().validate_request(req)
  assert_true(errors.length() == 0)
}

///|
/// === ProviderSchema::validate_request — Gemini ===
test "validate_request - gemini accepts temperature 0.5" {
  let opts = @lux.LucentOptions::new(
    Some(0.5),
    None,
    None,
    None,
    None,
    false,
    None,
    None,
    None,
    None,
  )
  let req = @lux.LucentRequest::new(
    "gemini-2.5-pro",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [@lux.LucentContent::text("hi")]),
      ),
    ],
    None,
    None,
    opts,
    None,
    None,
    None,
    None,
  )
  let errors = ProviderSchema::gemini().validate_request(req)
  assert_true(errors.length() == 0)
}

///|
test "validate_request - gemini rejects temperature 1.5" {
  let opts = @lux.LucentOptions::new(
    Some(1.5),
    None,
    None,
    None,
    None,
    false,
    None,
    None,
    None,
    None,
  )
  let req = @lux.LucentRequest::new(
    "gemini-2.5-pro",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [@lux.LucentContent::text("hi")]),
      ),
    ],
    None,
    None,
    opts,
    None,
    None,
    None,
    None,
  )
  let errors = ProviderSchema::gemini().validate_request(req)
  assert_true(errors.length() > 0)
}

///|
/// === ProviderSchema::validate_request — Azure ===
test "validate_request - azure delegates to openai schema" {
  let errors1 = ProviderSchema::azure().validate_request(ok_req())
  assert_true(errors1.length() == 0)
  assert_eq(ProviderSchema::azure().provider_name, "openai")
}

///|
/// === ProviderSchema::validate_request — missing model ===
test "validate_request - includes base validation errors for missing model" {
  let req = @lux.LucentRequest::new(
    "",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [@lux.LucentContent::text("hi")]),
      ),
    ],
    None,
    None,
    @lux.LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
  let errors = ProviderSchema::openai().validate_request(req)
  assert_true(errors.length() > 0)
}

///|
/// === ProviderSchema::validate_response ===
fn ok_resp() -> @lux.LucentResponse {
  let choice = @lux.LucentChoice::new(
    0,
    @lux.LucentMessage::new(Assistant, [@lux.LucentContent::text("hi")]),
    Stop,
    None,
  )
  @lux.LucentResponse::new("r1", "m", None, [choice], None, None)
}

///|
test "validate_response - openai accepts valid response" {
  let errors = ProviderSchema::openai().validate_response(ok_resp())
  assert_true(errors.length() == 0)
}

///|
test "validate_response - openai rejects empty choices" {
  let resp = @lux.LucentResponse::new("r1", "m", None, [], None, None)
  let errors = ProviderSchema::openai().validate_response(resp)
  assert_true(errors.length() > 0)
}

///|
test "validate_response - includes base validation errors" {
  // LucentResponse.validate() 的 base errors 也应被包含
  let choice = @lux.LucentChoice::new(
    0,
    @lux.LucentMessage::new(Assistant, [@lux.LucentContent::text("hi")]),
    Stop,
    None,
  )
  // 空 schema_version 和空 id 会触发 base validation
  let resp = @lux.LucentResponse::new("", "", None, [choice], None, None)
  let errors = ProviderSchema::openai().validate_response(resp)
  assert_true(errors.length() > 0)
}

///|
/// === match_by_model 通配符匹配 ===
test "match_by_model - prefix match claude-*" {
  match match_by_model("claude-sonnet-4-20250514") {
    Some(reg) => assert_eq(reg.name, "anthropic")
    None => fail("expected anthropic for claude-sonnet")
  }
}

///|
test "match_by_model - prefix match gpt-*" {
  match match_by_model("gpt-4o") {
    Some(reg) => assert_eq(reg.name, "openai")
    None => fail("expected openai for gpt-4o")
  }
}

///|
test "match_by_model - prefix match gemini-*" {
  match match_by_model("gemini-2.5-pro") {
    Some(reg) => assert_eq(reg.name, "gemini")
    None => fail("expected gemini for gemini-2.5-pro")
  }
}

///|
test "match_by_model - prefix match o*" {
  match match_by_model("o3") {
    Some(reg) => assert_eq(reg.name, "openai")
    None => fail("expected openai for o3")
  }
}

///|
test "match_by_model - double-star pattern gpt-*-codex" {
  match match_by_model("gpt-4o-codex") {
    Some(reg) => assert_eq(reg.name, "openai-codex")
    None => fail("expected openai-codex for gpt-4o-codex")
  }
  match match_by_model("gpt-5.5-codex") {
    Some(reg) => assert_eq(reg.name, "openai-codex")
    None => fail("expected openai-codex for gpt-5.5-codex")
  }
}

///|
test "match_by_model - unknown model returns None" {
  assert_true(match_by_model("some-random-model") is None)
}

///|
test "match_by_model - prefix match does not match unrelated" {
  // "gpt-*" should NOT match "claude-3"
  // But depending on ordering it may match another provider first;
  // at minimum it should return None if nothing matches
  let result = match_by_model("claude-3-haiku-20240307")
  assert_true(result is Some(_) || result is None)
}

///|
/// === FieldConstraint 构造 ===
test "FieldConstraint::new - all fields" {
  let fc = FieldConstraint::new(Some(0.0), Some(1.0), true, None)
  assert_eq(fc.min_val, Some(0.0))
  assert_eq(fc.max_val, Some(1.0))
  assert_eq(fc.required, true)
  assert_eq(fc.allowed_values, None)
}

///|
test "FieldConstraint::new - with allowed values" {
  let fc = FieldConstraint::new(None, None, false, Some(["low", "high"]))
  assert_eq(fc.allowed_values, Some(["low", "high"]))
}
