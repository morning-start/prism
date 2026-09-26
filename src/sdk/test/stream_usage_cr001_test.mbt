///|
/// CR-001 复现测试（Batch 1）：流式 usage 保真
///
/// acceptance 1–5 见 `docs/cr/CR-001.md`。本文件先在红态落库（B1），
/// 由 B2/B3/B4 分别修复后转绿；断言必须写成对"目标行为"的描述，
/// 不得为迁就现状而放宽。

///|
/// messages 源 SSE：message_start（输入侧用量 + 缓存计费项）+ 文本 + message_delta（输出侧用量）
fn cr001_messages_sse() -> String {
  "event: message_start\ndata: {\"type\":\"message_start\",\"message\":{\"id\":\"msg_1\",\"type\":\"message\",\"role\":\"assistant\",\"content\":[],\"model\":\"claude\",\"stop_reason\":null,\"usage\":{\"input_tokens\":10,\"output_tokens\":1,\"cache_read_input_tokens\":7,\"cache_creation_input_tokens\":3}}}\n\n" +
  "event: content_block_start\ndata: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}\n\n" +
  "event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"hi\"}}\n\n" +
  "event: content_block_stop\ndata: {\"type\":\"content_block_stop\",\"index\":0}\n\n" +
  "event: message_delta\ndata: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\"},\"usage\":{\"output_tokens\":20}}\n\n" +
  "event: message_stop\ndata: {\"type\":\"message_stop\"}\n\n"
}

///|
/// messages 源 SSE：缓存计费项挂在 message_delta.usage（另一种上游形态）
fn cr001_messages_sse_delta_cache() -> String {
  "event: message_start\ndata: {\"type\":\"message_start\",\"message\":{\"id\":\"msg_2\",\"type\":\"message\",\"role\":\"assistant\",\"content\":[],\"model\":\"claude\",\"stop_reason\":null,\"usage\":{\"input_tokens\":10,\"output_tokens\":1}}}\n\n" +
  "event: content_block_start\ndata: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}\n\n" +
  "event: content_block_stop\ndata: {\"type\":\"content_block_stop\",\"index\":0}\n\n" +
  "event: message_delta\ndata: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\"},\"usage\":{\"output_tokens\":20,\"input_tokens\":10,\"cache_read_input_tokens\":5,\"cache_creation_input_tokens\":2}}\n\n" +
  "event: message_stop\ndata: {\"type\":\"message_stop\"}\n\n"
}

///|
/// Gemini 上游形态一：finishReason 与 usageMetadata 同帧（仓库既有 fixture 形态）
fn cr001_gemini_same_frame() -> String {
  "data: {\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"text\":\"hi\"}]},\"finishReason\":\"STOP\"}],\"usageMetadata\":{\"promptTokenCount\":10,\"candidatesTokenCount\":5,\"totalTokenCount\":15}}\n"
}

///|
/// Gemini 上游形态二：finishReason 帧与 usageMetadata 帧分离（另一种真实形态）
fn cr001_gemini_split_frames() -> String {
  "data: {\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"text\":\"hi\"}]},\"finishReason\":\"STOP\"}]}\n" +
  "data: {\"usageMetadata\":{\"promptTokenCount\":10,\"candidatesTokenCount\":5,\"totalTokenCount\":15}}\n"
}

///|
/// 1 字节切分喂入 StreamConverter，返回拼接后的输出（真实中间件逐帧路径）
fn cr001_one_byte_chunks(
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
/// usage 帧是否出现在 `data: [DONE]` 之前（无 [DONE] 时报 false：该目标不带该终止符）
fn cr001_usage_before_done(s : String) -> Bool {
  let done_parts = s.split("[DONE]").to_array()
  if done_parts.length() < 2 {
    false
  } else {
    let usage_pos = s.split("\"usage\"").to_array()[0].length()
    usage_pos < done_parts[0].length()
  }
}

///|
/// T1.1 · acceptance 1：messages→openai 的 usage 含输入侧用量与缓存项
test "CR-001 T1.1 messages to openai stream usage carries input tokens" {
  match @sdk.convert_stream("messages", cr001_messages_sse(), "openai") {
    Ok(cr) => {
      let s = cr.value()
      assert_true(s.contains("\"prompt_tokens\":10"))
      assert_true(s.contains("\"completion_tokens\":20"))
      assert_true(s.contains("\"total_tokens\":30"))
      assert_true(s.contains("\"cached_tokens\":7"))
    }
    Err(e) => fail("convert_stream failed: " + e)
  }
}

///|
/// T1.1b · acceptance 1：缓存项也可来自 message_delta.usage
test "CR-001 T1.1b messages to openai reads cache fields from message_delta" {
  match
    @sdk.convert_stream("messages", cr001_messages_sse_delta_cache(), "openai") {
    Ok(cr) => {
      let s = cr.value()
      assert_true(s.contains("\"prompt_tokens\":10"))
      assert_true(s.contains("\"total_tokens\":30"))
      assert_true(s.contains("\"cached_tokens\":5"))
    }
    Err(e) => fail("convert_stream failed: " + e)
  }
}

///|
/// T1.2 · acceptance 2：messages→messages 只保留一条带 usage 的 message_delta
test "CR-001 T1.2 messages to messages keeps a single usage message_delta" {
  match cr001_one_byte_chunks("messages", "messages", cr001_messages_sse()) {
    Ok(s) => {
      assert_eq(s.split("event: message_delta").to_array().length() - 1, 1)
      assert_true(s.contains("\"output_tokens\":20"))
      assert_false(s.contains("\"output_tokens\":0"))
      // acceptance 1：缓存计费项在 messages 目标端同样输出
      // （message_delta.usage 的 cache_read / cache_creation 是 Anthropic 计费核心）
      assert_true(s.contains("\"cache_read_input_tokens\":7"))
      assert_true(s.contains("\"cache_creation_input_tokens\":3"))
    }
    Err(e) => fail("incremental convert failed: " + e)
  }
}

///|
/// T1.2b · acceptance 3：messages 源增量输出与整缓冲逐字节一致
test "CR-001 T1.2b stream converter byte-identical for messages source" {
  for target in ["openai", "messages"] {
    match @sdk.convert_stream("messages", cr001_messages_sse(), target) {
      Ok(base) =>
        match cr001_one_byte_chunks("messages", target, cr001_messages_sse()) {
          Ok(incremental) => assert_eq(incremental, base.value())
          Err(e) => fail("incremental failed (" + target + "): " + e)
        }
      Err(e) => fail("convert_stream failed (" + target + "): " + e)
    }
  }
}

///|
/// T1.3 · acceptance 4：gemini→openai 的 usage 帧早于 [DONE]（两种上游形态 × 两条路径）
test "CR-001 T1.3 gemini to openai emits usage before done" {
  for sse in [cr001_gemini_same_frame(), cr001_gemini_split_frames()] {
    match @sdk.convert_stream("gemini", sse, "openai") {
      Ok(cr) => assert_true(cr001_usage_before_done(cr.value()))
      Err(e) => fail("convert_stream failed: " + e)
    }
    match cr001_one_byte_chunks("gemini", "openai", sse) {
      Ok(s) => assert_true(cr001_usage_before_done(s))
      Err(e) => fail("incremental failed: " + e)
    }
  }
}

///|
/// T1.3b · acceptance 4：gemini→messages 的 output_tokens 正确（同帧与分离两帧）
test "CR-001 T1.3b gemini to messages keeps output tokens" {
  for sse in [cr001_gemini_same_frame(), cr001_gemini_split_frames()] {
    match @sdk.convert_stream("gemini", sse, "messages") {
      Ok(cr) => assert_true(cr.value().contains("\"output_tokens\":5"))
      Err(e) => fail("convert_stream failed: " + e)
    }
  }
}

///|
/// T1.4 · acceptance 5：openai 出站流式请求注入 stream_options.include_usage
test "CR-001 T1.4 openai outbound streaming request injects include_usage" {
  let req = "{\"model\":\"gpt-4o\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"stream\":true}"
  match @sdk.convert_request("openai", req, "openai") {
    Ok(cr) =>
      assert_true(
        cr.value().contains("\"stream_options\":{\"include_usage\":true}"),
      )
    Err(e) => fail("convert_request failed: " + e)
  }
  // 中间件场景：Anthropic 格式来源 → openai 目标（调用方无法表达 stream_options）
  let anthropic_req = "{\"model\":\"claude\",\"max_tokens\":64,\"stream\":true,\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}"
  match @sdk.convert_request("messages", anthropic_req, "openai") {
    Ok(cr) =>
      assert_true(
        cr.value().contains("\"stream_options\":{\"include_usage\":true}"),
      )
    Err(e) => fail("convert_request failed: " + e)
  }
}

///|
/// T1.4b · acceptance 5：调用方自带 stream_options 优先，不被覆盖；非流式不注入
test "CR-001 T1.4b caller stream_options wins and non-stream stays clean" {
  let req = "{\"model\":\"gpt-4o\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"stream\":true,\"stream_options\":{\"include_obfuscation\":true}}"
  match @sdk.convert_request("openai", req, "openai") {
    Ok(cr) => {
      assert_true(cr.value().contains("\"include_obfuscation\":true"))
      assert_false(cr.value().contains("\"include_usage\":true"))
    }
    Err(e) => fail("convert_request failed: " + e)
  }
  let plain = "{\"model\":\"gpt-4o\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}"
  match @sdk.convert_request("openai", plain, "openai") {
    Ok(cr) => assert_false(cr.value().contains("stream_options"))
    Err(e) => fail("convert_request failed: " + e)
  }
}
