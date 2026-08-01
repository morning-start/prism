///|
/// Context 链式构造不应修改原始上下文。
test "Context::add_user does not mutate source" {
  let base = Context::new()
  let derived = base.add_user("hello")
  assert_eq(base.messages.length(), 0)
  assert_eq(derived.messages.length(), 1)
}

///|
test "Context::add_assistant does not mutate source" {
  let base = Context::new()
  let derived = base.add_assistant("hello")
  assert_eq(base.messages.length(), 0)
  assert_eq(derived.messages.length(), 1)
}
