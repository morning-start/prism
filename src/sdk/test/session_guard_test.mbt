///|
/// 会话收尾防护（项 1）：`finish()` 遗漏是使用陷阱 —— 尾部帧与终止符只在
/// `finish()` 产出。本文件验证两层防护：
///   1. `StreamConverter::finished()` 可查询（宿主可自查是否已收尾）；
///   2. `convert_stream_session` 便捷入口把 new+feed+finish 收敛为一次调用，
///      从 API 形态上消除"忘记 finish"的可能。

///|
/// finished() 在 finish 前后正确切换
test "session guard - finished reflects finish() call" {
  let sse = "data: {\"id\":\"c1\",\"object\":\"chat.completion.chunk\",\"created\":1,\"model\":\"m\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\"}}]}\n\n" +
    "data: {\"id\":\"c1\",\"object\":\"chat.completion.chunk\",\"created\":1,\"model\":\"m\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"hi\"}}]}\n\n" +
    "data: [DONE]\n\n"
  match @sdk.StreamConverter::new("openai", "messages") {
    Ok(conv) => {
      assert_false(conv.finished())
      let _ = match conv.feed(sse) {
        Ok(f) => f
        Err(e) => fail("feed failed: " + e)
      }
      // 未 finish 前仍未收尾（尾部帧尚未产出）
      assert_false(conv.finished())
      let _ = match conv.finish() {
        Ok(f) => f
        Err(e) => fail("finish failed: " + e)
      }
      assert_true(conv.finished())
      // 幂等：再次 finish 不改变状态，也不重复产出
      let tail = match conv.finish() {
        Ok(f) => f
        Err(e) => fail("second finish failed: " + e)
      }
      assert_eq(tail.length(), 0)
      assert_true(conv.finished())
    }
    Err(e) => fail("new failed: " + e)
  }
}

///|
/// 未调用 finish() 时**确实会丢帧**——这是防护存在的理由，用测试把它钉死。
/// （对比：finish 后帧数与便捷入口一致；不 finish 则缺终止符。）
test "session guard - omitting finish loses tail frames (documents the trap)" {
  let sse = "data: {\"id\":\"c1\",\"object\":\"chat.completion.chunk\",\"created\":1,\"model\":\"m\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\"}}]}\n\n" +
    "data: {\"id\":\"c1\",\"object\":\"chat.completion.chunk\",\"created\":1,\"model\":\"m\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"hi\"}}]}\n\n" +
    "data: [DONE]\n\n"
  // 完整流程（含 finish）
  let full = match @sdk.convert_stream_session("openai", "messages", sse) {
    Ok(frames) => frames.join("")
    Err(e) => fail("session failed: " + e)
  }
  assert_true(full.contains("event: message_stop"))
  // 漏掉 finish：同一 feed 结果不含终止符（证明该防护有必要）
  match @sdk.StreamConverter::new("openai", "messages") {
    Ok(conv) => {
      let partial = match conv.feed(sse) {
        Ok(frames) => frames.join("")
        Err(e) => fail("feed failed: " + e)
      }
      assert_false(partial.contains("event: message_stop"))
      assert_false(conv.finished())
      // 补上 finish 后即完整
      let tail = match conv.finish() {
        Ok(frames) => frames.join("")
        Err(e) => fail("finish failed: " + e)
      }
      assert_true(tail.contains("event: message_stop"))
      assert_eq(partial + tail, full)
    }
    Err(e) => fail("new failed: " + e)
  }
}

///|
/// 便捷入口与分帧 API 产出逐字节一致（含工具调用场景）
test "session guard - convenience entry equals feed+finish byte-for-byte" {
  let sse = "data: {\"id\":\"cc1\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\"}}]}\n\n" +
    "data: {\"id\":\"cc1\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"c1\",\"type\":\"function\",\"function\":{\"name\":\"f1\",\"arguments\":\"{\\\"a\\\":1}\"}}]}}]}\n\n" +
    "data: {\"id\":\"cc1\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"tool_calls\"}]}\n\n" +
    "data: [DONE]\n\n"
  for target in ["responses", "messages", "gemini", "openai"] {
    let via_entry = match @sdk.convert_stream_session("openai", target, sse) {
      Ok(frames) => frames.join("")
      Err(e) => fail("entry openai->" + target + ": " + e)
    }
    // 手动分帧（1 字节）必须与便捷入口一致
    let manual = match @sdk.StreamConverter::new("openai", target) {
      Ok(conv) => {
        let out : Array[String] = []
        let mut i = 0
        while i < sse.length() {
          match conv.feed(sse[i:i + 1].to_owned()) {
            Ok(frames) =>
              for f in frames {
                out.push(f)
              }
            Err(e) => fail("feed failed: " + e)
          }
          i = i + 1
        }
        match conv.finish() {
          Ok(frames) =>
            for f in frames {
              out.push(f)
            }
          Err(e) => fail("finish failed: " + e)
        }
        assert_true(conv.finished())
        out.join("")
      }
      Err(e) => fail("new failed: " + e)
    }
    assert_eq(manual, via_entry)
  }
}

///|
/// 截断流（openai 源，文本块未闭合）：finish() 必须经**源解码会话**收尾，
/// 与经 normalizer 合成 BlockEnd 的路径共同保证块被闭合。
///
/// 覆盖 `StreamConverter::finish` 中 `decoder.finish()` 收尾事件的编码路径。
test "session - truncated openai source closes blocks via decoder finish path" {
  // 文本块已打开但流中断（无 finish_reason、无 [DONE]、无尾空行）
  let sse = "data: {\"id\":\"ccZ\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\"}}]}\n\n" +
    "data: {\"id\":\"ccZ\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"partial\"}}]}\n"
  for target in ["messages", "openai"] {
    let batch = match @sdk.convert_stream("openai", sse, target) {
      Ok(r) => r.value()
      Err(e) => fail("batch openai->" + target + ": " + e)
    }
    let inc = match @sdk.convert_stream_session("openai", target, sse) {
      Ok(frames) => frames.join("")
      Err(e) => fail("session openai->" + target + ": " + e)
    }
    if inc != batch {
      fail("truncated openai->" + target + ": session != batch\n" + inc)
    }
  }
  // messages 目标必须真的闭合块
  match @sdk.convert_stream_session("openai", "messages", sse) {
    Ok(frames) => {
      let joined = frames.join("")
      assert_true(joined.contains("event: content_block_stop"))
      assert_true(joined.contains("partial"))
    }
    Err(e) => fail("session failed: " + e)
  }
}

///|
/// 截断流 + thinking 块打开：源解码会话同样必须收尾
test "session - truncated openai thinking block closes via decoder finish" {
  let sse = "data: {\"id\":\"ccY\",\"choices\":[{\"delta\":{\"reasoning_content\":\"hmm\"}}]}\n"
  let batch = match @sdk.convert_stream("openai", sse, "messages") {
    Ok(r) => r.value()
    Err(e) => fail("batch failed: " + e)
  }
  let inc = match @sdk.convert_stream_session("openai", "messages", sse) {
    Ok(frames) => frames.join("")
    Err(e) => fail("session failed: " + e)
  }
  assert_eq(inc, batch)
}

///|
/// convert_stream_session 的错误传播分支：未知 provider → Err
test "session guard - convenience entry propagates unknown provider error" {
  match @sdk.convert_stream_session("no-such", "messages", "data: x\n\n") {
    Err(e) => assert_true(e.contains("unknown provider"))
    Ok(_) => fail("expected error for unknown source")
  }
  match @sdk.convert_stream_session("openai", "no-such", "data: x\n\n") {
    Err(e) => assert_true(e.contains("unknown provider"))
    Ok(_) => fail("expected error for unknown target")
  }
}

///|
/// 源解码会话的收尾事件被规整并编码（`decoder.finish()` 返回非空）。
///
/// openai 源：thinking 块（固定索引 1）与文本块同时打开后中断 —— normalizer
/// 先闭合它追踪的块，而解码会话仍持有 thinking 索引，其 finish() 产出的事件
/// 走 `normalize(closing)` 后并入待编码集。
test "session - decoder finish events are normalized and encoded" {
  let sse = "data: {\"id\":\"ccM\",\"choices\":[{\"index\":0,\"delta\":{\"reasoning_content\":\"think\"}}]}\n\n" +
    "data: {\"id\":\"ccM\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"text\"}}]}\n"
  let batch = match @sdk.convert_stream("openai", sse, "messages") {
    Ok(r) => r.value()
    Err(e) => fail("batch failed: " + e)
  }
  let inc = match @sdk.convert_stream_session("openai", "messages", sse) {
    Ok(frames) => frames.join("")
    Err(e) => fail("session failed: " + e)
  }
  assert_eq(inc, batch)
  assert_true(inc.contains("event: content_block_stop"))
}
