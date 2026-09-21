///|
/// ═══ 功能组：diagnostics（诊断策略与聚合，T10）═══
/// DiagnosticPolicy + DiagnosticCollector：让转换诊断从"返回数组"
/// 升级为可运维信号——中间件按策略熔断、按租户统计降级率。
///
/// 背景（架构审计 P1-10）：诊断有 Exact/Degraded/Unsupported 分级，
/// 但没有策略控制与聚合；宿主全部自建。本组补上：
/// - 策略：ReportOnly（默认，行为不变）/ FailOnUnsupported /
///   FailOnDegraded——"Unsupported capabilities MUST fail explicitly"
///   的可配置落地
/// - 聚合：按 status/field 计数、最重诊断、人类可读 summary

///|
/// status 标签（ConversionStatus 无 to_string；集中于此避免散落字面量）
fn status_label(status : @lux.ConversionStatus) -> String {
  match status {
    Exact => "Exact"
    Degraded => "Degraded"
    Unsupported => "Unsupported"
    Invalid => "Invalid"
  }
}

///|
/// DiagnosticPolicy — 诊断处置策略
pub(all) enum DiagnosticPolicy {
  /// 只报告不失败（默认；与既有行为完全一致）
  ReportOnly
  /// 任一 Unsupported（或更严重）诊断即失败
  FailOnUnsupported
  /// 任一 Degraded（或更严重）诊断即失败
  FailOnDegraded
} derive(Eq, Debug)

///|
/// 诊断严重度排序（数值越大越重）：Exact < Degraded < Unsupported < Invalid
fn status_severity(status : @lux.ConversionStatus) -> Int {
  match status {
    Exact => 0
    Degraded => 1
    Unsupported => 2
    Invalid => 3
  }
}

///|
/// 策略阈值：达到该严重度即失败（ReportOnly 返回 -1 = 不失败）
fn policy_threshold(policy : DiagnosticPolicy) -> Int {
  match policy {
    ReportOnly => -1
    FailOnUnsupported => 2
    FailOnDegraded => 1
  }
}

///|
/// 策略名（错误消息用）
fn policy_label(policy : DiagnosticPolicy) -> String {
  match policy {
    ReportOnly => "ReportOnly"
    FailOnUnsupported => "FailOnUnsupported"
    FailOnDegraded => "FailOnDegraded"
  }
}

///|
/// 对「值 + 诊断」执行策略（T10 一次性入口）
///
/// ReportOnly → 原样 Ok；FailOnUnsupported/FailOnDegraded → 存在达到
/// 阈值的诊断时返回 Err（消息含计数与首条诊断详情）。
pub fn[T] enforce_policy(
  value : T,
  diagnostics : Array[@lux.ConversionDiagnostic],
  policy : DiagnosticPolicy,
) -> Result[T, String] {
  let threshold = policy_threshold(policy)
  if threshold < 0 {
    return Ok(value)
  }
  let mut violations = 0
  let mut first_detail : String? = None
  for d in diagnostics {
    if status_severity(d.status) >= threshold {
      violations = violations + 1
      if first_detail is None {
        first_detail = Some(d.field + ": " + status_label(d.status))
      }
    }
  }
  if violations == 0 {
    Ok(value)
  } else {
    Err(
      "diagnostic policy " +
      policy_label(policy) +
      " violated: " +
      violations.to_string() +
      " diagnostic(s) at or above threshold; first: " +
      first_detail.unwrap_or(""),
    )
  }
}

///|
/// DiagnosticCounts — 按 status 的计数（ConversionStatus 无 Hash 实现，
/// 用专用结构体而非 Map；运维直接读字段）
pub struct DiagnosticCounts {
  mut exact : Int
  mut degraded : Int
  mut unsupported : Int
  mut invalid : Int
} derive(Eq, Debug)

///|
pub fn DiagnosticCounts::default() -> DiagnosticCounts {
  { exact: 0, degraded: 0, unsupported: 0, invalid: 0, }
}

///|
/// 计数总数
pub fn DiagnosticCounts::total(self : DiagnosticCounts) -> Int {
  self.exact + self.degraded + self.unsupported + self.invalid
}

///|
/// DiagnosticCollector — 诊断聚合器（T10）
///
/// 中间件运维视图：跨请求累积诊断，按 status/field 计数，
/// 取最重诊断，输出人类可读 summary。典型用法：
/// ```moonbit nochecheck
/// let collector = DiagnosticCollector::new()
/// collector.add_all(result.diagnostics())
/// // 周期性：
/// log(collector.summary())
/// collector.reset()
/// ```
pub struct DiagnosticCollector {
  all : Array[@lux.ConversionDiagnostic]
}

///|
pub fn DiagnosticCollector::new() -> DiagnosticCollector {
  { all: [], }
}

///|
/// 追加单条诊断
pub fn DiagnosticCollector::push(
  self : DiagnosticCollector,
  diagnostic : @lux.ConversionDiagnostic,
) -> Unit {
  self.all.push(diagnostic)
}

///|
/// 追加一组诊断（如 ConversionResult.diagnostics()）
pub fn DiagnosticCollector::add_all(
  self : DiagnosticCollector,
  diagnostics : Array[@lux.ConversionDiagnostic],
) -> Unit {
  for d in diagnostics {
    self.all.push(d)
  }
}

///|
/// 按 status 计数
pub fn DiagnosticCollector::count_by_status(
  self : DiagnosticCollector,
) -> DiagnosticCounts {
  let counts = DiagnosticCounts::default()
  for d in self.all {
    match d.status {
      Exact => counts.exact = counts.exact + 1
      Degraded => counts.degraded = counts.degraded + 1
      Unsupported => counts.unsupported = counts.unsupported + 1
      Invalid => counts.invalid = counts.invalid + 1
    }
  }
  counts
}

///|
/// 按 field 计数（运维定位热点字段，如 options.previous_response_id）
pub fn DiagnosticCollector::count_by_field(
  self : DiagnosticCollector,
  field : String,
) -> Int {
  let mut n = 0
  for d in self.all {
    if d.field == field {
      n = n + 1
    }
  }
  n
}

///|
/// 诊断总数
pub fn DiagnosticCollector::total(self : DiagnosticCollector) -> Int {
  self.all.length()
}

///|
/// 最重诊断的 status（空收集器返回 None）
pub fn DiagnosticCollector::worst_status(
  self : DiagnosticCollector,
) -> @lux.ConversionStatus? {
  let mut worst : @lux.ConversionStatus? = None
  let mut worst_score = -1
  for d in self.all {
    let score = status_severity(d.status)
    if score > worst_score {
      worst_score = score
      worst = Some(d.status)
    }
  }
  worst
}

///|
/// 对收集的诊断执行策略（周期巡检/熔断判定用）
pub fn DiagnosticCollector::enforce(
  self : DiagnosticCollector,
  policy : DiagnosticPolicy,
) -> Result[Unit, String] {
  match enforce_policy((), self.all, policy) {
    Ok(_) => Ok(())
    Err(e) => Err(e)
  }
}

///|
/// 人类可读摘要（日志/监控用）
pub fn DiagnosticCollector::summary(self : DiagnosticCollector) -> String {
  if self.all.length() == 0 {
    return "diagnostics: none"
  }
  let counts = self.count_by_status()
  let parts : Array[String] = []
  if counts.exact > 0 {
    parts.push("Exact=" + counts.exact.to_string())
  }
  if counts.degraded > 0 {
    parts.push("Degraded=" + counts.degraded.to_string())
  }
  if counts.unsupported > 0 {
    parts.push("Unsupported=" + counts.unsupported.to_string())
  }
  if counts.invalid > 0 {
    parts.push("Invalid=" + counts.invalid.to_string())
  }
  "diagnostics: total=" +
  self.all.length().to_string() +
  " [" +
  parts.join(" ") +
  "]"
}

///|
/// 取全部诊断（上报/导出用）
pub fn DiagnosticCollector::diagnostics(
  self : DiagnosticCollector,
) -> Array[@lux.ConversionDiagnostic] {
  self.all.copy()
}

///|
/// 清空（周期快照后重置）
pub fn DiagnosticCollector::reset(self : DiagnosticCollector) -> Unit {
  while self.all.length() > 0 {
    ignore(self.all.pop())
  }
}
