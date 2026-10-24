///|
/// ConversationSnapshot + previous_response_id 标准字段测试（T8）
///
/// IR 规范：`docs/lux-ir-design.md` ConversationSnapshot 节
/// 治理：`docs/rules/lucent-ir-evolution.md`（非破坏性：新增可选标准字段 + 新类型）

///|
/// LucentOptions.previous_response_id 序列化 round-trip
test "LucentOptions - previous_response_id round-trips" {
  let opts = @lux.LucentOptions::default().with_previous_response_id(
    Some("resp_abc"),
  )
  let json = opts.to_json()
  match @lux.LucentOptions::from_json(json) {
    Ok(parsed) => assert_eq(parsed.previous_response_id, Some("resp_abc"))
    Err(e) => fail("from_json failed: \{e}")
  }
}

///|
/// 缺省不落字段（无侵入）
test "LucentOptions - previous_response_id absent by default" {
  let opts = @lux.LucentOptions::default()
  let json = opts.to_json().stringify()
  assert_false(json.contains("previous_response_id"))
  match @lux.LucentOptions::from_json(opts.to_json()) {
    Ok(parsed) => assert_eq(parsed.previous_response_id, None)
    Err(e) => fail("from_json failed: \{e}")
  }
}

///|
/// 旧载荷（无该字段）软失败为 None，不抛错
test "LucentOptions - legacy payload without field parses" {
  let json = @json.parse("{\"stream\":false}") catch { _ => Json::null() }
  match @lux.LucentOptions::from_json(json) {
    Ok(parsed) => assert_eq(parsed.previous_response_id, None)
    Err(e) => fail("legacy parse failed: \{e}")
  }
}

///|
/// ConversationSnapshot round-trip
test "ConversationSnapshot - round-trips with request and text" {
  let req = @lux.LucentRequest::new(
    "gpt-5.3",
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
  let snap = @lux.ConversationSnapshot::new("resp_1", req, Some("Hello back"))
  let json = snap.to_json()
  match @lux.ConversationSnapshot::from_json(json) {
    Ok(parsed) => {
      assert_eq(parsed.response_id, "resp_1")
      assert_eq(parsed.response_text, Some("Hello back"))
      assert_eq(parsed.request.model, "gpt-5.3")
      assert_eq(parsed.request.conversation.length(), 1)
    }
    Err(e) => fail("from_json failed: \{e}")
  }
}

///|
/// response_text 可选：缺省时 round-trip 为 None
test "ConversationSnapshot - response_text optional" {
  let req = @lux.LucentRequest::new(
    "gpt-5.3",
    None,
    [],
    None,
    None,
    @lux.LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
  let snap = @lux.ConversationSnapshot::new("resp_2", req, None)
  match @lux.ConversationSnapshot::from_json(snap.to_json()) {
    Ok(parsed) => {
      assert_eq(parsed.response_id, "resp_2")
      assert_eq(parsed.response_text, None)
    }
    Err(e) => fail("from_json failed: \{e}")
  }
}

///|
/// 非法 JSON 明确报错（Invalid 语义）
test "ConversationSnapshot - invalid json errors" {
  let json = @json.parse("{\"response_id\":\"r\"}") catch { _ => Json::null() }
  match @lux.ConversationSnapshot::from_json(json) {
    Ok(_) => fail("expected error for missing request")
    Err(e) => assert_true(e.contains("request"))
  }
}
