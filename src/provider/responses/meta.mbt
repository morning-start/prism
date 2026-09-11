///|
/// OpenAI Responses 的 provider 元数据唯一入口。
///
/// Responses 与 Chat Completions 同属 OpenAI 家族，字段约束完全一致，
/// 因此 schema 的 `provider_name` 保持 `"openai"`（与
/// `sdk.get_schema("responses").provider_name == "openai"` 的既有契约一致），
/// 仅注册名与别名不同。

///|
pub fn metadata() -> @meta.ProviderMeta {
  @meta.ProviderMeta::new(
    "responses",
    ["openai-responses"],
    "gpt-*,o*",
    capability(),
    schema(),
  )
}

///|
/// Responses 复用 OpenAI 家族约束（与 `openai/schema()` 同值）。
pub fn schema() -> @meta.ProviderSchema {
  @meta.ProviderSchema::new(
    "openai",
    @meta.FieldConstraint::range(0.0, 2.0),
    @meta.FieldConstraint::range(0.0, 1.0),
    @meta.FieldConstraint::any(),
    @meta.FieldConstraint::min(1.0),
    1,
    true,
    true,
    None,
    None,
  )
}
