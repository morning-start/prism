///|
/// 5. responses_sse_to_events — 流解码
///
/// 使用逐行状态机解析 SSE 流，正确处理：
/// - 多行 data: 字段（SSE 规范：用换行符合并）
/// - 心跳注释行（: keep-alive 等）
/// - data: 值内含换行符的 JSON（pretty-printed）
/// - CRLF 行尾
pub fn responses_sse_to_events(
  sse_str : String,
) -> Result[@lux.ConversionResult[Array[@lux.LucentStreamEvent]], String] {
  let events : Array[@lux.LucentStreamEvent] = []
  let diagnostics : Array[@lux.ConversionDiagnostic] = []
  // 统一换行符：CRLF → LF，再用统一 SSE 解析
  let normalized = sse_str
    .replace(old="\r\n", new="\n")
    .replace(old="\r", new="\n")
  let messages = @internal.parse_sse_messages(normalized)
  let mut i = 0
  while i < messages.length() {
    let event_type_raw = messages[i].event_type.unwrap_or("")
    let data_raw = messages[i].data.trim().to_owned()
    if data_raw == "" {
      i = i + 1
      continue
    }
    // 清理心跳、截断检测、转义清理
    let data_str = @internal.sanitize_json_escapes(
      @internal.clean_sse_heartbeat(data_raw),
    )
    if data_str == "" {
      i = i + 1
      continue
    }
    if @internal.is_json_truncated(data_str) {
      diagnostics.push(
        @lux.ConversionDiagnostic::new(
          "sse.data",
          Invalid,
          Some(
            "truncated JSON in SSE data (stream may be incomplete): " + data_str,
          ),
        ),
      )
      i = i + 1
      continue
    }
    let jv = @json.parse(data_str) catch {
      _ => {
        diagnostics.push(
          @lux.ConversionDiagnostic::new(
            "sse.data",
            Invalid,
            Some("invalid JSON in SSE data: " + data_str),
          ),
        )
        i = i + 1
        continue
      }
    }
    // event: 行缺失时，从 JSON 的 type 字段回退推断事件类型
    let event_type = if event_type_raw == "" {
      @internal.field_str(jv, "type").unwrap_or(event_type_raw)
    } else {
      event_type_raw
    }
    match event_type {
      "response.created" =>
        match @internal.obj_get(jv, "response") {
          Some(r) => {
            let rid = @internal.field_str(r, "id")
            let rmodel = @internal.field_str(r, "model")
            let created_at = @internal.field_int(r, "created_at")
            let extra = build_extra(r, ["id", "model", "created_at"])
            events.push(
              ConversationStart(
                @lux.LucentConversationMeta::new_full(
                  rid,
                  rmodel,
                  None,
                  created_at,
                  extra,
                ),
              ),
            )
          }
          None => ()
        }
      "response.output_item.added" => {
        let idx = @internal.field_int(jv, "output_index").unwrap_or(0)
        match @internal.obj_get(jv, "item") {
          Some(item) =>
            match parse_input_item(item, diagnostics) {
              Some(ci) => events.push(ItemStart(idx, ci))
              None => ()
            }
          None => ()
        }
      }
      "response.content_part.added" => {
        let idx = @internal.field_int(jv, "content_index").unwrap_or(0)
        match @internal.obj_get(jv, "part") {
          Some(part) =>
            match @internal.field_str(part, "type") {
              Some("output_text") => events.push(BlockStart(idx, Text))
              Some("refusal") => events.push(BlockStart(idx, Refusal))
              _ => ()
            }
          None => ()
        }
      }
      "response.output_text.delta" => {
        let idx = @internal.field_int(jv, "content_index").unwrap_or(0)
        match @internal.field_str(jv, "delta") {
          Some(t) =>
            events.push(BlockDelta(idx, @lux.LucentBlockDelta::text_delta(t)))
          None => ()
        }
      }
      "response.output_text.done" => {
        let idx = @internal.field_int(jv, "content_index").unwrap_or(0)
        events.push(BlockEnd(idx))
      }
      "response.reasoning_summary_text.delta" => {
        let idx = @internal.field_int(jv, "content_index").unwrap_or(0)
        match @internal.field_str(jv, "delta") {
          Some(t) =>
            events.push(
              BlockDelta(idx, @lux.LucentBlockDelta::thinking_delta(t)),
            )
          None => ()
        }
      }
      "response.reasoning_summary_text.done" => {
        let idx = @internal.field_int(jv, "content_index").unwrap_or(0)
        events.push(BlockEnd(idx))
      }
      "response.function_call_arguments.delta" => {
        let idx = @internal.field_int(jv, "output_index").unwrap_or(0)
        match @internal.field_str(jv, "delta") {
          Some(a) =>
            events.push(
              BlockDelta(idx, @lux.LucentBlockDelta::tool_arguments_delta(a)),
            )
          None => ()
        }
      }
      "response.function_call_arguments.done" => {
        let idx = @internal.field_int(jv, "output_index").unwrap_or(0)
        events.push(BlockEnd(idx))
      }
      "response.completed" => {
        match @internal.obj_get(jv, "response") {
          Some(r) => {
            match @internal.field_str(r, "status") {
              Some(s) =>
                events.push(Finish(@lux.LucentFinishReason::from_string(s)))
              None => ()
            }
            match @internal.obj_get(r, "usage") {
              Some(u) => {
                let pt = @internal.field_int(u, "input_tokens").unwrap_or(0)
                let ct = @internal.field_int(u, "output_tokens").unwrap_or(0)
                let tt = @internal.field_int(u, "total_tokens").unwrap_or(
                  pt + ct,
                )
                events.push(Usage(@lux.LucentUsage::new(pt, ct, tt)))
              }
              None => ()
            }
          }
          None => ()
        }
        events.push(Done)
      }
      "error" =>
        match @internal.field_str(jv, "error") {
          Some(err_msg) => events.push(Error(@lux.LucentError::simple(err_msg)))
          None => ()
        }
      _ => ()
    }
    i = i + 1
  }
  let result = @lux.ConversionResult::new(events)
  Ok(result.with_diagnostics(diagnostics))
}

///|
/// 6. lux_events_to_responses_sse — 流编码
pub fn lux_events_to_responses_sse(
  events : Array[@lux.LucentStreamEvent],
) -> Result[@lux.ConversionResult[String], String] {
  let lines : Array[String] = []
  let mut i = 0
  while i < events.length() {
    // Track output_index for item_start events
    match events[i] {
      ConversationStart(meta) => {
        let mut fields = ""
        match meta.id {
          Some(id) => fields = "\"id\":\"" + @internal.json_escape(id) + "\""
          None => ()
        }
        match meta.model {
          Some(m) =>
            fields = fields +
              (if fields == "" { "" } else { "," }) +
              "\"model\":\"" +
              @internal.json_escape(m) +
              "\""
          None => ()
        }
        match meta.created_at {
          Some(ts) =>
            fields = fields +
              (if fields == "" { "" } else { "," }) +
              "\"created_at\":" +
              ts.to_string()
          None => ()
        }
        // 合并 extra 中的非通用字段（instructions, status 等）
        match meta.extra {
          Some(ex) =>
            match ex {
              Object(m) =>
                m.each(fn(key, val) {
                  fields = fields +
                    (if fields == "" { "" } else { "," }) +
                    "\"" +
                    @internal.json_escape(key) +
                    "\":" +
                    val.stringify()
                })
              _ => ()
            }
          None => ()
        }
        lines.push(
          "event: response.created\ndata: {\"type\":\"response.created\",\"response\":{" +
          fields +
          "}}",
        )
      }
      ItemStart(idx, item) => {
        let item_json = match item {
          Message(m) => {
            let role_str = m.role.to_string()
            let cparts : Array[String] = []
            let mut k = 0
            while k < m.content.length() {
              match m.content[k] {
                Text(t, _) =>
                  cparts.push(
                    "{\"type\":\"input_text\",\"text\":\"" +
                    @internal.json_escape(t) +
                    "\"}",
                  )
                _ => ()
              }
              k = k + 1
            }
            "{\"type\":\"message\",\"role\":\"" +
            @internal.json_escape(role_str) +
            "\",\"content\":[" +
            cparts.join(",") +
            "]}"
          }
          ToolCall(tu) =>
            "{\"type\":\"function_call\",\"id\":\"" +
            @internal.json_escape(tu.id) +
            "\",\"name\":\"" +
            @internal.json_escape(tu.name) +
            "\"}"
          ToolResult(tr) =>
            "{\"type\":\"function_call_output\",\"call_id\":\"" +
            @internal.json_escape(tr.tool_use_id) +
            "\"}"
          Reasoning(th) => {
            let summary = match th.summary {
              Some(arr) => {
                let parts : Array[String] = []
                let mut k = 0
                while k < arr.length() {
                  match arr[k] {
                    Text(t, _) =>
                      parts.push(
                        "{\"type\":\"summary_text\",\"text\":\"" +
                        @internal.json_escape(t) +
                        "\"}",
                      )
                    _ => ()
                  }
                  k = k + 1
                }
                ",\"summary\":[" + parts.join(",") + "]"
              }
              None => ""
            }
            let sig = match th.signature {
              Some(s) => ",\"signature\":\"" + @internal.json_escape(s) + "\""
              None => ""
            }
            "{\"type\":\"reasoning\"" + summary + sig + "}"
          }
          AgentAction(aa) =>
            "{\"type\":\"computer_call\",\"id\":\"" +
            @internal.json_escape(aa.id) +
            "\"}"
        }
        lines.push(
          "event: response.output_item.added\ndata: {\"type\":\"response.output_item.added\",\"output_index\":" +
          idx.to_string() +
          ",\"item\":" +
          item_json +
          "}",
        )
      }
      ItemEnd(_) => ()
      BlockStart(idx, bt) => {
        let part_json = match bt {
          Text => "{\"type\":\"output_text\",\"text\":\"\"}"
          Refusal => "{\"type\":\"refusal\",\"refusal\":\"\"}"
          _ => "{\"type\":\"output_text\",\"text\":\"\"}"
        }
        lines.push(
          "event: response.content_part.added\ndata: {\"type\":\"response.content_part.added\",\"output_index\":" +
          idx.to_string() +
          ",\"content_index\":" +
          idx.to_string() +
          ",\"part\":" +
          part_json +
          "}",
        )
      }
      BlockDelta(idx, delta) =>
        match delta {
          TextDelta(s) =>
            lines.push(
              "event: response.output_text.delta\ndata: {\"type\":\"response.output_text.delta\",\"output_index\":" +
              idx.to_string() +
              ",\"content_index\":" +
              idx.to_string() +
              ",\"delta\":\"" +
              @internal.json_escape(s) +
              "\"}",
            )
          ThinkingDelta(s) =>
            lines.push(
              "event: response.reasoning_summary_text.delta\ndata: {\"type\":\"response.reasoning_summary_text.delta\",\"output_index\":" +
              idx.to_string() +
              ",\"content_index\":" +
              idx.to_string() +
              ",\"delta\":\"" +
              @internal.json_escape(s) +
              "\"}",
            )
          ToolArgumentsDelta(s) =>
            lines.push(
              "event: response.function_call_arguments.delta\ndata: {\"type\":\"response.function_call_arguments.delta\",\"output_index\":" +
              idx.to_string() +
              ",\"delta\":\"" +
              @internal.json_escape(s) +
              "\"}",
            )
          _ => ()
        }
      BlockEnd(idx) =>
        // We don't know the type of the block that ended, emit both done events
        // In practice only one will match
        lines.push(
          "event: response.output_text.done\ndata: {\"type\":\"response.output_text.done\",\"output_index\":" +
          idx.to_string() +
          ",\"content_index\":" +
          idx.to_string() +
          "}",
        )
      BlockDiscard(_) | Annotations(_, _) => ()
      Finish(fr) => {
        let status_str = match fr {
          Stop => "\"completed\""
          Length => "\"incomplete\""
          Error => "\"failed\""
          _ => "\"completed\""
        }
        lines.push(
          "event: response.completed\ndata: {\"type\":\"response.completed\",\"response\":{\"status\":" +
          status_str +
          "}}",
        )
      }
      Usage(u) =>
        lines.push(
          "event: response.completed\ndata: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\",\"usage\":{\"input_tokens\":" +
          u.prompt_tokens.to_string() +
          ",\"output_tokens\":" +
          u.completion_tokens.to_string() +
          ",\"total_tokens\":" +
          u.total_tokens.to_string() +
          "}}}",
        )
      Error(e) =>
        lines.push(
          "event: error\ndata: {\"type\":\"error\",\"error\":\"" +
          @internal.json_escape(e.message) +
          "\"}",
        )
      Done => () // Responses 流以 response.completed 结束，无独立 done 事件
    }
    i = i + 1
  }
  Ok(@lux.ConversionResult::new(lines.join("\n\n") + "\n\n"))
}
