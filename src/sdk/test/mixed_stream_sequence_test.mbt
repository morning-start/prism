///|
/// 混合流（先文本后工具调用）的增量会话与整批 decode_sse 等价性回归。
///
/// 背景（P0 修复）：openai 流解码器曾把 text 块固定为索引 0，而 tool_calls 的
/// wire index 也从 0 起 → 混合流下两个块共用索引 0。下游 EventNormalizer 按
/// 索引去重，把第二个 BlockStart(0)（ToolCall）当重复事件丢弃，增量会话
/// （Prism::stream_session / StreamConverter 共用）整体丢失工具调用，而整批
/// decode_sse 路径保留——破坏"增量与整批等价"契约。

///|
/// PrismEvent 序列的字符串拼接（本文件专用；成员判等仍用 events_repr）
fn events_join(events : Array[@sdk.PrismEvent]) -> String {
  events_repr(events).join("|")
}

///|
/// openai 混合流 fixture：role → content → tool_calls(index 0) → 增量 →
/// finish_reason=tool_calls → [DONE]
test "stream_session - openai mixed text then tool call is not lost" {
  let sse = "data: {\"id\":\"cc1\",\"object\":\"chat.completion.chunk\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\"}}]}\n\n" +
    "data: {\"id\":\"cc1\",\"object\":\"chat.completion.chunk\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Let me check\"}}]}\n\n" +
    "data: {\"id\":\"cc1\",\"object\":\"chat.completion.chunk\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"call_1\",\"type\":\"function\",\"function\":{\"name\":\"get_weather\",\"arguments\":\"\"}}]}}]}\n\n" +
    "data: {\"id\":\"cc1\",\"object\":\"chat.completion.chunk\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"{\\\"city\\\":\\\"SH\\\"}\"}}]}}]}\n\n" +
    "data: {\"id\":\"cc1\",\"object\":\"chat.completion.chunk\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"tool_calls\"}]}\n\n" +
    "data: [DONE]\n\n"
  let p = @sdk.Prism::new().with_provider("openai")
  // 整批路径
  let batch_events : Array[@sdk.PrismEvent] = match p.decode_sse(sse) {
    Ok(evs) => evs
    Err(e) => fail("batch decode failed: " + e)
  }
  // 增量路径（一整个流作为单个 chunk 喂入）
  let sess_events : Array[@sdk.PrismEvent] = match p.stream_session() {
    Ok(sess) => {
      let acc : Array[@sdk.PrismEvent] = []
      match sess.feed(sse) {
        Ok(evs) =>
          for ev in evs {
            acc.push(ev)
          }
        Err(e) => fail("feed failed: " + e)
      }
      match sess.finish() {
        Ok(evs) =>
          for ev in evs {
            acc.push(ev)
          }
        Err(e) => fail("finish failed: " + e)
      }
      acc
    }
    Err(e) => fail("session failed: " + e)
  }
  // 两路径事件序列逐字节一致
  assert_eq(events_repr(sess_events), events_repr(batch_events))
  // 工具调用不得丢失，且文本保留
  assert_true(
    events_join(batch_events).contains("C:call_1:get_weather:{\"city\":\"SH\"}"),
  )
  assert_true(events_join(batch_events).contains("T:Let me check"))
  assert_true(
    events_join(sess_events).contains("C:call_1:get_weather:{\"city\":\"SH\"}"),
  )
  assert_true(events_join(sess_events).contains("T:Let me check"))
}

///|
/// openai 混合流：1 字节切分喂入时同样不得丢失工具调用（帧切分与块索引
/// 去重在增量路径上叠加，是本次 P0 的触发路径）。
test "stream_session - openai mixed text then tool call survives 1-byte feeds" {
  let sse = "data: {\"id\":\"cc1\",\"object\":\"chat.completion.chunk\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\"}}]}\n\n" +
    "data: {\"id\":\"cc1\",\"object\":\"chat.completion.chunk\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Let me check\"}}]}\n\n" +
    "data: {\"id\":\"cc1\",\"object\":\"chat.completion.chunk\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"call_1\",\"type\":\"function\",\"function\":{\"name\":\"get_weather\",\"arguments\":\"\"}}]}}]}\n\n" +
    "data: {\"id\":\"cc1\",\"object\":\"chat.completion.chunk\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"{\\\"city\\\":\\\"SH\\\"}\"}}]}}]}\n\n" +
    "data: {\"id\":\"cc1\",\"object\":\"chat.completion.chunk\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"tool_calls\"}]}\n\n" +
    "data: [DONE]\n\n"
  let p = @sdk.Prism::new().with_provider("openai")
  match p.stream_session() {
    Ok(sess) => {
      let acc : Array[@sdk.PrismEvent] = []
      let mut i = 0
      while i < sse.length() {
        match sess.feed(sse[i:i + 1].to_owned()) {
          Ok(evs) =>
            for ev in evs {
              acc.push(ev)
            }
          Err(e) => fail("feed failed: " + e)
        }
        i = i + 1
      }
      match sess.finish() {
        Ok(evs) =>
          for ev in evs {
            acc.push(ev)
          }
        Err(e) => fail("finish failed: " + e)
      }
      let repr = events_join(acc)
      assert_true(repr.contains("T:Let me check"))
      if !repr.contains("C:call_1:get_weather:{\"city\":\"SH\"}") {
        fail("ToolCall lost under 1-byte incremental feeds: " + repr)
      }
    }
    Err(e) => fail("session failed: " + e)
  }
}

///|
/// thinking（DeepSeek/vLLM reasoning_content）+ 文本 + 两个工具的混合流：
/// thinking 占用固定索引 1，第二个工具的 wire index 同样为 1 → 曾同索引
/// 双开，被 normalizer 去重丢弃。
test "stream_session - openai reasoning + text + two tool calls keep all blocks" {
  let sse = "data: {\"id\":\"cc2\",\"choices\":[{\"delta\":{\"reasoning_content\":\"hmm\"}}]}\n\n" +
    "data: {\"id\":\"cc2\",\"choices\":[{\"delta\":{\"content\":\"ok\"}}]}\n\n" +
    "data: {\"id\":\"cc2\",\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"c1\",\"function\":{\"name\":\"a\",\"arguments\":\"{}\"}}]}}]}\n\n" +
    "data: {\"id\":\"cc2\",\"choices\":[{\"delta\":{\"tool_calls\":[{\"index\":1,\"id\":\"c2\",\"function\":{\"name\":\"b\",\"arguments\":\"{}\"}}]}}]}\n\n" +
    "data: {\"id\":\"cc2\",\"choices\":[{\"delta\":{},\"finish_reason\":\"tool_calls\"}]}\n\n" +
    "data: [DONE]\n\n"
  let p = @sdk.Prism::new().with_provider("openai")
  let batch_events : Array[@sdk.PrismEvent] = match p.decode_sse(sse) {
    Ok(evs) => evs
    Err(e) => fail("batch decode failed: " + e)
  }
  let sess_events : Array[@sdk.PrismEvent] = match p.stream_session() {
    Ok(sess) => {
      let acc : Array[@sdk.PrismEvent] = []
      match sess.feed(sse) {
        Ok(evs) =>
          for ev in evs {
            acc.push(ev)
          }
        Err(e) => fail("feed failed: " + e)
      }
      match sess.finish() {
        Ok(evs) =>
          for ev in evs {
            acc.push(ev)
          }
        Err(e) => fail("finish failed: " + e)
      }
      acc
    }
    Err(e) => fail("session failed: " + e)
  }
  assert_eq(events_repr(sess_events), events_repr(batch_events))
  let repr = events_join(sess_events)
  assert_true(events_join(sess_events).contains("K:hmm"))
  assert_true(repr.contains("T:ok"))
  if !repr.contains("C:c1:a:{}") || !repr.contains("C:c2:b:{}") {
    fail("tool call lost in mixed reasoning+text+2tools stream: " + repr)
  }
}
