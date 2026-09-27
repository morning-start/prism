///|
/// CR-002 复现测试（Batch 1）：相邻缺口 A1 / D5 / A4 / A3 / A5
///
/// acceptance 1–5 见 `docs/cr/CR-002.md`。本文件先在红态落库，由 B2–B5 修复后转绿。

///|
/// Gemini 流：首帧带 responseId/modelVersion，finishReason 与 usageMetadata 同帧
fn cr002_gemini_single() -> String {
  "data: {\"responseId\":\"r-9\",\"modelVersion\":\"gemini-2.5-pro\",\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"hi\"}],\"role\":\"model\"},\"finishReason\":\"STOP\"}],\"usageMetadata\":{\"promptTokenCount\":10,\"candidatesTokenCount\":5,\"totalTokenCount\":15}}\n"
}

///|
/// Gemini 流：第一个内容帧就带 usageMetadata（中间帧形态），随后是 finishReason 帧
/// —— 这是 D5 的关键形态：逐帧路径下第一个帧末尾就会发 Done
fn cr002_gemini_multi() -> String {
  "data: {\"responseId\":\"r-9\",\"modelVersion\":\"gemini-2.5-pro\",\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"hi\"}],\"role\":\"model\"}}],\"usageMetadata\":{\"promptTokenCount\":7,\"candidatesTokenCount\":2,\"totalTokenCount\":9}}\n" +
  "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\" there\"}],\"role\":\"model\"},\"finishReason\":\"STOP\"}],\"usageMetadata\":{\"promptTokenCount\":10,\"candidatesTokenCount\":5,\"totalTokenCount\":15}}\n"
}

///|
/// Anthropic 流：message_start 携带缓存计费项（A4）
fn cr002_messages_cache() -> String {
  "event: message_start\ndata: {\"type\":\"message_start\",\"message\":{\"id\":\"msg_c\",\"model\":\"claude\",\"usage\":{\"input_tokens\":10,\"output_tokens\":1,\"cache_read_input_tokens\":7,\"cache_creation_input_tokens\":3}}}\n\n" +
  "event: content_block_start\ndata: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}\n\n" +
  "event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"hi\"}}\n\n" +
  "event: content_block_stop\ndata: {\"type\":\"content_block_stop\",\"index\":0}\n\n" +
  "event: message_delta\ndata: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\"},\"usage\":{\"output_tokens\":20}}\n\n" +
  "event: message_stop\ndata: {\"type\":\"message_stop\"}\n\n"
}

///|
/// Anthropic 截断流：块已打开但未收到 content_block_stop / message_stop（上游断连，A5）
fn cr002_messages_truncated() -> String {
  "event: message_start\ndata: {\"type\":\"message_start\",\"message\":{\"id\":\"msg_t\",\"model\":\"claude\"}}\n\n" +
  "event: content_block_start\ndata: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}\n\n" +
  "event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"partial\"}}\n\n"
}

///|
/// 1 字节切分喂入 StreamConverter，返回拼接后的输出（真实中间件逐帧路径）
fn cr002_incremental(
  source : String,
  target : String,
  sse : String,
) -> Result[String, String] {
  match @sdk.StreamConverter::new(source, target) {
    Ok(conv) => {
      let out : Array[String] = []
      let mut i = 0
      while i < sse.length() {
        match conv.feed(sse[i:i + 1].to_owned()) {
          Ok(frames) =>
            for f in frames {
              out.push(f)
            }
          Err(e) => return Err(e)
        }
        i = i + 1
      }
      match conv.finish() {
        Ok(frames) => {
          for f in frames {
            out.push(f)
          }
          Ok(out.join(""))
        }
        Err(e) => Err(e)
      }
    }
    Err(e) => Err(e)
  }
}

///|
/// 终止符出现且仅出现一次、且其后没有非空白内容
fn cr002_terminator_last(s : String, terminator : String) -> Bool {
  let parts = s.split(terminator).to_array()
  parts.length() == 2 && parts[1].trim().length() == 0
}

///|
/// 目标协议对应的终止符
fn cr002_terminator(target : String) -> String {
  if target == "openai" {
    "data: [DONE]"
  } else {
    // 不能只用 "message_stop"：它在 event 行与 data 行各出现一次
    "event: message_stop\ndata: {\"type\":\"message_stop\"}"
  }
}

///|
/// T-CR002-1 · acceptance 1：Gemini 流式产出协议合法首帧与元信息
test "CR-002 gemini stream emits conversation metadata first" {
  // messages 目标：必须有 message_start，且出现在所有内容帧之前
  match @sdk.convert_stream("gemini", cr002_gemini_single(), "messages") {
    Ok(cr) => {
      let s = cr.value()
      assert_true(s.contains("event: message_start"))
      assert_true(
        s.split("event: message_start").to_array()[0].trim().length() == 0,
      )
      assert_true(s.contains("\"id\":\"r-9\""))
      assert_true(s.contains("gemini-2.5-pro"))
    }
    Err(e) => fail("convert_stream failed: " + e)
  }
  // responses 目标：必须有 response.created
  match @sdk.convert_stream("gemini", cr002_gemini_single(), "responses") {
    Ok(cr) => {
      assert_true(cr.value().contains("event: response.created"))
      assert_true(cr.value().contains("r-9"))
    }
    Err(e) => fail("convert_stream failed: " + e)
  }
  // openai 目标：首个 chunk 带源 id/model
  match @sdk.convert_stream("gemini", cr002_gemini_single(), "openai") {
    Ok(cr) => {
      let s = cr.value()
      assert_true(s.contains("\"id\":\"r-9\""))
      assert_true(s.contains("\"model\":\"gemini-2.5-pro\""))
      // Gemini 无时间戳字段 ⇒ created 保持 0（不是缺陷）
      assert_true(s.contains("\"created\":0"))
    }
    Err(e) => fail("convert_stream failed: " + e)
  }
  // 逐帧路径同样成立
  match cr002_incremental("gemini", "messages", cr002_gemini_single()) {
    Ok(s) => {
      assert_true(s.contains("event: message_start"))
      assert_true(s.contains("\"id\":\"r-9\""))
    }
    Err(e) => fail("incremental failed: " + e)
  }
}

///|
/// T-CR002-2 · acceptance 2：任意形态下终止符只出现一次且在最后
test "CR-002 gemini multi-frame terminates once at the end" {
  for target in ["openai", "messages"] {
    let terminator = cr002_terminator(target)
    match @sdk.convert_stream("gemini", cr002_gemini_multi(), target) {
      Ok(cr) => assert_true(cr002_terminator_last(cr.value(), terminator))
      Err(e) => fail("convert_stream failed (" + target + "): " + e)
    }
    match cr002_incremental("gemini", target, cr002_gemini_multi()) {
      Ok(s) => assert_true(cr002_terminator_last(s, terminator))
      Err(e) => fail("incremental failed (" + target + "): " + e)
    }
  }
}

///|
/// T-CR002-3 · acceptance 3：message_start 透传缓存计费项，且两条路径逐字节一致
test "CR-002 messages message_start carries cache usage" {
  let expected = "\"usage\":{\"input_tokens\":10,\"cache_read_input_tokens\":7,\"cache_creation_input_tokens\":3}"
  match @sdk.convert_stream("messages", cr002_messages_cache(), "messages") {
    Ok(cr) => assert_true(cr.value().contains(expected))
    Err(e) => fail("convert_stream failed: " + e)
  }
  match cr002_incremental("messages", "messages", cr002_messages_cache()) {
    Ok(s) => assert_true(s.contains(expected))
    Err(e) => fail("incremental failed: " + e)
  }
  // 上游未提供缓存项时不得凭空输出（字节形态保持）
  let plain = "event: message_start\ndata: {\"type\":\"message_start\",\"message\":{\"id\":\"m\",\"model\":\"c\",\"usage\":{\"input_tokens\":4}}}\n\nevent: message_stop\ndata: {\"type\":\"message_stop\"}\n\n"
  match @sdk.convert_stream("messages", plain, "messages") {
    Ok(cr) => assert_false(cr.value().contains("cache_read_input_tokens"))
    Err(e) => fail("convert_stream failed: " + e)
  }
}

///|
/// T-CR002-4 · acceptance 4：IR 事件序 [Usage, Finish] 不得把用量清零
test "CR-002 messages encoder pairs usage with finish in any order" {
  let events : Array[@lux.LucentStreamEvent] = [
    ConversationStart(
      @lux.LucentConversationMeta::new(Some("m1"), Some("c1"), None),
    ),
    BlockStart(0, Text),
    BlockDelta(0, @lux.LucentBlockDelta::text_delta("hi")),
    BlockEnd(0),
    Usage(@lux.LucentUsage::new(10, 20, 30)),
    Finish(Stop),
    Done,
  ]
  match @messages.lux_events_to_messages_sse(events) {
    Ok(cr) => {
      let s = cr.value()
      assert_eq(s.split("event: message_delta").to_array().length() - 1, 1)
      assert_true(s.contains("\"output_tokens\":20"))
      assert_false(s.contains("\"output_tokens\":0"))
    }
    Err(e) => fail("encode failed: " + e)
  }
}

///|
/// T-CR002-5 · acceptance 5：截断流闭合块，两条路径逐字节一致
test "CR-002 truncated stream closes open blocks" {
  for target in ["messages", "openai"] {
    match @sdk.convert_stream("messages", cr002_messages_truncated(), target) {
      Ok(base) =>
        match
          cr002_incremental("messages", target, cr002_messages_truncated()) {
          Ok(incremental) => assert_eq(incremental, base.value())
          Err(e) => fail("incremental failed (" + target + "): " + e)
        }
      Err(e) => fail("convert_stream failed (" + target + "): " + e)
    }
  }
  // messages 目标：未闭合的块必须被补上 content_block_stop，且早于 message_stop
  match
    @sdk.convert_stream("messages", cr002_messages_truncated(), "messages") {
    Ok(cr) => {
      let s = cr.value()
      assert_true(s.contains("event: content_block_stop"))
      let stop_pos = s.split("event: content_block_stop").to_array()[0].length()
      let done_pos = s.split("message_stop").to_array()[0].length()
      assert_true(stop_pos < done_pos)
    }
    Err(e) => fail("convert_stream failed: " + e)
  }
}
