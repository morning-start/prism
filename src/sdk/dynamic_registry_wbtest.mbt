///|
/// 运行时 provider 注册测试（T6）
///
/// 覆盖 register_provider / unregister_provider /
/// ProviderRegistration::with_overrides / Prism::endpoint：
///   - 动态注册可被名称/别名/模型模式命中
///   - 静态表优先（动态项不遮蔽静态匹配）——默认路径零影响
///   - with_overrides 继承 codecs（编码输出与基座一致）+ 覆盖端点
///   - all_providers / list_provider_names 叠加动态表
///   - Prism::endpoint 查询部署态端点配置
///
/// 注意：动态表是包级全局，每个测试必须在结束前注销自注册项，
/// 避免污染同包其他测试（测试名各自使用独立 provider 名）。

///|
/// 取静态 openai 注册项作基座
fn base_openai_reg() -> ProviderRegistration {
  match match_provider_name("openai") {
    Some(reg) => reg
    None => abort("static openai registration not found")
  }
}

///|
test "dynamic registry - register and match by name" {
  let base = base_openai_reg()
  let derived = base.with_overrides({
    ..RegistrationOverrides::default(),
    name: Some("t6-azure"),
    base_url: Some("https://t6.openai.azure.com"),
    auth_header: Some("api-key"),
    api_version: Some("2024-10-21"),
  })
  register_provider(derived)
  match match_provider_name("t6-azure") {
    Some(reg) => {
      assert_eq(reg.name, "t6-azure")
      assert_eq(reg.base_url, Some("https://t6.openai.azure.com"))
      assert_eq(reg.auth_header, Some("api-key"))
      assert_eq(reg.api_version, Some("2024-10-21"))
    }
    None => fail("dynamic registration not matched")
  }
  // 清理
  assert_true(unregister_provider("t6-azure"))
  assert_true(match_provider_name("t6-azure") is None)
}

///|
test "dynamic registry - match by alias and model pattern" {
  let base = base_openai_reg()
  let derived = base.with_overrides({
    ..RegistrationOverrides::default(),
    name: Some("t6-vllm"),
    aliases: Some(["t6-local"]),
    model_pattern: Some("t6-qwen*"),
    base_url: Some("http://localhost:8000/v1"),
  })
  register_provider(derived)
  // 别名命中
  match match_provider_name("t6-local") {
    Some(reg) => assert_eq(reg.name, "t6-vllm")
    None => fail("alias not matched")
  }
  // 模型模式命中
  match match_by_model("t6-qwen-72b") {
    Some(reg) => assert_eq(reg.name, "t6-vllm")
    None => fail("model pattern not matched")
  }
  assert_true(unregister_provider("t6-vllm"))
}

///|
/// 静态表优先：动态项使用静态别名也不得遮蔽静态匹配
test "dynamic registry - static table wins over dynamic alias" {
  let base = base_openai_reg()
  let derived = base.with_overrides({
    ..RegistrationOverrides::default(),
    name: Some("t6-shadow"),
    aliases: Some(["chat"]), // "chat" 是静态 openai 的别名
  })
  register_provider(derived)
  match match_provider_name("chat") {
    Some(reg) => assert_eq(reg.name, "openai") // 静态优先
    None => fail("expected static match")
  }
  assert_true(unregister_provider("t6-shadow"))
}

///|
/// 注销静态表名返回 false（静态表不可被动态注销）
test "dynamic registry - unregister static name returns false" {
  assert_false(unregister_provider("openai"))
  assert_false(unregister_provider("messages"))
}

///|
/// with_overrides 继承 codecs：编码输出与基座逐字节一致
test "dynamic registry - derived registration inherits codecs" {
  let base = base_openai_reg()
  let derived = base.with_overrides({
    ..RegistrationOverrides::default(),
    name: Some("t6-codec"),
    base_url: Some("https://t6.example.com"),
  })
  let req = @lux.LucentRequest::from_messages(
    "gpt-4o",
    None,
    [@lux.LucentMessage::new(User, [@lux.LucentContent::text("Hi")])],
    None,
    None,
    @lux.LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
  match (base.request_encode)(req) {
    Ok(base_cr) =>
      match (derived.request_encode)(req) {
        Ok(derived_cr) => assert_eq(derived_cr.value(), base_cr.value())
        Err(e) => fail("derived encode failed: \{e}")
      }
    Err(e) => fail("base encode failed: \{e}")
  }
}

///|
/// 幂等：同名重复注册替换旧项（不重复堆积）
test "dynamic registry - re-register replaces" {
  let base = base_openai_reg()
  let first = base.with_overrides({
    ..RegistrationOverrides::default(),
    name: Some("t6-idem"),
    base_url: Some("https://first.example.com"),
  })
  register_provider(first)
  let second = base.with_overrides({
    ..RegistrationOverrides::default(),
    name: Some("t6-idem"),
    base_url: Some("https://second.example.com"),
  })
  register_provider(second)
  match match_provider_name("t6-idem") {
    Some(reg) => assert_eq(reg.base_url, Some("https://second.example.com"))
    None => fail("expected re-registered entry")
  }
  // 动态表中同名项只有一个
  let mut count = 0
  for reg in all_providers() {
    if reg.name == "t6-idem" {
      count = count + 1
    }
  }
  assert_eq(count, 1)
  assert_true(unregister_provider("t6-idem"))
}

///|
/// all_providers / list_provider_names 叠加动态表
test "dynamic registry - listings include dynamic entries" {
  let base_names = list_provider_names().length()
  let base = base_openai_reg()
  let derived = base.with_overrides({
    ..RegistrationOverrides::default(),
    name: Some("t6-listed"),
  })
  register_provider(derived)
  assert_eq(list_provider_names().length(), base_names + 1)
  assert_eq(all_providers().length(), base_names + 1)
  assert_true(unregister_provider("t6-listed"))
  assert_eq(list_provider_names().length(), base_names)
}

///|
/// 端到端：注册后 Prism 门面可用新 provider 编码 + endpoint 查询
test "dynamic registry - Prism facade uses dynamic provider" {
  let base = base_openai_reg()
  let derived = base.with_overrides({
    ..RegistrationOverrides::default(),
    name: Some("t6-e2e"),
    model_pattern: Some("t6-model*"),
    base_url: Some("https://t6-e2e.example.com/v1"),
    auth_header: Some("Authorization"),
  })
  register_provider(derived)
  let p = Prism::new().with_provider("t6-e2e")
  match p.encode_request("Hi", PrismOptions::default()) {
    Ok(json) => assert_true(json.contains("messages"))
    Err(e) => fail("encode failed: \{e}")
  }
  match p.endpoint("t6-e2e") {
    Some(ep) => {
      assert_eq(ep.base_url, Some("https://t6-e2e.example.com/v1"))
      assert_eq(ep.auth_header, Some("Authorization"))
      assert_eq(ep.api_version, None)
    }
    None => fail("expected endpoint config")
  }
  // 模型模式回退：未知名称按模型命中动态项
  match match_provider_name("t6-model-1") {
    Some(reg) => assert_eq(reg.name, "t6-e2e")
    None => fail("model pattern fallback failed")
  }
  assert_true(unregister_provider("t6-e2e"))
}

///|
/// 零回归门禁：静态匹配在动态注册存在时行为不变
test "dynamic registry - static matching unaffected" {
  let base = base_openai_reg()
  let derived = base.with_overrides({
    ..RegistrationOverrides::default(),
    name: Some("t6-noise"),
  })
  register_provider(derived)
  // 静态精确/别名/模型模式全部保持原命中
  match match_provider_name("openai") {
    Some(reg) => assert_eq(reg.name, "openai")
    None => fail("static exact match broken")
  }
  match match_provider_name("anthropic") {
    Some(reg) => assert_eq(reg.name, "messages")
    None => fail("static alias match broken")
  }
  match match_by_model("gpt-4o") {
    Some(reg) => assert_eq(reg.name, "responses")
    None => fail("static model match broken")
  }
  assert_true(unregister_provider("t6-noise"))
}
