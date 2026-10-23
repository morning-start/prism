///|
/// finish_reason 的协议枚举收敛器 —— 非流式与流式编码器共用。
///
/// ## 为什么需要
///
/// IR 的 `LucentFinishReason::to_string()` 输出的是 **IR 自己的词汇表**
/// （`stop` / `length` / `tool_calls` / `safety` / `recitation` /
/// `malformed_tool_call` / `error` / `content_filter`），它与任何一家 wire
/// 协议的枚举都不同。直接把 `to_string()` 写进出站 body 会产生**非法枚举值**，
/// 严格校验的对端会拒绝整个响应体或整条流。
///
/// 非流式路径此前已在各 provider 的 `response.mbt` 内做了逐协议收敛；
/// 流式路径却直接 `fr.to_string()` —— 同一个协议两条路径输出不同词汇表。
/// 本文件把收敛规则集中，两条路径共用，避免再次漂移。
///
/// ## 为什么放在 `meta`
///
/// 收敛需要 `@lux` 的类型与 `@internal.json_escape`，且要被四个 provider 共享。
/// 放 `lux` 会引入对 wire 协议的认知（破坏分层），四个 provider 各写一份会漂移。
/// `meta` 是 provider 共享叶子包，同时依赖两者，是无环的落点。

///|
/// IR → Anthropic Messages `stop_reason` 的**合法**取值。
///
/// 官方枚举（`schemas/endpoints/` 与 Anthropic 文档）：
/// `end_turn` / `max_tokens` / `stop_sequence` / `tool_use` / `refusal` /
/// `pause_turn` / `model_context_window_exceeded`。
///
/// 映射：
/// - `Stop` → `end_turn`（正常结束）
/// - `Length` → `max_tokens`
/// - `ToolCalls` → `tool_use`（**不是 `tool_calls`**，那是 OpenAI 的词）
/// - `ContentFilter` → `refusal`（语义最近的载体）
/// - `Native(s)` → 原样透传（厂商自定义值，保持不丢）
/// - `Safety` / `Recitation` / `MalformedToolCall` / `Error` → 无对等值，
///   收敛为 `end_turn` **并打 Unsupported 诊断**：四者语义差异很大
///   （安全拦截 / 复述 / 工具调用畸形 / 上游出错），静默压成 `end_turn`
///   会让调用方误以为模型正常说完。
///
/// 返回已是带引号的 JSON 字符串字面量（含转义），可直接拼接。
pub fn messages_stop_reason_json(
  fr : @lux.LucentFinishReason,
  field_prefix : String,
  diagnostics : Array[@lux.ConversionDiagnostic],
) -> String {
  match fr {
    Stop => "\"end_turn\""
    Length => "\"max_tokens\""
    ToolCalls => "\"tool_use\""
    ContentFilter => "\"refusal\""
    Native(s) => "\"" + @internal.json_escape(s) + "\""
    other => {
      diagnostics.push(
        @lux.ConversionDiagnostic::unsupported(
          field_prefix + ".finish_reason",
          Some(
            "finish_reason \"" +
            other.to_string() +
            "\" has no anthropic stop_reason equivalent; emitted \"end_turn\" instead",
          ),
        ),
      )
      "\"end_turn\""
    }
  }
}

///|
/// IR → OpenAI Chat `finish_reason` 的**合法**取值。
///
/// 官方枚举（vendored `schemas/endpoints/openai-openapi.yaml`，
/// `CreateChatCompletionResponse.choices[].finish_reason`）：
/// `stop` / `length` / `tool_calls` / `content_filter` / `function_call`。
///
/// 映射：
/// - `Stop` → `stop`；`Length` → `length`；`ToolCalls` → `tool_calls`；
///   `ContentFilter` → `content_filter`
/// - `Native(s)` → 原样透传
/// - `Safety` / `Recitation` / `MalformedToolCall` / `Error` → 无合法对等枚举，
///   收敛为 `stop` + Unsupported 诊断。
///
/// 返回已是带引号的 JSON 字符串字面量（含转义）。
pub fn openai_finish_reason_json(
  fr : @lux.LucentFinishReason,
  field_prefix : String,
  diagnostics : Array[@lux.ConversionDiagnostic],
) -> String {
  match fr {
    Stop => "\"stop\""
    Length => "\"length\""
    ToolCalls => "\"tool_calls\""
    ContentFilter => "\"content_filter\""
    Native(s) => "\"" + @internal.json_escape(s) + "\""
    other => {
      diagnostics.push(
        @lux.ConversionDiagnostic::unsupported(
          field_prefix + ".finish_reason",
          Some(
            "finish_reason \"" +
            other.to_string() +
            "\" has no openai-chat equivalent; emitted \"stop\" instead",
          ),
        ),
      )
      "\"stop\""
    }
  }
}

///|
/// IR → Gemini `finishReason` 的**合法**取值。
///
/// 官方枚举（全大写）：`STOP` / `MAX_TOKENS` / `SAFETY` / `RECITATION` /
/// `LANGUAGE` / `OTHER` / `BLOCKLIST` / `PROHIBITED_CONTENT` /
/// `SPII` / `MALFORMED_FUNCTION_CALL` / `IMAGE_SAFETY` / `UNEXPECTED_TOOL_CALL`。
///
/// 映射：
/// - `Stop` → `STOP`；`Length` → `MAX_TOKENS`；`Safety` → `SAFETY`；
///   `Recitation` → `RECITATION`；`MalformedToolCall` → `MALFORMED_FUNCTION_CALL`
/// - `ToolCalls` → `STOP`：Gemini 的 `finishReason` **没有**工具调用枚举
///   （工具调用由 `functionCall` part 表达，不是结束原因），属**语义对等**
///   而非丢失，故不诊断。
/// - `ContentFilter` → `STOP` + Unsupported 诊断。注：`ContentFilter` 在
///   Gemini 侧真正的载体是 `promptFeedback.blockReason`（见
///   `gemini/response.mbt` 的拦截分支）；`FinishReason` 层面无对等项。
/// - `Error` → `OTHER`（官方语义即「出错/不支持」，Exact，不诊断）。
/// - `Native(s)` → 原样透传（厂商自定义值，保持不丢）。
pub fn gemini_finish_reason_string(
  fr : @lux.LucentFinishReason,
  field_prefix : String,
  diagnostics : Array[@lux.ConversionDiagnostic],
) -> String {
  match fr {
    Stop => "STOP"
    Length => "MAX_TOKENS"
    Safety => "SAFETY"
    Recitation => "RECITATION"
    MalformedToolCall => "MALFORMED_FUNCTION_CALL"
    // 语义对等：Gemini 无工具调用结束原因，由 functionCall part 表达
    ToolCalls => "STOP"
    // Error 有官方对等项 OTHER（"error / unsupported"）—— Exact，不诊断
    Error => "OTHER"
    // 厂商自定义值原样透传（如 gemini 自己解出的 LANGUAGE / BLOCKLIST / SPII，
    // 往返不丢）。注意：此处必须是透传而非收敛 —— 流式旧实现的兜底
    // `_ => "STOP"` 会把这些值静默吞成 STOP（数据丢失），与同协议的非流式
    // 路径不一致。
    Native(s) => @internal.json_escape(s)
    // ContentFilter 在 Gemini 侧真正的载体是 promptFeedback.blockReason
    // （见 gemini/response.mbt 的拦截分支）；FinishReason 层面无对等项 →
    // 收敛为 STOP 并诊断。收敛必须显式，不能静默。
    other => {
      diagnostics.push(
        @lux.ConversionDiagnostic::unsupported(
          field_prefix + ".finishReason",
          Some(
            "finish_reason \"" +
            other.to_string() +
            "\" has no gemini FinishReason equivalent; emitted \"STOP\" instead",
          ),
        ),
      )
      "STOP"
    }
  }
}
