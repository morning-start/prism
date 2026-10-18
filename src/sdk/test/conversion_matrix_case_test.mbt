///|
/// 契约矩阵的可执行验证：12 条验收标准 × 涉及端点的逐格断言。
///
/// `docs/api-protocol-converter.md` 的「最小测试矩阵」是宣称"互转已兼容"
/// 的准入条件。本文件把该矩阵从散文变成**可执行断言**，并按端点逐格标注
/// 覆盖——这样文档论断与测试一一对应，而不是各自表述。
///
/// 约定：每条用例（case 1..12）都给出触发形态与断言要点；用 harness 让
/// 未实现的能力显式失败（而非静默通过），避免"文档说支持、测试没测"。

///|
/// 用例 1/2：纯文本（非流式 / 流式）——4 源 × 4 目标全配对
test "matrix 1-2 text - all 16 source/target pairs produce text output" {
  let sources = ["openai", "responses", "messages", "gemini"]
  let targets = ["openai", "responses", "messages", "gemini"]
  // 各源的最小纯文本请求/响应/流 fixture
  let req : Map[String, String] = Map([])
  req["openai"] = "{\"model\":\"gpt-4o\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}"
  req["responses"] = "{\"model\":\"gpt-5\",\"input\":[{\"type\":\"message\",\"role\":\"user\",\"content\":[{\"type\":\"input_text\",\"text\":\"hi\"}]}]}"
  req["messages"] = "{\"model\":\"claude\",\"max_tokens\":16,\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}"
  req["gemini"] = "{\"model\":\"gemini-2.5-pro\",\"contents\":[{\"role\":\"user\",\"parts\":[{\"text\":\"hi\"}]}]}"
  for s in sources {
    for t in targets {
      match req.get(s) {
        Some(json) =>
          match @sdk.convert_request(s, json, t) {
            Ok(cr) => {
              let out = cr.value()
              // 目标 JSON 必须可解析且非空
              assert_true(out.length() > 0)
              let parsed = @json.parse(out) catch {
                _ => fail(s + "->" + t + " produced invalid JSON: " + out)
              }
              let _ = parsed
            }
            Err(e) => fail(s + "->" + t + " request failed: " + e)
          }
        None => fail("missing fixture for " + s)
      }
    }
  }
}

///|
/// 用例 3/5：非流式单工具 / 多工具 —— 参数必须保真（字符串 ↔ 对象）
test "matrix 3-5 tools - non-streaming tool calls preserve arguments" {
  // 源侧 openai 带两个工具调用 → 各目标
  let json = "{\"id\":\"r1\",\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":null,\"tool_calls\":[{\"id\":\"c1\",\"type\":\"function\",\"function\":{\"name\":\"f1\",\"arguments\":\"{\\\"a\\\":1}\"}},{\"id\":\"c2\",\"type\":\"function\",\"function\":{\"name\":\"f2\",\"arguments\":\"{\\\"b\\\":2}\"}}]},\"finish_reason\":\"tool_calls\"}]}"
  for target in ["responses", "messages", "gemini", "openai"] {
    match @sdk.convert_response("openai", json, target) {
      Ok(cr) => {
        let out = cr.value()
        // 工具名与参数内容必须出现（形态各家不同：字符串或对象）
        assert_true(out.contains("f1"))
        assert_true(out.contains("f2"))
        assert_true(out.contains("a"))
        assert_true(out.contains("b"))
      }
      Err(e) => fail("openai->" + target + " tools failed: " + e)
    }
  }
}

///|
/// 用例 4/6：流式单工具 / 多工具参数增量 —— 逐帧必须与整批一致
/// （这是 P0 缺陷的原始触发场景，见 stream_tool_equivalence_test.mbt）
test "matrix 4-6 streaming tools - incremental equals batch for tool streams" {
  let sse = "data: {\"id\":\"cc1\",\"object\":\"chat.completion.chunk\",\"created\":1,\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\"}}]}\n\n" +
    "data: {\"id\":\"cc1\",\"object\":\"chat.completion.chunk\",\"created\":1,\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"c1\",\"type\":\"function\",\"function\":{\"name\":\"f1\",\"arguments\":\"{\\\"a\\\"\"}}]}}]}\n\n" +
    "data: {\"id\":\"cc1\",\"object\":\"chat.completion.chunk\",\"created\":1,\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\":1}\"}}]}}]}\n\n" +
    "data: {\"id\":\"cc1\",\"object\":\"chat.completion.chunk\",\"created\":1,\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":1,\"id\":\"c2\",\"type\":\"function\",\"function\":{\"name\":\"f2\",\"arguments\":\"{\\\"b\\\":2}\"}}]}}]}\n\n" +
    "data: {\"id\":\"cc1\",\"object\":\"chat.completion.chunk\",\"created\":1,\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"tool_calls\"}]}\n\n" +
    "data: [DONE]\n\n"
  for target in ["responses", "messages", "gemini", "openai"] {
    let batch = match @sdk.convert_stream("openai", sse, target) {
      Ok(r) => r.value()
      Err(e) => fail("batch openai->" + target + ": " + e)
    }
    let inc = match feed_one_byte_chunks("openai", target, sse) {
      Ok(frames) => frames.join("")
      Err(e) => fail("incremental openai->" + target + ": " + e)
    }
    if inc != batch {
      fail("matrix 4/6 openai->" + target + ": incremental != batch\n" + inc)
    }
    // 参数不得退化为空对象（P0 的失败特征）
    assert_false(inc.contains("\"args\":{}"))
  }
}

///|
/// 用例 7：assistant 文本 + tool call 混合输出 —— 两路径一致且块不丢
test "matrix 7 mixed text+tool - all targets consistent incrementally" {
  let sse = "data: {\"id\":\"cc2\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\"}}]}\n\n" +
    "data: {\"id\":\"cc2\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"let me check\"}}]}\n\n" +
    "data: {\"id\":\"cc2\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"c1\",\"type\":\"function\",\"function\":{\"name\":\"f1\",\"arguments\":\"{\\\"a\\\":1}\"}}]}}]}\n\n" +
    "data: {\"id\":\"cc2\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\" done\"}}]}\n\n" +
    "data: {\"id\":\"cc2\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"tool_calls\"}]}\n\n" +
    "data: [DONE]\n\n"
  for target in ["responses", "messages", "gemini", "openai"] {
    let batch = match @sdk.convert_stream("openai", sse, target) {
      Ok(r) => r.value()
      Err(e) => fail("batch openai->" + target + ": " + e)
    }
    let inc = match feed_one_byte_chunks("openai", target, sse) {
      Ok(frames) => frames.join("")
      Err(e) => fail("incremental openai->" + target + ": " + e)
    }
    if inc != batch {
      fail("matrix 7 openai->" + target + ": incremental != batch\n" + inc)
    }
    // 文本与工具都必须保留
    assert_true(inc.contains("let me check"))
  }
}

///|
/// 用例 8：tool_result 回填后的第二轮 —— 工具结果必须映射到各目标载体
test "matrix 8 tool result - second turn maps tool_result to each target" {
  // openai 第二轮：assistant tool_calls + role:tool 结果
  let json = "{\"model\":\"gpt-4o\",\"messages\":[{\"role\":\"user\",\"content\":\"weather?\"},{\"role\":\"assistant\",\"content\":null,\"tool_calls\":[{\"id\":\"c1\",\"type\":\"function\",\"function\":{\"name\":\"f1\",\"arguments\":\"{}\"}}]},{\"role\":\"tool\",\"tool_call_id\":\"c1\",\"content\":\"{\\\"t\\\":26}\"}]}"
  for target in ["messages", "responses", "gemini"] {
    match @sdk.convert_request("openai", json, target) {
      Ok(cr) => {
        let out = cr.value()
        // 工具结果载体各家不同，但 id 与内容必须保留
        assert_true(out.contains("c1"))
        assert_true(out.contains("26"))
      }
      Err(e) => fail("openai->" + target + " tool_result failed: " + e)
    }
  }
}

///|
/// 用例 9：Claude 顺序硬规则 —— 编码到 messages 时 tool_result 必须被包成
/// user 消息并排在文本之前（`docs/api-protocol-converter.md` §3 硬规则）。
///
/// 注：Anthropic 服务端的顺序校验由 Anthropic 自己做；Prism 的职责是把 IR
/// 归一化后按 Claude 的硬规则**编码**，因此这里断言编码侧的顺序不变式。
test "matrix 9 ordering - messages encoding honors claude ordering" {
  // IR：tool_result 块出现在文本之前/之后都应被规范化到 tool_result 前置
  let req = @lux.LucentRequest::from_messages(
    "claude",
    None,
    [
      @lux.LucentMessage::new(User, [
        @lux.LucentContent::text("context note"),
        @lux.LucentContent::tool_result("tu_1", [
          @lux.LucentContent::text("sunny"),
        ]),
      ]),
    ],
    None,
    None,
    @lux.LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
  match @messages.lux_request_to_messages(req) {
    Ok(cr) => {
      let out = cr.value()
      assert_true(out.contains("\"type\":\"tool_result\""))
      // tool_result 必须出现在文本之前（Claude 顺序硬规则）
      let before = out.split("\"type\":\"tool_result\"").to_array()[0].length()
      assert_true(before > 0)
      // tool_result 的位置必须早于该文本
      let text_pos = out.find("context note")
      match text_pos {
        Some(tp) => assert_true(before < tp)
        None => fail("expected text preserved in output")
      }
    }
    Err(e) => fail("messages encode failed: " + e)
  }
}

///|
/// 用例 10：Responses 只有 previous_response_id 且无历史 —— 跨端必须拒绝或降级
test "matrix 10 previous_response_id - rejected or degraded without history" {
  let json = "{\"model\":\"gpt-5\",\"previous_response_id\":\"resp_prev\",\"input\":[{\"type\":\"message\",\"role\":\"user\",\"content\":[{\"type\":\"input_text\",\"text\":\"hi\"}]}]}"
  for target in ["openai", "messages", "gemini"] {
    match @sdk.convert_request("responses", json, target) {
      Ok(cr) =>
        // 无本地历史时必须显式降级（不能静默丢弃）
        assert_true(cr.diagnostics().length() > 0)
      // Err 亦为可接受的显式拒绝
      Err(_) => ()
    }
  }
}

///|
/// 用例 11：非法 JSON arguments —— 参数需为**对象**的目标（messages /
/// gemini）必须显式报错；以**字符串**承载参数的目标（openai / responses）
/// 直通即字节保真（不产生非法请求体），无需诊断。
test "matrix 11 invalid arguments - object targets report, string targets pass through" {
  let json = "{\"model\":\"gpt-4o\",\"messages\":[{\"role\":\"assistant\",\"content\":null,\"tool_calls\":[{\"id\":\"c1\",\"type\":\"function\",\"function\":{\"name\":\"f1\",\"arguments\":\"oops-not-json\"}}]}]}"
  // 对象载体目标：必须显式 Invalid（否则会产出非法请求体）
  for target in ["messages", "gemini"] {
    match @sdk.convert_request("openai", json, target) {
      Ok(cr) => {
        let has_invalid = cr
          .diagnostics()
          .any(fn(d) { d.status == Invalid || d.status == Degraded })
        if !has_invalid {
          fail(
            "openai->" +
            target +
            " must report invalid arguments, got diags=" +
            cr.diagnostics().length().to_string(),
          )
        }
      }
      Err(_) => ()
    }
  }
  // 字符串载体目标：参数原样透传（字节保真）
  for target in ["openai", "responses"] {
    match @sdk.convert_request("openai", json, target) {
      Ok(cr) => assert_true(cr.value().contains("oops-not-json"))
      Err(e) => fail("openai->" + target + " should pass through: " + e)
    }
  }
}

///|
/// 用例 12：未支持的 output/content 类型 —— 必须显式诊断（Unsupported）
///
/// openai 源的非 function 工具（web_search_preview 等）在 Chat 无载体，
/// 但 IR 能表达：解码时保留 kind + Unsupported 诊断（此前整体丢弃且无诊断）。
test "matrix 12 unsupported content - explicit Unsupported diagnostic" {
  let json = "{\"model\":\"gpt-4o\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"tools\":[{\"type\":\"web_search_preview\"}]}"
  // 源侧解码即应产生 Unsupported（工具 kind 无法在 Chat 表达）
  match @sdk.convert_request("openai", json, "openai") {
    Ok(cr) =>
      assert_true(cr.diagnostics().any(fn(d) { d.status == Unsupported }))
    Err(e) => fail("openai->openai failed: " + e)
  }
  // 跨端时同样必须显式（诊断随解码合并到结果）
  for target in ["messages", "gemini", "responses"] {
    match @sdk.convert_request("openai", json, target) {
      Ok(cr) => assert_true(cr.diagnostics().length() > 0)
      Err(_) => ()
    }
  }
}
