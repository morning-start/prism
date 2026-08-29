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
