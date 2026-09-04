///|
/// 协议符合性测试（Protocol Conformance Tests）
///
/// 验证器实现位于独立包 `src/conformance/`（`@conformance.*`，纯 core/json
/// 依赖，零 provider 依赖），供各测试子包复用。本文件只保留测试夹具与用例。
///
/// 目的：验证各 provider 编码输出是否符合**目标协议 wire format**，
/// 而不是只做 round-trip 语义等价（后者测不出"编码出的 JSON 会被真实
/// API 拒绝"的问题，例如 responses 的 `id` 字段必须是非空字符串）。

///|
/// === 测试夹具：标准 IR 请求 / 响应 ===
///
/// 与 cross_protocol_test 同源：用构造器构建 IR，避免手写 JSON。
fn std_request() -> @lux.LucentRequest {
  @lux.LucentRequest::new(
    "test-model",
    Some([@lux.LucentContent::text("You are helpful")]),
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [@lux.LucentContent::text("Hi")]),
      ),
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(Assistant, [
          @lux.LucentContent::text("Hello!"),
          @lux.LucentContent::tool_use(
            "tu_1",
            "get_weather",
            "{\"city\":\"Beijing\"}",
            None,
          ),
        ]),
      ),
      @lux.LucentConversationItem::tool_result(
        @lux.LucentToolResult::ok("tu_1", [@lux.LucentContent::text("sunny")]),
      ),
    ],
    Some([
      @lux.LucentTool::simple(
        "get_weather", "Get weather", "{\"type\":\"object\",\"properties\":{\"city\":{\"type\":\"string\"}}}",
      ),
    ]),
    Some(Auto),
    @lux.LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
}

///|
fn std_response() -> @lux.LucentResponse {
  @lux.LucentResponse::new(
    "resp_123",
    "test-model",
    Some(1700000000),
    [
      @lux.LucentChoice::new(
        0,
        @lux.LucentMessage::new(Assistant, [@lux.LucentContent::text("Hi!")]),
        Stop,
        None,
      ),
    ],
    Some(@lux.LucentUsage::full(10, 20, 30, None, None, None)),
    None,
  )
}

///|
/// === 测试：编码输出符合目标协议 wire format ===
///
/// 每个协议：请求编码 + 响应编码 → 对应验证器 → 违规列表必须为空。
/// 这能捕获 round-trip 测不出的问题（如 responses id 缺失/类型错误）。

///|
test "conformance - openai request matches chat.completions wire format" {
  match @openai.lux_request_to_openai(std_request()) {
    Ok(cr) => {
      let violations = @conformance.check_openai_request(cr.value())
      assert_eq(violations, [])
    }
    Err(e) => fail("openai encode failed: \{e}")
  }
}

///|
test "conformance - openai response matches chat.completions wire format" {
  match @openai.lux_response_to_openai(std_response()) {
    Ok(cr) => {
      let violations = @conformance.check_openai_response(cr.value())
      assert_eq(violations, [])
    }
    Err(e) => fail("openai encode failed: \{e}")
  }
}

///|
test "conformance - responses request matches responses wire format" {
  match @responses.lux_request_to_responses(std_request()) {
    Ok(cr) => {
      let violations = @conformance.check_responses_request(cr.value())
      assert_eq(violations, [])
    }
    Err(e) => fail("responses encode failed: \{e}")
  }
}

///|
test "conformance - responses response matches responses wire format" {
  match @responses.lux_response_to_responses(std_response()) {
    Ok(cr) => {
      let violations = @conformance.check_responses_response(cr.value())
      assert_eq(violations, [])
    }
    Err(e) => fail("responses encode failed: \{e}")
  }
}

///|
test "conformance - messages request matches anthropic wire format" {
  match @messages.lux_request_to_messages(std_request()) {
    Ok(cr) => {
      let violations = @conformance.check_messages_request(cr.value())
      assert_eq(violations, [])
    }
    Err(e) => fail("messages encode failed: \{e}")
  }
}

///|
test "conformance - messages response matches anthropic wire format" {
  match @messages.lux_response_to_messages(std_response()) {
    Ok(cr) => {
      let violations = @conformance.check_messages_response(cr.value())
      assert_eq(violations, [])
    }
    Err(e) => fail("messages encode failed: \{e}")
  }
}

///|
test "conformance - gemini request matches gemini wire format" {
  match @gemini.lux_request_to_gemini(std_request()) {
    Ok(cr) => {
      let violations = @conformance.check_gemini_request(cr.value())
      assert_eq(violations, [])
    }
    Err(e) => fail("gemini encode failed: \{e}")
  }
}

///|
test "conformance - gemini response matches gemini wire format" {
  match @gemini.lux_response_to_gemini(std_response()) {
    Ok(cr) => {
      let violations = @conformance.check_gemini_response(cr.value())
      assert_eq(violations, [])
    }
    Err(e) => fail("gemini encode failed: \{e}")
  }
}

///|
/// === 测试：验证器本身能捕获协议违规（负例回归）===
///
/// 确保验证器不是"永远通过"的空壳：对已知违规输入必须报出违规。

///|
test "conformance - validator catches missing responses id" {
  // responses 响应缺少 id → 必须被捕获
  let bad = "{\"object\":\"response\",\"status\":\"completed\",\"model\":\"m\",\"output\":[]}"
  let violations = @conformance.check_responses_response(bad)
  assert_true(violations.length() > 0)
  assert_true(violations.contains("resp.id is missing"))
}

///|
test "conformance - validator catches non-string responses function_call id" {
  // function_call 的 id 是数字 → 必须被捕获（"Expected 'id' to be a string" 场景）
  let bad = "{\"object\":\"response\",\"status\":\"completed\",\"model\":\"m\",\"output\":[{\"type\":\"function_call\",\"id\":123,\"call_id\":\"c1\",\"name\":\"f\",\"arguments\":\"{}\"}]}"
  let violations = @conformance.check_responses_response(bad)
  assert_true(violations.length() > 0)
  assert_true(violations.contains("resp.output[0].id must be a string"))
}

///|
test "conformance - validator catches empty openai id" {
  let bad = "{\"id\":\"\",\"object\":\"chat.completion\",\"model\":\"m\",\"choices\":[]}"
  let violations = @conformance.check_openai_response(bad)
  assert_true(violations.length() > 0)
  assert_true(violations.contains("resp.id must not be empty"))
}
