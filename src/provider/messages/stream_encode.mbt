///|
/// Anthropic Messages — 流编码（LucentStreamEvent → SSE）
///
/// 把 Lux 事件流编码为 Anthropic SSE 格式（同 stream_decode 的逆过程）
pub fn lux_events_to_messages_sse(
  events : Array[@lux.LucentStreamEvent],
) -> Result[@lux.ConversionResult[String], String] {
  let lines : Array[String] = []
  let mut i = 0
  while i < events.length() {
    match events[i] {
      ConversationStart(meta) => {
        let mut fields = "\"type\":\"message_start\""
        match meta.id {
          Some(id) =>
            fields = fields + ",\"id\":\"" + @internal.json_escape(id) + "\""
          None => ()
        }
        match meta.model {
          Some(m) =>
            fields = fields + ",\"model\":\"" + @internal.json_escape(m) + "\""
          None => ()
        }
        let usage_val = match meta.usage_input {
          Some(n) => n
          None => 0
        }
        fields = fields +
          ",\"usage\":{\"input_tokens\":" +
          usage_val.to_string() +
          "}"
        lines.push(
          "event: message_start\ndata: {\"type\":\"message_start\",\"message\":{" +
          fields +
          "}}",
        )
      }
      ItemStart(_, _) | ItemEnd(_) | BlockDiscard(_) | Annotations(_, _) => ()
      BlockStart(idx, bt) => {
        let block_json = match bt {
          Text => "{\"type\":\"text\",\"text\":\"\"}"
          Thinking => "{\"type\":\"thinking\",\"thinking\":\"\"}"
          ToolCall(id, name) =>
            "{\"type\":\"tool_use\",\"id\":\"" +
            @internal.json_escape(id) +
            "\",\"name\":\"" +
            @internal.json_escape(name) +
            "\",\"input\":{}}"
          Refusal => "{\"type\":\"text\",\"text\":\"\"}"
          Image | Audio | Video => "{\"type\":\"text\",\"text\":\"\"}"
          Native(tag) => "{\"type\":\"" + @internal.json_escape(tag) + "\"}"
        }
        lines.push(
          "event: content_block_start\ndata: {\"type\":\"content_block_start\",\"index\":" +
          idx.to_string() +
          ",\"content_block\":" +
          block_json +
          "}",
        )
      }
      BlockDelta(idx, delta) => {
        let delta_json = match delta {
          TextDelta(s) =>
            "{\"type\":\"text_delta\",\"text\":\"" +
            @internal.json_escape(s) +
            "\"}"
          ThinkingDelta(s) =>
            "{\"type\":\"thinking_delta\",\"thinking\":\"" +
            @internal.json_escape(s) +
            "\"}"
          SignatureDelta(s) =>
            "{\"type\":\"signature_delta\",\"signature\":\"" +
            @internal.json_escape(s) +
            "\"}"
          ToolArgumentsDelta(s) =>
            "{\"type\":\"input_json_delta\",\"partial_json\":\"" +
            @internal.json_escape(s) +
            "\"}"
          RefusalDelta(s) =>
            "{\"type\":\"text_delta\",\"text\":\"" +
            @internal.json_escape(s) +
            "\"}"
          NativeDelta(tag, _) =>
            "{\"type\":\"" + @internal.json_escape(tag) + "\"}"
        }
        lines.push(
          "event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":" +
          idx.to_string() +
          ",\"delta\":" +
          delta_json +
          "}",
        )
      }
      BlockEnd(idx) =>
        lines.push(
          "event: content_block_stop\ndata: {\"type\":\"content_block_stop\",\"index\":" +
          idx.to_string() +
          "}",
        )
      Finish(fr) => {
        // 向后查找 Usage 事件，合并为单个 message_delta
        let mut output_tokens = 0
        let mut has_usage = false
        let mut j = i + 1
        while j < events.length() {
          match events[j] {
            Usage(u) => {
              output_tokens = u.completion_tokens
              has_usage = true
            }
            _ => ()
          }
          j = j + 1
        }
        if has_usage {
          // 标记 Usage 已被消费（通过将 index 设为 -1 或其他方式跳过）
          // 由于 MoonBit 的 match 需要穷尽，我们在 Usage 分支检查
        }
        lines.push(
          "event: message_delta\ndata: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"" +
          @internal.json_escape(fr.to_string()) +
          "\"},\"usage\":{\"output_tokens\":" +
          output_tokens.to_string() +
          "}}",
        )
      }
      Usage(u) => {
        // 检查前面是否有 Finish 事件（如果有则跳过，因为已合并到 Finish 中）
        let mut has_finish = false
        let mut j = 0
        while j < i {
          match events[j] {
            Finish(_) => has_finish = true
            _ => ()
          }
          j = j + 1
        }
        if !has_finish {
          // 没有 Finish 事件时，单独输出 Usage
          lines.push(
            "event: message_delta\ndata: {\"type\":\"message_delta\",\"delta\":{},\"usage\":{\"output_tokens\":" +
            u.completion_tokens.to_string() +
            "}}",
          )
        }
      }
      Error(e) => {
        // 官方错误帧：event: error + {"type":"error","error":{"type":"...","message":"..."}}
        let error_type = match e.kind {
          @lux.RateLimit => "rate_limit_error"
          @lux.InvalidRequest => "invalid_request_error"
          @lux.Authentication => "authentication_error"
          @lux.ServerError => "api_error"
          @lux.ContentFilter => "invalid_request_error"
          @lux.Native(tag) => tag
        }
        lines.push(
          "event: error\ndata: {\"type\":\"error\",\"error\":{\"type\":\"" +
          @internal.json_escape(error_type) +
          "\",\"message\":\"" +
          @internal.json_escape(e.message) +
          "\"}}",
        )
      }
      Done =>
        lines.push("event: message_stop\ndata: {\"type\":\"message_stop\"}")
    }
    i = i + 1
  }
  Ok(@lux.ConversionResult::new(lines.join("\n\n") + "\n\n"))
}
