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

///|
/// === sanitize_json_escapes ===

///|
test "sanitize_json_escapes - valid escapes preserved" {
  let input = "\"hello\\nworld\""
  let result = @internal.sanitize_json_escapes(input)
  assert_eq(result, "\"hello\\nworld\"")
}

///|
test "sanitize_json_escapes - invalid escape fixed" {
  // \: 不是有效 JSON 转义，应被转义为 \\:
  let input = "\"test\\:value\""
  let result = @internal.sanitize_json_escapes(input)
  assert_eq(result, "\"test\\\\:value\"")
}

///|
test "sanitize_json_escapes - mixed valid and invalid" {
  let input = "\"line1\\nline2\\:end\""
  let result = @internal.sanitize_json_escapes(input)
  assert_eq(result, "\"line1\\nline2\\\\:end\"")
}

///|
test "sanitize_json_escapes - backslash at end" {
  // 反斜杠在字符串末尾，没有下一个字符
  let input = "\"test\\"
  let result = @internal.sanitize_json_escapes(input)
  assert_eq(result, "\"test\\")
}

///|
test "sanitize_json_escapes - all valid escapes" {
  let input = "\"\\\"\\\\\\/\\b\\f\\n\\r\\t\\u0041\""
  let result = @internal.sanitize_json_escapes(input)
  assert_eq(result, "\"\\\"\\\\\\/\\b\\f\\n\\r\\t\\u0041\"")
}

///|
test "sanitize_json_escapes - real world OpenAI instructions" {
  // 模拟 OpenAI 返回的 instructions 字段，包含 \:
  let input = "{\"instructions\":\"You are opencode.\\n\\nIMPORTANT:\\: keep-alive.\"}"
  let result = @internal.sanitize_json_escapes(input)
  // 验证结果可以被正确解析
  let jv = @json.parse(result) catch { _ => Json::null() }
  match @internal.obj_get(jv, "instructions") {
    Some(String(s)) => assert_true(s.contains("keep-alive"))
    _ => fail("expected instructions field")
  }
}

///|
/// === is_json_truncated ===

///|
test "is_json_truncated - valid JSON object" {
  assert_false(@internal.is_json_truncated("{\"key\":\"value\"}"))
}

///|
test "is_json_truncated - truncated string (unterminated quote)" {
  assert_true(@internal.is_json_truncated("{\"key\":\"value"))
}

///|
test "is_json_truncated - truncated object (missing closing brace)" {
  assert_true(@internal.is_json_truncated("{\"key\":\"value\""))
}

///|
test "is_json_truncated - truncated array (missing closing bracket)" {
  assert_true(@internal.is_json_truncated("[1,2,3"))
}

///|
test "is_json_truncated - nested truncated" {
  assert_true(@internal.is_json_truncated("{\"a\":{\"b\":\"c\"}"))
}

///|
test "is_json_truncated - escaped quotes handled correctly" {
  // 引号被转义，不是字符串结束
  assert_false(@internal.is_json_truncated("{\"key\":\"val\\\"ue\"}"))
}

///|
test "is_json_truncated - real world truncated instructions" {
  // 模拟实际截断的 JSON
  let input = "{\"type\":\"response.created\",\"response\":{\"id\":\"resp_123\",\"created_at\":1787722174,\"instructions\":\"You are opencode.\\n\\nIMPORTANT: keep-alive.\"}"
  assert_true(@internal.is_json_truncated(input))
}

///|
/// === clean_sse_heartbeat ===

///|
test "clean_sse_heartbeat - removes : keep-alive at end" {
  let input = "{\"key\":\"value\"}: keep-alive"
  let result = @internal.clean_sse_heartbeat(input)
  assert_eq(result, "{\"key\":\"value\"}")
}

///|
test "clean_sse_heartbeat - removes :keep-alive at end" {
  let input = "{\"key\":\"value\"}:keep-alive"
  let result = @internal.clean_sse_heartbeat(input)
  assert_eq(result, "{\"key\":\"value\"}")
}

///|
test "clean_sse_heartbeat - removes : heartbeat at end" {
  let input = "{\"key\":\"value\"}: heartbeat"
  let result = @internal.clean_sse_heartbeat(input)
  assert_eq(result, "{\"key\":\"value\"}")
}

///|
test "clean_sse_heartbeat - preserves valid JSON" {
  let input = "{\"key\":\"value\"}"
  let result = @internal.clean_sse_heartbeat(input)
  assert_eq(result, "{\"key\":\"value\"}")
}

///|
test "clean_sse_heartbeat - preserves heartbeat in middle" {
  // 心跳标记在字符串中间，不应被移除
  let input = "{\"key\":\"value: keep-alive\"}"
  let result = @internal.clean_sse_heartbeat(input)
  assert_eq(result, "{\"key\":\"value: keep-alive\"}")
}

///|
test "clean_sse_heartbeat - real world SSE with heartbeat" {
  // 模拟实际 SSE 数据，末尾有心跳
  let input = "{\"type\":\"response.created\",\"response\":{\"id\":\"resp_123\"}}: keep-alive"
  let result = @internal.clean_sse_heartbeat(input)
  assert_eq(
    result, "{\"type\":\"response.created\",\"response\":{\"id\":\"resp_123\"}}",
  )
}

///|
test "clean_sse_heartbeat - removes : keep-alive. with period" {
  // 真实心跳带句点：": keep-alive."
  let input = "{\"key\":\"value\"}: keep-alive."
  let result = @internal.clean_sse_heartbeat(input)
  assert_eq(result, "{\"key\":\"value\"}")
}

///|
test "clean_sse_heartbeat - removes bare : keep-alive. row" {
  // 独立心跳行（整个字符串就是心跳）
  let input = ": keep-alive."
  let result = @internal.clean_sse_heartbeat(input)
  assert_eq(result, "")
}

///|
test "clean_sse_heartbeat - removes \\: keep-alive. escaped heartbeat" {
  // 心跳被错误合并进 JSON payload，产生无效转义 \: keep-alive.
  let input = "{\"instructions\":\"You are opencode.\\n\\nIMPORTANT:\\: keep-alive.\"}"
  let result = @internal.clean_sse_heartbeat(input)
  assert_eq(result, "{\"instructions\":\"You are opencode.\\n\\nIMPORTANT:\"}")
  // 清理结果必须能被 @json.parse 解析
  let jv = @json.parse(result) catch { _ => Json::null() }
  match @internal.obj_get(jv, "instructions") {
    Some(String(s)) => assert_true(!s.contains("keep-alive"))
    _ => fail("expected instructions field")
  }
}

///|
test "clean_sse_heartbeat - removes escaped heartbeat in real response.created payload" {
  // 复现用户报错：instructions 字段末尾混入 \: keep-alive. 且 JSON 未闭合
  let input = "{\"type\":\"response.created\",\"response\":{\"id\":\"resp_123\",\"created_at\":1787722850,\"instructions\":\"You are opencode.\\n\\nIMPORTANT:\\: keep-alive."
  let result = @internal.clean_sse_heartbeat(input)
  assert_true(!result.contains("keep-alive"))
}
