///|
/// capability — 适配器能力声明
///
/// parallel_tool_calls 曾声明为 `Absent`，但 Chat Completions 原生支持
/// `parallel_tool_calls` 请求参数（多 tool_calls 响应），encode/decode 均按
/// 多 tool_calls 处理，因此声明修正为 `Full`（消除声明漂移）。
pub fn capability() -> @lux.ProviderCapability {
  @lux.ProviderCapability::new(
    "gpt-*,o*",
    "openai",
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
