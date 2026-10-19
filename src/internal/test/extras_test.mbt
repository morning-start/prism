///|
/// 测试 internal/extras.mbt — extras 透传

///|
/// 解析 JSON 的辅助函数
fn extras_parse(s : String) -> Json {
  @json.parse(s) catch {
    _ => Json::null()
  }
}

///|
/// === collect_extra_fields ===
/// 非 Object 输入 → None（extras.mbt L32）
test "internal extras - collect_extra_fields returns None for non-object" {
  for c in ["\"text\"", "42", "true", "null", "[\"a\"]"] {
    assert_true(@internal.collect_extra_fields(extras_parse(c), ["a"]) is None)
  }
}

///|
test "internal extras - collect_extra_fields keeps only unknown keys" {
  // 全部是已知字段 → None
  assert_true(
    @internal.collect_extra_fields(
      extras_parse("{\"model\":\"m\",\"messages\":[]}"),
      ["model", "messages"],
    )
    is None,
  )

  // 未知字段被收集
  match
    @internal.collect_extra_fields(
      extras_parse("{\"model\":\"m\",\"vendor_id\":7}"),
      ["model"],
    ) {
    Some(m) => {
      assert_eq(m.length(), 1)
      assert_true(m.contains("vendor_id"))
      assert_false(m.contains("model"))
    }
    None => fail("expected extras map")
  }
}

///|
/// === merge_extras_json_dedup ===
///
/// 安全版本：跳过与已编码片段撞名的键并返回被跳过的键列表。
/// （不安全的 `merge_extras_json` 已删除 —— 它会产出重复 JSON 键。）
test "internal extras - merge_extras_json_dedup skips colliding keys" {
  // parts 的元素在真实编码器里是裸的 `"key":value` 片段（花括号由 join 时补），
  // 因此这里也用裸片段。
  let parts : Array[String] = ["\"a\":1"]

  // extras 为 None → 不追加、无丢弃
  assert_true(@internal.merge_extras_json_dedup(parts, None).length() == 0)
  assert_eq(parts.length(), 1)

  // 不撞名 → 追加 `"key":value`，无丢弃
  let m : Map[String, Json] = Map([])
  m["note"] = extras_parse("\"hello\"")
  assert_true(@internal.merge_extras_json_dedup(parts, Some(m)).length() == 0)
  assert_eq(parts.length(), 2)
  assert_true(parts[1].contains("\"note\":"))

  // 空 Map → 不追加
  let empty : Map[String, Json] = Map([])
  assert_true(
    @internal.merge_extras_json_dedup(parts, Some(empty)).length() == 0,
  )
  assert_eq(parts.length(), 2)

  // 撞名（键 "a" 已在 parts 里）→ 跳过并把键报回来
  let collide : Map[String, Json] = Map([])
  collide["a"] = extras_parse("999")
  let dropped = @internal.merge_extras_json_dedup(parts, Some(collide))
  assert_eq(dropped.length(), 1)
  assert_true(dropped.contains("a"))
  // 未新增片段 → 不会出现第二个 "a"
  assert_eq(parts.length(), 2)
}

///|
/// === extras_without ===
test "internal extras - extras_without removes key and empties to None" {
  let m : Map[String, Json] = Map([])
  m["a"] = extras_parse("1")
  m["b"] = extras_parse("2")

  match @internal.extras_without(Some(m), "a") {
    Some(nm) => {
      assert_eq(nm.length(), 1)
      assert_false(nm.contains("a"))
      assert_true(nm.contains("b"))
    }
    None => fail("expected remaining extras")
  }

  // 移除不存在的键 → 原样保留
  match @internal.extras_without(Some(m), "zzz") {
    Some(nm) => assert_eq(nm.length(), 2)
    None => fail("expected unchanged extras")
  }

  // 移除最后一个键 → None
  let single : Map[String, Json] = Map([])
  single["only"] = extras_parse("1")
  assert_true(@internal.extras_without(Some(single), "only") is None)

  // extras 本身为 None → None
  assert_true(@internal.extras_without(None, "only") is None)
}
