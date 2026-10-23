///|
/// `protocol_native_keys` / `foreign_extra_keys` / `extras_excluding` /
/// `extras_without_keys` / `overlapping_extra_keys` 的纯函数契约。
///
/// 这些函数是「extras 跨端归属过滤」与「扩展通道优先级」的判定核心，
/// 端到端行为见 `src/sdk/test/extension_channel_test.mbt`；本文件补充
/// 空值 / 未知协议等边界分支（那些分支在端到端路径里不可达）。

///|
fn keys_map(pairs : Array[(String, Json)]) -> Map[String, Json] {
  let m : Map[String, Json] = Map([])
  for p in pairs {
    m[p.0] = p.1
  }
  m
}

///|
test "protocol keys - unknown protocol has no native keys" {
  assert_eq(@internal.protocol_native_keys("no-such-protocol").length(), 0)
  assert_eq(
    @internal.protocol_native_response_keys("no-such-protocol").length(),
    0,
  )
  // 四个已知协议都非空
  for p in ["openai", "responses", "messages", "gemini"] {
    assert_true(@internal.protocol_native_keys(p).length() > 0)
    assert_true(@internal.protocol_native_response_keys(p).length() > 0)
  }
}

///|
/// 响应级原生表与 vendored spec 的锚定：openai 的四个非建模响应级字段；
/// responses 只有 moderation（service_tier 只出现在 CreateResponse 请求侧）。
test "protocol keys - response tables match the vendored spec" {
  let chat = @internal.protocol_native_response_keys("openai")
  for k in ["system_fingerprint", "service_tier", "metadata", "moderation"] {
    assert_true(chat.contains(k))
  }
  let resp = @internal.protocol_native_response_keys("responses")
  assert_true(resp.contains("moderation"))
  assert_false(resp.contains("service_tier"))
}

///|
/// 编码旋钮（reasoning_field）在分拣时必须被跳过：既不写出、也不报外来诊断。
test "protocol keys - split_provider_payload skips encoder knobs" {
  let payload = @internal.parse_json_opt(
    "{\"reasoning_field\":\"reasoning_content\",\"system_fingerprint\":\"fp\",\"gateway_x\":1}",
  )
  match payload {
    None => fail("test payload must parse")
    Some(v) => {
      let (kept, dropped) = @internal.split_provider_payload(Some(v), "openai")
      // 旋钮不出现在可写出集合
      match kept {
        Some(m) => {
          assert_eq(m.contains("reasoning_field"), false)
          assert_eq(m.contains("system_fingerprint"), true)
          assert_eq(m.contains("gateway_x"), true)
        }
        None => fail("expected kept entries")
      }
      // 旋钮也不是外来键
      assert_eq(dropped.contains("reasoning_field"), false)
    }
  }
  // 非 Object 载体 → 原样为空（不崩溃、不诊断）
  let scalar = @internal.parse_json_opt("\"just-a-string\"")
  match scalar {
    None => fail("test payload must parse")
    Some(v) => {
      let (kept, dropped) = @internal.split_provider_payload(Some(v), "openai")
      assert_eq(kept, None)
      assert_eq(dropped.is_empty(), true)
    }
  }
}

///|
/// build_meta_extra / build_json_object 的边界分支：
/// 空 map → None；全被排除 → None；非 Object → None。
test "protocol keys - build_meta_extra and build_json_object edges" {
  // 全部键被排除 → None
  let full = @internal.parse_json_opt("{\"id\":\"a\",\"model\":\"b\"}")
  match full {
    None => fail("test payload must parse")
    Some(v) => assert_eq(@internal.build_meta_extra(v, ["id", "model"]), None)
  }
  // 部分排除 → 保留其余
  match full {
    None => fail("test payload must parse")
    Some(v) =>
      match @internal.build_meta_extra(v, ["id"]) {
        Some(rest) => assert_true(rest.stringify().contains("model"))
        None => fail("expected remaining key")
      }
  }
  // 非 Object → None
  let scalar = @internal.parse_json_opt("42")
  match scalar {
    None => fail("test payload must parse")
    Some(v) => assert_eq(@internal.build_meta_extra(v, []), None)
  }
  // 空 map → None
  assert_eq(@internal.build_json_object(Map([])), None)
  // 有值 map → 可解析的 JSON 对象
  let m : Map[String, Json] = Map([])
  m["k"] = Json::number(1)
  match @internal.build_json_object(m) {
    Some(v) => assert_true(v.stringify().contains("\"k\":1"))
    None => fail("expected a JSON object")
  }
}

///|
/// `openai` / `responses` 的原生表由 vendored 官方 OpenAPI 展开得到，
/// 这里锚定几个关键事实（改表时若与 spec 冲突，这些断言会先失败）：
/// - `stop` / `logit_bias` / `seed` / `n` 是 Chat Completions 顶层参数；
/// - `truncation` / `include` / `background` 是 Responses 顶层参数；
/// - `seed` / `stop` / `logit_bias` / `n` **不在** Responses 里。
test "protocol keys - openai and responses tables match the vendored spec" {
  let chat = @internal.protocol_native_keys("openai")
  for k in ["stop", "logit_bias", "seed", "n", "stream_options", "top_p"] {
    assert_true(chat.contains(k))
  }
  let resp = @internal.protocol_native_keys("responses")
  for k in ["truncation", "include", "background", "max_output_tokens", "text"] {
    assert_true(resp.contains(k))
  }
  for k in ["stop", "logit_bias", "seed", "n"] {
    assert_false(resp.contains(k))
  }
  assert_false(chat.contains("truncation"))
}

///|
test "protocol keys - foreign detection respects ownership" {
  let seed = keys_map([("seed", Json::number(1))])
  // seed：openai + gemini 原生
  assert_eq(@internal.foreign_extra_keys(Some(seed), "openai").is_empty(), true)
  assert_eq(@internal.foreign_extra_keys(Some(seed), "gemini").is_empty(), true)
  match @internal.foreign_extra_keys(Some(seed), "messages").get("seed") {
    Some(who) => assert_true(who.contains("openai") && who.contains("gemini"))
    None => fail("seed should be foreign to messages")
  }
  // 未知键不是外来键（防误丢的关键保证）
  let unknown = keys_map([("vendor_only_key", Json::boolean(true))])
  for p in ["openai", "responses", "messages", "gemini"] {
    assert_eq(@internal.foreign_extra_keys(Some(unknown), p).is_empty(), true)
  }
  // None 输入
  assert_eq(@internal.foreign_extra_keys(None, "openai").is_empty(), true)
}

///|
test "protocol keys - extras_excluding and extras_without_keys edge cases" {
  let m = keys_map([("a", Json::number(1)), ("b", Json::number(2))])
  // 排除后为空 → None
  assert_eq(@internal.extras_without_keys(Some(m), ["a", "b"]), None)
  // 排除部分 → 保留其余
  match @internal.extras_without_keys(Some(m), ["a"]) {
    Some(rest) => {
      assert_eq(rest.contains("a"), false)
      assert_eq(rest.contains("b"), true)
    }
    None => fail("expected the remaining key")
  }
  // 输入 None → None
  assert_eq(@internal.extras_without_keys(None, ["a"]), None)
  // Map 作为键集合的重载版本与数组版一致
  let set : Map[String, String] = Map([])
  set["a"] = "openai"
  match @internal.extras_excluding(Some(m), set) {
    Some(rest) => assert_eq(rest.contains("a"), false)
    None => fail("expected the remaining key")
  }
  assert_eq(@internal.extras_excluding(None, set), None)
}

///|
test "protocol keys - overlapping_extra_keys covers all None combinations" {
  let a = keys_map([("k", Json::number(1)), ("only_a", Json::number(2))])
  let b = keys_map([("k", Json::number(9))])
  assert_eq(@internal.overlapping_extra_keys(Some(a), Some(b)), ["k"])
  assert_eq(@internal.overlapping_extra_keys(Some(a), None).length(), 0)
  assert_eq(@internal.overlapping_extra_keys(None, Some(b)).length(), 0)
  assert_eq(@internal.overlapping_extra_keys(None, None).length(), 0)
}
