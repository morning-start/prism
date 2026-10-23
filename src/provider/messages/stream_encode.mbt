///|
/// CR-001：message_delta.usage 渲染。prompt caching 的缓存计费项是 Anthropic
/// 用量核算的核心，有值时必须透传（无值时保持既有字节形态）。
fn messages_usage_json(u : @lux.LucentUsage) -> String {
  let mut s = "{\"output_tokens\":" + u.completion_tokens.to_string()
  match u.cached_tokens {
    Some(n) => s = s + ",\"cache_read_input_tokens\":" + n.to_string()
    None => ()
  }
  match u.cache_creation_tokens {
    Some(n) => s = s + ",\"cache_creation_input_tokens\":" + n.to_string()
    None => ()
  }
  s + "}"
}

///|
/// CR-002 A4：读取会话元信息 `extra` 中透传的输入侧缓存用量。
/// 键名与写入端 `stream_decode.mbt` 一致（extension 载体，缺失即 None）。
fn messages_meta_cache(meta : @lux.LucentConversationMeta) -> (Int32?, Int32?) {
  match meta.extra {
    Some(jv) =>
      (
        @internal.field_int(jv, "usage_cached"),
        @internal.field_int(jv, "usage_cache_creation"),
      )
    None => (None, None)
  }
}

///|
/// CR-002 A3：把事件流按 Finish 分段配对 Usage。
///
/// 每个 Finish 与它所在窗口（上一个 Finish 与下一个 Finish 之间，开区间）内的
/// Usage 配对：优先取 Finish **之后**的最后一个 Usage（Anthropic 正常形态：
/// message_delta 同帧给 stop_reason + usage），否则回退到 Finish **之前**窗口内
/// 最后一个 Usage（IR 事件序为 [Usage, Finish] 时）。被配对的 Usage 由该 Finish
/// 合并发射，其余 Usage 独立发射 —— 避免"Finish 输出 output_tokens: 0 把真实用量
/// 覆盖成 0"。
///
/// 返回：(每个 Usage 是否已被消费, 每个 Finish 配对的 Usage)
fn messages_pair_usages(
  events : Array[@lux.LucentStreamEvent],
) -> (Array[Bool], Array[@lux.LucentUsage?]) {
  let n = events.length()
  let consumed : Array[Bool] = []
  let paired : Array[@lux.LucentUsage?] = []
  let mut k = 0
  while k < n {
    consumed.push(false)
    paired.push(None)
    k = k + 1
  }
  let mut i = 0
  while i < n {
    match events[i] {
      Finish(_) => {
        // 窗口下界：上一个 Finish 之后
        let mut lower = 0
        let mut prev = i - 1
        let mut prev_done = false
        while prev >= 0 && !prev_done {
          match events[prev] {
            Finish(_) => {
              lower = prev + 1
              prev_done = true
            }
            _ => prev = prev - 1
          }
        }
        // 窗口上界：下一个 Finish 之前
        let mut upper = n
        let mut nxt = i + 1
        let mut next_done = false
        while nxt < n && !next_done {
          match events[nxt] {
            Finish(_) => {
              upper = nxt
              next_done = true
            }
            _ => nxt = nxt + 1
          }
        }
        // 1) Finish 之后窗口内最后一个 Usage
        let mut after_last = -1
        let mut j = i + 1
        while j < upper {
          match events[j] {
            Usage(_) => after_last = j
            _ => ()
          }
          j = j + 1
        }
        // 2) 否则取 Finish 之前窗口内最后一个 Usage
        let mut before_last = -1
        if after_last < 0 {
          let mut j2 = lower
          while j2 < i {
            match events[j2] {
              Usage(_) => before_last = j2
              _ => ()
            }
            j2 = j2 + 1
          }
        }
        let chosen = if after_last >= 0 { after_last } else { before_last }
        if chosen >= 0 {
          consumed[chosen] = true
          match events[chosen] {
            Usage(u) => paired[i] = Some(u)
            _ => ()
          }
        }
      }
      _ => ()
    }
    i = i + 1
  }
  (consumed, paired)
}

///|
/// Anthropic Messages — 流编码（LucentStreamEvent → SSE）
///
/// 把 Lux 事件流编码为 Anthropic SSE 格式（同 stream_decode 的逆过程）
pub fn lux_events_to_messages_sse(
  events : Array[@lux.LucentStreamEvent],
) -> Result[@lux.ConversionResult[String], String] {
  let (usage_consumed, finish_usage) = messages_pair_usages(events)
  let lines : Array[String] = []
  let diagnostics : Array[@lux.ConversionDiagnostic] = []
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
        // CR-002 A4：缓存计费项随 message_start.usage 透传（缺失时不输出，保持字节形态）
        let (meta_cached, meta_cache_creation) = messages_meta_cache(meta)
        let mut usage_fields = "{\"input_tokens\":" + usage_val.to_string()
        match meta_cached {
          Some(n) =>
            usage_fields = usage_fields +
              ",\"cache_read_input_tokens\":" +
              n.to_string()
          None => ()
        }
        match meta_cache_creation {
          Some(n) =>
            usage_fields = usage_fields +
              ",\"cache_creation_input_tokens\":" +
              n.to_string()
          None => ()
        }
        // CR-003 R1：Anthropic 的 message_start.usage 同时给出 output_tokens
        // （首帧语义为 1，与官方响应一致）；此前只输出 input_tokens + 缓存项。
        fields = fields + ",\"usage\":" + usage_fields + ",\"output_tokens\":1}"
        // 元数据扩展载体：Anthropic 顶层唯一的非建模字段是 container
        // （见 @internal.protocol_native_response_keys），其它协议的键被
        // 归属门控剔除并诊断（对称于请求侧 options.extras）。
        fields = fields +
          @meta.payload_fragments(
            meta.extra,
            "messages",
            ["id", "type", "role", "model", "usage", "content", "stop_reason"],
            diagnostics,
          )
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
        // CR-002 A3：与预扫描配对好的 Usage 合并为单条 message_delta
        let usage_json = match finish_usage[i] {
          Some(u) => messages_usage_json(u)
          None => messages_usage_json(@lux.LucentUsage::new(0, 0, 0))
        }
        lines.push(
          "event: message_delta\ndata: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"" +
          @internal.json_escape(fr.to_string()) +
          "\"},\"usage\":" +
          usage_json +
          "}",
        )
      }
      Usage(u) =>
        // CR-002 A3：仅未被 Finish 消费的 Usage 独立发射
        if !usage_consumed[i] {
          lines.push(
            "event: message_delta\ndata: {\"type\":\"message_delta\",\"delta\":{},\"usage\":" +
            messages_usage_json(u) +
            "}",
          )
        }
      Error(e) => {
        // 官方错误帧：event: error + {"type":"error","error":{"type":"...","message":"..."}}
        let error_type = match e.kind {
          RateLimit => "rate_limit_error"
          InvalidRequest => "invalid_request_error"
          Authentication => "authentication_error"
          ServerError => "api_error"
          ContentFilter => "invalid_request_error"
          Native(tag) => tag
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
  Ok(
    @lux.ConversionResult::new(lines.join("\n\n") + "\n\n").with_diagnostics(
      diagnostics,
    ),
  )
}
