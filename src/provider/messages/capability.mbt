///|
/// capability — 适配器能力声明
///
/// parallel_tool_calls 曾声明为 `Absent`，但 Messages 原生支持并行工具调用
/// （`disable_parallel_tool_use` 默认 false 即允许并行，单条 assistant 消息
/// 可返回多个 tool_use 块），encode/decode 均按多 tool_use 处理，因此声明
/// 修正为 `Full`（消除声明漂移）。
pub fn capability() -> @lux.ProviderCapability {
  @lux.ProviderCapability::new(
    "claude-*",
    "messages",
    @lux.LucentCapabilities::create(
      Full,
      Full,
      Full,
      Full,
      Full,
      [Text, Image],
      [Text],
    ),
    None,
  )
}
