///|
/// provider/meta 黑盒测试 — 仅通过公开 API 验证 descriptor 与校验行为
///
/// 该包是 provider 元数据的公共叶子包：provider 身份、能力与 schema 约束
/// 都从这里出发，因此这里同时验证「getter 正确」和「校验真的会报错」。

///|
/// 构造被测 schema：temperature ∈ [0,1]、response 至少 1 个 choice、支持工具。
fn test_schema() -> @meta.ProviderSchema {
  @meta.ProviderSchema::new(
    "test",
    @meta.FieldConstraint::range(0.0, 1.0),
    @meta.FieldConstraint::any(),
    @meta.FieldConstraint::any(),
    @meta.FieldConstraint::min(1.0),
    1,
    true,
    true,
    None,
    None,
  )
}

///|
fn test_capability() -> @lux.ProviderCapability {
  @lux.ProviderCapability::new(
    "test-*",
    "test",
    @lux.LucentCapabilities::create(
      Full,
      Absent,
      Full,
      Full,
      Full,
      [Text, Image],
      [Text],
    ),
    None,
  )
}

///|
fn test_meta() -> @meta.ProviderMeta {
  @meta.ProviderMeta::new(
    "test",
    ["t"],
    "test-*",
    test_capability(),
    test_schema(),
  )
}

///|
/// errors 中任一条包含 needle 即视为命中。
///
/// 注意：`@lux.LucentRequest::validate()` 自身也会对 temperature 做通用校验，
/// 因此 provider 级错误不一定排在首位。
fn has_error(errors : Array[String], needle : String) -> Bool {
  let mut i = 0
  while i < errors.length() {
    if errors[i].contains(needle) {
      return true
    }
    i = i + 1
  }
  false
}

///|
/// 带指定 temperature 的最小可用请求。
fn req_with_temperature(temperature : Double?) -> @lux.LucentRequest {
  @lux.LucentRequest::from_messages(
    "test-model",
    None,
    [@lux.LucentMessage::new(User, [@lux.LucentContent::text("hi")])],
    None,
    None,
    @lux.LucentOptions::new(
      temperature,
      None,
      None,
      None,
      None,
      false,
      None,
      None,
      None,
      None,
    ),
    None,
    None,
    None,
    None,
  )
}

///|
fn one_choice_response() -> @lux.LucentResponse {
  @lux.LucentResponse::new(
    "resp-1",
    "test-model",
    None,
    [
      @lux.LucentChoice::new(
        0,
        @lux.LucentMessage::new(Assistant, [@lux.LucentContent::text("ok")]),
        Stop,
        None,
      ),
    ],
    None,
    None,
  )
}

///|
/// === descriptor getter ===

///|
test "descriptor - meta accessors" {
  let meta = test_meta()
  assert_eq(meta.name(), "test")
  assert_eq(meta.aliases(), ["t"])
  assert_eq(meta.model_pattern(), "test-*")
  assert_eq(meta.capability(), test_capability())
  assert_eq(meta.schema().provider_name(), "test")
}

///|
test "descriptor - schema field accessors" {
  let schema = test_schema()
  assert_eq(schema.resp_min_choices(), 1)
  assert_true(schema.supports_tools())
  assert_true(schema.supports_system_instruction())
  assert_true(schema.supported_reasoning_efforts() is None)
  assert_eq(schema.temperature().min_bound(), Some(0.0))
  assert_eq(schema.temperature().max_bound(), Some(1.0))
  assert_eq(schema.max_output_tokens().min_bound(), Some(1.0))
  assert_eq(schema.top_p().min_bound(), None)
}

///|
/// === FieldConstraint 语义 ===

///|
test "FieldConstraint - bounded constructors are optional by default" {
  assert_false(@meta.FieldConstraint::any().is_required())
  assert_false(@meta.FieldConstraint::range(0.0, 1.0).is_required())
  assert_false(@meta.FieldConstraint::min(1.0).is_required())
  assert_false(@meta.FieldConstraint::max(1.0).is_required())
  assert_true(@meta.FieldConstraint::any_required().is_required())
  assert_true(@meta.FieldConstraint::range_required(0.0, 1.0).is_required())
  assert_true(@meta.FieldConstraint::min_required(1.0).is_required())
}

///|
test "FieldConstraint - one_of carries allowed values" {
  let fc = @meta.FieldConstraint::one_of(["low", "high"])
  assert_eq(fc.allowed(), Some(["low", "high"]))
  assert_false(fc.is_required())
}

///|
/// === validate_request ===

///|
test "validate_request - accepts in-range temperature" {
  let errors = test_schema().validate_request(req_with_temperature(Some(0.5)))
  assert_eq(errors.length(), 0)
}

///|
test "validate_request - rejects temperature above max" {
  let errors = test_schema().validate_request(req_with_temperature(Some(1.5)))
  assert_true(has_error(errors, "temperature must be <= 1"))
}

///|
test "validate_request - rejects temperature below min" {
  let errors = test_schema().validate_request(req_with_temperature(Some(-0.5)))
  assert_true(has_error(errors, "temperature must be >= 0"))
}

///|
test "validate_request - optional temperature may be absent" {
  let errors = test_schema().validate_request(req_with_temperature(None))
  assert_eq(errors.length(), 0)
}

///|
test "validate_request - required temperature must be present" {
  let required_schema = @meta.ProviderSchema::new(
    "test",
    @meta.FieldConstraint::range_required(0.0, 1.0),
    @meta.FieldConstraint::any(),
    @meta.FieldConstraint::any(),
    @meta.FieldConstraint::any(),
    1,
    true,
    true,
    None,
    None,
  )
  let errors = required_schema.validate_request(req_with_temperature(None))
  assert_true(has_error(errors, "temperature is required"))
}

///|
test "validate_request - tools rejected when provider declares no tool support" {
  let no_tools_schema = @meta.ProviderSchema::new(
    "test",
    @meta.FieldConstraint::any(),
    @meta.FieldConstraint::any(),
    @meta.FieldConstraint::any(),
    @meta.FieldConstraint::any(),
    1,
    false,
    true,
    None,
    None,
  )
  let tools_req = @lux.LucentRequest::from_messages(
    "test-model",
    None,
    [@lux.LucentMessage::new(User, [@lux.LucentContent::text("hi")])],
    Some([@lux.LucentTool::simple("ping", "ping", "{\"type\":\"object\"}")]),
    None,
    @lux.LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
  let errors = no_tools_schema.validate_request(tools_req)
  assert_true(has_error(errors, "does not support tools"))
}

///|
test "validate_request - model is required" {
  let no_model = @lux.LucentRequest::from_messages(
    "",
    None,
    [@lux.LucentMessage::new(User, [@lux.LucentContent::text("hi")])],
    None,
    None,
    @lux.LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
  let errors = test_schema().validate_request(no_model)
  assert_true(errors.length() > 0)
}

///|
/// === validate_response ===

///|
test "validate_response - accepts response with enough choices" {
  let errors = test_schema().validate_response(one_choice_response())
  assert_eq(errors.length(), 0)
}

///|
test "validate_response - rejects response with too few choices" {
  let strict_schema = @meta.ProviderSchema::new(
    "test",
    @meta.FieldConstraint::any(),
    @meta.FieldConstraint::any(),
    @meta.FieldConstraint::any(),
    @meta.FieldConstraint::any(),
    2,
    true,
    true,
    None,
    None,
  )
  let errors = strict_schema.validate_response(one_choice_response())
  assert_true(has_error(errors, "at least 2 choice(s)"))
}

///|
/// 宽松字段约束：可选、无上下界、无枚举限制。
///
/// 语义与 `any()` 完全相同，用 `any_optional()` 顺带覆盖其委派路径。
fn fc_any() -> @meta.FieldConstraint {
  @meta.FieldConstraint::any_optional()
}

///|
/// schema_for — 只指定四个请求字段约束，其余 schema 字段取宽松默认值
/// （resp_min_choices=1、支持工具、支持 system 指令、无 reasoning 限制）。
fn schema_for(
  temperature : @meta.FieldConstraint,
  top_p : @meta.FieldConstraint,
  top_k : @meta.FieldConstraint,
  max_output_tokens : @meta.FieldConstraint,
) -> @meta.ProviderSchema {
  @meta.ProviderSchema::new(
    "prov",
    temperature,
    top_p,
    top_k,
    max_output_tokens,
    1,
    true,
    true,
    None,
    None,
  )
}

///|
/// req_with — 带指定 temperature / top_p / top_k / max_output_tokens 的最小可用请求。
fn req_with(
  temperature : Double?,
  top_p : Double?,
  top_k : Int?,
  max_output_tokens : Int?,
) -> @lux.LucentRequest {
  @lux.LucentRequest::from_messages(
    "prov-model",
    None,
    [@lux.LucentMessage::new(User, [@lux.LucentContent::text("hi")])],
    None,
    None,
    @lux.LucentOptions::new(
      temperature,
      top_p,
      top_k,
      max_output_tokens,
      None,
      false,
      None,
      None,
      None,
      None,
    ),
    None,
    None,
    None,
    None,
  )
}

///|
/// validate_request — 四个可调字段各自的「下界越界 / 上界越界 / 边界内 / 边界缺失 /
/// 必填缺失」矩阵，外加 tools 缺失分支与 extra_checks 自定义校验分支。
///
/// needle 为空串表示该用例期望零错误；否则期望某条错误包含 needle。
/// needle 一律带 "prov " 前缀，避免与 `LucentRequest::validate` 的通用错误
/// （如 "top_p must be in [0, 1]"）混淆。
test "meta validate_request - per-field constraint matrix" {
  assert_false(@meta.FieldConstraint::any_optional().is_required())

  let t_min = 0.5
  let t_max = 0.75
  let p_min = 0.3
  let p_max = 0.7
  let k_min = 4.0
  let m_min = 8.0
  let extra_checks : Array[() -> Array[String]] = [
    fn() -> Array[String] { ["prov extra check rejected: unsupported model"] },
    fn() -> Array[String] { [] },
  ]
  let cases : Array[(String, @meta.ProviderSchema, @lux.LucentRequest, String)] = [
    // ── temperature：min 越界 / max 越界 / 边界内
    (
      "temperature below min",
      schema_for(
        @meta.FieldConstraint::min(t_min),
        fc_any(),
        fc_any(),
        fc_any(),
      ),
      req_with(Some(0.25), None, None, None),
      "prov temperature must be >= " + t_min.to_string(),
    ),
    (
      "temperature above max",
      schema_for(
        @meta.FieldConstraint::max(t_max),
        fc_any(),
        fc_any(),
        fc_any(),
      ),
      req_with(Some(0.9), None, None, None),
      "prov temperature must be <= " + t_max.to_string(),
    ),
    (
      "temperature at min bound",
      schema_for(
        @meta.FieldConstraint::min(t_min),
        fc_any(),
        fc_any(),
        fc_any(),
      ),
      req_with(Some(t_min), None, None, None),
      "",
    ),
    // ── temperature：min / max 边界缺失但有取值（None => () 分支）
    (
      "temperature without min bound",
      schema_for(
        @meta.FieldConstraint::max(t_max),
        fc_any(),
        fc_any(),
        fc_any(),
      ),
      req_with(Some(0.5), None, None, None),
      "",
    ),
    (
      "temperature without max bound",
      schema_for(
        @meta.FieldConstraint::min(t_min),
        fc_any(),
        fc_any(),
        fc_any(),
      ),
      req_with(Some(0.75), None, None, None),
      "",
    ),
    (
      "temperature with no bound at all",
      schema_for(fc_any(), fc_any(), fc_any(), fc_any()),
      req_with(Some(0.5), None, None, None),
      "",
    ),
    // ── temperature：必填但缺失
    (
      "temperature required but absent",
      schema_for(
        @meta.FieldConstraint::range_required(0.0, 1.0),
        fc_any(),
        fc_any(),
        fc_any(),
      ),
      req_with(None, None, None, None),
      "prov temperature is required",
    ),
    // ── top_p：min 越界 / max 越界 / 边界内
    (
      "top_p below min",
      schema_for(
        fc_any(),
        @meta.FieldConstraint::min(p_min),
        fc_any(),
        fc_any(),
      ),
      req_with(None, Some(0.1), None, None),
      "prov top_p must be >= " + p_min.to_string(),
    ),
    (
      "top_p above max",
      schema_for(
        fc_any(),
        @meta.FieldConstraint::max(p_max),
        fc_any(),
        fc_any(),
      ),
      req_with(None, Some(0.9), None, None),
      "prov top_p must be <= " + p_max.to_string(),
    ),
    (
      "top_p at min bound",
      schema_for(
        fc_any(),
        @meta.FieldConstraint::min(p_min),
        fc_any(),
        fc_any(),
      ),
      req_with(None, Some(p_min), None, None),
      "",
    ),
    // ── top_p：min / max 边界缺失但有取值（None => () 分支）
    (
      "top_p without min bound",
      schema_for(
        fc_any(),
        @meta.FieldConstraint::max(p_max),
        fc_any(),
        fc_any(),
      ),
      req_with(None, Some(0.5), None, None),
      "",
    ),
    (
      "top_p without max bound",
      schema_for(
        fc_any(),
        @meta.FieldConstraint::min(p_min),
        fc_any(),
        fc_any(),
      ),
      req_with(None, Some(0.5), None, None),
      "",
    ),
    (
      "top_p with no bound at all",
      schema_for(fc_any(), fc_any(), fc_any(), fc_any()),
      req_with(None, Some(0.5), None, None),
      "",
    ),
    // ── top_p：必填但缺失
    (
      "top_p required but absent",
      schema_for(
        fc_any(),
        @meta.FieldConstraint::any_required(),
        fc_any(),
        fc_any(),
      ),
      req_with(None, None, None, None),
      "prov top_p is required",
    ),
    // ── top_k：min 越界 / 边界内 / 边界缺失 / 必填缺失
    (
      "top_k below min",
      schema_for(
        fc_any(),
        fc_any(),
        @meta.FieldConstraint::min(k_min),
        fc_any(),
      ),
      req_with(None, None, Some(1), None),
      "prov top_k must be >= " + k_min.to_string(),
    ),
    (
      "top_k at min bound",
      schema_for(
        fc_any(),
        fc_any(),
        @meta.FieldConstraint::min(k_min),
        fc_any(),
      ),
      req_with(None, None, Some(k_min.to_int()), None),
      "",
    ),
    (
      "top_k without min bound",
      schema_for(fc_any(), fc_any(), fc_any(), fc_any()),
      req_with(None, None, Some(4), None),
      "",
    ),
    (
      "top_k required but absent",
      schema_for(
        fc_any(),
        fc_any(),
        @meta.FieldConstraint::any_required(),
        fc_any(),
      ),
      req_with(None, None, None, None),
      "prov top_k is required",
    ),
    // ── max_output_tokens：min 越界 / 边界内 / 边界缺失 / 必填缺失
    (
      "max_output_tokens below min",
      schema_for(
        fc_any(),
        fc_any(),
        fc_any(),
        @meta.FieldConstraint::min(m_min),
      ),
      req_with(None, None, None, Some(1)),
      "prov max_output_tokens must be >= " + m_min.to_string(),
    ),
    (
      "max_output_tokens at min bound",
      schema_for(
        fc_any(),
        fc_any(),
        fc_any(),
        @meta.FieldConstraint::min(m_min),
      ),
      req_with(None, None, None, Some(m_min.to_int())),
      "",
    ),
    (
      "max_output_tokens without min bound",
      schema_for(fc_any(), fc_any(), fc_any(), fc_any()),
      req_with(None, None, None, Some(16)),
      "",
    ),
    (
      "max_output_tokens required but absent",
      schema_for(
        fc_any(),
        fc_any(),
        fc_any(),
        @meta.FieldConstraint::any_required(),
      ),
      req_with(None, None, None, None),
      "prov max_output_tokens is required",
    ),
    // ── tools：provider 不支持工具，但请求本身没带工具 → 不报错
    (
      "tools absent is fine without tool support",
      @meta.ProviderSchema::new(
        "prov",
        fc_any(),
        fc_any(),
        fc_any(),
        fc_any(),
        1,
        false,
        true,
        None,
        None,
      ),
      req_with(None, None, None, None),
      "",
    ),
    // ── extra_checks：自定义校验逐条执行，报错项进入 errors
    (
      "extra checks run and surface their errors",
      @meta.ProviderSchema::new(
        "prov",
        fc_any(),
        fc_any(),
        fc_any(),
        fc_any(),
        1,
        true,
        true,
        None,
        Some(extra_checks),
      ),
      req_with(None, None, None, None),
      "prov extra check rejected: unsupported model",
    ),
  ]
  for case in cases {
    let name = case.0
    let schema = case.1
    let req = case.2
    let needle = case.3
    let errors = schema.validate_request(req)
    if needle == "" {
      if errors.length() > 0 {
        fail(name + ": expected no errors, got " + errors.length().to_string())
      }
    } else if !has_error(errors, needle) {
      fail(name + ": expected error containing \"" + needle + "\"")
    }
  }
}

///|
/// validate_response — `LucentResponse::validate()` 的通用错误也要并入返回列表
/// （response id 缺失 → "response id is required"）。
test "meta validate_response - base validation errors are surfaced" {
  let broken = @lux.LucentResponse::new(
    "",
    "prov-model",
    None,
    [
      @lux.LucentChoice::new(
        0,
        @lux.LucentMessage::new(Assistant, [@lux.LucentContent::text("ok")]),
        Stop,
        None,
      ),
    ],
    None,
    None,
  )
  let errors = schema_for(fc_any(), fc_any(), fc_any(), fc_any()).validate_response(
    broken,
  )
  assert_true(has_error(errors, "response id is required"))
}
