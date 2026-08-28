///|
/// capability — 适配器能力声明
pub fn capability() -> @lux.ProviderCapability {
  @lux.ProviderCapability::new(
    "gpt-*,o*",
    "openai",
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
