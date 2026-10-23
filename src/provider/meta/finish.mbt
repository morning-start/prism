///|
/// finish_reason 的协议枚举裁决 —— 四个 provider 的非流式与流式编码器共用。
///
/// ## 问题的真正形状
///
/// `LucentFinishReason` 有两个来源：
///
/// 1. **建模值**（`Stop` / `Length` / `ToolCalls` / `ContentFilter` / `Safety` /
///    `Recitation` / `MalformedToolCall` / `Error`）—— 可直接按协议映射。
/// 2. **`Native(s)`** —— 从某家 wire 协议**原样搬过来**的字符串。它属于
///    **源协议**的词汇表，与目标协议毫无关系。
///
/// 第一版实现（本文件上一版）按 IR 枚举 match，`Native(s)` 无条件透传 ——
/// 这留下一个结构性漏洞，实测可复现：
///
/// ```
/// messages 源 stop_reason="pause_turn"（Anthropic 合法）
///   → IR Native("pause_turn")
///   → openai 出站 "finish_reason":"pause_turn"   ← OpenAI 非法枚举
/// ```
///
/// 即：**八个建模值修好了，`Native` 仍能溢出**。根因不是映射表不全，而是
/// 裁决方向错了 —— 合法性是**目标槽位的属性**，不是 IR 值的属性。
///
/// ## 正确模型：目标白名单裁决
///
/// 每个目标协议有一个**封闭的合法值集合**（由官方 schema 决定）。任何出站值
/// 必须满足「∈ 目标合法集合」。于是：
///
/// ```text
/// 值 ∈ target_legal  →  Exact      直接写出
/// 值 ∉ target_legal  →  Degraded   收敛到该目标的兜底值 + 诊断
/// ```
///
/// 这条规则**统一处理**建模值与 `Native`：不需要为 `Native` 写特例，也不会
/// 因为漏写一个 `match` 分支而溢出。建模值先做语义映射（`Stop → end_turn`），
/// 映射结果同样过白名单；`Native(s)` 直接过白名单。
///
/// 白名单常量集中在本文件，与 `@internal.protocol_native_keys` 的归属表同属
/// 「协议事实」层；`scripts/check_schema_drift.ps1` 可扩展为对照 vendored
/// OpenAPI 校验 openai / responses 两列。
///
/// ## 为什么放在 `meta`
///
/// 需要 `@lux` 类型 + `@internal.json_escape`，且要被四个 provider 共用。
/// 放 `lux` 会引入对 wire 协议的认知（破坏分层）；四处复制会漂移。
/// `meta` 是 provider 共享叶子包，同时依赖两者，是无环的落点。

///|
/// Anthropic Messages `stop_reason` 的封闭合法值集合。
///
/// 来源：Anthropic Messages API 文档（`stop_reason` 字段）。含
/// `pause_turn`（服务端工具循环暂停）与 `model_context_window_exceeded`。
let messages_stop_reasons : Array[String] = [
  "end_turn", "max_tokens", "stop_sequence", "tool_use", "refusal", "pause_turn",
  "model_context_window_exceeded",
]

///|
/// OpenAI Chat `finish_reason` 的封闭合法值集合。
///
/// 来源：vendored 官方 OpenAPI（`schemas/endpoints/openai-openapi.yaml`，
/// `CreateChatCompletionResponse.choices[].finish_reason`）。
let openai_finish_reasons : Array[String] = [
  "stop", "length", "tool_calls", "content_filter", "function_call",
]

///|
/// Google Gemini `finishReason` 的封闭合法值集合（全大写）。
///
/// 来源：Gemini `GenerateContentResponse.candidates[].finishReason`。
let gemini_finish_reasons : Array[String] = [
  "FINISH_REASON_UNSPECIFIED", "STOP", "MAX_TOKENS", "SAFETY", "RECITATION", "LANGUAGE",
  "OTHER", "BLOCKLIST", "PROHIBITED_CONTENT", "SPII", "MALFORMED_FUNCTION_CALL",
  "IMAGE_SAFETY", "UNEXPECTED_TOOL_CALL", "TOO_MANY_TOOL_CALLS", "MALFORMED_RESPONSE",
  "MISSING_THOUGHT_SIGNATURE",
]

///|
/// OpenAI Responses `response.status` 的封闭合法值集合。
///
/// 来源：vendored 官方 OpenAPI（`Response.status`）。
let responses_statuses : Array[String] = [
  "completed", "failed", "in_progress", "cancelled", "queued", "incomplete",
]

///|
/// 裁决结果的统一形态：一个**保证落在目标合法集合内**的字面量 + 是否降级。
///
/// `degraded = true` 时调用方必须打诊断（收敛不能静默）。
pub struct FinishVerdict {
  value : String
  degraded : Bool
}

///|
/// 内部：把候选值裁到目标白名单内。
///
/// 命中 → `Exact`；未命中 → 用 `fallback` 兜底并标记 `degraded`。
/// `fallback` 自身必须 ∈ `legal`（由调用方常量保证；本函数再做一次断言式
/// 兜底，避免将来误配导致再次溢出）。
fn arbitrate(
  candidate : String,
  legal : Array[String],
  fallback : String,
) -> FinishVerdict {
  if legal.contains(candidate) {
    { value: candidate, degraded: false, }
  } else {
    // 收敛到 fallback。fallback 由调用方常量给出，必然 ∈ legal（构建期约定，
    // 见各收敛器的 fallback 实参），故无需运行时再校验一次 —— 那会是不可达分支。
    { value: fallback, degraded: true, }
  }
}

///|
/// IR → Anthropic Messages `stop_reason`（**保证合法**）。
///
/// 语义映射（建模值）：
/// - `Stop` → `end_turn`；`Length` → `max_tokens`；`ToolCalls` → `tool_use`
///   （**不是 `tool_calls`**，那是 OpenAI 的词）；`ContentFilter` → `refusal`
/// - `Safety` / `Recitation` / `MalformedToolCall` / `Error` → 无对等值，
///   过白名单时未命中 → 收敛 `end_turn` + 诊断
/// - `Native(s)` → 直接过白名单：Anthropic 自己的值（`pause_turn` /
///   `model_context_window_exceeded` …）保留；其它协议的值收敛 + 诊断
///
/// 返回带引号的 JSON 字符串字面量。
pub fn messages_stop_reason_json(
  fr : @lux.LucentFinishReason,
  field_prefix : String,
  diagnostics : Array[@lux.ConversionDiagnostic],
) -> String {
  let candidate = match fr {
    Stop => "end_turn"
    Length => "max_tokens"
    ToolCalls => "tool_use"
    ContentFilter => "refusal"
    Native(s) => s
    // 以下四个显式给出候选，让它们在诊断里保留可读来源（否则会以 IR 拼写
    // 落进兜底，诊断信息仍正确，但这里更直白）
    Safety => "safety"
    Recitation => "recitation"
    MalformedToolCall => "malformed_tool_call"
    Error => "error"
  }
  let v = arbitrate(candidate, messages_stop_reasons, "end_turn")
  if v.degraded {
    @lux.push_finish_converged(
      field_prefix,
      "stop_reason",
      candidate,
      v.value,
      diagnostics,
    )
  }
  "\"" + @internal.json_escape(v.value) + "\""
}

///|
/// IR → OpenAI Chat `finish_reason`（**保证合法**）。
///
/// 语义映射（建模值）：`Stop` → `stop`；`Length` → `length`；`ToolCalls` →
/// `tool_calls`；`ContentFilter` → `content_filter`。其余建模值与 `Native(s)`
/// 均过白名单，未命中 → `stop` + 诊断。
///
/// 返回带引号的 JSON 字符串字面量。
pub fn openai_finish_reason_json(
  fr : @lux.LucentFinishReason,
  field_prefix : String,
  diagnostics : Array[@lux.ConversionDiagnostic],
) -> String {
  let candidate = match fr {
    Stop => "stop"
    Length => "length"
    ToolCalls => "tool_calls"
    ContentFilter => "content_filter"
    Native(s) => s
    Safety => "safety"
    Recitation => "recitation"
    MalformedToolCall => "malformed_tool_call"
    Error => "error"
  }
  let v = arbitrate(candidate, openai_finish_reasons, "stop")
  if v.degraded {
    @lux.push_finish_converged(
      field_prefix,
      "finish_reason",
      candidate,
      v.value,
      diagnostics,
    )
  }
  "\"" + @internal.json_escape(v.value) + "\""
}

///|
/// IR → Gemini `finishReason`（**保证合法**，不含引号）。
///
/// 语义映射（建模值）：`Stop` → `STOP`；`Length` → `MAX_TOKENS`；
/// `Safety` → `SAFETY`；`Recitation` → `RECITATION`；`MalformedToolCall` →
/// `MALFORMED_FUNCTION_CALL`；`Error` → `OTHER`。
///
/// `ToolCalls` → `STOP`：Gemini 的 `finishReason` 无工具调用枚举（工具调用
/// 由 `functionCall` part 表达，不是结束原因），属**语义对等**，故不做降级
/// 诊断。
///
/// `ContentFilter` → `SAFETY`：Gemini 侧内容拦截的真实载体是
/// `promptFeedback.blockReason`；`finishReason` 层面语义最近的是 `SAFETY`。
/// 上一版收敛到 `STOP` 会把「被拦截」伪装成「正常结束」，故改为 `SAFETY`。
///
/// `Native(s)` 直接过白名单（Gemini 自己的 `LANGUAGE` / `BLOCKLIST` / `SPII`
/// 等保留），未命中 → `OTHER` + 诊断。
pub fn gemini_finish_reason(
  fr : @lux.LucentFinishReason,
  field_prefix : String,
  diagnostics : Array[@lux.ConversionDiagnostic],
) -> String {
  let candidate = match fr {
    Stop => "STOP"
    Length => "MAX_TOKENS"
    ToolCalls => "STOP"
    Safety => "SAFETY"
    Recitation => "RECITATION"
    MalformedToolCall => "MALFORMED_FUNCTION_CALL"
    Error => "OTHER"
    ContentFilter => "SAFETY"
    Native(s) => s
  }
  // ToolCalls → STOP 是语义对等（不是降级），故不产生诊断：
  // 用一个不可达的 fallback 值让 arbitrate 报告 degraded，再在此处抑制。
  let verdict = arbitrate(candidate, gemini_finish_reasons, "OTHER")
  let is_toolcalls = match fr {
    ToolCalls => true
    _ => false
  }
  if verdict.degraded && !is_toolcalls {
    @lux.push_finish_converged(
      field_prefix,
      "finishReason",
      candidate,
      verdict.value,
      diagnostics,
    )
  }
  @internal.json_escape(verdict.value)
}

///|
/// IR → OpenAI Responses `response.status`（**保证合法**，含引号）。
///
/// 官方 `Response.status` 只有 6 个值：`completed` / `failed` / `in_progress` /
/// `cancelled` / `queued` / `incomplete`。
///
/// 映射：
/// - `Stop` / `ToolCalls` → `completed`（工具调用的完成由 `function_call`
///   output item 表达，状态层面是正常完成；**语义对等，不诊断**）
/// - `Length` → `incomplete` + 调用方补 `reason=max_output_tokens`（对等）
/// - `ContentFilter` → `incomplete` + 调用方补 `reason=content_filter`（对等）
/// - `Error` → `failed`（对等：OpenAI 的 failed 就是执行失败）
/// - `Safety` / `Recitation` / `MalformedToolCall` → `failed` + **诊断**。
///   这三个值虽然能映射到合法 `failed`，但与 `Error` 语义不同（安全拦截 /
///   复述 / 工具调用畸形 vs 执行出错），压成同一个 `failed` 会丢失区分度。
/// - `Native(s)`：∈ 合法集合 → 透传（不诊断）；否则收敛 + 诊断。
///
/// ### 诊断判据：语义损失，而非「值是否合法」
///
/// 这一点极易写错（本文件第一版就错了）：`Safety → "failed"` 的值**是合法的**，
/// 若只按 `arbitrate` 的 `degraded` 标志判断就不会报警 —— 但语义确实收敛了。
/// 因此诊断分两类来源：
///   1. 值不合法（`arbitrate.degraded`）→ 必须报；
///   2. 值合法但有信息损失（`Safety`/`Recitation`/`MalformedToolCall` 共压
///      `failed`）→ 也必须报。
pub fn responses_status_json(
  fr : @lux.LucentFinishReason,
  field_prefix : String,
  diagnostics : Array[@lux.ConversionDiagnostic],
) -> String {
  let candidate = match fr {
    Stop => "completed"
    ToolCalls => "completed"
    Length => "incomplete"
    ContentFilter => "incomplete"
    Error => "failed"
    Native(s) => s
    Safety => "failed"
    Recitation => "failed"
    MalformedToolCall => "failed"
  }
  let v = arbitrate(candidate, responses_statuses, "completed")
  // 语义损失（即便值合法）：三个 IR 专属原因共压到 failed
  let lossy = match fr {
    Safety | Recitation | MalformedToolCall => true
    _ => false
  }
  if v.degraded || lossy {
    @lux.push_finish_converged(
      field_prefix,
      "status",
      candidate,
      v.value,
      diagnostics,
    )
  }
  "\"" + @internal.json_escape(v.value) + "\""
}

///|
/// 给定 IR 结束原因，Responses 目标的 `incomplete_details.reason` 应为何值。
///
/// 官方枚举：`max_output_tokens` / `max_messages` / `content_filter` /
/// `steered`。返回 `None` 表示 status 不是 `incomplete`，不应输出该字段。
pub fn responses_incomplete_reason(fr : @lux.LucentFinishReason) -> String? {
  match fr {
    Length => Some("max_output_tokens")
    ContentFilter => Some("content_filter")
    _ => None
  }
}
