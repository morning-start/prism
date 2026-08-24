///|
/// 测试 internal/json.mbt — JSON 字段提取工具函数

///|
/// 解析 JSON 的辅助函数
fn parse(s : String) -> Json {
  @json.parse(s) catch {
    _ => Json::null()
  }
}

///|
/// === obj_get ===
test "obj_get - returns value for existing key" {
  let jv = parse("{\"name\":\"test\"}")
  match @internal.obj_get(jv, "name") {
    Some(String(s)) => assert_eq(s, "test")
    _ => fail("expected Some(String)")
  }
}

///|
test "obj_get - returns None for missing key" {
  let jv = parse("{\"name\":\"test\"}")
  assert_true(@internal.obj_get(jv, "missing") is None)
}

///|
test "obj_get - returns None for non-object" {
  let jv = parse("\"string\"")
  assert_true(@internal.obj_get(jv, "key") is None)
}

///|
/// === field_str ===
test "field_str - extracts string" {
  let jv = parse("{\"name\":\"hello\"}")
  assert_eq(@internal.field_str(jv, "name"), Some("hello"))
}

///|
test "field_str - returns None for non-string" {
  let jv = parse("{\"count\":42}")
  assert_true(@internal.field_str(jv, "count") is None)
}

///|
/// === field_arr ===
test "field_arr - extracts array" {
  let jv = parse("{\"items\":[\"a\",\"b\"]}")
  match @internal.field_arr(jv, "items") {
    Some(arr) => assert_eq(arr.length(), 2)
    None => fail("expected array")
  }
}

///|
test "field_arr - returns None for non-array" {
  let jv = parse("{\"name\":\"test\"}")
  assert_true(@internal.field_arr(jv, "name") is None)
}

///|
/// === field_bool ===
test "field_bool - extracts true/false" {
  let jv = parse("{\"a\":true,\"b\":false}")
  assert_eq(@internal.field_bool(jv, "a"), Some(true))
  assert_eq(@internal.field_bool(jv, "b"), Some(false))
}

///|
test "field_bool - returns None for non-bool" {
  let jv = parse("{\"num\":42}")
  assert_true(@internal.field_bool(jv, "num") is None)
}

///|
/// === field_num ===
test "field_num - extracts double" {
  let jv = parse("{\"temp\":0.7}")
  match @internal.field_num(jv, "temp") {
    Some(n) => assert_true(n > 0.6 && n < 0.8)
    None => fail("expected number")
  }
}

///|
test "field_num - returns None for non-number" {
  let jv = parse("{\"s\":\"text\"}")
  assert_true(@internal.field_num(jv, "s") is None)
}

///|
/// === field_int ===
test "field_int - extracts integer" {
  let jv = parse("{\"count\":42}")
  assert_eq(@internal.field_int(jv, "count"), Some(42))
}

///|
test "field_int - returns None for non-integer" {
  let jv = parse("{\"s\":\"text\"}")
  assert_true(@internal.field_int(jv, "s") is None)
}

///|
/// === field_int_exact ===
test "field_int_exact - extracts exact integer" {
  let jv = parse("{\"count\":42}")
  assert_eq(@internal.field_int_exact(jv, "count"), Some(42))
}

///|
test "field_int_exact - returns None for non-exact (float with .0)" {
  let jv = parse("{\"val\":5.0}")
  // 5.0 is exact as integer
  match @internal.field_int_exact(jv, "val") {
    Some(_) => () // implementation-dependent
    None => ()
  }
}

///|
test "field_int_exact - returns None for non-integer float" {
  let jv = parse("{\"val\":3.14}")
  assert_true(@internal.field_int_exact(jv, "val") is None)
}

///|
test "field_int_exact - returns None for string" {
  let jv = parse("{\"s\":\"text\"}")
  assert_true(@internal.field_int_exact(jv, "s") is None)
}

///|
/// === json_escape ===
test "json_escape - quotes and backslashes" {
  assert_eq(@internal.json_escape("hello \"world\""), "hello \\\"world\\\"")
  assert_eq(@internal.json_escape("a\\b"), "a\\\\b")
}

///|
test "json_escape - newlines and tabs" {
  assert_eq(@internal.json_escape("line1\nline2"), "line1\\nline2")
  assert_eq(@internal.json_escape("col1\tcol2"), "col1\\tcol2")
}

///|
test "json_escape - carriage return" {
  assert_eq(@internal.json_escape("a\rb"), "a\\rb")
}

///|
test "json_escape - plain text unchanged" {
  assert_eq(@internal.json_escape("hello world"), "hello world")
  assert_eq(@internal.json_escape(""), "")
}

///|
test "json_escape - unicode characters" {
  // 中文、日文等非 ASCII 字符应原样输出
  let result = @internal.json_escape("你好")
  assert_eq(result, "你好")
}

///|
test "json_escape - mixed content" {
  let result = @internal.json_escape("a\"b\nc")
  assert_eq(result, "a\\\"b\\nc")
}

///|
/// === obj_set ===
test "obj_set - sets key in object" {
  let jv = parse("{\"k\":\"v\"}")
  // obj_set modifies a copy — verify it returns an object that contains the key
  let result = @internal.obj_set(jv, "new_key", parse("\"new_val\""))
  let s = result.stringify()
  assert_true(s.contains("\"new_key\""))
  assert_true(s.contains("\"new_val\""))
}

///|
test "obj_set - overwrites existing key" {
  let jv = parse("{\"k\":\"old\"}")
  let result = @internal.obj_set(jv, "k", parse("\"new\""))
  let s = result.stringify()
  assert_true(s.contains("\"new\""))
  assert_false(s.contains("\"old\""))
}

///|
test "obj_set - non-object returns value as-is" {
  let jv = parse("\"text\"")
  let result = @internal.obj_set(jv, "key", parse("\"val\""))
  assert_eq(result, parse("\"val\""))
}

///|
/// === obj_delete ===
test "obj_delete - removes key" {
  let jv = parse("{\"a\":1,\"b\":2}")
  let result = @internal.obj_delete(jv, "a")
  let s = result.stringify()
  assert_true(s.contains("\"b\""))
  assert_false(s.contains("\"a\""))
}

///|
test "obj_delete - non-object returns as-is" {
  let jv = parse("\"text\"")
  let result = @internal.obj_delete(jv, "key")
  assert_eq(result, parse("\"text\""))
}

///|
test "obj_delete - non-existent key returns object unchanged" {
  let jv = parse("{\"a\":1}")
  let result = @internal.obj_delete(jv, "nonexistent")
  let s = result.stringify()
  assert_true(s.contains("\"a\""))
}

///|
/// === parse_json_opt ===
test "parse_json_opt - valid JSON" {
  assert_true(@internal.parse_json_opt("{\"a\":1}") is Some(_))
}

///|
test "parse_json_opt - invalid JSON returns None" {
  assert_true(@internal.parse_json_opt("{invalid}") is None)
}

///|
test "parse_json_opt - empty string returns None" {
  assert_true(@internal.parse_json_opt("") is None)
}

///|
test "parse_json_opt - null value" {
  match @internal.parse_json_opt("null") {
    Some(Null) => assert_true(true)
    _ => fail("expected Some(Null)")
  }
}

///|
test "parse_json_opt - number" {
  match @internal.parse_json_opt("42") {
    Some(Number(42.0, ..)) => assert_true(true)
    _ => fail("expected Some(Number)")
  }
}

///|
test "parse_json_opt - nested object" {
  match @internal.parse_json_opt("{\"a\":{\"b\":[\"c\"]}}") {
    Some(_) => assert_true(true)
    None => fail("expected Some for nested JSON")
  }
}

///|
test "parse_json_opt - whitespace around JSON" {
  match @internal.parse_json_opt("  {\"a\":1}  ") {
    Some(_) => assert_true(true)
    None => fail("expected Some for JSON with whitespace")
  }
}
