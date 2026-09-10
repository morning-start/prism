import {
  "morning-start/prism/provider/meta",
}

pub fn main() -> Unit {
  let schema = @meta.ProviderSchema::new(
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
  let meta = @meta.ProviderMeta::new(
    "test",
    ["t"],
    "test-*",
    @lux.ProviderCapability::new("test", "test-*", []),
    schema,
  )
  assert_eq(meta.name(), "test")
  assert_eq(meta.aliases(), ["t"])
  assert_eq(meta.model_pattern(), "test-*")
  assert_eq(meta.schema().provider_name(), "test")
}
