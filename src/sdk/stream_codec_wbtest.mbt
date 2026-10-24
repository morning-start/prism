///|
/// EventNormalizer / 会话回退 / 流尾冲刷的白盒分支覆盖（P0/P1 修复配套）
///
/// 这些分支在黑盒路径下不可达，只能白盒直达：
/// - `EventNormalizer.item_open`：responses 源的 ItemStart→BlockEnd 配对
///   （ItemEnd 注销、孤儿 BlockEnd、BlockDiscard 命中 item_open）
/// - `StreamConverter` 的编码器 `finish()` 冲刷分支
/// - `meta_cache_usage` 的 extra 载体分支

///|
/// responses 源：ItemStart 开启 → BlockEnd 收尾（无 BlockStart 配对）
/// 必须被保留（此前被当孤儿丢弃，导致逐帧路径丢 content_block_stop）
test "wbtest - normalizer keeps BlockEnd paired with ItemStart" {
  let n : EventNormalizer = EventNormalizer::new()
  let item : @lux.LucentConversationItem = @lux.LucentConversationItem::tool_call(
    @lux.LucentToolUse::new("c1", "f", "{\"a\":1}", None),
  )
  let out = n.normalize([
    ItemStart(0, item),
    BlockDelta(0, ToolArgumentsDelta("x")),
    BlockEnd(0),
  ])
  // 三者都应保留（无 BlockStart，但 item_open 配对成功）
  assert_eq(out.length(), 3)
  assert_eq(n.item_open.length(), 0)
}

///|
/// responses 源：ItemEnd 显式注销；其后孤儿 BlockEnd 应被丢弃
test "wbtest - normalizer ItemEnd deregisters and orphan BlockEnd is dropped" {
  let n : EventNormalizer = EventNormalizer::new()
  let item : @lux.LucentConversationItem = @lux.LucentConversationItem::tool_call(
    @lux.LucentToolUse::new("c1", "f", "{}", None),
  )
  let out = n.normalize([ItemStart(3, item), ItemEnd(3), BlockEnd(3)])
  // ItemStart + ItemEnd 保留，孤儿 BlockEnd(3) 丢弃
  assert_eq(out.length(), 2)
  assert_eq(n.item_open.length(), 0)
}

///|
/// responses 源：ItemStart 后 BlockDiscard 命中 item_open 分支
test "wbtest - normalizer BlockDiscard clears item registration" {
  let n : EventNormalizer = EventNormalizer::new()
  let item : @lux.LucentConversationItem = @lux.LucentConversationItem::tool_call(
    @lux.LucentToolUse::new("c1", "f", "{}", None),
  )
  let out = n.normalize([ItemStart(5, item), BlockDiscard(5)])
  assert_eq(out.length(), 2)
  assert_eq(n.item_open.length(), 0)
}

///|
/// 同一索引不同种类块复用：先补 BlockEnd 闭合旧块再开新块
/// （openai 流里 text 固定索引 0 与 tool_calls 的 wire index 重叠）
test "wbtest - normalizer index reuse emits closing BlockEnd before new start" {
  let n : EventNormalizer = EventNormalizer::new()
  let out = n.normalize([
    BlockStart(0, Text),
    BlockDelta(0, TextDelta("hi")),
    BlockStart(0, ToolCall("c1", "f")),
  ])
  // 期望：BlockStart(0,Text) / delta / BlockEnd(0) / BlockStart(0,ToolCall)
  assert_eq(out.length(), 4)
  match out[2] {
    BlockEnd(0) => ()
    _ => fail("expected synthesized BlockEnd(0)")
  }
}

///|
/// 同索引同种类重复 BlockStart 丢弃（上游对同一块的重发）
test "wbtest - normalizer drops duplicate same-kind BlockStart" {
  let n : EventNormalizer = EventNormalizer::new()
  let out = n.normalize([
    BlockStart(0, Text),
    BlockStart(0, Text),
    BlockDelta(0, TextDelta("hi")),
  ])
  assert_eq(out.length(), 2)
}

///|
/// Finish 分支：首个 Finish 合成缺失 BlockEnd；第二个 Finish 被丢弃
test "wbtest - normalizer Finish synthesizes BlockEnd once and dedups" {
  let n : EventNormalizer = EventNormalizer::new()
  let out = n.normalize([
    BlockStart(0, Text),
    BlockStart(1, Text),
    Finish(Stop, None),
    Finish(Stop, None),
  ])
  // BlockStart×2 + BlockEnd×2（逆序）+ 首个 Finish = 5
  assert_eq(out.length(), 5)
  assert_eq(n.finish_seen, true)
}

///|
/// Usage 回填分支：prompt_tokens == 0 且 stream_ctx 有 usage_input 时回填
test "wbtest - normalizer backfills usage input tokens from stream ctx" {
  let n : EventNormalizer = EventNormalizer::new()
  let cache_fields : Map[String, Json] = Map([])
  cache_fields["usage_cached"] = Json(7)
  cache_fields["usage_cache_creation"] = Json(3)
  n.stream_ctx = Some(
    @lux.LucentConversationMeta::new_full(
      Some("m1"),
      Some("model"),
      Some(100),
      None,
      Some(Json::object(cache_fields)),
    ),
  )
  let out = n.normalize([
    Usage(@lux.LucentUsage::full(0, 5, 5, None, None, None)),
  ])
  assert_eq(out.length(), 1)
  match out[0] {
    Usage(u) => {
      assert_eq(u.prompt_tokens, 100)
      assert_eq(u.total_tokens, 105)
      assert_eq(u.cached_tokens, Some(7))
      assert_eq(u.cache_creation_tokens, Some(3))
    }
    _ => fail("expected backfilled Usage")
  }
}

///|
/// Usage 回填：stream_ctx 缺失或无 usage_input 时原样保留
test "wbtest - normalizer keeps usage when no ctx input tokens" {
  let n : EventNormalizer = EventNormalizer::new()
  let out = n.normalize([
    Usage(@lux.LucentUsage::full(0, 5, 5, None, None, None)),
  ])
  assert_eq(out.length(), 1)
  // 无 ctx → 原样（prompt_tokens 仍为 0）
  match out[0] {
    Usage(u) => assert_eq(u.prompt_tokens, 0)
    _ => fail("expected Usage")
  }
  // ctx 存在但 usage_input 为 None → 原样
  let n2 : EventNormalizer = EventNormalizer::new()
  n2.stream_ctx = Some(@lux.LucentConversationMeta::new(None, None, None))
  let out2 = n2.normalize([
    Usage(@lux.LucentUsage::full(0, 5, 5, None, None, None)),
  ])
  assert_eq(out2.length(), 1)
}

///|
/// Done 一律丢弃（终止符由会话层唯一产生）
test "wbtest - normalizer drops Done events" {
  let n : EventNormalizer = EventNormalizer::new()
  let out = n.normalize([Done, Done, BlockStart(0, Text), Done])
  assert_eq(out.length(), 1)
}

///|
/// meta_cache_usage：extra 缺失 / 非对象时返回 (None, None)
test "wbtest - meta_cache_usage handles absent and non-object extra" {
  // extra = None
  let m1 = @lux.LucentConversationMeta::new(None, None, None)
  let (a, b) = meta_cache_usage(m1)
  assert_eq(a, None)
  assert_eq(b, None)
  // extra = 非 Object（字符串）
  let m2 = @lux.LucentConversationMeta::new_full(
    None,
    None,
    None,
    None,
    Some(Json::string("not-an-object")),
  )
  let (c, d) = meta_cache_usage(m2)
  assert_eq(c, None)
  assert_eq(d, None)
}

///|
/// openai 源截断流：解码器会话的 finish() 必须闭合仍打开的块。
///
/// 覆盖 `StreamConverter::finish` 的 `decoder.finish()` 分支 —— 在冲刷
/// 编码器状态之前先补齐源侧收尾事件。
test "wbtest - stream converter closes source blocks via decoder finish" {
  // 文本块打开后中断（无 finish_reason / 无 [DONE]）
  let sse = "data: {\"id\":\"ccX\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\"}}]}\n\n" +
    "data: {\"id\":\"ccX\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"partial\"}}]}\n"
  match StreamConverter::new("openai", "messages") {
    Ok(conv) => {
      let acc : Array[String] = []
      match conv.feed(sse) {
        Ok(f) =>
          for x in f {
            acc.push(x)
          }
        Err(e) => fail("feed failed: " + e)
      }
      match conv.finish() {
        Ok(f) =>
          for x in f {
            acc.push(x)
          }
        Err(e) => fail("finish failed: " + e)
      }
      let joined = acc.join("")
      // 文本块必须被闭合（messages 目标：content_block_stop）
      if !joined.contains("event: content_block_stop") {
        fail("source block not closed at stream end; got:\n" + joined)
      }
    }
    Err(e) => fail("new failed: " + e)
  }
}

///|
/// openai 源的 thinking 块打开后中断：解码器 finish 必须闭合 thinking 索引块
test "wbtest - stream converter closes open thinking block via decoder finish" {
  let sse = "data: {\"id\":\"ccY\",\"choices\":[{\"delta\":{\"reasoning_content\":\"thinking...\"}}]}\n"
  match StreamConverter::new("openai", "openai") {
    Ok(conv) => {
      let acc : Array[String] = []
      match conv.feed(sse) {
        Ok(f) =>
          for x in f {
            acc.push(x)
          }
        Err(e) => fail("feed failed: " + e)
      }
      match conv.finish() {
        Ok(f) =>
          for x in f {
            acc.push(x)
          }
        Err(e) => fail("finish failed: " + e)
      }
      // openai 目标无块边界载体，只要求不 panic 且产出终止符
      let joined = acc.join("")
      assert_true(joined.contains("data: [DONE]"))
    }
    Err(e) => fail("new failed: " + e)
  }
}

///|
/// StreamConverter 的编码器 finish() 冲刷分支：gemini 目标在截断流下
/// 必须把跨帧累积的工具参数在流尾发出
test "wbtest - stream converter flushes encoder state at finish" {
  let sse = "data: {\"id\":\"ccT\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\"}}]}\n\n" +
    "data: {\"id\":\"ccT\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"c1\",\"function\":{\"name\":\"f1\",\"arguments\":\"{\\\"a\\\":1}\"}}]}}]}\n"
  match StreamConverter::new("openai", "gemini") {
    Ok(conv) => {
      let acc : Array[String] = []
      match conv.feed(sse) {
        Ok(f) =>
          for x in f {
            acc.push(x)
          }
        Err(e) => fail("feed failed: " + e)
      }
      match conv.finish() {
        Ok(f) =>
          for x in f {
            acc.push(x)
          }
        Err(e) => fail("finish failed: " + e)
      }
      let joined = acc.join("")
      if !joined.contains("\"args\":{\"a\":1}") {
        fail("encoder finish did not flush pending tool args; got:\n" + joined)
      }
    }
    Err(e) => fail("new failed: " + e)
  }
}
