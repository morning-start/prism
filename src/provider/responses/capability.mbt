///|
/// capability — 适配器能力声明
///
/// parallel_tool_calls 曾声明为 `Absent`，但 Responses 原生支持
/// `parallel_tool_calls` 请求参数（官方 schema required 字段，多 function_call
/// 输出），encode/decode 均按多 tool 项处理，因此声明修正为 `Full`
/// （消除声明漂移）。
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
      [Text, Image, Pdf],
      [Text],
    ),
    None,
  )
}
