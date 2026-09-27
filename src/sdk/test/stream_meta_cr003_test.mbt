///|
/// CR-003 复现测试：R1（message_start.usage 补 output_tokens）
/// 与 R2（Gemini 无可解析帧时也发首帧）。断言见 `change-request-CR-003.md`。

///|
/// R1：messages 目标的 message_start.usage 必须同时给出 input_tokens 与 output_tokens
test "CR-003 R1 message_start carries output tokens" {
  let sse = "event: message_start\ndata: {\"type\":\"message_start\",\"message\":{\"id\":\"m1\",\"model\":\"claude\",\"usage\":{\"input_tokens\":9,\"cache_read_input_tokens\":4}}}\n\nevent: message_stop\ndata: {\"type\":\"message_stop\"}\n\n"
  match @sdk.convert_stream("messages", sse, "messages") {
    Ok(cr) => {
      let s = cr.value()
      assert_true(s.contains("\"input_tokens\":9"))
      assert_true(s.contains("\"output_tokens\":1"))
      // 缓存项仍在同一 usage 对象内（CR-002 A4 不回退）
      assert_true(s.contains("\"cache_read_input_tokens\":4"))
      // 顺序：input_tokens → 缓存项 → output_tokens
      let usage_pos = s.split("\"usage\":{").to_array()[0].length()
      let out_pos = s.split("\"output_tokens\":1").to_array()[0].length()
      assert_true(usage_pos < out_pos)
    }
    Err(e) => fail("convert_stream failed: " + e)
  }
}

///|
/// R2：Gemini 输入没有任何可解析帧时，退化流仍要产出目标协议的协议首帧
test "CR-003 R2 gemini empty stream still emits first frame" {
  // 空流
  match @sdk.convert_stream("gemini", "", "messages") {
    Ok(cr) =>
      assert_true(
        cr
        .value()
        .contains("event: message_start\ndata: {\"type\":\"message_start\""),
      )
    Err(e) => fail("convert_stream failed: " + e)
  }
  match @sdk.convert_stream("gemini", "", "responses") {
    Ok(cr) => assert_true(cr.value().contains("event: response.created"))
    Err(e) => fail("convert_stream failed: " + e)
  }
  // 仅非法帧
  match @sdk.convert_stream("gemini", "data: {oops\n", "messages") {
    Ok(cr) => assert_true(cr.value().contains("event: message_start"))
    Err(e) => fail("convert_stream failed: " + e)
  }
  // 有可解析帧时行为不变（字段取自该帧）
  match
    @sdk.convert_stream(
      "gemini", "data: {\"responseId\":\"r-3\",\"modelVersion\":\"gemini-2.5-pro\",\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"hi\"}],\"role\":\"model\"},\"finishReason\":\"STOP\"}]}\n",
      "messages",
    ) {
    Ok(cr) => {
      assert_true(cr.value().contains("event: message_start"))
      assert_true(cr.value().contains("\"id\":\"r-3\""))
    }
    Err(e) => fail("convert_stream failed: " + e)
  }
}
