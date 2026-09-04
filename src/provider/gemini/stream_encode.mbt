///|
/// Google Gemini — 流编码（LucentStreamEvent → SSE）
///
/// Gemini 流式是完整帧格式，块周期事件需要合并为完整 candidates
/// 简化实现：累加文本内容，每帧发送完整文本
pub fn lux_events_to_gemini_sse(
  events : Array[@lux.LucentStreamEvent],
) -> Result[@lux.ConversionResult[String], String] {
  // Gemini 流式是完整帧格式，块周期事件需要合并为完整 candidates
  // 简化实现：累加文本内容，每帧发送完整文本
  let lines : Array[String] = []
  let diagnostics : Array[@lux.ConversionDiagnostic] = []
  let mut acc_text = ""
  let mut last_text = ""
  let mut acc_thinking = ""
  let mut acc_signature = ""
  let mut blocks_with_args : Array[String] = []
  let mut i = 0
  while i < events.length() {
    match events[i] {
      BlockDelta(_, TextDelta(s)) => {
        acc_text = acc_text + s
        if acc_text != last_text {
          lines.push(
            "data: {\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"text\":\"" +
            @internal.json_escape(acc_text) +
            "\"}]}}]}",
          )
          last_text = acc_text
        }
      }
      BlockDelta(_, ThinkingDelta(s)) => {
        // Gemini 有原生 thought 载体（thought:true part）：以 thought part 帧输出，
        // 不静默丢弃（标准 §11.5）。thought 帧为全量语义，与文本累加帧独立。
        acc_thinking = acc_thinking + s
        lines.push(
          "data: {\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"text\":\"" +
          @internal.json_escape(acc_thinking) +
          "\",\"thought\":true}]}}]}",
        )
      }
      BlockDelta(_, SignatureDelta(s)) => {
        // thinking signature → thoughtSignature（跨轮延续凭证）
        acc_signature = acc_signature + s
        lines.push(
          "data: {\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"text\":\"" +
          @internal.json_escape(acc_thinking) +
          "\",\"thought\":true,\"thoughtSignature\":\"" +
          @internal.json_escape(acc_signature) +
          "\"}]}}]}",
        )
      }
      BlockDelta(_, ToolArgumentsDelta(s)) => blocks_with_args.push(s)
      BlockStart(_, ToolCall(_, name)) => {
        let args = if blocks_with_args.length() > 0 {
          blocks_with_args.join("")
        } else {
          "{}"
        }
        lines.push(
          "data: {\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"functionCall\":{\"name\":\"" +
          @internal.json_escape(name) +
          "\",\"args\":" +
          args +
          "}}]}}]}",
        )
        blocks_with_args = []
      }
      Finish(fr) => {
        let finish_str = match fr {
          Stop => "STOP"
          Length => "MAX_TOKENS"
          ToolCalls => "STOP"
          Safety => "SAFETY"
          Recitation => "RECITATION"
          MalformedToolCall => "MALFORMED_FUNCTION_CALL"
          Error => "OTHER"
          _ => "STOP"
        }
        lines.push(
          "data: {\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"text\":\"" +
          @internal.json_escape(acc_text) +
          "\"}]},\"finishReason\":\"" +
          finish_str +
          "\"}]}",
        )
      }
      Usage(u) => {
        let mut usage_json = "\"candidates\":[],\"usageMetadata\":{\"promptTokenCount\":" +
          u.prompt_tokens.to_string() +
          ",\"candidatesTokenCount\":" +
          u.completion_tokens.to_string() +
          ",\"totalTokenCount\":" +
          u.total_tokens.to_string()
        match u.reasoning_tokens {
          Some(n) =>
            usage_json = usage_json + ",\"thoughtsTokenCount\":" + n.to_string()
          None => ()
        }
        match u.cached_tokens {
          Some(n) =>
            usage_json = usage_json +
              ",\"cachedContentTokenCount\":" +
              n.to_string()
          None => ()
        }
        lines.push("data: {" + usage_json + "}}")
      }
      _ => ()
    }
    i = i + 1
  }
  Ok(
    @lux.ConversionResult::new(lines.join("\n") + "\n").with_diagnostics(
      diagnostics,
    ),
  )
}
