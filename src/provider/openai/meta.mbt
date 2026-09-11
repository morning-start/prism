///|
/// OpenAI Chat Completions 的 provider 元数据唯一入口。
///
/// 约束值与 `src/sdk/schema.mbt::ProviderSchema::openai()` 保持一致；
/// SDK registry 只从这里取元数据接线 codec，不再重复字段字面量。

///|
pub fn metadata() -> @meta.ProviderMeta {
  @meta.ProviderMeta::new(
    "openai",
    ["chat"],
    "gpt-*,o*",
    capability(),
    schema(),
  )
}

///|
/// OpenAI 家族（Chat Completions / Responses）共享的字段约束。
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
