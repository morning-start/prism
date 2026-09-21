///|
/// SDK 基础示例测试 — 冒烟集
///
/// 只保留 README 快速开始场景的端到端验证：编码请求、切换 provider、
/// mock transport 完整往返。SDK 门面的完整行为覆盖见
/// `src/sdk/test/sdk_test.mbt`（含 context/tools/stream/error/capability），
/// 此处不再重复同义断言；示例本身的可编译性由 moon check 门禁保证。

///|
/// 快速开始：Prism 编码请求返回合法 JSON
test "L1 - encode request returns valid JSON" {
  let prism = @sdk.Prism::new().with_provider("openai")
  let result = prism.encode_request("Hello", @sdk.PrismOptions::default())
  match result {
    Ok(json) => {
      assert_true(json.length() > 0)
      assert_true(json.contains("model"))
      assert_true(json.contains("messages"))
    }
    Err(e) => fail("encode failed: " + e)
  }
}

///|
/// 切换 provider 只改一个名字，输出格式随之变化
test "L1 - switch provider changes format" {
  let openai = @sdk.Prism::new().with_provider("responses")
  let anthropic = @sdk.Prism::new().with_provider("messages")

  let openai_result = openai.encode_request(
    "Hello",
    @sdk.PrismOptions::default(),
  )
  let anthropic_result = anthropic.encode_request(
    "Hello",
    @sdk.PrismOptions::default(),
  )

  match (openai_result, anthropic_result) {
    (Ok(o), Ok(a)) => {
      // Different providers should produce different JSON formats
      assert_true(o.contains("\"input\"")) // OpenAI Responses uses input
      assert_true(a.contains("\"messages\"")) // Anthropic uses messages
    }
    _ => fail("Both should succeed")
  }
}

///|
/// 完整调用：文本进、文本出（mock transport，见 USAGE.md）
test "L1 - complete with mock transport" {
  let prism = @sdk.Prism::new().with_provider("openai")

  fn mock_send(_req : String) -> Result[String, String] {
    Ok(
      "{\"id\":\"resp-1\",\"object\":\"chat.completion\",\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"Hi there!\"},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":5,\"completion_tokens\":3,\"total_tokens\":8}}",
    )
  }

  let result = prism.complete("Hello", @sdk.PrismOptions::default(), mock_send)
  match result {
    Ok(text) => assert_eq(text, "Hi there!")
    Err(e) => fail("complete failed: " + e)
  }
}
