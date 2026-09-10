import {
  "morning-start/prism/provider/meta",
  "morning-start/prism/provider/responses",
}

pub fn metadata() -> @meta.ProviderMeta {
  let capability = @responses.capability()
  let schema = @meta.ProviderSchema::new(
    "responses",
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
    "responses",
    ["openai-responses"],
    "gpt-*,o*",
    capability,
    schema,
  )
}
