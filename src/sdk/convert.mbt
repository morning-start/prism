///|
/// ═══ 功能组：convert（跨协议中转）═══
/// convert_request/response/stream 组合入口；管线实现见 codec_pipeline.mbt。

///|
/// convert_* 组合入口 — 中转站（场景 2）
///
/// 协议 A JSON/SSE → Lux IR → 协议 B JSON/SSE。
/// 实现 = source 解码 + target 编码，零新增转换逻辑，复用 ProviderRegistration 注册表。

///|
/// ConvertMetaResult — convert 结果：目标协议 JSON + 来源元信息（D8）
pub struct ConvertMetaResult {
  value : String
  meta : ConversionMeta
}

///|
pub fn ConvertMetaResult::new(
  value : String,
  meta : ConversionMeta,
) -> ConvertMetaResult {
  { value, meta, }
}

///|
pub fn ConvertMetaResult::value(self : ConvertMetaResult) -> String {
  self.value
}

///|
pub fn ConvertMetaResult::meta(self : ConvertMetaResult) -> ConversionMeta {
  self.meta
}

///|
/// 解析 source 和 target provider。
fn resolve_pair(
  source : String,
  target : String,
) -> Result[(ProviderRegistration, ProviderRegistration), String] {
  let src = match match_provider_name(source) {
    Some(reg) => reg
    None => return Err("unknown provider: " + source)
  }
  let dst = match match_provider_name(target) {
    Some(reg) => reg
    None => return Err("unknown provider: " + target)
  }
  Ok((src, dst))
}

///|
/// 响应转换（带来源元信息）：source 协议 JSON → target 协议 JSON。
pub fn convert_response_with_meta(
  source : String,
  json_str : String,
  target : String,
) -> Result[ConvertMetaResult, String] {
  match resolve_pair(source, target) {
    Ok((src, dst)) =>
      match (src.response_decode)(json_str) {
        Ok(dcr) =>
          match (dst.response_encode)(dcr.value()) {
            Ok(ecr) => {
              let merged = merge_diagnostics(ecr, dcr.diagnostics())
              let meta = ConversionMeta::new(
                src.name,
                merged.diagnostics(),
                dcr.value().provider_payload,
                None,
              )
              Ok(ConvertMetaResult::new(merged.value(), meta))
            }
            Err(e) => Err(e)
          }
        Err(e) => Err(e)
      }
    Err(e) => Err(e)
  }
}

///|
/// 请求：source 协议 JSON → target 协议 JSON（带诊断）
pub fn convert_request(
  source : String,
  json_str : String,
  target : String,
) -> Result[@lux.ConversionResult[String], String] {
  match resolve_pair(source, target) {
    Ok((src, dst)) =>
      decode_encode_request(json_str, src.request_decode, dst.request_encode)
    Err(e) => Err(e)
  }
}

///|
/// 响应：source 协议 JSON → target 协议 JSON（带诊断）
pub fn convert_response(
  source : String,
  json_str : String,
  target : String,
) -> Result[@lux.ConversionResult[String], String] {
  match resolve_pair(source, target) {
    Ok((src, dst)) =>
      decode_encode_response(json_str, src.response_decode, dst.response_encode)
    Err(e) => Err(e)
  }
}

///|
/// 流式：source 协议 SSE → target 协议 SSE（事件级转换，带诊断）
pub fn convert_stream(
  source : String,
  sse_str : String,
  target : String,
) -> Result[@lux.ConversionResult[String], String] {
  match resolve_pair(source, target) {
    Ok((src, dst)) =>
      decode_encode_stream(sse_str, src.events_decode, dst.events_encode)
    Err(e) => Err(e)
  }
}

///|
/// ═══ 类型化错误入口（T7）═══
/// 既有 String 错误 API 全部保留；以下入口把错误升级为 PrismError
/// （kind 供重试/熔断按类型匹配），成功路径与无类型版一致。

///|
/// 请求转换（类型化错误版）
pub fn convert_request_typed(
  source : String,
  json_str : String,
  target : String,
) -> Result[@lux.ConversionResult[String], PrismError] {
  match convert_request(source, json_str, target) {
    Ok(cr) => Ok(cr)
    Err(e) => Err(PrismError::from_string(e).with_provider(Some(source)))
  }
}

///|
/// 响应转换（类型化错误版）
pub fn convert_response_typed(
  source : String,
  json_str : String,
  target : String,
) -> Result[@lux.ConversionResult[String], PrismError] {
  match convert_response(source, json_str, target) {
    Ok(cr) => Ok(cr)
    Err(e) => Err(PrismError::from_string(e).with_provider(Some(source)))
  }
}

///|
/// 流转换（类型化错误版）
pub fn convert_stream_typed(
  source : String,
  sse_str : String,
  target : String,
) -> Result[@lux.ConversionResult[String], PrismError] {
  match convert_stream(source, sse_str, target) {
    Ok(cr) => Ok(cr)
    Err(e) => Err(PrismError::from_string(e).with_provider(Some(source)))
  }
}

///|
/// ═══ 增量流转换（T5，中间件逐帧转发）═══

///|
/// StreamConverter — 增量流转换会话
///
/// 场景 2（中转中间件）逐帧转发：host 持有会话对象，把上游 SSE chunk
/// 原样 feed 进来，立即取得目标协议 SSE 帧——TFTB 从"整条响应到达"
/// 降到"首帧到达"。
///
/// 帧边界由 @internal.SseFrameSplitter 处理（跨 chunk 半帧缓冲，
/// CRLF/CR/LF 归一化，含 \r|\n 切分边界）。每帧独立完成
/// source decode → IR → target encode；跨帧上下文（会话 id/model）
/// 由本会话跟踪，经 events_encode_with_ctx 传给需要它的编码器
/// （openai/responses），保证逐帧输出与整缓冲转换逐字节一致。
///
/// 用法：
/// ```moonbit nocheck
/// let conv = StreamConverter::new("openai", "messages")?
/// for chunk in upstream_chunks {
///   let frames = conv.feed(chunk)?   // 立即转发给下游
///   downstream.write(frames)
/// }
/// let tail = conv.finish()?          // 冲刷尾部半帧
/// ```
pub struct StreamConverter {
  source : ProviderRegistration
  target : ProviderRegistration
  splitter : @internal.SseFrameSplitter
  /// 跨帧解码侧规整器（块去重/Finish 去重/usage 回填/Done 丢弃），
  /// 与 Prism::stream_session 共享同一实现（event_stream.mbt）。
  normalizer : EventNormalizer
  /// Finish 帧保持：推迟一帧发射，让紧随其后的 Usage 帧并入同一次
  /// 编码（messages 编码器把 Finish+Usage 合并为单条 message_delta），
  /// 保证逐帧输出与整缓冲输出逐字节一致。
  mut held_events : Array[@lux.LucentStreamEvent]
  /// CR-002 D5：会话是否已收尾（`finish()` 幂等）。终止符由会话层唯一产生：
  /// 解码器在流中途发出的 Done 一律丢弃（Gemini 的帧级兜底 Done 会落在
  /// usage/内容之前），`finish()` 在最后补且仅补一个终止符。
  mut closed : Bool
}

///|
/// 创建增量转换会话（解析 source/target provider）
pub fn StreamConverter::new(
  source : String,
  target : String,
) -> Result[StreamConverter, String] {
  match resolve_pair(source, target) {
    Ok((src, dst)) =>
      Ok({
        source: src,
        target: dst,
        splitter: @internal.SseFrameSplitter::new(),
        normalizer: EventNormalizer::new(),
        held_events: [],
        closed: false,
      })
    Err(e) => Err(e)
  }
}

///|
/// 喂入一个上游 chunk，返回目标协议 SSE 帧数组（可能为空：半帧缓冲中）
pub fn StreamConverter::feed(
  self : StreamConverter,
  chunk : String,
) -> Result[Array[String], String] {
  self.convert_frames(self.splitter.feed(chunk))
}

///|
/// 流结束：冲刷尾部半帧（无结束空行的流）并转换，闭合仍打开的块，补终止符。
///
/// CR-002 D5：Done 由会话层唯一产生 —— 整场解码事件里的 Done 都在
/// `normalize_events` 被丢弃，终止符在这里补发一次（幂等：`closed` 之后重复调用
/// 只返回本次冲刷的帧）。
pub fn StreamConverter::finish(
  self : StreamConverter,
) -> Result[Array[String], String] {
  let frames = self.splitter.flush()
  let out = self.convert_frames(frames)
  match out {
    Ok(emitted) => {
      if self.closed {
        return Ok(emitted)
      }
      self.closed = true
      // 冲刷保持的 Finish 帧（无后续 Usage 帧时）
      let pending = self.held_events.copy()
      self.held_events = []
      // CR-002 A5：截断流（整场没有 Finish）仍打开的块在此闭合 —— 否则 messages
      // 目标会留下未闭合的 content_block。逆序闭合与整缓冲路径的栈语义一致。
      let mut k = self.normalizer.open_blocks.length() - 1
      while k >= 0 {
        pending.push(BlockEnd(self.normalizer.open_blocks[k]))
        k = k - 1
      }
      self.normalizer.open_blocks = []
      if pending.length() > 0 {
        match self.encode_events(pending) {
          Ok(sse) => if sse.trim().length() > 0 { emitted.push(sse) }
          Err(e) => return Err(e)
        }
      }
      // 终止符：会话唯一，且必定排在最后（其后不再有内容）
      let tail : Array[@lux.LucentStreamEvent] = [Done]
      match self.encode_events(tail) {
        Ok(sse) => if sse.trim().length() > 0 { emitted.push(sse) }
        Err(e) => return Err(e)
      }
      Ok(emitted)
    }
    Err(e) => Err(e)
  }
}

///|
/// 帧组转换：decode → 跨帧状态规整 → encode（ctx 感知）
fn StreamConverter::convert_frames(
  self : StreamConverter,
  frames : Array[String],
) -> Result[Array[String], String] {
  let out : Array[String] = []
  for frame in frames {
    match (self.source.events_decode)(frame) {
      Ok(dcr) => {
        let events = self.normalizer.normalize(dcr.value())
        // Finish 帧保持：与后续帧合并发射（usage 合并 + 字节一致）
        let combined : Array[@lux.LucentStreamEvent] = if self.held_events.length() >
          0 {
          let merged = self.held_events.copy()
          for ev in events {
            merged.push(ev)
          }
          self.held_events = []
          merged
        } else {
          events
        }
        if ends_with_finish(combined) {
          self.held_events = combined
        } else {
          match self.encode_events(combined) {
            // CR-001：无事件可编码的帧（BlockStart/BlockEnd 在 Chat 系无载体）
            // 只会产出空块；丢弃它既避免空 SSE 块，也保证逐帧输出与整缓冲
            // 输出逐字节一致。
            Ok(sse) => if sse.trim().length() > 0 { out.push(sse) }
            Err(e) => return Err(e)
          }
        }
      }
      Err(e) => return Err(e)
    }
  }
  Ok(out)
}

///|
/// 编码事件组（ctx 感知）+ 跟踪会话元信息
fn StreamConverter::encode_events(
  self : StreamConverter,
  events : Array[@lux.LucentStreamEvent],
) -> Result[String, String] {
  for ev in events {
    match ev {
      ConversationStart(meta) => self.normalizer.stream_ctx = Some(meta)
      _ => ()
    }
  }
  match
    (self.target.events_encode_with_ctx)(events, self.normalizer.stream_ctx) {
    Ok(ecr) => Ok(ecr.value())
    Err(e) => Err(e)
  }
}

///|
/// 跨帧状态规整已抽取为共享的 `EventNormalizer`（event_stream.mbt），
/// 由 StreamConverter 与 Prism::stream_session 共用，语义不变：
/// 块事件去重/孤儿过滤 + Finish 去重并合成缺失 BlockEnd + usage 回填 + 丢弃 Done。

///|
/// 从数组中移除指定元素（保持顺序）
fn remove_int(arr : Array[Int], value : Int) -> Array[Int] {
  let result : Array[Int] = []
  for v in arr {
    if v != value {
      result.push(v)
    }
  }
  result
}

///|
/// 事件组是否以 Finish 结尾（需要保持等待后续 Usage 帧）
fn ends_with_finish(events : Array[@lux.LucentStreamEvent]) -> Bool {
  if events.length() == 0 {
    false
  } else {
    match events[events.length() - 1] {
      Finish(_) => true
      _ => false
    }
  }
}

///|
/// CR-001：读取会话元信息 `extra` 中透传的输入侧缓存用量（messages 解码器写入）。
/// 非 messages 源或上游未提供时为 (None, None)，不影响其他 provider。
fn meta_cache_usage(meta : @lux.LucentConversationMeta) -> (Int?, Int?) {
  match meta.extra {
    Some(jv) =>
      (
        @internal.field_int(jv, "usage_cached"),
        @internal.field_int(jv, "usage_cache_creation"),
      )
    None => (None, None)
  }
}
