///|
/// Google Gemini — 流编码（LucentStreamEvent → SSE）
///
/// 官方流式语义：
///   - 每个 chunk 的 `parts[].text` 是**增量**（"the new text, not the running
///     total. Concatenate; do not replace"）→ 文本/思考增量必须逐帧透传，
///     不能每帧重发累计文本
///   - `functionCall` 是完整块：参数增量必须**累积后**在块结束时一次性输出
///     （旧实现把 functionCall 发在 BlockStart 上，导致 `"args":{}` 参数丢失）
///   - 无 `[DONE]` 终止符

///|
/// 把累积的工具参数片段规范化为合法 JSON object 字面量。
///
/// 返回 `{}` 并记 Degraded 的情况：片段为空或不是合法 JSON object。
fn normalize_tool_args(
  raw : String,
  diagnostics : Array[@lux.ConversionDiagnostic],
) -> String {
  if raw == "" {
    return "{}"
  }
  match @internal.parse_protocol_json(raw) {
    Ok(Object(_)) => raw
    Ok(_) => {
      diagnostics.push(
        @lux.ConversionDiagnostic::degraded(
          "stream.tool_arguments",
          Some("tool arguments delta is not a JSON object; emitted as {}"),
        ),
      )
      "{}"
    }
    Err(_) => {
      diagnostics.push(
        @lux.ConversionDiagnostic::degraded(
          "stream.tool_arguments",
          Some("tool arguments delta is not valid JSON; emitted as {}"),
        ),
      )
      "{}"
    }
  }
}

///|

///|
/// Gemini 流编码的跨帧状态（P1 修复）。
///
/// 工具块参数必须**跨帧累积**：BlockStart 在首帧开块、参数增量分布在后续帧、
/// BlockEnd 时才一次性输出完整 `functionCall`。此前这些状态是编码函数的局部
/// 变量，逐帧调用（StreamConverter 每帧调一次）时每帧重建 → 参数累积被打断
/// → 输出的 `args` 恒为 `{}`（整批调用因整条数组一次传入而恰好保留）。
/// 会话化后两条路径共享同一份状态机。
pub struct GeminiStreamState {
  mut pending_tool_index : Int32?
  mut pending_tool_id : String
  mut pending_tool_name : String
  mut pending_tool_args : String
  mut acc_signature : String
}

///|
pub fn GeminiStreamState::new() -> GeminiStreamState {
  {
    pending_tool_index: None,
    pending_tool_id: "",
    pending_tool_name: "",
    pending_tool_args: "",
    acc_signature: "",
  }
}

///|
pub fn lux_events_to_gemini_sse(
  events : Array[@lux.LucentStreamEvent],
) -> Result[@lux.ConversionResult[String], String] {
  gemini_encode_frames(events, GeminiStreamState::new(), true)
}

///|
/// 编码一帧事件（复用会话内跨帧状态）
///
/// `flush_at_end`：整批路径在数组处理完后冲刷悬挂的工具块（一次性输入的
/// 语义完整）；逐帧路径由 `finish()` 显式冲刷（会话仍可能收到后续帧）。
fn gemini_encode_frames(
  events : Array[@lux.LucentStreamEvent],
  st : GeminiStreamState,
  flush_at_end : Bool,
) -> Result[@lux.ConversionResult[String], String] {
  let lines : Array[String] = []
  let diagnostics : Array[@lux.ConversionDiagnostic] = []
  // 工具块：BlockStart(ToolCall) 打开，参数增量累积，BlockEnd 时一次性输出
  let mut pending_tool_index = st.pending_tool_index
  let mut pending_tool_id = st.pending_tool_id
  let mut pending_tool_name = st.pending_tool_name
  let mut pending_tool_args = st.pending_tool_args
  // thinking signature 是完整不透明令牌：累积到当前值后再发
  let mut acc_signature = st.acc_signature
  // ConversationStart 是否已产出首帧（元数据帧只发一次）
  let mut conv_started = false
  let mut i = 0
  while i < events.length() {
    match events[i] {
      BlockDelta(_, TextDelta(s)) =>
        // 增量透传：不发累计文本
        lines.push(
          "data: {\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"text\":\"" +
          @internal.json_escape(s) +
          "\"}]}}]}",
        )
      ConversationStart(meta) =>
        // 元数据扩展载体：Gemini 顶层唯一的非建模字段是 modelStatus
        // （见 @internal.protocol_native_response_keys）。此前 gemini 流编码
        // 完全不处理 ConversationStart，元数据无处可去。
        // 写到**首帧**顶层（与解码侧 build_meta_extra 的排除口径一致）。
        //
        // IR 不变量保证 ConversationStart 是流的**第一个**事件（见
        // LucentStreamEvent 文档），故无需处理「已有内容帧」的情形；保留
        // conv_started 只作为断言性防护（若被违反则跳过而非发第二帧）。
        if !conv_started {
          conv_started = true
          let extra_json = @meta.payload_fragments(
            meta.extra,
            "gemini",
            [
              "responseId", "modelVersion", "candidates", "usageMetadata", "promptFeedback",
            ],
            diagnostics,
          )
          let id_part = match meta.id {
            Some(v) => "\"responseId\":\"" + @internal.json_escape(v) + "\","
            None => ""
          }
          let model_part = match meta.model {
            Some(v) => "\"modelVersion\":\"" + @internal.json_escape(v) + "\","
            None => ""
          }
          lines.push(
            "data: {" + id_part + model_part + extra_json + "\"candidates\":[]}",
          )
        }
      BlockDelta(_, ThinkingDelta(s)) =>
        // Gemini 有原生 thought 载体（thought:true part），增量透传
        lines.push(
          "data: {\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"text\":\"" +
          @internal.json_escape(s) +
          "\",\"thought\":true}]}}]}",
        )
      BlockDelta(_, SignatureDelta(s)) => {
        // thinking signature → thoughtSignature（跨轮延续凭证，值为完整令牌）
        acc_signature = acc_signature + s
        lines.push(
          "data: {\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"text\":\"\",\"thought\":true,\"thoughtSignature\":\"" +
          @internal.json_escape(acc_signature) +
          "\"}]}}]}",
        )
      }
      BlockDelta(_, ToolArgumentsDelta(s)) =>
        // 参数片段累积，等到 BlockEnd 再输出完整 functionCall
        if pending_tool_index is Some(_) {
          pending_tool_args = pending_tool_args + s
        } else {
          diagnostics.push(
            @lux.ConversionDiagnostic::degraded(
              "stream.tool_arguments",
              Some(
                "tool arguments delta without a preceding tool_call block start",
              ),
            ),
          )
        }
      BlockStart(idx, ToolCall(id, name)) => {
        // 前一个工具块未显式 BlockEnd 时先补发
        if pending_tool_index is Some(_) {
          lines.push(
            "data: {\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"functionCall\":{\"name\":\"" +
            @internal.json_escape(pending_tool_name) +
            "\",\"args\":" +
            normalize_tool_args(pending_tool_args, diagnostics) +
            "}}]}}]}",
          )
        }
        pending_tool_index = Some(idx)
        pending_tool_id = id
        pending_tool_name = name
        pending_tool_args = ""
      }
      BlockEnd(idx) => {
        // 工具块结束 → 一次性输出完整 functionCall
        let is_tool_end = match pending_tool_index {
          Some(t) => t == idx
          None => false
        }
        if is_tool_end {
          let id_part = if pending_tool_id == "" {
            ""
          } else {
            ",\"id\":\"" + @internal.json_escape(pending_tool_id) + "\""
          }
          lines.push(
            "data: {\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"functionCall\":{\"name\":\"" +
            @internal.json_escape(pending_tool_name) +
            "\"" +
            id_part +
            ",\"args\":" +
            normalize_tool_args(pending_tool_args, diagnostics) +
            "}}]}}]}",
          )
          pending_tool_index = None
          pending_tool_id = ""
          pending_tool_name = ""
          pending_tool_args = ""
        }
      }
      BlockDelta(_, RefusalDelta(s)) =>
        diagnostics.push(
          @lux.ConversionDiagnostic::unsupported(
            "stream.refusal",
            Some(
              "gemini has no refusal content block; refusal delta dropped: " + s,
            ),
          ),
        )
      BlockDelta(_, NativeDelta(tag, _)) =>
        diagnostics.push(
          @lux.ConversionDiagnostic::unsupported(
            "stream.native",
            Some("native stream delta (" + tag + ") not supported by gemini"),
          ),
        )
      BlockDiscard(idx) =>
        // 官方 chunk 是增量语义，不存在「整帧覆盖」，BlockDiscard 在 Gemini 无载体
        diagnostics.push(
          @lux.ConversionDiagnostic::degraded(
            "stream.block_discard",
            Some(
              "block_discard has no gemini streaming equivalent (index " +
              idx.to_string() +
              ")",
            ),
          ),
        )
      Finish(fr) => {
        // 先补发未结束的工具块，保证工具链不丢参数
        if pending_tool_index is Some(_) {
          let id_part = if pending_tool_id == "" {
            ""
          } else {
            ",\"id\":\"" + @internal.json_escape(pending_tool_id) + "\""
          }
          lines.push(
            "data: {\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"functionCall\":{\"name\":\"" +
            @internal.json_escape(pending_tool_name) +
            "\"" +
            id_part +
            ",\"args\":" +
            normalize_tool_args(pending_tool_args, diagnostics) +
            "}}]}}]}",
          )
          pending_tool_index = None
          pending_tool_id = ""
          pending_tool_name = ""
          pending_tool_args = ""
        }
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
          "data: {\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[]},\"finishReason\":\"" +
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
  // 兜底：流结束时仍有未闭合的工具块
  if flush_at_end {
    if pending_tool_index is Some(_) {
      let id_part = if pending_tool_id == "" {
        ""
      } else {
        ",\"id\":\"" + @internal.json_escape(pending_tool_id) + "\""
      }
      lines.push(
        "data: {\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"functionCall\":{\"name\":\"" +
        @internal.json_escape(pending_tool_name) +
        "\"" +
        id_part +
        ",\"args\":" +
        normalize_tool_args(pending_tool_args, diagnostics) +
        "}}]}}]}",
      )
      pending_tool_index = None
      pending_tool_id = ""
      pending_tool_name = ""
      pending_tool_args = ""
    }
  }
  // 标量状态写回会话
  st.pending_tool_index = pending_tool_index
  st.pending_tool_id = pending_tool_id
  st.pending_tool_name = pending_tool_name
  st.pending_tool_args = pending_tool_args
  st.acc_signature = acc_signature
  Ok(
    @lux.ConversionResult::new(lines.join("\n") + "\n").with_diagnostics(
      diagnostics,
    ),
  )
}

///|
/// 创建 gemini 流编码会话（T5 增量转换入口，跨帧状态由会话持有）
///
/// `encode` 逐帧调用复用同一状态（工具参数跨帧累积）；`finish` 冲刷流尾
/// 仍悬挂的工具块（上游未给出 BlockEnd 的截断流）。
pub fn gemini_stream_encoder() -> @lux.LucentStreamEncoder {
  let st = GeminiStreamState::new()
  @lux.LucentStreamEncoder::new(
    fn(events) { gemini_encode_frames(events, st, false) },
    fn() { gemini_encode_frames([], st, true) },
    fn(_ctx) { () },
  )
}
