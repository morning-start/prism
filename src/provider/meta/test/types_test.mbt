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
