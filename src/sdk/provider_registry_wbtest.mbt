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

///|
/// === 元数据唯一源一致性（provider meta ↔ registry ↔ schema facade）===
///
/// 这三条不变量是「provider 元数据唯一源」重构的验收条件：
/// registry 只能搬运 `meta.mbt` 的数据，schema facade 不得与 meta 漂移。

///|
/// 注册项的每个身份字段都必须逐一等于 provider 自己的 metadata()，
/// 且顺序必须与 build_providers 声明的状态一致。
test "registry - registrations mirror provider metadata" {
  let providers = build_providers()
  assert_eq(providers.length(), 4)
  let expected_names = ["responses", "openai", "messages", "gemini"]
  let metas = [
    @responses.metadata(),
    @openai.metadata(),
    @messages.metadata(),
    @gemini.metadata(),
  ]
  let mut i = 0
  while i < providers.length() {
    let reg = providers[i]
    let meta = metas[i]
    assert_eq(reg.name, expected_names[i])
    assert_eq(reg.name, meta.name())
    assert_eq(reg.model_pattern, meta.model_pattern())
    assert_eq(reg.aliases, meta.aliases())
    assert_eq(reg.capability, meta.capability())
    i = i + 1
  }
}

///|
/// 每个 alias 都必须解析回它所属的注册项（别名不在 registry 里重复声明）。
test "registry - every alias resolves to its own provider" {
  for reg in build_providers() {
    for alias_name in reg.aliases {
      match match_provider_name(alias_name) {
        Some(found) => assert_eq(found.name, reg.name)
        None => fail("alias " + alias_name + " must resolve")
      }
    }
  }
}

///|
/// `all_providers()` 是 `build_providers()` 的只读投影（顺序一致）。
test "registry - all_providers mirrors build_providers" {
  let snapshot = all_providers()
  let expected = build_providers()
  assert_eq(snapshot.length(), expected.length())
  let mut i = 0
  while i < snapshot.length() {
    assert_eq(snapshot[i].name, expected[i].name)
    i = i + 1
  }
}

///|
/// 声明漂移闸门：registry 承载的 schema 必须与 sdk 兼容 facade
/// (`get_schema` → `ProviderSchema::openai/anthropic/gemini`) 完全一致。
/// responses 复用 openai 家族约束，messages 复用 anthropic。
test "registry - metadata schema matches sdk facade schema" {
  let providers = build_providers()
  let facade_names = ["openai", "openai", "anthropic", "gemini"]
  let mut i = 0
  while i < providers.length() {
    let facade_name = facade_names[i]
    let actual = providers[i].schema
    match get_schema(facade_name) {
      Some(facade) => {
        assert_eq(actual.provider_name(), facade.provider_name)
        assert_eq(actual.resp_min_choices(), facade.resp_min_choices)
        assert_eq(actual.supports_tools(), facade.supports_tools)
        assert_eq(
          actual.supports_system_instruction(),
          facade.supports_system_instruction,
        )
        assert_eq(actual.temperature().min_bound(), facade.temperature.min_val)
        assert_eq(actual.temperature().max_bound(), facade.temperature.max_val)
        assert_eq(
          actual.temperature().is_required(),
          facade.temperature.required,
        )
        assert_eq(actual.top_p().min_bound(), facade.top_p.min_val)
        assert_eq(actual.top_p().max_bound(), facade.top_p.max_val)
        assert_eq(actual.top_k().min_bound(), facade.top_k.min_val)
        assert_eq(actual.top_k().max_bound(), facade.top_k.max_val)
        assert_eq(
          actual.max_output_tokens().min_bound(),
          facade.max_output_tokens.min_val,
        )
        assert_eq(
          actual.max_output_tokens().max_bound(),
          facade.max_output_tokens.max_val,
        )
        assert_true(actual.supported_reasoning_efforts() is None)
        assert_true(facade.supported_reasoning_efforts is None)
      }
      None => fail("facade schema missing for " + facade_name)
    }
    i = i + 1
  }
}
