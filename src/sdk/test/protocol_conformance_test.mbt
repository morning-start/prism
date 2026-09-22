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

///|
/// === 测试：违规检出分支全覆盖（每个检测分支一个用例）===
///
/// 正面用例只验证"合法输入 → 0 违规"；验证器内部的分支（缺失/类型错误/
/// 空值/非法枚举/非法 JSON 字符串/非对象输入）需要负例驱动，否则
/// "永远通过"与"正确放行"无法区分。每个用例断言违规列表中包含精确违规串。

///|
fn assert_violation(
  violations : Array[String],
  expect : String,
  input : String,
) -> Unit raise {
  if !violations.contains(expect) {
    // 不插值 violations 本身：数组的 Show 插值已弃用，expect+input 足以定位用例
    fail("expected violation: \{expect} | input: \{input}")
  }
}

///|
/// check_openai_request：缺失/类型/空值/枚举/arguments/stream 各分支
test "conformance - openai request violation branches" {
  let cases : Array[(String, String)] = [
    ("not json", "invalid JSON"),
    ("123", "req.model is missing"),
    ("{\"messages\":[]}", "req.model is missing"),
    ("{\"model\":\"\",\"messages\":[]}", "req.model must not be empty"),
    ("{\"model\":42,\"messages\":[]}", "req.model must be a string"),
    ("{\"model\":\"m\",\"messages\":\"x\"}", "req.messages must be an array"),
    ("{\"model\":\"m\"}", "req.messages is missing"),
    (
      "{\"model\":\"m\",\"messages\":[{\"role\":\"bot\",\"content\":\"hi\"}]}", "req.messages[0].role must be one of [system, user, assistant, tool, developer], got \"bot\"",
    ),
    (
      "{\"model\":\"m\",\"messages\":[{\"role\":42,\"content\":\"hi\"}]}", "req.messages[0].role must be a string",
    ),
    (
      "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":42}]}", "req.messages[0].content must be a string or array",
    ),
    (
      "{\"model\":\"m\",\"messages\":[{\"role\":\"user\"}]}", "req.messages[0].content is missing",
    ),
    (
      "{\"model\":\"m\",\"messages\":[{\"role\":\"assistant\",\"content\":\"x\",\"tool_calls\":[{}]}]}",
      "req.messages[0].tool_calls[0].id is missing",
    ),
    (
      "{\"model\":\"m\",\"messages\":[{\"role\":\"assistant\",\"content\":\"x\",\"tool_calls\":[{\"id\":\"t1\"}]}]}",
      "req.messages[0].tool_calls[0].function is missing",
    ),
    (
      "{\"model\":\"m\",\"messages\":[{\"role\":\"assistant\",\"content\":\"x\",\"tool_calls\":[{\"id\":\"t1\",\"function\":{\"arguments\":\"oops\"}}]}]}",
      "req.messages[0].tool_calls[0].function.arguments must be valid JSON",
    ),
    (
      "{\"model\":\"m\",\"messages\":[{\"role\":\"assistant\",\"content\":\"x\",\"tool_calls\":[{\"id\":\"t1\",\"function\":{}}]}]}",
      "req.messages[0].tool_calls[0].function.name is missing",
    ),
    (
      "{\"model\":\"m\",\"messages\":[],\"tools\":[{}]}", "req.tools[0].type is missing",
    ),
    (
      "{\"model\":\"m\",\"messages\":[],\"tools\":[{\"type\":\"web\"}]}", "req.tools[0].type must be one of [function], got \"web\"",
    ),
    (
      "{\"model\":\"m\",\"messages\":[],\"tools\":[{\"type\":\"function\"}]}", "req.tools[0].function is missing",
    ),
    (
      "{\"model\":\"m\",\"messages\":[],\"tools\":[{\"type\":\"function\",\"function\":{\"name\":\"f\",\"parameters\":\"x\"}}]}",
      "req.tools[0].function.parameters must be an object",
    ),
    (
      "{\"model\":\"m\",\"messages\":[],\"tools\":[{\"type\":\"function\",\"function\":{\"name\":\"f\"}}]}",
      "req.tools[0].function.parameters is missing",
    ),
    (
      "{\"model\":\"m\",\"messages\":[],\"stream\":\"yes\"}", "req.stream must be a boolean",
    ),
  ]
  for c in cases {
    assert_violation(@conformance.check_openai_request(c.0), c.1, c.0)
  }
}

///|
/// check_openai_response：object/index/message/usage 各分支
test "conformance - openai response violation branches" {
  let cases : Array[(String, String)] = [
    ("not json", "invalid JSON"),
    ("[1,2]", "resp.id is missing"),
    (
      "{\"id\":42,\"object\":\"chat.completion\",\"model\":\"m\",\"choices\":[]}",
      "resp.id must be a string",
    ),
    (
      "{\"id\":\"x\",\"object\":\"resp\",\"model\":\"m\",\"choices\":[]}", "resp.object must be one of [chat.completion], got \"resp\"",
    ),
    (
      "{\"id\":\"x\",\"object\":\"chat.completion\",\"choices\":[]}", "resp.model is missing",
    ),
    (
      "{\"id\":\"x\",\"object\":\"chat.completion\",\"model\":\"m\"}", "resp.choices is missing",
    ),
    (
      "{\"id\":\"x\",\"object\":\"chat.completion\",\"model\":\"m\",\"choices\":{}}",
      "resp.choices must be an array",
    ),
    (
      "{\"id\":\"x\",\"object\":\"chat.completion\",\"model\":\"m\",\"choices\":[]}",
      "resp.choices must not be empty",
    ),
    (
      "{\"id\":\"x\",\"object\":\"chat.completion\",\"model\":\"m\",\"choices\":[{\"message\":{\"role\":\"assistant\",\"content\":\"x\"},\"finish_reason\":\"stop\"}]}",
      "resp.choices[0].index is missing",
    ),
    (
      "{\"id\":\"x\",\"object\":\"chat.completion\",\"model\":\"m\",\"choices\":[{\"index\":0,\"finish_reason\":\"stop\"}]}",
      "resp.choices[0].message is missing",
    ),
    (
      "{\"id\":\"x\",\"object\":\"chat.completion\",\"model\":\"m\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"bot\",\"content\":\"x\"},\"finish_reason\":\"stop\"}]}",
      "resp.choices[0].message.role must be one of [assistant, system, user, tool], got \"bot\"",
    ),
    (
      "{\"id\":\"x\",\"object\":\"chat.completion\",\"model\":\"m\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":42},\"finish_reason\":\"stop\"}]}",
      "resp.choices[0].message.content must be a string, null or array",
    ),
    (
      "{\"id\":\"x\",\"object\":\"chat.completion\",\"model\":\"m\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\"},\"finish_reason\":\"stop\"}]}",
      "resp.choices[0].message.content is missing",
    ),
    (
      "{\"id\":\"x\",\"object\":\"chat.completion\",\"model\":\"m\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"x\"},\"finish_reason\":\"halt\"}]}",
      "resp.choices[0].finish_reason must be one of [stop, length, tool_calls, content_filter, function_call], got \"halt\"",
    ),
    (
      "{\"id\":\"x\",\"object\":\"chat.completion\",\"model\":\"m\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"x\"},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":1}}",
      "resp.usage.completion_tokens is missing",
    ),
  ]
  for c in cases {
    assert_violation(@conformance.check_openai_response(c.0), c.1, c.0)
  }
}

///|
/// check_responses_request：input 四类型 / tools / continue 分支
test "conformance - responses request violation branches" {
  let cases : Array[(String, String)] = [
    ("not json", "invalid JSON"),
    ("\"str\"", "req.model is missing"),
    ("{\"input\":[]}", "req.model is missing"),
    ("{\"model\":\"\",\"input\":[]}", "req.model must not be empty"),
    ("{\"model\":42,\"input\":[]}", "req.model must be a string"),
    ("{\"model\":\"m\",\"input\":\"x\"}", "req.input must be an array"),
    ("{\"model\":\"m\"}", "req.input is missing"),
    (
      "{\"model\":\"m\",\"input\":[{\"type\":\"bogus\"}]}", "req.input[0].type must be one of [message, function_call, function_call_output, reasoning], got \"bogus\"",
    ),
    (
      "{\"model\":\"m\",\"input\":[{\"type\":42}]}", "req.input[0].type must be a string",
    ),
    (
      "{\"model\":\"m\",\"input\":[{\"type\":\"message\",\"role\":\"bot\",\"content\":[]}]}",
      "req.input[0].role must be one of [user, assistant, system, developer], got \"bot\"",
    ),
    (
      "{\"model\":\"m\",\"input\":[{\"type\":\"message\",\"role\":\"user\"}]}", "req.input[0].content is missing",
    ),
    (
      "{\"model\":\"m\",\"input\":[{\"type\":\"message\",\"role\":\"user\",\"content\":[{\"text\":\"x\"}]}]}",
      "req.input[0].content[0].type is missing",
    ),
    (
      "{\"model\":\"m\",\"input\":[{\"type\":\"message\",\"role\":\"user\",\"content\":[{\"type\":\"input_text\"}]}]}",
      "req.input[0].content[0].text is missing",
    ),
    (
      "{\"model\":\"m\",\"input\":[{\"type\":\"function_call\",\"arguments\":\"oops\"}]}",
      "req.input[0].id is missing",
    ),
    (
      "{\"model\":\"m\",\"input\":[{\"type\":\"function_call\",\"id\":\"a\",\"call_id\":\"b\",\"name\":\"f\",\"arguments\":\"oops\"}]}",
      "req.input[0].arguments must be valid JSON",
    ),
    (
      "{\"model\":\"m\",\"input\":[{\"type\":\"function_call_output\",\"output\":\"o\"}]}",
      "req.input[0].call_id is missing",
    ),
    (
      "{\"model\":\"m\",\"input\":[{\"type\":\"function_call_output\",\"call_id\":\"c\"}]}",
      "req.input[0].output is missing",
    ),
    (
      "{\"model\":\"m\",\"input\":[],\"tools\":[{\"type\":\"nope\"}]}", "req.tools[0].type must be one of [function, file_search, web_search, code_interpreter, computer_use, mcp], got \"nope\"",
    ),
    (
      "{\"model\":\"m\",\"input\":[],\"tools\":[{\"type\":\"function\"}]}", "req.tools[0].name is missing",
    ),
  ]
  for c in cases {
    assert_violation(@conformance.check_responses_request(c.0), c.1, c.0)
  }
}

///|
/// check_responses_response：output 类型 / message / function_call 分支
test "conformance - responses response violation branches" {
  let cases : Array[(String, String)] = [
    ("not json", "invalid JSON"),
    ("123", "resp.id is missing"),
    (
      "{\"object\":\"response\",\"status\":\"completed\",\"model\":\"m\",\"output\":[]}",
      "resp.id is missing",
    ),
    (
      "{\"id\":\"\",\"object\":\"response\",\"status\":\"completed\",\"model\":\"m\",\"output\":[]}",
      "resp.id must not be empty",
    ),
    (
      "{\"id\":\"x\",\"object\":\"resp\",\"status\":\"completed\",\"model\":\"m\",\"output\":[]}",
      "resp.object must be one of [response], got \"resp\"",
    ),
    (
      "{\"id\":\"x\",\"object\":\"response\",\"status\":\"weird\",\"model\":\"m\",\"output\":[]}",
      "resp.status must be one of [completed, incomplete, failed], got \"weird\"",
    ),
    (
      "{\"id\":\"x\",\"object\":\"response\",\"status\":\"completed\",\"output\":[]}",
      "resp.model is missing",
    ),
    (
      "{\"id\":\"x\",\"object\":\"response\",\"status\":\"completed\",\"model\":\"m\"}",
      "resp.output is missing",
    ),
    (
      "{\"id\":\"x\",\"object\":\"response\",\"status\":\"completed\",\"model\":\"m\",\"output\":{}}",
      "resp.output must be an array",
    ),
    (
      "{\"id\":\"x\",\"object\":\"response\",\"status\":\"completed\",\"model\":\"m\",\"output\":[{\"type\":\"bogus\"}]}",
      "resp.output[0].type must be one of [message, function_call, reasoning, function_call_output], got \"bogus\"",
    ),
    (
      "{\"id\":\"x\",\"object\":\"response\",\"status\":\"completed\",\"model\":\"m\",\"output\":[{\"type\":\"message\",\"role\":\"user\",\"content\":[]}]}",
      "resp.output[0].id is missing",
    ),
    (
      "{\"id\":\"x\",\"object\":\"response\",\"status\":\"completed\",\"model\":\"m\",\"output\":[{\"type\":\"message\",\"id\":\"i\",\"role\":\"bot\",\"content\":[]}]}",
      "resp.output[0].role must be one of [assistant], got \"bot\"",
    ),
    (
      "{\"id\":\"x\",\"object\":\"response\",\"status\":\"completed\",\"model\":\"m\",\"output\":[{\"type\":\"message\",\"id\":\"i\",\"role\":\"assistant\"}]}",
      "resp.output[0].content is missing",
    ),
    (
      "{\"id\":\"x\",\"object\":\"response\",\"status\":\"completed\",\"model\":\"m\",\"output\":[{\"type\":\"message\",\"id\":\"i\",\"role\":\"assistant\",\"content\":[{\"type\":\"output_text\"}]}]}",
      "resp.output[0].content[0].text is missing",
    ),
    (
      "{\"id\":\"x\",\"object\":\"response\",\"status\":\"completed\",\"model\":\"m\",\"output\":[{\"type\":\"function_call\",\"arguments\":\"oops\"}]}",
      "resp.output[0].id is missing",
    ),
    (
      "{\"id\":\"x\",\"object\":\"response\",\"status\":\"completed\",\"model\":\"m\",\"output\":[{\"type\":\"function_call\",\"id\":\"a\",\"call_id\":\"b\",\"name\":\"f\",\"arguments\":\"oops\"}]}",
      "resp.output[0].arguments must be valid JSON",
    ),
  ]
  for c in cases {
    assert_violation(@conformance.check_responses_response(c.0), c.1, c.0)
  }
}

///|
/// check_messages_request：max_tokens / blocks 类型 / tools 分支
test "conformance - messages request violation branches" {
  let cases : Array[(String, String)] = [
    ("not json", "invalid JSON"),
    ("42", "req.model is missing"),
    ("{\"max_tokens\":10,\"messages\":[]}", "req.model is missing"),
    ("{\"model\":\"m\",\"messages\":[]}", "req.max_tokens is missing"),
    (
      "{\"model\":\"m\",\"max_tokens\":\"10\",\"messages\":[]}", "req.max_tokens must be a number",
    ),
    (
      "{\"model\":\"m\",\"max_tokens\":0,\"messages\":[]}", "req.max_tokens must be >= 1",
    ),
    (
      "{\"model\":\"m\",\"max_tokens\":10,\"messages\":\"x\"}", "req.messages must be an array",
    ),
    (
      "{\"model\":\"m\",\"max_tokens\":10,\"messages\":[{\"role\":\"bot\",\"content\":\"hi\"}]}",
      "req.messages[0].role must be one of [user, assistant], got \"bot\"",
    ),
    (
      "{\"model\":\"m\",\"max_tokens\":10,\"messages\":[{\"role\":\"user\",\"content\":42}]}",
      "req.messages[0].content must be a string or array",
    ),
    (
      "{\"model\":\"m\",\"max_tokens\":10,\"messages\":[{\"role\":\"user\"}]}", "req.messages[0].content is missing",
    ),
    (
      "{\"model\":\"m\",\"max_tokens\":10,\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"bogus\"}]}]}",
      "req.messages[0].content[0].type must be one of [text, image, tool_use, tool_result, thinking], got \"bogus\"",
    ),
    (
      "{\"model\":\"m\",\"max_tokens\":10,\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"text\"}]}]}",
      "req.messages[0].content[0].text is missing",
    ),
    (
      "{\"model\":\"m\",\"max_tokens\":10,\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"tool_use\",\"name\":\"f\",\"input\":{}}]}]}",
      "req.messages[0].content[0].id is missing",
    ),
    (
      "{\"model\":\"m\",\"max_tokens\":10,\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"tool_use\",\"id\":\"t\",\"input\":{}}]}]}",
      "req.messages[0].content[0].name is missing",
    ),
    (
      "{\"model\":\"m\",\"max_tokens\":10,\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"tool_use\",\"id\":\"t\",\"name\":\"f\",\"input\":\"x\"}]}]}",
      "req.messages[0].content[0].input must be an object",
    ),
    (
      "{\"model\":\"m\",\"max_tokens\":10,\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"tool_use\",\"id\":\"t\",\"name\":\"f\"}]}]}",
      "req.messages[0].content[0].input is missing",
    ),
    (
      "{\"model\":\"m\",\"max_tokens\":10,\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"tool_result\",\"content\":\"x\"}]}]}",
      "req.messages[0].content[0].tool_use_id is missing",
    ),
    (
      "{\"model\":\"m\",\"max_tokens\":10,\"messages\":[],\"tools\":[{}]}", "req.tools[0].name is missing",
    ),
    (
      "{\"model\":\"m\",\"max_tokens\":10,\"messages\":[],\"tools\":[{\"name\":\"f\",\"input_schema\":\"x\"}]}",
      "req.tools[0].input_schema must be an object",
    ),
    (
      "{\"model\":\"m\",\"max_tokens\":10,\"messages\":[],\"tools\":[{\"name\":\"f\"}]}",
      "req.tools[0].input_schema is missing",
    ),
  ]
  for c in cases {
    assert_violation(@conformance.check_messages_request(c.0), c.1, c.0)
  }
}

///|
/// check_messages_response：type/role/content blocks/stop_reason 分支
test "conformance - messages response violation branches" {
  let cases : Array[(String, String)] = [
    ("not json", "invalid JSON"),
    ("true", "resp.id is missing"),
    (
      "{\"type\":\"message\",\"role\":\"assistant\",\"model\":\"m\",\"content\":[],\"stop_reason\":\"end_turn\"}",
      "resp.id is missing",
    ),
    (
      "{\"id\":\"\",\"type\":\"message\",\"role\":\"assistant\",\"model\":\"m\",\"content\":[],\"stop_reason\":\"end_turn\"}",
      "resp.id must not be empty",
    ),
    (
      "{\"id\":\"x\",\"type\":\"msg\",\"role\":\"assistant\",\"model\":\"m\",\"content\":[],\"stop_reason\":\"end_turn\"}",
      "resp.type must be one of [message], got \"msg\"",
    ),
    (
      "{\"id\":\"x\",\"type\":\"message\",\"role\":\"bot\",\"model\":\"m\",\"content\":[],\"stop_reason\":\"end_turn\"}",
      "resp.role must be one of [assistant], got \"bot\"",
    ),
    (
      "{\"id\":\"x\",\"type\":\"message\",\"role\":\"assistant\",\"content\":[],\"stop_reason\":\"end_turn\"}",
      "resp.model is missing",
    ),
    (
      "{\"id\":\"x\",\"type\":\"message\",\"role\":\"assistant\",\"model\":\"m\",\"stop_reason\":\"end_turn\"}",
      "resp.content is missing",
    ),
    (
      "{\"id\":\"x\",\"type\":\"message\",\"role\":\"assistant\",\"model\":\"m\",\"content\":{},\"stop_reason\":\"end_turn\"}",
      "resp.content must be an array",
    ),
    (
      "{\"id\":\"x\",\"type\":\"message\",\"role\":\"assistant\",\"model\":\"m\",\"content\":[{\"type\":\"bogus\"}],\"stop_reason\":\"end_turn\"}",
      "resp.content[0].type must be one of [text, tool_use, thinking], got \"bogus\"",
    ),
    (
      "{\"id\":\"x\",\"type\":\"message\",\"role\":\"assistant\",\"model\":\"m\",\"content\":[{\"type\":\"text\"}],\"stop_reason\":\"end_turn\"}",
      "resp.content[0].text is missing",
    ),
    (
      "{\"id\":\"x\",\"type\":\"message\",\"role\":\"assistant\",\"model\":\"m\",\"content\":[{\"type\":\"tool_use\",\"name\":\"f\"}],\"stop_reason\":\"end_turn\"}",
      "resp.content[0].id is missing",
    ),
    (
      "{\"id\":\"x\",\"type\":\"message\",\"role\":\"assistant\",\"model\":\"m\",\"content\":[{\"type\":\"tool_use\",\"id\":\"t\"}],\"stop_reason\":\"end_turn\"}",
      "resp.content[0].name is missing",
    ),
    (
      "{\"id\":\"x\",\"type\":\"message\",\"role\":\"assistant\",\"model\":\"m\",\"content\":[],\"stop_reason\":\"weird\"}",
      "resp.stop_reason must be one of [end_turn, max_tokens, stop_sequence, tool_use, refusal], got \"weird\"",
    ),
  ]
  for c in cases {
    assert_violation(@conformance.check_messages_response(c.0), c.1, c.0)
  }
}

///|
/// check_gemini_request：role/parts/text/functionCall/functionResponse/inlineData/fileData 分支
test "conformance - gemini request violation branches" {
  let cases : Array[(String, String)] = [
    ("not json", "invalid JSON"),
    ("{}", "req.contents is missing"),
    ("{\"contents\":\"x\"}", "req.contents must be an array"),
    (
      "{\"contents\":[{\"role\":\"bot\",\"parts\":[{\"text\":\"hi\"}]}]}", "req.contents[0].role must be one of [user, model, tool], got \"bot\"",
    ),
    ("{\"contents\":[{\"role\":\"user\"}]}", "req.contents[0].parts is missing"),
    (
      "{\"contents\":[{\"role\":\"user\",\"parts\":[{\"text\":42}]}]}", "req.contents[0].parts[0].text must be a string",
    ),
    (
      "{\"contents\":[{\"role\":\"user\",\"parts\":[{\"functionCall\":{\"args\":{}}}]}]}",
      "req.contents[0].parts[0].functionCall.name is missing",
    ),
    (
      "{\"contents\":[{\"role\":\"user\",\"parts\":[{\"functionCall\":{\"name\":\"f\"}}]}]}",
      "req.contents[0].parts[0].functionCall.args is missing",
    ),
    (
      "{\"contents\":[{\"role\":\"user\",\"parts\":[{\"functionCall\":{\"name\":\"f\",\"args\":\"x\"}}]}]}",
      "req.contents[0].parts[0].functionCall.args must be an object",
    ),
    (
      "{\"contents\":[{\"role\":\"user\",\"parts\":[{\"functionCall\":\"x\"}]}]}",
      "req.contents[0].parts[0].functionCall must be an object",
    ),
    (
      "{\"contents\":[{\"role\":\"user\",\"parts\":[{\"functionResponse\":{\"response\":{}}}]}]}",
      "req.contents[0].parts[0].functionResponse.name is missing",
    ),
    (
      "{\"contents\":[{\"role\":\"user\",\"parts\":[{\"functionResponse\":{\"name\":\"f\"}}]}]}",
      "req.contents[0].parts[0].functionResponse.response is missing",
    ),
    (
      "{\"contents\":[{\"role\":\"user\",\"parts\":[{\"functionResponse\":{\"name\":\"f\",\"response\":\"x\"}}]}]}",
      "req.contents[0].parts[0].functionResponse.response must be an object",
    ),
    (
      "{\"contents\":[{\"role\":\"user\",\"parts\":[{\"functionResponse\":\"x\"}]}]}",
      "req.contents[0].parts[0].functionResponse must be an object",
    ),
    (
      "{\"contents\":[{\"role\":\"user\",\"parts\":[{\"inlineData\":\"x\"}]}]}",
      "req.contents[0].parts[0].inlineData must be an object",
    ),
    (
      "{\"contents\":[{\"role\":\"user\",\"parts\":[{\"fileData\":\"x\"}]}]}", "req.contents[0].parts[0].fileData must be an object",
    ),
  ]
  for c in cases {
    assert_violation(@conformance.check_gemini_request(c.0), c.1, c.0)
  }
}

///|
/// check_gemini_response：candidates/content/parts/finishReason 分支
test "conformance - gemini response violation branches" {
  let cases : Array[(String, String)] = [
    ("not json", "invalid JSON"),
    ("{}", "resp.candidates is missing"),
    ("{\"candidates\":\"x\"}", "resp.candidates must be an array"),
    ("{\"candidates\":[]}", "resp.candidates must not be empty"),
    ("{\"candidates\":[{}]}", "resp.candidates[0].content is missing"),
    (
      "{\"candidates\":[{\"content\":{},\"finishReason\":\"STOP\"}]}", "resp.candidates[0].content.parts is missing",
    ),
    (
      "{\"candidates\":[{\"content\":{\"parts\":[{\"text\":42}]},\"finishReason\":\"STOP\"}]}",
      "resp.candidates[0].content.parts[0].text must be a string",
    ),
    (
      "{\"candidates\":[{\"content\":{\"parts\":[{\"functionCall\":\"x\"}]},\"finishReason\":\"STOP\"}]}",
      "resp.candidates[0].content.parts[0].functionCall must be an object",
    ),
    (
      "{\"candidates\":[{\"content\":{\"parts\":[]},\"finishReason\":\"bogus\"}]}",
      "resp.candidates[0].finishReason must be one of [STOP, MAX_TOKENS, SAFETY, RECITATION, OTHER], got \"bogus\"",
    ),
  ]
  for c in cases {
    assert_violation(@conformance.check_gemini_response(c.0), c.1, c.0)
  }
}

///|
/// === 测试：合法输入的"放行"分支（正例覆盖）===
///
/// 前面的负例只驱动违规检出分支。但验证器里同样存在**合法输入才会走到**
/// 的分支——`Some(Array(_)) => ()`、`Some(Null) => ()`、`Some(True) | Some(False) => ()`
/// 以及各 `match tp { ... _ => () }` 的"该类型不做深度校验"兜底臂（responses 的
/// reasoning、messages 的 image/thinking、responses 响应侧的 reasoning /
/// function_call_output）。只写违规用例永远碰不到它们，等于留白。
/// 本组每个用例都给**完全合法**的 JSON 文档，断言违规列表为空。

///|
/// 与 assert_violation 对称的正例断言：合法输入必须返回空违规列表。
/// 不直接插值 violations 数组（Show 已弃用），先 join 成 String。
fn assert_no_violation(
  violations : Array[String],
  input : String,
) -> Unit raise {
  if violations.length() != 0 {
    let joined = violations.join(" | ")
    fail("expected no violations but got [\{joined}] | input: \{input}")
  }
}

///|
/// check_openai_request：messages[].content 为数组、stream 为布尔值
/// （validators.mbt L247 `Some(Array(_)) => ()` / L311 `Some(True) | Some(False) => ()`）
test "conformance - openai request accepts array content and boolean stream" {
  let cases : Array[String] = [
    "{\"model\":\"m\",\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"hi\"}]}]}",
    "{\"model\":\"m\",\"messages\":[{\"role\":\"tool\",\"content\":[\"a\"]}],\"stream\":true}",
    "{\"model\":\"m\",\"messages\":[],\"stream\":false}", "{\"model\":\"m\",\"messages\":[{\"role\":\"assistant\",\"content\":[\"x\"],\"tool_calls\":[{\"id\":\"t1\",\"function\":{\"name\":\"f\",\"arguments\":\"{}\"}}]}],\"tools\":[{\"type\":\"function\",\"function\":{\"name\":\"f\",\"parameters\":{}}}]}",
  ]
  for c in cases {
    assert_no_violation(@conformance.check_openai_request(c), c)
  }
}

///|
/// check_openai_response：message.content 为 null 合法放行
/// （validators.mbt L354 `Some(Null) => ()`）
test "conformance - openai response accepts null content and full usage" {
  let cases : Array[String] = [
    "{\"id\":\"r1\",\"object\":\"chat.completion\",\"model\":\"m\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":null},\"finish_reason\":\"stop\"}]}",
    "{\"id\":\"r1\",\"object\":\"chat.completion\",\"model\":\"m\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":null},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":1,\"completion_tokens\":2,\"total_tokens\":3}}",
    "{\"id\":\"r1\",\"object\":\"chat.completion\",\"model\":\"m\",\"choices\":[{\"index\":1,\"message\":{\"role\":\"tool\",\"content\":[{\"type\":\"text\",\"text\":\"t\"}]},\"finish_reason\":\"tool_calls\"}]}",
  ]
  for c in cases {
    assert_no_violation(@conformance.check_openai_response(c), c)
  }
}

///|
/// check_responses_request：input 项 type 为 "reasoning"（不做深度校验）
/// （validators.mbt L456 `"reasoning" => ()`）
test "conformance - responses request accepts reasoning input items" {
  let cases : Array[String] = [
    "{\"model\":\"m\",\"input\":[{\"type\":\"reasoning\"}]}", "{\"model\":\"m\",\"input\":[{\"type\":\"reasoning\",\"summary\":[]},{\"type\":\"message\",\"role\":\"user\",\"content\":[{\"type\":\"input_text\",\"text\":\"hi\"}]}]}",
  ]
  for c in cases {
    assert_no_violation(@conformance.check_responses_request(c), c)
  }
}

///|
/// check_responses_response：output 项 type 为 reasoning / function_call_output
/// （validators.mbt L551 兜底臂 `_ => ()`）
test "conformance - responses response accepts reasoning and function_call_output items" {
  let cases : Array[String] = [
    "{\"id\":\"r1\",\"object\":\"response\",\"status\":\"completed\",\"model\":\"m\",\"output\":[{\"type\":\"reasoning\"}]}",
    "{\"id\":\"r1\",\"object\":\"response\",\"status\":\"incomplete\",\"model\":\"m\",\"output\":[{\"type\":\"reasoning\",\"summary\":[]},{\"type\":\"function_call_output\",\"call_id\":\"c1\",\"output\":\"done\"}]}",
  ]
  for c in cases {
    assert_no_violation(@conformance.check_responses_response(c), c)
  }
}

///|
/// check_messages_request：content 块 type 为 image / thinking（未做深度校验）
/// （validators.mbt L628 兜底臂 `_ => ()`）
test "conformance - messages request accepts image and thinking blocks" {
  let cases : Array[String] = [
    "{\"model\":\"m\",\"max_tokens\":10,\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"image\",\"source\":{\"type\":\"base64\",\"data\":\"x\"}}]}]}",
    "{\"model\":\"m\",\"max_tokens\":10,\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"thinking\",\"thinking\":\"t\",\"signature\":\"s\"}]}]}",
    "{\"model\":\"m\",\"max_tokens\":10,\"messages\":[{\"role\":\"user\",\"content\":[{\"type\":\"tool_result\",\"tool_use_id\":\"tu_1\"},{\"type\":\"image\",\"source\":{}}]}]}",
  ]
  for c in cases {
    assert_no_violation(@conformance.check_messages_request(c), c)
  }
}

///|
/// check_messages_response：content 块 type 为 thinking（未做深度校验）
/// （validators.mbt L700 兜底臂 `_ => ()`）
test "conformance - messages response accepts thinking blocks" {
  let cases : Array[String] = [
    "{\"id\":\"r1\",\"type\":\"message\",\"role\":\"assistant\",\"model\":\"m\",\"content\":[{\"type\":\"thinking\",\"thinking\":\"t\"}],\"stop_reason\":\"end_turn\"}",
    "{\"id\":\"r1\",\"type\":\"message\",\"role\":\"assistant\",\"model\":\"m\",\"content\":[{\"type\":\"thinking\"},{\"type\":\"text\",\"text\":\"t\"},{\"type\":\"tool_use\",\"id\":\"tu_1\",\"name\":\"f\"}],\"stop_reason\":\"tool_use\"}",
  ]
  for c in cases {
    assert_no_violation(@conformance.check_messages_response(c), c)
  }
}

///|
/// check_gemini_request：part 含 inlineData / fileData 对象（合法放行）
/// （validators.mbt L805 / L810 `Some(Object(_)) => ()`）
test "conformance - gemini request accepts inlineData and fileData parts" {
  let cases : Array[String] = [
    "{\"contents\":[{\"role\":\"user\",\"parts\":[{\"inlineData\":{\"mimeType\":\"image/png\",\"data\":\"x\"}}]}]}",
    "{\"contents\":[{\"role\":\"user\",\"parts\":[{\"fileData\":{\"mimeType\":\"text/plain\",\"fileUri\":\"u\"}}]}]}",
    "{\"contents\":[{\"role\":\"model\",\"parts\":[{\"text\":\"hi\"},{\"functionCall\":{\"name\":\"f\",\"args\":{}}},{\"functionResponse\":{\"name\":\"f\",\"response\":{}}},{\"inlineData\":{}},{\"fileData\":{}}]}]}",
  ]
  for c in cases {
    assert_no_violation(@conformance.check_gemini_request(c), c)
  }
}

///|
/// check_gemini_response：part 含 functionCall 对象（合法放行）
/// （validators.mbt L856 `Some(Object(_)) => ()`）
test "conformance - gemini response accepts functionCall parts" {
  let cases : Array[String] = [
    "{\"candidates\":[{\"content\":{\"parts\":[{\"functionCall\":{\"name\":\"f\",\"args\":{}}}]},\"finishReason\":\"STOP\"}]}",
    "{\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"hi\"},{\"functionCall\":{\"name\":\"f\",\"args\":{}}}]},\"finishReason\":\"MAX_TOKENS\"}]}",
  ]
  for c in cases {
    assert_no_violation(@conformance.check_gemini_response(c), c)
  }
}

///|
/// check_gemini_request：functionCall/functionResponse 子对象 name 字段的
/// 空值 + 非字符串分支（require_map_str 的 Some("") / Some(错误类型)）
/// （validators.mbt L92 `val_err(... "must not be empty")` / L98 `type_err(...)`）
test "conformance - gemini request function name field violation branches" {
  let cases : Array[(String, String)] = [
    (
      "{\"contents\":[{\"role\":\"user\",\"parts\":[{\"functionCall\":{\"name\":\"\",\"args\":{}}}]}]}",
      "req.contents[0].parts[0].functionCall.name must not be empty",
    ),
    (
      "{\"contents\":[{\"role\":\"user\",\"parts\":[{\"functionCall\":{\"name\":42,\"args\":{}}}]}]}",
      "req.contents[0].parts[0].functionCall.name must be a string",
    ),
    (
      "{\"contents\":[{\"role\":\"user\",\"parts\":[{\"functionResponse\":{\"name\":\"\",\"response\":{}}}]}]}",
      "req.contents[0].parts[0].functionResponse.name must not be empty",
    ),
    (
      "{\"contents\":[{\"role\":\"user\",\"parts\":[{\"functionResponse\":{\"name\":null,\"response\":{}}}]}]}",
      "req.contents[0].parts[0].functionResponse.name must be a string",
    ),
  ]
  for c in cases {
    assert_violation(@conformance.check_gemini_request(c.0), c.1, c.0)
  }
}
