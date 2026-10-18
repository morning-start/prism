///|
/// ProviderSchema 自定义约束分支覆盖（白盒：schema.mbt 字段包内可见）
///
/// 内置 schema（openai/anthropic/gemini）的 min_val / max_val 恒为 Some，
/// required 恒为 false，extra_checks 恒为 None —— 因此以下分支在黑盒路径下
/// 不可达，只能用自定义约束触达：
/// - min_val / max_val 为 None 时不校验（L233 / L246 / L264 / L273 / L304）
/// - temperature required=true 时报缺失（L251）
/// - extra_checks 自定义校验函数列表（L312）

///|
/// 构造一个最小合法请求（仅 model + 一条 user 文本消息）
fn cov_min_request(opts : @lux.LucentOptions) -> @lux.LucentRequest {
  @lux.LucentRequest::new(
    "m",
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
}

///|
test "schema wb - unconstrained fields skip min/max checks" {
  // 全部约束 min/max 为 None：任何取值都不产生错误
  let schema : ProviderSchema = {
    provider_name: "custom",
    temperature: {
      min_val: None,
      max_val: None,
      required: false,
      allowed_values: None,
    },
    top_p: {
      min_val: None,
      max_val: None,
      required: false,
      allowed_values: None,
    },
    top_k: {
      min_val: None,
      max_val: None,
      required: false,
      allowed_values: None,
    },
    max_output_tokens: {
      min_val: None,
      max_val: None,
      required: false,
      allowed_values: None,
    },
    resp_min_choices: 1,
    supports_tools: true,
    supports_system_instruction: true,
    supported_reasoning_efforts: None,
    extra_checks: None,
  }
  // 取值在通用校验区间内（避免 req.validate 的通用错误），
  // 但对本自定义 schema 而言这些值「本应越界」——因 min/max 为 None 而放行。
  // 若 None 分支未正确短路，会多出 temperature/top_p/top_k 错误。
  let opts = @lux.LucentOptions::new(
    Some(2.0),
    Some(1.0),
    Some(1),
    Some(1),
    None,
    false,
    None,
    None,
    None,
    None,
  )
  let errors = schema.validate_request(cov_min_request(opts))
  // 自定义 schema 的 min/max 全为 None → 不产生字段约束错误
  let mut constraint_errs = 0
  for e in errors {
    if e.contains("temperature") || e.contains("top_p") || e.contains("top_k") {
      constraint_errs = constraint_errs + 1
    }
  }
  assert_eq(constraint_errs, 0)
}

///|
test "schema wb - required temperature reports missing value" {
  // required=true + temperature 缺失（None）→ 报错
  let schema : ProviderSchema = {
    provider_name: "custom",
    temperature: {
      min_val: None,
      max_val: None,
      required: true,
      allowed_values: None,
    },
    top_p: {
      min_val: None,
      max_val: None,
      required: false,
      allowed_values: None,
    },
    top_k: {
      min_val: None,
      max_val: None,
      required: false,
      allowed_values: None,
    },
    max_output_tokens: {
      min_val: None,
      max_val: None,
      required: false,
      allowed_values: None,
    },
    resp_min_choices: 1,
    supports_tools: true,
    supports_system_instruction: true,
    supported_reasoning_efforts: None,
    extra_checks: None,
  }
  // temperature 未设置 → required 分支报错
  let errors = schema.validate_request(
    cov_min_request(@lux.LucentOptions::default()),
  )
  let mut found = false
  for e in errors {
    if e.contains("temperature is required") {
      found = true
    }
  }
  assert_true(found)
}

///|
test "schema wb - extra_checks run and contribute errors" {
  // extra_checks 存在 → 逐个调用并把返回的错误并入结果
  let schema : ProviderSchema = {
    provider_name: "custom",
    temperature: {
      min_val: None,
      max_val: None,
      required: false,
      allowed_values: None,
    },
    top_p: {
      min_val: None,
      max_val: None,
      required: false,
      allowed_values: None,
    },
    top_k: {
      min_val: None,
      max_val: None,
      required: false,
      allowed_values: None,
    },
    max_output_tokens: {
      min_val: None,
      max_val: None,
      required: false,
      allowed_values: None,
    },
    resp_min_choices: 1,
    supports_tools: true,
    supports_system_instruction: true,
    supported_reasoning_efforts: None,
    extra_checks: Some([fn() { ["tenant quota exceeded"] }, fn() { [] }]),
  }
  let errors = schema.validate_request(
    cov_min_request(@lux.LucentOptions::default()),
  )
  let mut found = false
  for e in errors {
    if e == "tenant quota exceeded" {
      found = true
    }
  }
  assert_true(found)
}
