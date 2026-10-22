///|
/// 响应侧（response）保真度契约。
///
/// ## 为什么需要这个文件
///
/// 前两轮 audit 都在**请求**侧：生成参数矩阵（§3.6）、扩展通道（§3.7/§3.8）。
/// 响应侧从未建过逐格矩阵，于是六个缺陷在 1300+ 测试全绿的情况下长期存在 ——
/// 它们不是「分支没测到」，而是**根本没有断言问过这个问题**。
///
/// ## 六个缺陷的共同形态
///
/// 全部是「目标协议无法承载 → 数据消失」，而消失时**没有任何诊断**。IR 的
/// 硬规则是「不支持的能力必须显式报错，绝不静默丢弃」，因此每个格子都必须
/// 落在「有表示」或「有诊断」二者之一。
///
/// 另外两个是**自相矛盾**型：编码侧产出的形态解码侧读不懂（responses 的
/// refusal 键名），或解码侧读取的字段编码侧不写出（gemini 的细化用量）。

///|
/// 是否有指定字段名的非 Exact 诊断。
fn rsp_diag(cr : @lux.ConversionResult[String], field : String) -> Bool {
  for d in cr.diagnostics() {
    if d.field == field {
      match d.status() {
        Degraded | Unsupported => return true
        _ => ()
      }
    }
  }
  false
}

///|
/// 某个 IR finish_reason 的响应编码结果 + 是否已诊断。
fn rsp_encode_one(
  fr : @lux.LucentFinishReason,
) -> @lux.ConversionResult[String] raise {
  let resp = @lux.LucentResponse::new(
    "id-1",
    "m-1",
    None,
    [
      @lux.LucentChoice::new(
        0,
        @lux.LucentMessage::new(Assistant, [@lux.LucentContent::text("t")]),
        fr,
        None,
      ),
    ],
    None,
    None,
  )
  match @openai.lux_response_to_openai(resp) {
    Ok(cr) => cr
    Err(e) => fail("openai encode failed: " + e)
  }
}

///|
/// 缺陷 1：OpenAI Chat 的 `finish_reason` 有 5 个官方枚举值
/// （vendored OpenAPI `CreateChatCompletionResponse`）：stop / length /
/// tool_calls / content_filter / function_call。
///
/// 此前直接写 IR 的 `to_string()`，而 IR 词表含 `safety` / `recitation` /
/// `malformed_tool_call` / `error` —— 这些**不是** OpenAI 的合法值，严格校验
/// 的对端会拒绝整个响应体。
test "response matrix - openai finish_reason only emits spec-legal values" {
  let legal = [
    "stop", "length", "tool_calls", "content_filter", "function_call",
  ]
  let cases : Array[@lux.LucentFinishReason] = [
    Stop,
    Length,
    ToolCalls,
    ContentFilter,
    Safety,
    Recitation,
    MalformedToolCall,
    Error,
  ]
  for fr in cases {
    let cr = rsp_encode_one(fr)
    let body = cr.value()
    // 抽 finish_reason 值
    let mut emitted = ""
    for v in legal {
      if body.contains("\"finish_reason\":\"" + v + "\"") {
        emitted = v
      }
    }
    if emitted == "" {
      fail(
        "IR " + fr.to_string() + " emitted a non-spec finish_reason: " + body,
      )
    }
    // IR 值与 wire 值不同（即发生了收敛）时必须诊断
    let lossy = fr.to_string() != emitted
    if lossy && !rsp_diag(cr, "choices.finish_reason") {
      fail(
        "finish_reason " +
        fr.to_string() +
        " converged to " +
        emitted +
        " without a diagnostic",
      )
    }
    // 无对等值的四个必须收敛为 stop（语义最近的合法值）
    match fr {
      Stop | Length | ToolCalls | ContentFilter => ()
      _ => assert_eq(emitted, "stop")
    }
  }
}

///|
/// 缺陷 2：Responses 的官方 `RefusalContent` 是
/// `{"type":"refusal","refusal":"<text>"}`（`refusal` 为 required 字段）。
/// 此前解码只读 `text`，于是**官方形态的 refusal 内容块被整体静默丢弃**：
/// 既没有 Refusal 块，也没有任何诊断。
test "response matrix - responses decodes the official refusal key" {
  let official = "{\"id\":\"r1\",\"model\":\"m\",\"status\":\"completed\",\"output\":[{\"type\":\"message\",\"id\":\"msg_1\",\"role\":\"assistant\",\"status\":\"completed\",\"content\":[{\"type\":\"refusal\",\"refusal\":\"I cannot help\"}]}]}"
  match @responses.responses_to_lux_response(official) {
    Err(e) => fail("decode failed: " + e)
    Ok(cr) => {
      let content = cr.value().choices[0].message.content
      assert_eq(content.length(), 1)
      match content[0] {
        Refusal(s) => assert_eq(s, "I cannot help")
        _ => fail("expected a Refusal block, got a different block type")
      }
    }
  }
  // 兼容回退：历史上本实现自己产出过 text 键，仍应可读
  let legacy = "{\"id\":\"r1\",\"model\":\"m\",\"status\":\"completed\",\"output\":[{\"type\":\"message\",\"id\":\"msg_1\",\"role\":\"assistant\",\"content\":[{\"type\":\"refusal\",\"text\":\"legacy\"}]}]}"
  match @responses.responses_to_lux_response(legacy) {
    Err(e) => fail("legacy decode failed: " + e)
    Ok(cr) =>
      match cr.value().choices[0].message.content[0] {
        Refusal(s) => assert_eq(s, "legacy")
        _ => fail("expected legacy text key to still decode")
      }
  }
}

///|
/// 缺陷 3：Responses 与 Messages 都只能承载**单一**结果，却静默丢弃
/// choices[1..]。
test "response matrix - single-result targets diagnose dropped choices" {
  let multi = [
    @lux.LucentChoice::new(
      0,
      @lux.LucentMessage::new(Assistant, [@lux.LucentContent::text("first")]),
      Stop,
      None,
    ),
    @lux.LucentChoice::new(
      1,
      @lux.LucentMessage::new(Assistant, [@lux.LucentContent::text("second")]),
      Length,
      None,
    ),
  ]
  let resp = @lux.LucentResponse::new("id-1", "m-1", None, multi, None, None)
  match @responses.lux_response_to_responses(resp) {
    Err(e) => fail("responses encode failed: " + e)
    Ok(cr) => {
      assert_true(rsp_diag(cr, "response.choices"))
      // 只承载第一个，且不泄漏第二个
      assert_true(cr.value().contains("first"))
      assert_false(cr.value().contains("second"))
    }
  }
  match @messages.lux_response_to_messages(resp) {
    Err(e) => fail("messages encode failed: " + e)
    Ok(cr) => {
      assert_true(rsp_diag(cr, "response.choices"))
      assert_true(cr.value().contains("first"))
      assert_false(cr.value().contains("second"))
    }
  }
  // 单 choice 不应产生该诊断（避免噪声）
  let single = @lux.LucentResponse::new(
    "id-1",
    "m-1",
    None,
    [multi[0]],
    None,
    None,
  )
  match @responses.lux_response_to_responses(single) {
    Err(e) => fail("responses single failed: " + e)
    Ok(cr) => assert_false(rsp_diag(cr, "response.choices"))
  }
}

///|
/// 缺陷 4：Messages 把 Safety / Recitation / MalformedToolCall / Error 全部
/// 收敛为 `end_turn`，且**无诊断**。这四个值语义差异极大（安全拦截 / 复述 /
/// 工具调用畸形 / 上游出错），压成 end_turn 会让调用方误以为模型正常说完。
test "response matrix - messages diagnoses converged stop_reason" {
  let cases : Array[@lux.LucentFinishReason] = [
    Safety,
    Recitation,
    MalformedToolCall,
    Error,
  ]
  for fr in cases {
    let resp = @lux.LucentResponse::new(
      "id-1",
      "m-1",
      None,
      [
        @lux.LucentChoice::new(
          0,
          @lux.LucentMessage::new(Assistant, [@lux.LucentContent::text("t")]),
          fr,
          None,
        ),
      ],
      None,
      None,
    )
    match @messages.lux_response_to_messages(resp) {
      Err(e) => fail("messages encode failed: " + e)
      Ok(cr) => {
        // 收敛值仍是合法枚举
        assert_true(cr.value().contains("\"stop_reason\":\"end_turn\""))
        // 但必须留诊断
        if !rsp_diag(cr, "choices.finish_reason") {
          fail(
            "messages converged " +
            fr.to_string() +
            " to end_turn without a diagnostic",
          )
        }
      }
    }
  }
}

///|
/// 缺陷 5：Gemini 解码读取 `thoughtsTokenCount` / `cachedContentTokenCount`，
/// 编码却不写 —— 「解 → 编」往返丢数据，且与自己的解码路径自相矛盾。
test "response matrix - gemini usage details survive the decode-encode round trip" {
  let j = "{\"responseId\":\"g1\",\"modelVersion\":\"m\",\"candidates\":[{\"index\":0,\"content\":{\"role\":\"model\",\"parts\":[{\"text\":\"hi\"}]},\"finishReason\":\"STOP\"}],\"usageMetadata\":{\"promptTokenCount\":10,\"candidatesTokenCount\":20,\"totalTokenCount\":30,\"thoughtsTokenCount\":7,\"cachedContentTokenCount\":3}}"
  match @gemini.gemini_to_lux_response(j) {
    Err(e) => fail("decode failed: " + e)
    Ok(cr) => {
      let u = match cr.value().usage {
        Some(u) => u
        None => fail("expected usage")
      }
      assert_eq(u.reasoning_tokens, Some(7))
      assert_eq(u.cached_tokens, Some(3))
      match @gemini.lux_response_to_gemini(cr.value()) {
        Err(e) => fail("encode failed: " + e)
        Ok(out) => {
          assert_true(out.value().contains("\"thoughtsTokenCount\":7"))
          assert_true(out.value().contains("\"cachedContentTokenCount\":3"))
        }
      }
    }
  }
}

///|
/// 缺陷 6：Gemini 提示词被整体拦截时 `candidates` 为空、原因在
/// `promptFeedback.blockReason`。此前一律返回 `Err`，调用方既拿不到
/// blockReason 也拿不到 usage —— 一个有明确业务含义的拒绝被降级成转换失败。
test "response matrix - gemini blocked prompt becomes a safety choice, not Err" {
  let j = "{\"promptFeedback\":{\"blockReason\":\"SAFETY\",\"safetyRatings\":[{\"category\":\"HARM_CATEGORY_HARASSMENT\",\"probability\":\"HIGH\"}]},\"usageMetadata\":{\"promptTokenCount\":5,\"candidatesTokenCount\":0,\"totalTokenCount\":5}}"
  match @gemini.gemini_to_lux_response(j) {
    Err(e) => fail("blocked prompt should not be a hard error: " + e)
    Ok(cr) => {
      assert_eq(cr.value().choices.length(), 1)
      assert_eq(cr.value().choices[0].finish_reason, Safety)
      assert_eq(cr.value().choices[0].message.content.length(), 0)
      // safetyRatings 随拦截原因保留
      match cr.value().choices[0].safety_ratings {
        Some(rs) => assert_eq(rs.length(), 1)
        None => fail("expected safety ratings from promptFeedback")
      }
      // usage 不丢
      match cr.value().usage {
        Some(u) => assert_eq(u.prompt_tokens, 5)
        None => fail("expected usage to survive")
      }
      // 拦截原因必须显式报出
      let mut reported = false
      for d in cr.diagnostics() {
        if d.field == "promptFeedback.blockReason" {
          reported = true
        }
      }
      assert_true(reported)
    }
  }
  // 没有 blockReason 的空 candidates 仍是真正的协议错误
  match @gemini.gemini_to_lux_response("{\"responseId\":\"g1\"}") {
    Err(_) => ()
    Ok(_) => fail("empty response without blockReason must stay an error")
  }
}

///|
/// Gemini 的 `ToolCalls → STOP` 是**语义对等**（Gemini 的 FinishReason 枚举
/// 没有工具调用项，模型发起函数调用时官方就返回 STOP），不是丢失，因此
/// 不应产生诊断 —— 否则每次工具调用都会报一条假 Unsupported。
test "response matrix - gemini tool call finish reason is equivalent, not lossy" {
  let resp = @lux.LucentResponse::new(
    "g1",
    "m",
    None,
    [
      @lux.LucentChoice::new(
        0,
        @lux.LucentMessage::new(Assistant, [
          @lux.LucentContent::tool_use("c1", "f", "{}", None),
        ]),
        ToolCalls,
        None,
      ),
    ],
    None,
    None,
  )
  match @gemini.lux_response_to_gemini(resp) {
    Err(e) => fail("encode failed: " + e)
    Ok(cr) => {
      assert_true(cr.value().contains("\"finishReason\":\"STOP\""))
      assert_false(rsp_diag(cr, "candidates.finishReason"))
    }
  }
}

///|
/// `Native(s)` 的 finish_reason 是**源协议原始字符串**，出站时必须原样透传
/// 而不是被当作「无对等值」收敛掉 —— 透传是无损路径，也不该有诊断。
/// （三个目标的收敛分支都靠这条覆盖，否则 `Native(s) => s` 永不执行。）
test "response matrix - Native finish reason passes through verbatim" {
  let fr : @lux.LucentFinishReason = Native("vendor_pause")
  let resp = @lux.LucentResponse::new(
    "id-1",
    "m-1",
    None,
    [
      @lux.LucentChoice::new(
        0,
        @lux.LucentMessage::new(Assistant, [@lux.LucentContent::text("t")]),
        fr,
        None,
      ),
    ],
    None,
    None,
  )
  match @openai.lux_response_to_openai(resp) {
    Err(e) => fail("openai encode failed: " + e)
    Ok(cr) => {
      assert_true(cr.value().contains("\"finish_reason\":\"vendor_pause\""))
      assert_false(rsp_diag(cr, "choices.finish_reason"))
    }
  }
  match @messages.lux_response_to_messages(resp) {
    Err(e) => fail("messages encode failed: " + e)
    Ok(cr) =>
      assert_true(cr.value().contains("\"stop_reason\":\"vendor_pause\""))
  }
  match @gemini.lux_response_to_gemini(resp) {
    Err(e) => fail("gemini encode failed: " + e)
    Ok(cr) =>
      assert_true(cr.value().contains("\"finishReason\":\"vendor_pause\""))
  }
}

///|
/// Gemini 拦截路径的二阶分支：`promptFeedback` 存在但**没有** `blockReason`
/// （只有 safetyRatings），以及 `usageMetadata` 缺失 —— 前者应退回
/// "response has no candidates" 错误而非伪造 Safety choice，后者不应阻断解码。
test "response matrix - gemini promptFeedback branch edges" {
  // 有 promptFeedback 但无 blockReason → 不得伪造 choice
  match
    @gemini.gemini_to_lux_response(
      "{\"responseId\":\"g1\",\"promptFeedback\":{\"safetyRatings\":[{\"category\":\"X\",\"probability\":\"LOW\"}]}}",
    ) {
    Err(_) => ()
    Ok(_) =>
      fail("promptFeedback without blockReason must not fabricate a choice")
  }
  // 被拦截但没有 usageMetadata / safetyRatings（可选字段缺失不应阻断）
  match
    @gemini.gemini_to_lux_response(
      "{\"responseId\":\"g1\",\"promptFeedback\":{\"blockReason\":\"OTHER\"}}",
    ) {
    Err(e) => fail("blocked prompt without usage should still decode: " + e)
    Ok(cr) => {
      assert_eq(cr.value().choices[0].finish_reason, Safety)
      assert_eq(cr.value().usage, None)
      assert_eq(cr.value().choices[0].safety_ratings, None)
    }
  }
}
