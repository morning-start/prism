///|
/// ═══ 功能组：stream codec session（流式编解码跨帧会话）═══
///
/// 背景（P0/P1 修复）：provider 的流式编解码是"整批"纯函数——跨帧状态
/// （块→输出索引映射、跨帧累积的工具参数、当前打开的块）保存在**函数局部
/// 变量**里。整批调用（一次传入整条事件数组）时这些状态自然存活，逐帧调用
/// （StreamConverter 每帧调一次）时则每帧重新初始化，于是：
///   - responses 编码器在 BlockEnd 时查不到 block→item 映射与累积参数 →
///     工具块的 function_call_arguments.done 整体消失、item_id 退化为占位符；
///   - gemini 编码器丢失跨帧累积的工具参数 → `args:{}`；
///   - openai 解码器丢失 current_tool_block → 工具索引切换时不再先闭合旧块，
///     改由规整器在 Finish 处逆序补闭合 → content_block_stop 顺序与整批不一致。
///
/// 本文件提供**会话载体**：provider 用工厂闭包捕获自己的可变状态，把
/// 「同一份实现」同时暴露给整批路径（一次 encode 全部）与增量路径（每帧
/// encode 一次）。两条路径因此共享同一套跨帧状态机，逐帧输出与整批输出
/// 一致性由构造保证，而非靠两套实现互相对齐。
///
/// 生命周期：
///   - `LucentStreamEncoder`：工厂 → 会话对象，`encode` 每次调用复用同一状态；
///     `finish` 在流结束时冲刷（如 gemini 未闭合的工具块）；
///     `set_ctx` 注入跨帧会话元信息（openai/responses 的 id/model/created）。
///   - `LucentStreamDecoder`：工厂 → 会话对象，`decode` 每次调用复用同一状态；
///     `finish` 在流结束时产出收尾事件（截断流闭合仍打开的块、空流兜底首帧）。

///|
/// 流式编码会话（跨帧状态由 provider 工厂闭包捕获）
pub struct LucentStreamEncoder {
  encode_events : (Array[LucentStreamEvent]) -> Result[
    ConversionResult[String],
    String,
  ]
  finish_stream : () -> Result[ConversionResult[String], String]
  apply_ctx : (LucentConversationMeta?) -> Unit
}

///|
/// 构造流式编码会话（provider 侧用工厂闭包捕获可变状态）
pub fn LucentStreamEncoder::new(
  encode_events : (Array[LucentStreamEvent]) -> Result[
    ConversionResult[String],
    String,
  ],
  finish_stream : () -> Result[ConversionResult[String], String],
  apply_ctx : (LucentConversationMeta?) -> Unit,
) -> LucentStreamEncoder {
  { encode_events, finish_stream, apply_ctx, }
}

///|
/// 编码一帧事件（复用会话内跨帧状态）
pub fn LucentStreamEncoder::encode(
  self : LucentStreamEncoder,
  events : Array[LucentStreamEvent],
) -> Result[ConversionResult[String], String] {
  (self.encode_events)(events)
}

///|
/// 流结束冲刷（编码器自身的未闭合状态，如 gemini 悬挂的工具块）
pub fn LucentStreamEncoder::finish(
  self : LucentStreamEncoder,
) -> Result[ConversionResult[String], String] {
  (self.finish_stream)()
}

///|
/// 注入跨帧会话元信息（逐帧转换时后续帧缺失 ConversationStart）
pub fn LucentStreamEncoder::set_ctx(
  self : LucentStreamEncoder,
  ctx : LucentConversationMeta?,
) -> Unit {
  (self.apply_ctx)(ctx)
}

///|
/// 流式解码会话（跨帧状态由 provider 工厂闭包捕获）
pub struct LucentStreamDecoder {
  decode_frame : (String) -> Result[
    ConversionResult[Array[LucentStreamEvent]],
    String,
  ]
  finish_stream : () -> Array[LucentStreamEvent]
}

///|
/// 构造流式解码会话（provider 侧用工厂闭包捕获可变状态）
pub fn LucentStreamDecoder::new(
  decode_frame : (String) -> Result[
    ConversionResult[Array[LucentStreamEvent]],
    String,
  ],
  finish_stream : () -> Array[LucentStreamEvent],
) -> LucentStreamDecoder {
  { decode_frame, finish_stream, }
}

///|
/// 解码一帧 SSE（复用会话内跨帧状态）
pub fn LucentStreamDecoder::decode(
  self : LucentStreamDecoder,
  sse_str : String,
) -> Result[ConversionResult[Array[LucentStreamEvent]], String] {
  (self.decode_frame)(sse_str)
}

///|
/// 流结束收尾事件（截断流闭合仍打开的块；空流兜底首帧）
pub fn LucentStreamDecoder::finish(
  self : LucentStreamDecoder,
) -> Array[LucentStreamEvent] {
  (self.finish_stream)()
}
