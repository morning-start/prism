///|
/// capability — 适配器能力声明
pub fn capability() -> @lux.ProviderCapability {
  @lux.ProviderCapability::new(
    "claude-*",
    "messages",
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
