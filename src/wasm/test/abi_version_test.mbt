///|
/// ABI 版本导出测试（T11）

///|
test "wasm_abi_version - returns abi and ir schema versions" {
  let result = @wasm.wasm_abi_version()
  assert_true(result.contains("\"value\""))
  let jv = @json.parse(result) catch { _ => Json::null() }
  match jv {
    Object(map) =>
      match map.get("value") {
        Some(Object(fields)) => {
          match fields.get("abi") {
            Some(String(v)) => assert_eq(v, "1")
            _ => fail("expected abi string")
          }
          match fields.get("ir_schema") {
            Some(String(v)) => assert_eq(v, "v1")
            _ => fail("expected ir_schema string")
          }
        }
        _ => fail("expected value object in envelope")
      }
    _ => fail("expected object envelope")
  }
}

///|
/// 与 Lux IR 实际 schema_version 一致（防漂移）
test "wasm_abi_version - ir schema matches LucentRequest" {
  let req = @lux.LucentRequest::new(
    "m",
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
  let result = @wasm.wasm_abi_version()
  assert_true(result.contains("\"" + req.schema_version + "\""))
}
