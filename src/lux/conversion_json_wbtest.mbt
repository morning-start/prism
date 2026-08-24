///|
/// 信封 JSON 编解码测试 — ConversionStatus / ConversionDiagnostic / ConversionResult
///
/// 目标：让 Exact/Degraded/Unsupported/Invalid 成为可检测的协议输出。
/// JSON 形状：
///   ConversionStatus:    "exact" | "degraded" | "unsupported" | "invalid"
///   ConversionDiagnostic: {"field":"...","status":"...","detail":"..."}
///   ConversionResult:     {"value":<T>,"diagnostics":[...]}
///   envelope_json:        {"value":<value_json>,"diagnostics":[...]}

///|
/// === ConversionStatus round-trip ===

///|
test "ConversionStatus round-trip - all variants" {
  let all = [Exact, Degraded, Unsupported, Invalid]
  for s in all {
    match ConversionStatus::from_json(s.to_json()) {
      Ok(d) => assert_eq(d, s)
      Err(e) => fail("status round-trip failed: \{e}")
    }
  }
}

///|
test "ConversionStatus to_json - lowercase strings" {
  assert_eq(Exact.to_json(), Json::string("exact"))
  assert_eq(Degraded.to_json(), Json::string("degraded"))
  assert_eq(Unsupported.to_json(), Json::string("unsupported"))
  assert_eq(Invalid.to_json(), Json::string("invalid"))
}

///|
test "ConversionStatus from_json - unknown value returns error" {
  match ConversionStatus::from_json(Json::string("bogus")) {
    Ok(_) => fail("expected error for unknown status")
    Err(_) => assert_true(true)
  }
}

///|
/// === ConversionDiagnostic round-trip ===

///|
test "ConversionDiagnostic round-trip - with detail" {
  let d = ConversionDiagnostic::new("content", Degraded, Some("media as text"))
  match ConversionDiagnostic::from_json(d.to_json()) {
    Ok(dd) => {
      assert_eq(dd.field, "content")
      assert_eq(dd.status, Degraded)
      assert_eq(dd.detail, Some("media as text"))
    }
    Err(e) => fail("diag round-trip failed: \{e}")
  }
}

///|
test "ConversionDiagnostic round-trip - no detail" {
  let d = ConversionDiagnostic::new("tool_choice", Unsupported, None)
  match ConversionDiagnostic::from_json(d.to_json()) {
    Ok(dd) => {
      assert_eq(dd.field, "tool_choice")
      assert_eq(dd.status, Unsupported)
      assert_eq(dd.detail, None)
    }
    Err(e) => fail("diag round-trip failed: \{e}")
  }
}

///|
test "ConversionDiagnostic from_json - missing field returns error" {
  match
    ConversionDiagnostic::from_json(
      Json::object({ "field": Json::string("x") }),
    ) {
    Ok(_) => fail("expected error for missing status")
    Err(_) => assert_true(true)
  }
}

///|
/// === ConversionResult round-trip ===

///|
test "ConversionResult round-trip - value with diagnostics" {
  let r : ConversionResult[String] = ConversionResult::new("ok")
  let r = r.with_diagnostic(ConversionDiagnostic::new("x", Unsupported, None))
  match
    ConversionResult::from_json(r.to_json(Json::string), fn(
      j : Json,
    ) -> Result[String, String] {
      match j {
        String(s) => Ok(s)
        _ => Err("expected string")
      }
    }) {
    Ok(cr) => {
      assert_eq(cr.value(), "ok")
      assert_eq(cr.diagnostics().length(), 1)
      assert_eq(cr.diagnostics()[0].field, "x")
      assert_eq(cr.diagnostics()[0].status, Unsupported)
    }
    Err(e) => fail("result round-trip failed: \{e}")
  }
}

///|
test "ConversionResult envelope - contains value and diagnostics" {
  let r : ConversionResult[String] = ConversionResult::new("ok")
  let r = r.with_diagnostic(
    ConversionDiagnostic::new("x", Invalid, Some("bad")),
  )
  let env = r.envelope_json(Json::string("ok"))
  let jv = @json.parse(env.stringify()) catch {
    _ => fail("envelope parse failed")
  }
  match jv {
    Object(map) => {
      assert_true(map.contains("value"))
      assert_true(map.contains("diagnostics"))
    }
    _ => fail("expected object envelope")
  }
}

///|
test "ConversionResult envelope - diagnostics array non-empty" {
  let r : ConversionResult[String] = ConversionResult::new("v")
  let r = r.with_diagnostic(ConversionDiagnostic::new("f", Degraded, Some("d")))
  let env = r.envelope_json(Json::string("v"))
  let jv = @json.parse(env.stringify()) catch {
    _ => fail("envelope parse failed")
  }
  match jv {
    Object(map) =>
      match map.get("diagnostics") {
        Some(Array(arr)) => assert_eq(arr.length(), 1)
        _ => fail("expected diagnostics array")
      }
    _ => fail("expected object envelope")
  }
}
