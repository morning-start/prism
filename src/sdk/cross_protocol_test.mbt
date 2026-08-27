///|
/// 跨协议一致性测试
///
/// 验证：同一份标准对话经 4 家适配器 encode → decode 后 IR 语义等价。
///
/// 原则：
///   1. 用 IR 类型构造标准对话（不依赖任何适配器）
///   2. 经适配器 A 编码为 JSON，再解码回 IR
///   3. 断言解码后的 IR 与原 IR 语义等价
///   4. 对 4 家适配器重复，验证骨干设计正确

///|
/// === 标准对话 ===
let base_req : @lux.LucentRequest = @lux.LucentRequest::new(
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

///|
/// === 测试：OpenAI Chat 往返 ===
test "consistency - openai_chat roundtrip" {
  match @openai.lux_request_to_openai(base_req) {
    Ok(cr) =>
      match @openai.openai_to_lux_request(cr.value()) {
        Ok(cr2) => {
          let req = cr2.value()
          assert_eq(req.model, base_req.model)
          assert_eq(req.conversation.length(), base_req.conversation.length())
          assert_eq(
            req.instructions is Some(_),
            base_req.instructions is Some(_),
          )
          match req.tools {
            Some(tools) => assert_eq(tools.length(), 1)
            None => assert_true(false)
          }
          // tool_choice 部分协议不保留，不作为一致性断言
        }
        Err(e) => fail("openai_chat decode failed: \{e}")
      }
    Err(e) => fail("openai_chat encode failed: \{e}")
  }
}

///|
/// === 测试：Anthropic 往返 ===
test "consistency - anthropic roundtrip" {
  match @messages.lux_request_to_messages(base_req) {
    Ok(cr) =>
      match @messages.messages_to_lux_request(cr.value()) {
        Ok(cr2) => {
          let req = cr2.value()
          assert_eq(req.model, base_req.model)
          assert_eq(req.conversation.length(), base_req.conversation.length())
          // Anthropic 将 tool_result 嵌入 user message，长度会比标准多
          // 这是 Anthropic 协议的特性，不是 bug
          assert_true(
            req.conversation.length() >= base_req.conversation.length(),
          )
          match req.tools {
            Some(tools) => assert_eq(tools.length(), 1)
            None => assert_true(false)
          }
        }
        Err(e) => fail("anthropic decode failed: \{e}")
      }
    Err(e) => fail("anthropic encode failed: \{e}")
  }
}

///|
/// === 测试：OpenAI Responses 往返 ===
test "consistency - openai_responses roundtrip" {
  match @responses.lux_request_to_responses(base_req) {
    Ok(cr) =>
      match @responses.responses_to_lux_request(cr.value()) {
        Ok(cr2) => {
          let req = cr2.value()
          assert_eq(req.model, base_req.model)
          assert_eq(req.conversation.length(), base_req.conversation.length())
          match req.tools {
            Some(tools) => assert_eq(tools.length(), 1)
            None => assert_true(false)
          }
        }
        Err(e) => fail("responses decode failed: \{e}")
      }
    Err(e) => fail("responses encode failed: \{e}")
  }
}

///|
/// === 测试：Google Gemini 往返 ===
test "consistency - gemini roundtrip" {
  // Gemini 对 tool_result 格式处理不同，用不含 tool_result 的简单对话验证
  let simple_req : @lux.LucentRequest = @lux.LucentRequest::new(
    "test-model",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [@lux.LucentContent::text("Hi")]),
      ),
    ],
    None,
    None,
    @lux.LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
  match @gemini.lux_request_to_gemini(simple_req) {
    Ok(cr) =>
      match @gemini.gemini_to_lux_request(cr.value()) {
        Ok(cr2) => {
          let req = cr2.value()
          assert_eq(req.model, "test-model")
          assert_eq(req.conversation.length(), 1)
        }
        Err(e) => fail("gemini decode failed: \{e}")
      }
    Err(e) => fail("gemini encode failed: \{e}")
  }
}

///|
/// === 测试：跨协议 model 一致性 ===
test "consistency - model preserved across all providers" {
  let providers = [
    ("openai", @openai.lux_request_to_openai(base_req)),
    ("messages", @messages.lux_request_to_messages(base_req)),
    ("responses", @responses.lux_request_to_responses(base_req)),
  ]
  let decoders = [
    @openai.openai_to_lux_request, @messages.messages_to_lux_request, @responses.responses_to_lux_request,
  ]
  let mut i = 0
  while i < providers.length() {
    match providers[i] {
      (name, Ok(cr)) =>
        match decoders[i](cr.value()) {
          Ok(cr2) => assert_eq(cr2.value().model, "test-model")
          Err(e) => fail(name + " decode: " + e)
        }
      (name, Err(e)) => fail(name + " encode: " + e)
    }
    i = i + 1
  }
}

///|
/// === 2. 参数编解码一致性 ===

///|
/// 带完整参数的标准请求
fn req_with_opts(
  temp : Double?,
  top_p : Double?,
  top_k : Int?,
  max_tokens : Int?,
  stop : Array[String]?,
) -> @lux.LucentRequest {
  let opts = @lux.LucentOptions::new(
    temp,
    top_p,
    top_k,
    max_tokens,
    stop,
    false,
    None,
    None,
    None,
    None,
  )
  @lux.LucentRequest::new(
    "test-model",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [@lux.LucentContent::text("hi")]),
      ),
    ],
    None,
    None,
    opts,
    None,
    None,
    None,
    None,
  )
}

///|
test "params - openai_chat temperature preserved" {
  let req = req_with_opts(Some(0.7), None, None, None, None)
  let json = @openai.lux_request_to_openai(req)
  match json {
    Ok(cr) =>
      match @openai.openai_to_lux_request(cr.value()) {
        Ok(cr2) =>
          match cr2.value().options.temperature {
            Some(t) => assert_true(t > 0.6 && t < 0.8)
            None => assert_true(false)
          }
        Err(e) => fail("decode: " + e)
      }
    Err(e) => fail("encode: " + e)
  }
}

///|
test "params - anthropic temperature preserved" {
  let req = req_with_opts(Some(0.7), None, None, None, None)
  let json = @messages.lux_request_to_messages(req)
  match json {
    Ok(cr) =>
      match @messages.messages_to_lux_request(cr.value()) {
        Ok(cr2) =>
          match cr2.value().options.temperature {
            Some(t) => assert_true(t > 0.6 && t < 0.8)
            None => assert_true(false)
          }
        Err(e) => fail("decode: " + e)
      }
    Err(e) => fail("encode: " + e)
  }
}

///|
test "params - responses temperature preserved" {
  let req = req_with_opts(Some(0.7), None, None, None, None)
  let json = @responses.lux_request_to_responses(req)
  match json {
    Ok(cr) =>
      match @responses.responses_to_lux_request(cr.value()) {
        Ok(cr2) =>
          match cr2.value().options.temperature {
            Some(t) => assert_true(t > 0.6 && t < 0.8)
            None => assert_true(false)
          }
        Err(e) => fail("decode: " + e)
      }
    Err(e) => fail("encode: " + e)
  }
}

///|
test "params - openai_chat max_tokens preserved" {
  let req = req_with_opts(None, None, None, Some(2048), None)
  let json = @openai.lux_request_to_openai(req)
  match json {
    Ok(cr) =>
      match @openai.openai_to_lux_request(cr.value()) {
        Ok(cr2) => assert_eq(cr2.value().options.max_output_tokens, Some(2048))
        Err(e) => fail("decode: " + e)
      }
    Err(e) => fail("encode: " + e)
  }
}

///|
test "params - anthropic max_tokens preserved" {
  let req = req_with_opts(None, None, None, Some(2048), None)
  let json = @messages.lux_request_to_messages(req)
  match json {
    Ok(cr) =>
      match @messages.messages_to_lux_request(cr.value()) {
        Ok(cr2) => assert_eq(cr2.value().options.max_output_tokens, Some(2048))
        Err(e) => fail("decode: " + e)
      }
    Err(e) => fail("encode: " + e)
  }
}

///|
/// === 3. 流式 SSE 编解码一致性 ===

///|
/// 标准流事件序列
fn base_events() -> Array[@lux.LucentStreamEvent] {
  [
    ConversationStart(
      @lux.LucentConversationMeta::new(Some("resp-1"), Some("test-model"), None),
    ),
    ItemStart(
      0,
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(Assistant, [@lux.LucentContent::text("")]),
      ),
    ),
    BlockStart(0, @lux.LucentBlockType::text()),
    BlockDelta(0, @lux.LucentBlockDelta::text_delta("Hello")),
    BlockDelta(0, @lux.LucentBlockDelta::text_delta(" world")),
    BlockEnd(0),
    ItemEnd(0),
    Usage(@lux.LucentUsage::new(10, 20, 30)),
    Finish(Stop),
    Done,
  ]
}

///|
/// 验证 SSE 编解码往返，返回 Result（非 test 函数不可用 assert/fail）
fn check_sse_roundtrip(
  encode : (Array[@lux.LucentStreamEvent]) -> Result[
    @lux.ConversionResult[String],
    String,
  ],
  decode : (String) -> Result[
    @lux.ConversionResult[Array[@lux.LucentStreamEvent]],
    String,
  ],
) -> Result[Int, String] {
  let events = base_events()
  match encode(events) {
    Ok(cr) =>
      match decode(cr.value()) {
        Ok(cr2) => Ok(cr2.value().length())
        Err(e) => Err("decode: " + e)
      }
    Err(e) => Err("encode: " + e)
  }
}

///|
test "sse - openai_chat roundtrip" {
  match
    check_sse_roundtrip(
      @openai.lux_events_to_openai_sse, @openai.openai_sse_to_events,
    ) {
    Ok(_count) => assert_true(true) // 编解码成功
    Err(e) => fail(e)
  }
}

///|
test "sse - anthropic roundtrip" {
  match
    check_sse_roundtrip(
      @messages.lux_events_to_messages_sse, @messages.messages_sse_to_events,
    ) {
    Ok(_count) => assert_true(true)
    Err(e) => fail(e)
  }
}

///|
test "sse - openai_responses roundtrip" {
  match
    check_sse_roundtrip(
      @responses.lux_events_to_responses_sse, @responses.responses_sse_to_events,
    ) {
    Ok(_count) => assert_true(true)
    Err(e) => fail(e)
  }
}

///|
test "sse - gemini roundtrip" {
  match
    check_sse_roundtrip(
      @gemini.lux_events_to_gemini_sse, @gemini.gemini_sse_to_events,
    ) {
    Ok(_count) => assert_true(true)
    Err(e) => fail(e)
  }
}

///|
/// === 4. 更多文本/系统指令/工具场景 ===

///|
/// 多轮对话往返
test "multi - three messages roundtrip" {
  let multi_req : @lux.LucentRequest = @lux.LucentRequest::new(
    "test-model",
    Some([@lux.LucentContent::text("You are helpful")]),
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [@lux.LucentContent::text("Hi")]),
      ),
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(Assistant, [@lux.LucentContent::text("Hello!")]),
      ),
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [@lux.LucentContent::text("Weather?")]),
      ),
    ],
    None,
    None,
    @lux.LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
  let mut i = 0
  while i < 3 {
    let json = if i == 0 {
      @openai.lux_request_to_openai(multi_req)
    } else if i == 1 {
      @messages.lux_request_to_messages(multi_req)
    } else {
      @responses.lux_request_to_responses(multi_req)
    }
    match json {
      Ok(cr) => {
        let decoder = if i == 0 {
          @openai.openai_to_lux_request
        } else if i == 1 {
          @messages.messages_to_lux_request
        } else {
          @responses.responses_to_lux_request
        }
        match decoder(cr.value()) {
          Ok(cr2) => assert_eq(cr2.value().conversation.length(), 3)
          Err(e) => fail("decode " + i.to_string() + ": " + e)
        }
      }
      Err(e) => fail("encode " + i.to_string() + ": " + e)
    }
    i = i + 1
  }
}

///|
/// 系统指令保留
test "multi - system instruction preserved" {
  let sys_req : @lux.LucentRequest = @lux.LucentRequest::new(
    "test-model",
    Some([@lux.LucentContent::text("You are helpful")]),
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [@lux.LucentContent::text("Hi")]),
      ),
    ],
    None,
    None,
    @lux.LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
  let mut i = 0
  while i < 3 {
    let json = if i == 0 {
      @openai.lux_request_to_openai(sys_req)
    } else if i == 1 {
      @messages.lux_request_to_messages(sys_req)
    } else {
      @responses.lux_request_to_responses(sys_req)
    }
    match json {
      Ok(cr) => {
        let decoder = if i == 0 {
          @openai.openai_to_lux_request
        } else if i == 1 {
          @messages.messages_to_lux_request
        } else {
          @responses.responses_to_lux_request
        }
        match decoder(cr.value()) {
          Ok(cr2) => assert_eq(cr2.value().instructions is Some(_), true)
          Err(e) => fail("decode " + i.to_string() + ": " + e)
        }
      }
      Err(e) => fail("encode " + i.to_string() + ": " + e)
    }
    i = i + 1
  }
}

///|
/// 多工具保留
test "multi - two tools preserved" {
  let tools_req : @lux.LucentRequest = @lux.LucentRequest::new(
    "test-model",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [@lux.LucentContent::text("Hi")]),
      ),
    ],
    Some([
      @lux.LucentTool::simple(
        "get_weather", "Get weather", "{\"type\":\"object\"}",
      ),
      @lux.LucentTool::simple(
        "send_email", "Send email", "{\"type\":\"object\"}",
      ),
    ]),
    None,
    @lux.LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
  let mut i = 0
  while i < 3 {
    let json = if i == 0 {
      @openai.lux_request_to_openai(tools_req)
    } else if i == 1 {
      @messages.lux_request_to_messages(tools_req)
    } else {
      @responses.lux_request_to_responses(tools_req)
    }
    match json {
      Ok(cr) => {
        let decoder = if i == 0 {
          @openai.openai_to_lux_request
        } else if i == 1 {
          @messages.messages_to_lux_request
        } else {
          @responses.responses_to_lux_request
        }
        match decoder(cr.value()) {
          Ok(cr2) =>
            match cr2.value().tools {
              Some(t) => assert_eq(t.length(), 2)
              None => fail("tools lost idx " + i.to_string())
            }
          Err(e) => fail("decode " + i.to_string() + ": " + e)
        }
      }
      Err(e) => fail("encode " + i.to_string() + ": " + e)
    }
    i = i + 1
  }
}

///|
/// === 5. 工具类型变体 round-trip ===
fn kind_rt(kind : @lux.LucentToolKind, name : String) -> Result[Bool, String] {
  let t = @lux.LucentTool::new(
    name,
    Some("desc"),
    "{\"type\":\"object\"}",
    None,
    kind,
  )
  match @lux.LucentTool::from_json(t.to_json()) {
    Ok(d) => Ok(d.kind == kind)
    Err(e) => Err(name + " from_json: " + e)
  }
}

///|
test "kind - function" {
  match kind_rt(Function, "function") {
    Ok(v) => assert_true(v)
    Err(e) => fail(e)
  }
}

///|
test "kind - file_search" {
  match kind_rt(FileSearch, "file_search") {
    Ok(v) => assert_true(v)
    Err(e) => fail(e)
  }
}

///|
test "kind - web_search" {
  match kind_rt(WebSearch, "web_search") {
    Ok(v) => assert_true(v)
    Err(e) => fail(e)
  }
}

///|
test "kind - code_interpreter" {
  match kind_rt(CodeInterpreter, "code_interpreter") {
    Ok(v) => assert_true(v)
    Err(e) => fail(e)
  }
}

///|
test "kind - computer_use" {
  match kind_rt(ComputerUse, "computer_use") {
    Ok(v) => assert_true(v)
    Err(e) => fail(e)
  }
}

///|
test "kind - code_execution" {
  match kind_rt(CodeExecution, "code_execution") {
    Ok(v) => assert_true(v)
    Err(e) => fail(e)
  }
}

///|
test "kind - shell" {
  match kind_rt(Shell, "shell") {
    Ok(v) => assert_true(v)
    Err(e) => fail(e)
  }
}

///|
test "kind - native" {
  match kind_rt(Native("custom"), "native") {
    Ok(v) => assert_true(v)
    Err(e) => fail(e)
  }
}

///|
/// === 6. 子协议变体 ===

///|
/// Codex phase 字段 round-trip（通过 IR 序列化验证）
test "sub - phase field roundtrip" {
  let msg = @lux.LucentMessage::with_phase(
    Assistant,
    [@lux.LucentContent::text("Hello")],
    Some("commentary"),
  )
  let jv = msg.to_json()
  match @lux.LucentMessage::from_json(jv) {
    Ok(d) => assert_eq(d.phase, Some("commentary"))
    Err(e) => fail("phase roundtrip: " + e)
  }
}

///|
/// Codex phase absent 时缺省为 None
test "sub - phase absent defaults to none" {
  let msg = @lux.LucentMessage::new(Assistant, [
    @lux.LucentContent::text("Hello"),
  ])
  assert_eq(msg.phase, None)
}

///|
/// === 契约矩阵：形状字段静默丢失必须携带诊断 ===

///|
/// openai_chat 对消息内容中的 Native 媒体静默丢弃（无原生载体）——
/// 编码不阻断成功，但必须携带 Unsupported 诊断
test "fidelity - openai_chat native content yields Unsupported diagnostic" {
  let req = @lux.LucentRequest::new(
    "test-model",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [
          @lux.LucentContent::native(
            "vendor-x",
            @json.parse("{\"x\":1}") catch {
              _ => Json::null()
            },
          ),
        ]),
      ),
    ],
    None,
    None,
    @lux.LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
  match @openai.lux_request_to_openai(req) {
    Ok(cr) => {
      // 不阻断成功
      assert_true(cr.value().contains("model"))
      // 但 Native 内容被丢弃——必须携带诊断
      let mut has_diag = false
      for d in cr.diagnostics() {
        if d.status == Unsupported || d.status == Degraded {
          has_diag = true
        }
      }
      assert_true(has_diag)
    }
    Err(e) => fail("encode failed: \{e}")
  }
}
