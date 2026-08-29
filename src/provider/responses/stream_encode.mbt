///|
/// 6. lux_events_to_responses_sse — 流编码
pub fn lux_events_to_responses_sse(
  events : Array[@lux.LucentStreamEvent],
) -> Result[@lux.ConversionResult[String], String] {
  let lines : Array[String] = []
  // Responses 流状态（标准 §10.2）：output_index 与 content_index 是独立空间。
  // - output_index：output item 索引（ItemStart 提供，或自动分配）
  // - content_index：单个 message item 内部 content part 索引，从 0 起独立计数
  // 维护 block index → (output_index, content_index, is_tool) 映射供 delta/end 反查。
  let block_output : Map[Int, Int] = Map([])
  let block_content : Map[Int, Int] = Map([])
  let block_is_tool : Map[Int, Bool] = Map([])
  let mut next_output_index = 0
  let mut cur_message_output : Int = -1
  let mut cur_content_index = 0
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
        // ItemStart 提供 output_index；message item 重置 content 计数
        next_output_index = idx + 1
        cur_message_output = -1
        cur_content_index = 0
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
      BlockStart(idx, bt) =>
        // 记录 block → (output_index, content_index) 映射；文本类块按 message item
        // 内独立 content 计数分配，ToolCall 块不产生 content part（独立 function_call item）。
        match bt {
          ToolCall(_, _) => {
            block_output[idx] = next_output_index
            block_is_tool[idx] = true
            next_output_index = next_output_index + 1
          }
          _ => {
            let out = if cur_message_output >= 0 {
              cur_message_output
            } else {
              cur_message_output = next_output_index
              next_output_index = next_output_index + 1
              cur_message_output
            }
            block_output[idx] = out
            block_content[idx] = cur_content_index
            block_is_tool[idx] = false
            let part_json = match bt {
              Text => "{\"type\":\"output_text\",\"text\":\"\"}"
              Refusal => "{\"type\":\"refusal\",\"refusal\":\"\"}"
              _ => "{\"type\":\"output_text\",\"text\":\"\"}"
            }
            lines.push(
              "event: response.content_part.added\ndata: {\"type\":\"response.content_part.added\",\"output_index\":" +
              out.to_string() +
              ",\"content_index\":" +
              cur_content_index.to_string() +
              ",\"part\":" +
              part_json +
              "}",
            )
            cur_content_index = cur_content_index + 1
          }
        }
      BlockDelta(idx, delta) => {
        // 用 BlockStart 记录的 output_index / content_index（缺失时回退 idx）
        let out = match block_output.get(idx) {
          Some(o) => o
          None => idx
        }
        let ci = match block_content.get(idx) {
          Some(c) => c
          None => idx
        }
        match delta {
          TextDelta(s) =>
            lines.push(
              "event: response.output_text.delta\ndata: {\"type\":\"response.output_text.delta\",\"output_index\":" +
              out.to_string() +
              ",\"content_index\":" +
              ci.to_string() +
              ",\"delta\":\"" +
              @internal.json_escape(s) +
              "\"}",
            )
          ThinkingDelta(s) =>
            lines.push(
              "event: response.reasoning_summary_text.delta\ndata: {\"type\":\"response.reasoning_summary_text.delta\",\"output_index\":" +
              out.to_string() +
              ",\"content_index\":" +
              ci.to_string() +
              ",\"delta\":\"" +
              @internal.json_escape(s) +
              "\"}",
            )
          ToolArgumentsDelta(s) =>
            lines.push(
              "event: response.function_call_arguments.delta\ndata: {\"type\":\"response.function_call_arguments.delta\",\"output_index\":" +
              out.to_string() +
              ",\"delta\":\"" +
              @internal.json_escape(s) +
              "\"}",
            )
          _ => ()
        }
      }
      BlockEnd(idx) => {
        let out = match block_output.get(idx) {
          Some(o) => o
          None => idx
        }
        let ci = match block_content.get(idx) {
          Some(c) => c
          None => idx
        }
        // 按块类型发对应 done 事件（标准 §10.2）：
        // tool 块 → function_call_arguments.done；文本/思考块 → output_text.done
        if block_is_tool.get(idx) == Some(true) {
          lines.push(
            "event: response.function_call_arguments.done\ndata: {\"type\":\"response.function_call_arguments.done\",\"output_index\":" +
            out.to_string() +
            "}",
          )
        } else {
          lines.push(
            "event: response.output_text.done\ndata: {\"type\":\"response.output_text.done\",\"output_index\":" +
            out.to_string() +
            ",\"content_index\":" +
            ci.to_string() +
            "}",
          )
        }
      }
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
