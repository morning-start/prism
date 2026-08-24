///|
/// Prism — 协议无关的 LLM API 统一适配层
///
/// 端用户入口：`use morning-start/prism`
///
/// 将 SDK 层的核心类型提升到根包，用户无需了解内部子包结构即可使用：
///
/// ```moonbit
/// let p = Prism::new().with_provider("openai")
/// let json = p.encode_request("Hello", PrismOptions::default())
/// ```

///|
/// Prism 主实例
pub type Prism = @sdk.Prism

///|
/// Prism 请求选项
pub type PrismOptions = @sdk.PrismOptions

///|
/// 流式事件类型
pub type PrismEvent = @sdk.PrismEvent

///|
/// 工具调用
pub type PrismToolCall = @sdk.PrismToolCall

///|
/// 工具结果
pub type PrismToolResult = @sdk.PrismToolResult

///|
/// 推理内容
pub type PrismThinking = @sdk.PrismThinking

///|
/// 结束原因
pub type PrismFinishReason = @sdk.PrismFinishReason
