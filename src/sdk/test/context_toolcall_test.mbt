///|
/// @sdk.Context assistant tool_use 回合表达测试（T1）
///
/// 覆盖：
///   - @sdk.SdkMessage::tool_call / @sdk.SdkToolCall::new 构造
///   - @sdk.Context::add_tool_call builder
///   - @sdk.context_to_lux_request：tool_call → Message{Assistant, [Text?, ToolUse]}
///   - Agent 循环三轮 transcript 对 openai / messages 的编码结构校验
///     （tool_result 必须紧跟 assistant tool_use 回合）

///|
/// === SdkToolCall / SdkMessage::tool_call 构造 ===
test "@sdk.SdkMessage::tool_call - fields set correctly" {
  let msg = @sdk.SdkMessage::tool_call(
    "call_1", "get_weather", "{\"city\":\"SH\"}", "let me check",
  )
  assert_eq(msg.role, "assistant")
  assert_eq(msg.content, "let me check")
  match msg.tool_call {
    Some(tc) => {
      assert_eq(tc.id, "call_1")
      assert_eq(tc.name, "get_weather")
      assert_eq(tc.arguments_json, "{\"city\":\"SH\"}")
    }
    None => fail("expected tool_call to be set")
  }
  assert_true(msg.tool_use_id is None)
}

///|
test "@sdk.SdkMessage::new - tool_call defaults to None" {
  let msg = @sdk.SdkMessage::new("user", "hi")
  assert_true(msg.tool_call is None)
  assert_true(msg.tool_use_id is None)
}

///|
/// === Context::add_tool_call ===
test "@sdk.Context::add_tool_call - appends assistant tool_call message" {
  let ctx = @sdk.Context::new()
    .add_user("weather?")
    .add_tool_call("call_1", "get_weather", "{\"city\":\"SH\"}", "")
    .add_tool_result("call_1", "{\"temp\":26}", false)
  assert_eq(ctx.messages.length(), 3)
  let m1 = ctx.messages[1]
  assert_eq(m1.role, "assistant")
  match m1.tool_call {
    Some(tc) => assert_eq(tc.name, "get_weather")
    None => fail("expected tool_call message")
  }
}

///|
/// === context_to_lux_request：tool_call → IR ToolUse content ===
test "@sdk.context_to_lux_request - tool_call maps to assistant ToolUse content" {
  let ctx = @sdk.Context::new()
    .add_user("weather?")
    .add_tool_call("call_1", "get_weather", "{\"city\":\"SH\"}", "")
    .add_tool_result("call_1", "{\"temp\":26}", false)
  let req = @sdk.context_to_lux_request(ctx, "m", @sdk.PrismOptions::default())
  assert_eq(req.conversation.length(), 3)
  // items[1] = assistant Message 含 ToolUse content
  match req.conversation[1] {
    @lux.Message(m) => {
      assert_eq(m.role, @lux.Assistant)
      let mut has_tool_use = false
      for c in m.content {
        match c {
          @lux.ToolUse(tu) => {
            has_tool_use = true
            assert_eq(tu.id, "call_1")
            assert_eq(tu.name, "get_weather")
            assert_eq(tu.arguments_json, "{\"city\":\"SH\"}")
          }
          _ => ()
        }
      }
      assert_true(has_tool_use)
    }
    _ => fail("expected assistant Message with ToolUse content")
  }
}

///|
test "@sdk.context_to_lux_request - tool_call with text yields Text+ToolUse" {
  let ctx = @sdk.Context::new()
    .add_user("weather?")
    .add_tool_call("call_1", "get_weather", "{}", "checking now")
  let req = @sdk.context_to_lux_request(ctx, "m", @sdk.PrismOptions::default())
  match req.conversation[1] {
    @lux.Message(m) => {
      assert_eq(m.content.length(), 2)
      match m.content[0] {
        @lux.Text(s, _) => assert_eq(s, "checking now")
        _ => fail("expected leading Text content")
      }
      match m.content[1] {
        @lux.ToolUse(tu) => assert_eq(tu.id, "call_1")
        _ => fail("expected trailing ToolUse content")
      }
    }
    _ => fail("expected assistant Message")
  }
}

///|
/// === Agent 循环 transcript 编码结构校验（T1 核心验收）===
/// 修复前：transcript 缺 assistant tool_use 回合，provider 硬校验拒绝第二轮。
/// 修复后：openai 编码含 assistant.tool_calls + role:tool；
///         messages 编码含 assistant content[].type=tool_use + user tool_result。

///|
fn agent_loop_ctx() -> @sdk.Context {
  @sdk.Context::new()
  .add_system("You are a bot")
  .add_user("weather in SH?")
  .add_tool_call("call_1", "get_weather", "{\"city\":\"SH\"}", "")
  .add_tool_result("call_1", "{\"temp\":26}", false)
}

///|
test "agent loop transcript - openai encode has tool_calls before tool message" {
  let req = @sdk.context_to_lux_request(
    agent_loop_ctx(),
    "gpt-4o",
    @sdk.PrismOptions::default(),
  )
  match @openai.lux_request_to_openai(req) {
    Ok(cr) => {
      let json = cr.value()
      assert_true(json.contains("\"tool_calls\""))
      assert_true(json.contains("\"role\":\"tool\""))
      // assistant tool_calls 必须出现在 role:tool 之前
      // （split 首段长度 = 首次出现位置，避免依赖 index_of API）
      let tc_pos = json.split("\"tool_calls\"").to_array()[0].length()
      let tool_pos = json.split("\"role\":\"tool\"").to_array()[0].length()
      assert_true(tc_pos < tool_pos)
    }
    Err(e) => fail("encode failed: " + e)
  }
}

///|
test "agent loop transcript - messages encode has tool_use then tool_result" {
  let req = @sdk.context_to_lux_request(
    agent_loop_ctx(),
    "claude-sonnet-4-5",
    @sdk.PrismOptions::default(),
  )
  match @messages.lux_request_to_messages(req) {
    Ok(cr) => {
      let json = cr.value()
      assert_true(json.contains("\"type\":\"tool_use\""))
      assert_true(json.contains("\"type\":\"tool_result\""))
      let use_pos = json.split("\"type\":\"tool_use\"").to_array()[0].length()
      let res_pos = json.split("\"type\":\"tool_result\"").to_array()[0].length()
      assert_true(use_pos < res_pos)
    }
    Err(e) => fail("encode failed: " + e)
  }
}

///|
/// 回归门禁：不含 tool_call 的普通消息路径行为不变
test "@sdk.context_to_lux_request - plain messages unchanged" {
  let ctx = @sdk.Context::new().add_system("s").add_user("u").add_assistant("a")
  let req = @sdk.context_to_lux_request(ctx, "m", @sdk.PrismOptions::default())
  assert_eq(req.conversation.length(), 2)
  match req.conversation[0] {
    @lux.Message(m) => {
      assert_eq(m.role, @lux.User)
      assert_eq(m.content.length(), 1)
    }
    _ => fail("expected user Message")
  }
  match req.conversation[1] {
    @lux.Message(m) => assert_eq(m.role, @lux.Assistant)
    _ => fail("expected assistant Message")
  }
}
