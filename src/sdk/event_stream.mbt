///|
/// ═══ 功能组：stream session（增量解码会话，首字实时）═══
/// 本文件：Prism::stream_session 拉式增量解码会话。
/// 跨帧规整器（EventNormalizer）与工具/文本事件累积器（PrismEventBuffer）
/// 由 convert.mbt（StreamConverter）与 pipeline.mbt（lucent_events_to_prism）共享。

///|
/// 块种类内核：去重键只看"这是哪一类块"，不看骨架载荷。
/// openai 逐帧解码时同一工具块的首帧带 (id,name)、续帧只剩 arguments，
/// LucentBlockType 整体比较会把同一逻辑块判成两类。
fn block_kind(bt : @lux.LucentBlockType) -> Int {
  match bt {
    Text => 0
    ToolCall(_, _) => 1
    Thinking => 2
    Refusal => 3
    Image => 4
    Audio => 5
    Video => 6
    Native(_) => 7
  }
}

///|
/// EventNormalizer — 解码侧跨帧规整器（T5/CR-001/CR-002 不变量）
///
/// 逐帧解码时源解码器是无跨帧状态的，本结构在会话内维护：
/// - open_blocks：重复 BlockStart 丢弃、孤儿 BlockEnd/BlockDiscard 丢弃
/// - finish_seen：同一会话只保留首个 Finish（CR-001 D2），并为仍打开的块
///   合成逆序 BlockEnd
/// - stream_ctx：首个 ConversationStart 的会话元信息（usage 回填用，CR-001 D1）
/// - Done：一律丢弃（CR-002 D5：终止符由会话层在收尾时唯一产生）
///
/// BlockStart 去重键是 (index, block_kind)：
/// - 同索引同种类才是真重复（gemini 全量帧覆盖前的重发）；
/// - 同索引不同种类说明该索引被另一类块复用 —— openai 流里 tool_calls 的
///   wire index 与 text（0）/thinking（1）固定索引分区重叠，逐帧解码时
///   上一帧的 text 块仍开着，本帧工具块 BlockStart(0) 到不了"先闭合"的
///   状态。此时视为索引复用：补一个 BlockEnd 闭合旧块再开新块，与整批
///   路径（解码器有跨帧状态）输出逐字节一致。
///   曾按裸索引去重把工具块的 BlockStart 当重复丢掉 → 混合流失工具调用。
///
/// StreamConverter（编码到目标协议）与 Prism::stream_session（解码到
/// PrismEvent）共用此规整逻辑，保证两条路径事件语义一致。
struct EventNormalizer {
  mut open_blocks : Array[Int]
  open_block_kinds : Map[Int, Int]
  mut finish_seen : Bool
  mut stream_ctx : @lux.LucentConversationMeta?
}

///|
fn EventNormalizer::new() -> EventNormalizer {
  {
    open_blocks: [],
    open_block_kinds: Map([]),
    finish_seen: false,
    stream_ctx: None,
  }
}

///|
fn EventNormalizer::normalize(
  self : EventNormalizer,
  events : Array[@lux.LucentStreamEvent],
) -> Array[@lux.LucentStreamEvent] {
  let result : Array[@lux.LucentStreamEvent] = []
  for ev in events {
    match ev {
      BlockStart(idx, bt) =>
        if self.open_blocks.contains(idx) {
          // 重复 BlockStart：同索引同种类 → 丢弃；同索引不同种类 → 索引复用，
          // 先补 BlockEnd 闭合旧块再开新块（见结构体注释）
          let kind = block_kind(bt)
          match self.open_block_kinds.get(idx) {
            Some(prev) if prev == kind => ()
            _ => {
              result.push(BlockEnd(idx))
              self.open_block_kinds[idx] = kind
              result.push(ev)
            }
          }
        } else {
          self.open_blocks.push(idx)
          self.open_block_kinds[idx] = block_kind(bt)
          result.push(ev)
        }
      BlockEnd(idx) =>
        if self.open_blocks.contains(idx) {
          self.open_blocks = remove_int(self.open_blocks, idx)
          self.open_block_kinds.remove(idx)
          result.push(ev)
        }
      BlockDiscard(idx) =>
        if self.open_blocks.contains(idx) {
          self.open_blocks = remove_int(self.open_blocks, idx)
          self.open_block_kinds.remove(idx)
          result.push(ev)
        }
      Finish(_) =>
        // CR-001 D2：同一会话只保留首个 Finish。
        if self.finish_seen {
          ()
        } else {
          self.finish_seen = true
          // 合成缺失的 BlockEnd（逆序闭合，与栈语义一致）
          let mut k = self.open_blocks.length() - 1
          while k >= 0 {
            result.push(BlockEnd(self.open_blocks[k]))
            k = k - 1
          }
          self.open_blocks = []
          result.push(ev)
        }
      Usage(u) =>
        // CR-001 D1（增量路径）：逐帧解码时 message_delta 帧看不到 message_start
        // 的 input_tokens，解出的 prompt_tokens 为 0；用会话元信息回填，
        // 保证逐帧输出与整缓冲输出逐字节一致。
        if u.prompt_tokens == 0 {
          match self.stream_ctx {
            Some(meta) =>
              match meta.usage_input {
                Some(n) => {
                  let (meta_cached, meta_cache_creation) = meta_cache_usage(
                    meta,
                  )
                  let cached = match u.cached_tokens {
                    Some(c) => Some(c)
                    None => meta_cached
                  }
                  let cache_creation = match u.cache_creation_tokens {
                    Some(c) => Some(c)
                    None => meta_cache_creation
                  }
                  result.push(
                    Usage(
                      @lux.LucentUsage::full(
                        n,
                        u.completion_tokens,
                        n + u.completion_tokens,
                        u.reasoning_tokens,
                        cached,
                        cache_creation,
                      ),
                    ),
                  )
                }
                None => result.push(ev)
              }
            None => result.push(ev)
          }
        } else {
          result.push(ev)
        }
      Done => ()
      _ => result.push(ev)
    }
  }
  result
}

///|
/// PrismStreamSession — 拉式增量解码会话（首字实时）
///
/// 用法：
/// ```moonbit nocheck
/// let sess = prism.stream_session()?
/// for chunk in upstream_chunks {
///   let events = sess.feed(chunk)?   // 立即得到该批完整帧的事件（可能为空）
///   for ev in events { render(ev) }  // 首字延迟 = 首个完整 SSE 帧
/// }
/// let tail = sess.finish()?          // 冲刷尾部半帧并闭合未完块
/// ```
///
/// - `feed`：跨 chunk 半帧由内部 SseFrameSplitter 缓冲（CRLF/CR/LF 归一），
///   只有完整帧才解码产出事件 —— 不完整 JSON 不会提前产生残缺事件
/// - `finish`：幂等（二次调用返回空）；冲刷尾部半帧、为仍打开的块合成
///   BlockEnd（截断流安全收尾）
/// - 事件产出与整批 `decode_sse` 一致（见 stream_session_test.mbt）
pub struct PrismStreamSession {
  reg : ProviderRegistration
  splitter : @internal.SseFrameSplitter
  normalizer : EventNormalizer
  events : PrismEventBuffer
}

///|
/// 创建增量解码会话（provider 在构造时解析一次）
pub fn Prism::stream_session(
  self : Prism,
) -> Result[PrismStreamSession, String] {
  match match_provider_name(self.provider) {
    Some(reg) =>
      Ok({
        reg,
        splitter: @internal.SseFrameSplitter::new(),
        normalizer: EventNormalizer::new(),
        events: PrismEventBuffer::new(),
      })
    None => Err("unknown provider: " + self.provider)
  }
}

///|
/// 喂入一个上游 chunk，立即返回其中完整帧解出的事件（可能为空）
pub fn PrismStreamSession::feed(
  self : PrismStreamSession,
  chunk : String,
) -> Result[Array[PrismEvent], String] {
  self.convert_frames(self.splitter.feed(chunk))
}

///|
/// 流结束：冲刷尾部半帧并转换，闭合仍打开的块，输出累积事件。
///
/// 幂等：`closed` 之后重复调用只返回空数组（与 StreamConverter::finish 一致）。
pub fn PrismStreamSession::finish(
  self : PrismStreamSession,
) -> Result[Array[PrismEvent], String] {
  let frames = self.splitter.flush()
  match self.convert_frames(frames) {
    Ok(_) =>
      if self.events.closed {
        Ok([])
      } else {
        self.events.closed = true
        // CR-002 A5：截断流仍打开的块在此闭合 —— 与整缓冲路径的栈语义一致。
        let mut k = self.normalizer.open_blocks.length() - 1
        while k >= 0 {
          self.events.absorb(BlockEnd(self.normalizer.open_blocks[k]))
          k = k - 1
        }
        self.normalizer.open_blocks = []
        self.events.flush()
        Ok(self.events.take())
      }
    Err(e) => Err(e)
  }
}

///|
fn PrismStreamSession::convert_frames(
  self : PrismStreamSession,
  frames : Array[String],
) -> Result[Array[PrismEvent], String] {
  for frame in frames {
    match (self.reg.events_decode)(frame) {
      Ok(dcr) => {
        let normalized = self.normalizer.normalize(dcr.value())
        for ev in normalized {
          self.events.absorb(ev)
        }
        // 注意：此处不冲刷未闭合 tool 块 —— 工具块的 BlockEnd 可能在后续帧
        // （openai 参数增量跨帧、messages content_block_stop 独立成帧），
        // 过早冲刷会把残缺 arguments 发射出去。冲刷仅在 finish() 收尾时执行。
      }
      Err(e) => return Err(e)
    }
  }
  Ok(self.events.take())
}

///|
/// PrismEventBuffer — Lucent 流事件 → PrismEvent 的跨帧状态机
///
/// 抽取自 pipeline.mbt `lucent_events_to_prism`：工具调用参数跨帧累积
/// （BlockStart(ToolCall) 开块 → ToolArgumentsDelta 追加 → BlockEnd 发射）。
/// 增量会话按帧调用 absorb()/flush()，与整批一次性 ingest 事件序列等价。
struct PrismEventBuffer {
  /// 已产出的事件（take() 之前累积）
  out : Array[PrismEvent]
  /// 当前 tool 块累积状态
  mut tool_active : Bool
  mut tool_idx : Int
  mut tool_id : String
  mut tool_name : String
  mut tool_args : String
  mut has_finish : Bool
  /// 会话是否已收尾（finish() 幂等标记）
  mut closed : Bool
}

///|
fn PrismEventBuffer::new() -> PrismEventBuffer {
  {
    out: [],
    tool_active: false,
    tool_idx: -1,
    tool_id: "",
    tool_name: "",
    tool_args: "",
    has_finish: false,
    closed: false,
  }
}

///|
/// 吸收一个 IR 流事件（维护工具块状态，产出中间事件）
fn PrismEventBuffer::absorb(
  self : PrismEventBuffer,
  ev : @lux.LucentStreamEvent,
) -> Unit {
  if self.has_finish {
    return
  }
  match ev {
    BlockDelta(_, TextDelta(s)) => self.out.push(TextDelta(s))
    BlockStart(idx, ToolCall(id, name)) => {
      if self.tool_active {
        self.emit_tool_call()
      }
      self.tool_active = true
      self.tool_idx = idx
      self.tool_id = id
      self.tool_name = name
      self.tool_args = ""
    }
    BlockStart(_, _) =>
      // 非 tool 块开始：冲刷未闭合 tool 块
      if self.tool_active {
        self.emit_tool_call()
      }
    BlockDelta(idx, ToolArgumentsDelta(s)) =>
      if self.tool_active && idx == self.tool_idx {
        self.tool_args = self.tool_args + s
      }
    BlockEnd(idx) =>
      if self.tool_active && idx == self.tool_idx {
        self.emit_tool_call()
      }
    BlockDiscard(idx) =>
      // Gemini 全量帧覆盖：丢弃该块（不发射 ToolCall）
      if self.tool_active && idx == self.tool_idx {
        self.tool_active = false
        self.tool_args = ""
      }
    ItemStart(idx, ToolCall(tu)) => {
      // responses 路径：骨架开启 tool 块（arguments 可能已在骨架中）
      if self.tool_active {
        self.emit_tool_call()
      }
      self.tool_active = true
      self.tool_idx = idx
      self.tool_id = tu.id
      self.tool_name = tu.name
      self.tool_args = tu.arguments_json
    }
    ItemStart(_, ToolResult(tr)) =>
      self.out.push(
        ToolResult({
          tool_use_id: tr.tool_use_id,
          content: @lux.lucent_content_to_text(tr.content),
          is_error: tr.is_error,
        }),
      )
    ItemStart(_, _) =>
      // 新 item 开始：冲刷未闭合 tool 块
      if self.tool_active {
        self.emit_tool_call()
      }
    BlockDelta(_, ThinkingDelta(s)) =>
      self.out.push(Thinking({ text: s, signature: None, redacted: false, }))
    Finish(fr) => {
      let pfr = match fr {
        Stop => Stop
        Length => Length
        ToolCalls => ToolCalls
        ContentFilter => ContentFilter
        _ => Error
      }
      self.out.push(Finish(pfr))
      self.has_finish = true
    }
    _ => ()
  }
}

///|
/// 发射当前累积的完整 ToolCall 事件
fn PrismEventBuffer::emit_tool_call(self : PrismEventBuffer) -> Unit {
  self.out.push(
    ToolCall({
      id: self.tool_id,
      name: self.tool_name,
      arguments_json: self.tool_args,
    }),
  )
  self.tool_active = false
  self.tool_args = ""
}

///|
/// 冲刷未闭合的 tool 块（流尾安全：避免静默丢失）
fn PrismEventBuffer::flush(self : PrismEventBuffer) -> Unit {
  if self.tool_active {
    self.emit_tool_call()
  }
}

///|
/// 取走全部已产出事件并清空缓冲
fn PrismEventBuffer::take(self : PrismEventBuffer) -> Array[PrismEvent] {
  let result = self.out.copy()
  while self.out.length() > 0 {
    let _ = self.out.pop()
  }
  result
}
