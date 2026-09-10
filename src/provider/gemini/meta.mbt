import {
  "morning-start/prism/provider/meta",
  "morning-start/prism/provider/gemini",
}

pub fn metadata() -> @meta.ProviderMeta {
  let capability = @gemini.capability()
  let schema = @meta.ProviderSchema::new(
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
  @meta.ProviderMeta::new(
    "gemini",
    ["google"],
    "gemini-*",
    capability,
    schema,
  )
}
