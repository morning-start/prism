///|
/// 诊断策略与聚合器测试（T10）
///
/// 覆盖 DiagnosticPolicy / enforce_policy / DiagnosticCollector：
///   - 三档策略的失败判定（ReportOnly 永不失败）
///   - 收集器计数（按 status / field）、最重诊断、summary、reset
///   - 与 convert_*_with_hooks 的集成（钩子诊断进入策略判定）

///|
/// === enforce_policy ===
test "enforce_policy - ReportOnly never fails" {
  let diags : Array[@lux.ConversionDiagnostic] = [
    @lux.ConversionDiagnostic::unsupported("tools.kind", Some("x")),
    @lux.ConversionDiagnostic::degraded("options.effort", None),
  ]
  match @sdk.enforce_policy("value", diags, ReportOnly) {
    Ok(v) => assert_eq(v, "value")
    Err(_) => fail("ReportOnly should never fail")
  }
}

///|
test "enforce_policy - FailOnUnsupported fails on Unsupported" {
  let diags : Array[@lux.ConversionDiagnostic] = [
    @lux.ConversionDiagnostic::degraded("a", None),
    @lux.ConversionDiagnostic::unsupported("tools.kind", Some("x")),
  ]
  match @sdk.enforce_policy(42, diags, FailOnUnsupported) {
    Ok(_) => fail("expected policy violation")
    Err(e) => assert_true(e.contains("FailOnUnsupported"))
  }
}

///|
test "enforce_policy - FailOnUnsupported passes on Degraded only" {
  let diags : Array[@lux.ConversionDiagnostic] = [
    @lux.ConversionDiagnostic::degraded("a", None),
  ]
  match @sdk.enforce_policy(42, diags, FailOnUnsupported) {
    Ok(v) => assert_eq(v, 42)
    Err(e) => fail("unexpected failure: \{e}")
  }
}

///|
test "enforce_policy - FailOnDegraded fails on Degraded" {
  let diags : Array[@lux.ConversionDiagnostic] = [
    @lux.ConversionDiagnostic::degraded("options.effort", None),
  ]
  match @sdk.enforce_policy(42, diags, FailOnDegraded) {
    Ok(_) => fail("expected policy violation")
    Err(e) => assert_true(e.contains("FailOnDegraded"))
  }
}

///|
test "enforce_policy - empty diagnostics always pass" {
  let diags : Array[@lux.ConversionDiagnostic] = []
  match @sdk.enforce_policy("v", diags, FailOnDegraded) {
    Ok(v) => assert_eq(v, "v")
    Err(e) => fail("unexpected failure: \{e}")
  }
}

///|
/// === DiagnosticCollector ===
test "collector - counts by status" {
  let c = @sdk.DiagnosticCollector::new()
  c.push(@lux.ConversionDiagnostic::degraded("a", None))
  c.push(@lux.ConversionDiagnostic::degraded("b", None))
  c.push(@lux.ConversionDiagnostic::unsupported("c", None))
  c.push(@lux.ConversionDiagnostic::new("d", Invalid, None))
  let counts = c.count_by_status()
  assert_eq(counts.degraded, 2)
  assert_eq(counts.unsupported, 1)
  assert_eq(counts.invalid, 1)
  assert_eq(counts.exact, 0)
  assert_eq(counts.total(), 4)
  assert_eq(c.total(), 4)
}

///|
test "collector - counts by field and worst status" {
  let c = @sdk.DiagnosticCollector::new()
  c.push(@lux.ConversionDiagnostic::degraded("options.effort", None))
  c.push(@lux.ConversionDiagnostic::unsupported("options.effort", None))
  c.push(@lux.ConversionDiagnostic::degraded("tools.kind", None))
  assert_eq(c.count_by_field("options.effort"), 2)
  assert_eq(c.count_by_field("tools.kind"), 1)
  assert_eq(c.count_by_field("nonexistent"), 0)
  assert_eq(c.worst_status(), Some(Unsupported))
}

///|
test "collector - empty state" {
  let c = @sdk.DiagnosticCollector::new()
  assert_eq(c.total(), 0)
  assert_eq(c.worst_status(), None)
  assert_eq(c.summary(), "diagnostics: none")
}

///|
test "collector - summary lists nonzero statuses" {
  let c = @sdk.DiagnosticCollector::new()
  c.add_all([
    @lux.ConversionDiagnostic::degraded("a", None),
    @lux.ConversionDiagnostic::unsupported("b", None),
  ])
  let s = c.summary()
  assert_true(s.contains("total=2"))
  assert_true(s.contains("Degraded=1"))
  assert_true(s.contains("Unsupported=1"))
  // 零计数 status 不出现
  assert_false(s.contains("Exact="))
}

///|
test "collector - enforce and reset" {
  let c = @sdk.DiagnosticCollector::new()
  c.push(@lux.ConversionDiagnostic::unsupported("tools.kind", None))
  match c.enforce(FailOnUnsupported) {
    Ok(_) => fail("expected violation")
    Err(e) => assert_true(e.contains("tools.kind"))
  }
  c.reset()
  assert_eq(c.total(), 0)
  match c.enforce(FailOnDegraded) {
    Ok(_) => ()
    Err(e) => fail("unexpected: \{e}")
  }
}

///|
test "collector - diagnostics returns copy" {
  let c = @sdk.DiagnosticCollector::new()
  c.push(@lux.ConversionDiagnostic::degraded("a", None))
  let copy = c.diagnostics()
  assert_eq(copy.length(), 1)
  // 修改副本不影响收集器
  ignore(copy.pop())
  assert_eq(c.total(), 1)
}

///|
/// === 集成：钩子诊断进入策略判定 ===
test "integration - hook diagnostics feed policy enforcement" {
  // 钩子注入一条 Unsupported 诊断（模拟中间件自有策略判定）
  let diag_hook = fn(
    ir : @lux.LucentRequest,
    diags : Array[@lux.ConversionDiagnostic],
  ) -> @lux.LucentRequest {
    diags.push(
      @lux.ConversionDiagnostic::unsupported("hook.audit", Some("injected")),
    )
    ir
  }
  let json = "{\"model\":\"gpt-4o\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}"
  match
    @sdk.convert_request_with_hooks("openai", json, "messages", [diag_hook]) {
    Ok(cr) => {
      let c = @sdk.DiagnosticCollector::new()
      c.add_all(cr.diagnostics())
      assert_eq(c.count_by_field("hook.audit"), 1)
      // ReportOnly 放行
      match @sdk.enforce_policy(cr.value(), c.diagnostics(), ReportOnly) {
        Ok(v) => assert_eq(v, cr.value())
        Err(e) => fail("ReportOnly should pass: \{e}")
      }
      // FailOnUnsupported 拦截
      match
        @sdk.enforce_policy(cr.value(), c.diagnostics(), FailOnUnsupported) {
        Ok(_) => fail("expected policy violation")
        Err(e) => assert_true(e.contains("hook.audit"))
      }
      // FailOnDegraded 同样拦截（Unsupported 重于 Degraded）
      match c.enforce(FailOnDegraded) {
        Ok(_) => fail("expected violation")
        Err(_) => ()
      }
    }
    Err(e) => fail("convert failed: \{e}")
  }
}
