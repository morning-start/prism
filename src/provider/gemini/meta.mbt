///|
/// Google Gemini (REST) 的 provider 元数据唯一入口。
///
/// 约束值与 `src/sdk/schema.mbt::ProviderSchema::gemini()` 保持一致。

///|
pub fn metadata() -> @meta.ProviderMeta {
  @meta.ProviderMeta::new(
    "gemini",
    ["google"],
    "gemini-*",
    capability(),
    schema(),
  )
}

///|
/// Gemini 字段约束（保留 `provider_name = "gemini"` 的既有契约）。
pub fn schema() -> @meta.ProviderSchema {
  @meta.ProviderSchema::new(
    "gemini",
    @meta.FieldConstraint::range(0.0, 1.0),
    @meta.FieldConstraint::range(0.0, 1.0),
    @meta.FieldConstraint::min(1.0),
    @meta.FieldConstraint::min(1.0),
    1,
    true,
    true,
    None,
    None,
  )
}
