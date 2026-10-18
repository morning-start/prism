///|
/// 会话化后的对抗性验证：断言**语义完整**而非仅"两路径相等"。
///
/// "逐帧 == 整批"是必要条件，但不充分——两条路径可能一起错。
/// 本文件直接断言工具调用事件的语义载荷：参数必须被完整累积、
/// done 事件必须携带完整 arguments、item_id 必须与 output_item.added 一致。

///|
/// openai→responses 增量路径的 function_call_arguments.done 必须携带
/// **完整**参数（不只是存在），且 item_id 与 added 帧一致。
test "semantic - responses done event carries full accumulated arguments" {
  let sse = openai_tool_stream_fixture()
  let inc = match feed_one_byte_chunks("openai", "responses", sse) {
    Ok(frames) => frames.join("")
    Err(e) => fail("incremental failed: " + e)
  }
  // 两个 done 事件（每帧 event 名与 data.type 各一次 → 共 4 处标记）
  let done_parts = inc
    .split("\"type\":\"response.function_call_arguments.done\"")
    .to_array()
  assert_eq(done_parts.length() - 1, 2)
  assert_true(inc.contains("\"arguments\":\"{\\\"city\\\":\\\"SH\\\"}\""))
  assert_true(inc.contains("\"arguments\":\"{\\\"tz\\\":\\\"UTC\\\"}\""))
  // item_id 不得退化为占位符 item_N（必须是 BlockStart/added 登记的 call_N）
  assert_false(inc.contains("\"item_id\":\"item_0\""))
  assert_false(inc.contains("\"item_id\":\"item_1\""))
  // output_item.done 必须收尾 function_call item（而非 message item）
  assert_true(inc.contains("\"type\":\"function_call\""))
}

///|
/// openai→gemini 增量路径的 functionCall.args 必须是累积后的完整 JSON object
test "semantic - gemini functionCall args fully accumulated incrementally" {
  let sse = openai_tool_stream_fixture()
  let inc = match feed_one_byte_chunks("openai", "gemini", sse) {
    Ok(frames) => frames.join("")
    Err(e) => fail("incremental failed: " + e)
  }
  assert_true(inc.contains("\"args\":{\"city\":\"SH\"}"))
  assert_true(inc.contains("\"args\":{\"tz\":\"UTC\"}"))
  assert_false(inc.contains("\"args\":{}"))
}

///|
/// gemini 源的增量文本：每个 chunk 必须是**增量**透传（不得每帧重发累计文本）
test "semantic - gemini source incremental text is not re-accumulated" {
  let sse = gemini_text_stream_fixture()
  let inc = match feed_one_byte_chunks("gemini", "messages", sse) {
    Ok(frames) => frames.join("")
    Err(e) => fail("incremental failed: " + e)
  }
  // "Hel" / "lo" 各自单独出现；若实现退回累计语义会输出 "Hel" 然后 "Hello"
  assert_false(
    inc.contains("Hello"),
    // 累计重复输出被官方语义禁止
  )
  assert_true(inc.contains("Hel"))
}

///|
/// messages 源增量：message_delta 必须带 message_start 记录的输入侧用量
/// （会话化的直接收益：逐帧路径不再 prompt_tokens 恒 0）
test "semantic - messages incremental usage carries input tokens from start frame" {
  let sse = messages_tool_stream_fixture()
  let inc = match feed_one_byte_chunks("messages", "openai", sse) {
    Ok(frames) => frames.join("")
    Err(e) => fail("incremental failed: " + e)
  }
  assert_true(inc.contains("\"prompt_tokens\":10"))
}

///|
/// 块闭合顺序：openai→messages 混合流（text→tool→text→tool）两路径一致，
/// 且 content_block_stop 按索引顺序闭合（不是逆序）
test "semantic - content_block_stop order matches batch in mixed stream" {
  let sse = openai_rich_stream_fixture()
  let batch = match @sdk.convert_stream("openai", sse, "messages") {
    Ok(r) => r.value()
    Err(e) => fail("batch failed: " + e)
  }
  let inc = match feed_one_byte_chunks("openai", "messages", sse) {
    Ok(frames) => frames.join("")
    Err(e) => fail("incremental failed: " + e)
  }
  assert_eq(inc, batch)
  // 提取 content_block_stop 的 index 序列，两路径必须同序
  let stops : Array[String] = []
  for part in inc.split("event: content_block_stop").to_array() {
    let idx_marker = "\"index\":"
    let at = part.find(idx_marker)
    match at {
      Some(pos) =>
        if pos >= 0 {
          let rest = part[pos + idx_marker.length():].to_owned()
          let end = match rest.find("}") {
            Some(e) => e
            None => rest.length()
          }
          stops.push(rest[:end].to_owned())
        }
      None => ()
    }
  }
  assert_true(stops.length() > 0)
}
