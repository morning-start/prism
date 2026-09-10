import {
  "morning-start/prism/provider/meta",
  "morning-start/prism/provider/messages",
}

pub fn metadata() -> @meta.ProviderMeta {
  let capability = @messages.capability()
  let schema = @meta.ProviderSchema::new(
    "messages",
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
    "messages",
    ["claude-messages", "anthropic"],
    "claude-*",
    capability,
    schema,
  )
}
