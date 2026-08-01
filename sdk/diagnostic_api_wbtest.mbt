///|
/// 转换诊断 API 在保留值的同时暴露校验边界。
test "decode_response_with_diagnostics preserves parsed response" {
  let response = "{\"id\":\"1\",\"object\":\"chat.completion\",\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"Hi\"},\"finish_reason\":\"stop\"}]}"
  let prism = Prism::new().with_provider("openai-chat")
  match prism.decode_response_with_diagnostics(response) {
    Ok(result) => {
      assert_eq(result.value().get_text(), "Hi")
      assert_eq(result.diagnostics().length(), 0)
    }
    Err(e) => fail("decode failed: " + e)
  }
}

///|
test "encode_request_with_diagnostics reports invalid options" {
  let opts = PrismOptions::new(Some("gpt-4o"), Some(-0.1), None, None, None)
  let prism = Prism::new().with_provider("openai-chat")
  match prism.encode_request_with_diagnostics("Hi", opts) {
    Ok(result) => {
      assert_true(result.value().contains("Hi"))
      assert_true(result.diagnostics().length() > 0)
      match result.diagnostics()[0].status() {
        @lux.Invalid => ()
        _ => fail("expected Invalid diagnostic")
      }
    }
    Err(e) => fail("encode failed: " + e)
  }
}
