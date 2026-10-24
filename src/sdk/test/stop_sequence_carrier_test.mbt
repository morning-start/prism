///|
/// `stop_sequence` 载体契约（CR-005 缺陷 A）。
///
/// ## 背景
///
/// 「实际命中的自定义终止序列」与「模型自然说完」是语义完全不同的事实，但
/// 修复前 messages 源把两者一起收敛为 `Stop`，命中值整体丢弃、回写恒为
/// `null`，且**连诊断都没有**。调用方无从区分：
///
/// ```
/// 输入:  {"stop_reason":"stop_sequence","stop_sequence":"END"}
/// 修复前: finish_reason = stop / 0 诊断 / 回写 {"stop_reason":"end_turn","stop_sequence":null}
/// 修复后: finish_reason = stop / stop_sequence = Some("END") / 回写原样
/// ```
///
/// ## 设计（非破坏性，治理 §6「新增可选标准字段」）
///
/// - `LucentChoice` 新增 `stop_sequence : String?`，默认 `None`；
/// - `LucentChoice::new` 签名不变（4 参数），88 处调用点零改动；
///   需要携带时用 `with_stop_sequence` builder；
/// - JSON 序列化：`None` 时**不输出该键**（不破坏既有字节形态）；
/// - 反序列化：缺失/空串/类型不符一律软失败为 `None`（治理 §4）。
///
/// ## 载体存在时的语义耦合
///
/// `stop_sequence.is_some()` ⟺ 官方 `stop_reason == "stop_sequence"`。
/// 因此 messages 编码器在既有值时会**强制**把 stop_reason 写成
/// `"stop_sequence"`，保证两个字段自洽。

///|
/// 同源往返：messages → IR → messages，命中序列必须原样保住（Exact）。
test "stop_sequence - messages round trip preserves hit value" {
  let json = "{\"id\":\"m\",\"type\":\"message\",\"role\":\"assistant\",\"model\":\"c\",\"content\":[{\"type\":\"text\",\"text\":\"t\"}],\"stop_reason\":\"stop_sequence\",\"stop_sequence\":\"END_TURN\"}"
  match @messages.messages_to_lux_response(json) {
    Err(e) => fail("decode failed: " + e)
    Ok(decoded) => {
      let ch = decoded.value().choices[0]
      assert_eq(ch.stop_sequence, Some("END_TURN"))
      // finish_reason 仍是 Stop（命中序列不是异常终止）
      assert_eq(ch.finish_reason, Stop)
      match @messages.lux_response_to_messages(decoded.value()) {
        Err(e) => fail("encode failed: " + e)
        Ok(out) => {
          // 两个字段都必须回写自洽
          assert_true(out.value().contains("\"stop_reason\":\"stop_sequence\""))
          assert_true(out.value().contains("\"stop_sequence\":\"END_TURN\""))
        }
      }
    }
  }
}

///|
/// 未命中序列（`stop_sequence: null`）→ `None`，且回写仍是 `null`。
/// 不得因为新增字段而改变既有字节形态。
test "stop_sequence - null hit value stays absent" {
  let json = "{\"id\":\"m\",\"type\":\"message\",\"role\":\"assistant\",\"model\":\"c\",\"content\":[],\"stop_reason\":\"end_turn\",\"stop_sequence\":null}"
  match @messages.messages_to_lux_response(json) {
    Err(e) => fail("decode failed: " + e)
    Ok(decoded) => {
      assert_eq(decoded.value().choices[0].stop_sequence, None)
      match @messages.lux_response_to_messages(decoded.value()) {
        Err(e) => fail("encode failed: " + e)
        Ok(out) => {
          assert_true(out.value().contains("\"stop_reason\":\"end_turn\""))
          assert_true(out.value().contains("\"stop_sequence\":null"))
        }
      }
    }
  }
}

///|
/// 字段缺失 / 空串 / 类型不符 → 软失败为 `None`（不得因可选字段反序列化失败
/// 而报错，治理 §4）。
test "stop_sequence - absent or malformed value degrades to none" {
  let cases : Array[String] = [
    // 字段缺失
    "{\"id\":\"m\",\"type\":\"message\",\"role\":\"assistant\",\"model\":\"c\",\"content\":[],\"stop_reason\":\"stop_sequence\"}",
    // 空串
     "{\"id\":\"m\",\"type\":\"message\",\"role\":\"assistant\",\"model\":\"c\",\"content\":[],\"stop_reason\":\"stop_sequence\",\"stop_sequence\":\"\"}",
    // 类型不符（数字）
     "{\"id\":\"m\",\"type\":\"message\",\"role\":\"assistant\",\"model\":\"c\",\"content\":[],\"stop_reason\":\"stop_sequence\",\"stop_sequence\":42}",
  ]
  for json in cases {
    match @messages.messages_to_lux_response(json) {
      Err(e) => fail("decode failed on soft-fail case: " + e)
      Ok(decoded) => assert_eq(decoded.value().choices[0].stop_sequence, None)
    }
  }
}

///|
/// 跨端：messages 源携带命中序列，转到 openai / responses / gemini 时必须
/// **显式诊断**（三个目标都无此载体），不能静默丢弃。
test "stop_sequence - cross-protocol drop is diagnosed" {
  let json = "{\"id\":\"m\",\"type\":\"message\",\"role\":\"assistant\",\"model\":\"c\",\"content\":[{\"type\":\"text\",\"text\":\"t\"}],\"stop_reason\":\"stop_sequence\",\"stop_sequence\":\"END\"}"
  match @messages.messages_to_lux_response(json) {
    Err(e) => fail("decode failed: " + e)
    Ok(decoded) => {
      let targets = [
        ("openai", fn() { @openai.lux_response_to_openai(decoded.value()) }),
        (
          "responses",
          fn() { @responses.lux_response_to_responses(decoded.value()) },
        ),
        ("gemini", fn() { @gemini.lux_response_to_gemini(decoded.value()) }),
      ]
      for t in targets {
        let (name, encode) = t
        match encode() {
          Err(e) => fail(name + " encode failed: " + e)
          Ok(cr) => {
            let mut found = false
            for d in cr.diagnostics() {
              if d.field.contains("stop_sequence") && d.status is Unsupported {
                found = true
              }
            }
            assert_true(found)
          }
        }
      }
    }
  }
}

///|
/// 流式路径：命中值有 IR 载体了（CR-006 批次 2 —— `Finish` 的第二位置参数
/// 与 `LucentChoice.stop_sequence` 同构），流式与非流式不再有第二套词汇表。
///
/// 0.1.x 时此处是「有意识的降级 + Degraded 诊断」；0.2.0 起值随 Finish
/// 携带，且流式累加器把它写进 `LucentChoice.stop_sequence`。
test "stop_sequence - streaming path carries hit value" {
  let sse = "event: message_start\n" +
    "data: {\"type\":\"message_start\",\"message\":{\"id\":\"m\",\"model\":\"c\"}}\n\n" +
    "event: message_delta\n" +
    "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"stop_sequence\",\"stop_sequence\":\"END\"}}\n\n" +
    "event: message_stop\ndata: {\"type\":\"message_stop\"}\n\n"
  match @messages.messages_sse_to_events(sse) {
    Err(e) => fail("decode failed: " + e)
    Ok(cr) => {
      // 值有载体后不再有降级诊断
      for d in cr.diagnostics() {
        assert_false(d.field.contains("stop_sequence"))
      }
      // Finish 携带命中值；且流式与非流式对同一 stop_reason 解出**同一**
      // IR finish_reason
      let mut finish : @lux.LucentFinishReason? = None
      let mut ss : String? = None
      for ev in cr.value() {
        match ev {
          Finish(fr, v) => {
            finish = Some(fr)
            ss = v
          }
          _ => ()
        }
      }
      assert_eq(finish, Some(Stop))
      assert_eq(ss, Some("END"))
      // 流式累加器：命中值进入 LucentChoice.stop_sequence（与非流式同字段）
      let acc = @lux.lucent_stream_events_to_accumulated(cr.value(), "m", "c")
      assert_eq(acc.response.choices[0].stop_sequence, Some("END"))
    }
  }
}

///|
/// 不带命中序列的流（正常 end_turn）不应产生任何 stop_sequence 噪音诊断。
test "stop_sequence - streaming without hit value stays silent" {
  let sse = "event: message_start\n" +
    "data: {\"type\":\"message_start\",\"message\":{\"id\":\"m\",\"model\":\"c\"}}\n\n" +
    "event: message_delta\n" +
    "data: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\"}}\n\n" +
    "event: message_stop\ndata: {\"type\":\"message_stop\"}\n\n"
  match @messages.messages_sse_to_events(sse) {
    Err(e) => fail("decode failed: " + e)
    Ok(cr) =>
      for d in cr.diagnostics() {
        assert_false(d.field.contains("stop_sequence"))
      }
  }
}

///|
/// `LucentChoice` 的 JSON 往返：载体存在时序列化输出该键，`None` 时不输出。
test "stop_sequence - ir json round trip" {
  let with_val = @lux.LucentChoice::new(
    0,
    @lux.LucentMessage::new(Assistant, []),
    Stop,
    None,
  ).with_stop_sequence("HALT")
  let j = with_val.to_json()
  assert_true(j.stringify().contains("\"stop_sequence\":\"HALT\""))
  match @lux.LucentChoice::from_json(j) {
    Err(e) => fail("from_json failed: " + e)
    Ok(back) => assert_eq(back.stop_sequence, Some("HALT"))
  }
  let without = @lux.LucentChoice::new(
    0,
    @lux.LucentMessage::new(Assistant, []),
    Stop,
    None,
  )
  // None 时不输出该键（保持既有字节形态）
  assert_false(without.to_json().stringify().contains("stop_sequence"))
}
