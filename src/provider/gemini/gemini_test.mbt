///|
/// Google Gemini 适配器黑盒测试 — 仅通过公开 API 验证
///
/// 与白盒测试（_wbtest.mbt）互补：模拟外部调用者视角，
/// 通过 6 函数 + capability 的公开契约验证双向转换与 round-trip 语义。

///|
/// === capability ===

///|
test "capability - declares provider name" {
  assert_eq(capability().provider, "google")
}

///|
/// === 请求 round-trip ===

///|
test "round trip - request encode then decode preserves semantics" {
  let original = @lux.LucentRequest::from_messages(
    "gemini-1.5-pro",
    Some([@lux.LucentContent::text("You are helpful")]),
    [@lux.LucentMessage::new(User, [@lux.LucentContent::text("hi")])],
    None,
    None,
    @lux.LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
  match lux_request_to_gemini(original) {
    Ok(cr1) =>
      match gemini_to_lux_request(cr1.value()) {
        Ok(cr) => {
          let round = cr.value()
          assert_eq(round.model, "gemini-1.5-pro")
          assert_eq(round.conversation.length(), 1)
          match round.conversation[0] {
            Message(m) => {
              assert_eq(m.role, User)
              match m.content[0] {
                Text(t, _) => assert_eq(t, "hi")
                _ => assert_true(false)
              }
            }
            _ => assert_true(false)
          }
          match round.instructions {
            Some(instrs) =>
              match instrs[0] {
                Text(t, _) => assert_eq(t, "You are helpful")
                _ => assert_true(false)
              }
            None => assert_true(false)
          }
        }
        Err(_) => assert_true(false)
      }
    Err(_) => assert_true(false)
  }
}

///|
/// === 响应 round-trip ===

///|
test "round trip - response encode then decode preserves text" {
  let resp = @lux.LucentResponse::new(
    "resp-1",
    "gemini-1.5-pro",
    None,
    [
      @lux.LucentChoice::new(
        0,
        @lux.LucentMessage::new(Assistant, [@lux.LucentContent::text("hi")]),
        Stop,
        None,
      ),
    ],
    None,
    None,
  )
  match lux_response_to_gemini(resp) {
    Ok(cr1) =>
      match gemini_to_lux_response(cr1.value()) {
        Ok(cr) => assert_eq(cr.value().get_text(), "hi")
        Err(_) => assert_true(false)
      }
    Err(_) => assert_true(false)
  }
}

///|
/// === 错误路径 ===

///|
test "invalid input - malformed JSON returns Err" {
  assert_true(gemini_to_lux_request("{invalid}") is Err(_))
  assert_true(gemini_to_lux_response("{invalid}") is Err(_))
}
