import {
  "morning-start/prism/provider/meta",
  "morning-start/prism/provider/openai",
}

pub fn metadata() -> @meta.ProviderMeta {
  let capability = @openai.capability()
  let schema = @meta.ProviderSchema::new(
    "openai",
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
  @meta.ProviderMeta::new(
    "openai",
    ["chat"],
    "gpt-*,o*",
    capability,
    schema,
  )
}
