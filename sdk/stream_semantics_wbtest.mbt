///|
/// 流事件到 PrismEvent 的映射必须保留 Thinking 语义，
/// 不能把推理文本伪装成 TextDelta。
test "lucent_events_to_prism maps thinking delta to Thinking event" {
  let events = [
    @lux.BlockStart(0, @lux.LucentBlockType::thinking()),
    @lux.BlockDelta(0, @lux.LucentBlockDelta::thinking_delta("I reason...")),
    @lux.BlockEnd(0),
    @lux.Finish(@lux.Stop),
  ]
  let prism_events = lucent_events_to_prism(events)
  let mut found_thinking = false
  let mut found_text_delta = false
  for ev in prism_events {
    match ev {
      Thinking(th) => if th.text == "I reason..." { found_thinking = true }
      TextDelta(s) => if s == "I reason..." { found_text_delta = true }
      _ => ()
    }
  }
  assert_true(found_thinking)
  assert_true(!found_text_delta)
}
