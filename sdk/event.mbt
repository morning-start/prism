///|
/// PrismEvent — 流式事件类型（L2 框架作者看到的 5 种语义单位）
///
/// 框架作者只需要 match 这 5 种事件，所有协议差异由 SDK 内部消化。

///|
/// PrismToolCall — 工具调用
pub struct PrismToolCall {
  id : String
  name : String
  arguments_json : String
}

///|
/// PrismToolResult — 工具结果
pub struct PrismToolResult {
  tool_use_id : String
  content : String
  is_error : Bool
}

///|
/// PrismThinking — 推理内容
pub struct PrismThinking {
  text : String
  signature : String?
  redacted : Bool
}

///|
/// PrismFinishReason — 结束原因
pub(all) enum PrismFinishReason {
  Stop
  Length
  ToolCalls
  ContentFilter
  Error
}

///|
/// PrismEvent — 流事件枚举
pub(all) enum PrismEvent {
  /// 文本增量（追加到当前输出）
  TextDelta(String)
  /// 工具调用（中断循环，执行工具，注入结果）
  ToolCall(PrismToolCall)
  /// 工具结果（追加到上下文）
  ToolResult(PrismToolResult)
  /// 推理过程（可展示 UI 或忽略）
  Thinking(PrismThinking)
  /// 本轮结束
  Finish(PrismFinishReason)
}
