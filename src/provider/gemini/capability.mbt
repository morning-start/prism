///|
/// capability — 适配器能力声明
///
/// parallel_tool_calls 曾声明为 `Absent`，但 Gemini 官方支持并行函数调用
/// （一条 model 消息里可返回多个 functionCall part），适配器解码/编码也都
/// 按多 functionCall 处理，因此声明修正为 `Full`（消除声明漂移）。
pub fn capability() -> @lux.ProviderCapability {
  @lux.ProviderCapability::new(
    "gemini-*",
    "google",
    @lux.LucentCapabilities::create(
      Full,
      Full,
      Full,
      Full,
      Full,
      [Text, Image, Audio, Video, Pdf],
      [Text],
    ),
    None,
  )
}
