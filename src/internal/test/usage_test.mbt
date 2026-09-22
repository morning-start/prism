///|
/// 测试 internal/usage.mbt — token 用量解析

///|
/// 解析 JSON 的辅助函数
fn usage_parse(s : String) -> Json {
  @json.parse(s) catch {
    _ => Json::null()
  }
}

///|
/// === parse_reasoning_tokens / parse_cached_tokens ===
/// path 中途解析不到 → 循环内 `None => return None`（usage.mbt L42 / L72）；
/// 非空 path 的 cache creation → `return None`（usage.mbt L96）
test "internal usage - missing token fields return None" {
  // path 第二层起即缺失 → 循环内提前返回 None
  assert_true(
    @internal.parse_reasoning_tokens(usage_parse("{\"usage\":{}}"), [
      "usage", "completion_tokens_details", "reasoning_tokens",
    ])
    is None,
  )
  assert_true(
    @internal.parse_reasoning_tokens(usage_parse("{}"), ["a", "b"]) is None,
  )
  assert_true(
    @internal.parse_cached_tokens(usage_parse("{\"usage\":{}}"), [
      "usage", "prompt_tokens_details", "cached_tokens",
    ])
    is None,
  )
  assert_true(
    @internal.parse_cached_tokens(usage_parse("{}"), ["a", "b"]) is None,
  )

  // 字段存在但目标键缺失 → None（非循环内路径）
  assert_true(
    @internal.parse_reasoning_tokens(
      usage_parse("{\"completion_tokens_details\":{\"other\":1}}"),
      ["completion_tokens_details"],
    )
    is None,
  )

  // 非空 path 表示 OpenAI/Gemini 形态，无 cache creation 概念 → None
  assert_true(
    @internal.parse_cache_creation_tokens(
      usage_parse("{\"cache_creation_input_tokens\":7}"),
      ["completion_tokens_details"],
    )
    is None,
  )
}

///|
/// === 各形态正路径 ===
/// OpenAI / Anthropic / Gemini 三种 usage 字段形态
test "internal usage - reads present token fields" {
  // tt_key 为 None → total = pt + ct
  assert_eq(
    @internal.parse_usage_json(
      usage_parse("{\"input_tokens\":3,\"output_tokens\":4}"),
      "input_tokens",
      "output_tokens",
      None,
    ),
    (3, 4, 7),
  )

  // tt_key 存在 → 直接读取
  assert_eq(
    @internal.parse_usage_json(
      usage_parse(
        "{\"prompt_tokens\":1,\"completion_tokens\":2,\"total_tokens\":9}",
      ),
      "prompt_tokens",
      "completion_tokens",
      Some("total_tokens"),
    ),
    (1, 2, 9),
  )

  // 字段缺失 → 0 / 计算值
  assert_eq(
    @internal.parse_usage_json(
      usage_parse("{}"),
      "prompt_tokens",
      "completion_tokens",
      None,
    ),
    (0, 0, 0),
  )

  // OpenAI 形态：completion_tokens_details.reasoning_tokens
  assert_eq(
    @internal.parse_reasoning_tokens(
      usage_parse("{\"completion_tokens_details\":{\"reasoning_tokens\":12}}"),
      ["completion_tokens_details"],
    ),
    Some(12),
  )

  // Gemini 形态：path 为空 → 顶层 thoughtsTokenCount
  assert_eq(
    @internal.parse_reasoning_tokens(
      usage_parse("{\"thoughtsTokenCount\":5}"),
      [],
    ),
    Some(5),
  )

  // OpenAI 形态：prompt_tokens_details.cached_tokens
  assert_eq(
    @internal.parse_cached_tokens(
      usage_parse("{\"prompt_tokens_details\":{\"cached_tokens\":8}}"),
      ["prompt_tokens_details"],
    ),
    Some(8),
  )

  // Anthropic 形态：path 为空 → 顶层 cache_read_input_tokens
  assert_eq(
    @internal.parse_cached_tokens(
      usage_parse("{\"cache_read_input_tokens\":6}"),
      [],
    ),
    Some(6),
  )

  // Anthropic 形态：path 为空 → 顶层 cache_creation_input_tokens
  assert_eq(
    @internal.parse_cache_creation_tokens(
      usage_parse("{\"cache_creation_input_tokens\":7}"),
      [],
    ),
    Some(7),
  )

  // Gemini 形态：cachedContentTokenCount
  assert_eq(
    @internal.parse_cached_tokens_gemini(
      usage_parse("{\"cachedContentTokenCount\":4}"),
    ),
    Some(4),
  )
}
