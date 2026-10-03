///|
/// P1-5 / P1-4 门面修复回归：decode_response_with_meta 透传解码诊断；
/// Prism::stream 可携带 PrismOptions（model / temperature 等）。

///|
/// P1-5：decode_response_with_meta 的 meta.diagnostics 必须携带解码阶段
/// 诊断。此前硬编码空数组——D8 契约宣称携带"转换损失诊断"，实际恒空，
/// 走这条路的调用方永远看不到 Degraded/Unsupported（静默通道）。
test "meta - decode_response_with_meta carries decode diagnostics" {
  let prism = @sdk.Prism::new().with_provider("responses")
  // web_search_call 是 responses→Lux 明确 Unsupported 的 server-side item
  //（见 responses/test：responses decode - server side output items yield
  // Unsupported diagnostic）
  let json = "{\"id\":\"r\",\"model\":\"m\",\"output\":[" +
    "{\"type\":\"web_search_call\",\"id\":\"ws_1\"}," +
    "{\"type\":\"message\",\"content\":[{\"type\":\"output_text\",\"text\":\"ok\"}]}" +
    "]}"
  match prism.decode_response_with_meta(json) {
    Ok(decoded) => {
      assert_eq(decoded.text, "ok")
      assert_eq(decoded.meta.source_provider, "responses")
      if decoded.meta.diagnostics.length() == 0 {
        fail("decode diagnostics were dropped by decode_response_with_meta")
      }
      let mut has_ws = false
      for d in decoded.meta.diagnostics {
        if d.field == "response.output.web_search_call" &&
          d.status == Unsupported {
          has_ws = true
        }
      }
      if !has_ws {
        fail("web_search_call Unsupported diagnostic missing from meta")
      }
    }
    Err(e) => fail("decode failed: \{e}")
  }
}

///|
/// P1-4：Prism::stream_with_options 让 PrismOptions 与 model 生效
/// （此前 stream() 硬编码 PrismOptions::default() 与 DEFAULT_MODEL，
/// L2 门面无法表达任何生成参数）。
test "stream - stream_with_options encodes model and temperature" {
  let prism = @sdk.Prism::new().with_provider("openai")
  let ctx = @sdk.Context::new().add_user("Hi")
  // PrismOptions::new(model, temperature, max_tokens, store, extras)
  let opts = @sdk.PrismOptions::new(
    Some("gpt-5-mini"),
    Some(0.3),
    None,
    None,
    None,
  )
  let captured : Array[String] = []
  match
    prism.stream_with_options(ctx, opts, fn(json) {
      captured.push(json)
      sdk_mock_sse()
    }) {
    Ok(events) => {
      assert_true(events.length() >= 2)
      if captured.length() == 0 {
        fail("mock transport never called")
      }
      // 请求 JSON 必须携带调用方显式设置的 model 与 temperature
      let json = captured[0]
      if !json.contains("\"model\":\"gpt-5-mini\"") {
        fail("stream_with_options ignored opts.model: " + json)
      }
      if !json.contains("\"temperature\":0.3") {
        fail("stream_with_options ignored opts.temperature: " + json)
      }
      if !json.contains("\"stream\":true") {
        fail("stream_with_options forgot stream flag: " + json)
      }
    }
    Err(e) => fail("stream_with_options failed: \{e}")
  }
}

///|
/// P1-4：stream() 旧签名保持兼容（委托 stream_with_options + 默认选项）。
test "stream - legacy signature still works with default options" {
  let prism = @sdk.Prism::new().with_provider("openai")
  let ctx = @sdk.Context::new().add_user("Hi")
  match prism.stream(ctx, fn(_json) { sdk_mock_sse() }) {
    Ok(events) => assert_true(events.length() >= 2)
    Err(e) => fail("stream failed: \{e}")
  }
}

///|
/// 固定 SSE fixture（与 sdk_test.mbt 的 mock_send_fixed_sse 同构：
/// 一段文本增量 + Finish(Stop)）
fn sdk_mock_sse() -> Result[String, String] {
  let events : Array[@lux.LucentStreamEvent] = [
    ConversationStart(
      @lux.LucentConversationMeta::new(
        Some("chatcmpl-1"),
        Some("gpt-5-mini"),
        None,
      ),
    ),
    BlockStart(0, Text),
    BlockDelta(0, @lux.LucentBlockDelta::text_delta("Hello")),
    BlockEnd(0),
    Finish(Stop),
    Done,
  ]
  @openai.lux_events_to_openai_sse(events).map(cr => cr.value())
}
