///|
/// OpenAI Responses API — 请求编码
///
/// LucentRequest → OpenAI Responses API JSON

///|
/// 从 extras Map 中移除指定键（返回新 Map；移除后为空返回 None）
fn extras_without(
  extras : Map[String, Json]?,
  key : String,
) -> Map[String, Json]? {
  match extras {
    Some(m) => {
      let nm : Map[String, Json] = Map([])
      for k, v in m {
        if k != key {
          nm[k] = v
        }
      }
      if nm.is_empty() {
        None
      } else {
        Some(nm)
      }
    }
    None => None
  }
}

///|
/// 2. lux_request_to_responses — 请求编码
pub fn lux_request_to_responses(
  req : @lux.LucentRequest,
) -> Result[@lux.ConversionResult[String], String] {
  let parts : Array[String] = []
  let diagnostics : Array[@lux.ConversionDiagnostic] = []
  parts.push("\"model\":\"" + @internal.json_escape(req.model) + "\"")
  // instructions
  match req.instructions {
    Some(instrs) => {
      let text = @lux.lucent_content_to_text(instrs)
      if text != "" {
        parts.push("\"instructions\":\"" + @internal.json_escape(text) + "\"")
      }
    }
    None => ()
  }
  // input items
  let items : Array[String] = []
  let mut i = 0
  while i < req.conversation.length() {
    match req.conversation[i] {
      Message(m) => {
        let role_str = m.role.to_string()
        let content_parts : Array[String] = []
        let mut j = 0
        while j < m.content.length() {
          match m.content[j] {
            Text(s, _) =>
              content_parts.push(
                "{\"type\":\"input_text\",\"text\":\"" +
                @internal.json_escape(s) +
                "\"}",
              )
            Image(mm) =>
              match mm.source {
                Url(url) =>
                  content_parts.push(
                    "{\"type\":\"input_image\",\"image_url\":\"" +
                    @internal.json_escape(url) +
                    "\"}",
                  )
                Inline(data) =>
                  content_parts.push(
                    "{\"type\":\"input_image\",\"image_url\":\"data:" +
                    @internal.json_escape(mm.media_type) +
                    ";base64," +
                    @internal.json_escape(data) +
                    "\"}",
                  )
                FileUri(_) =>
                  diagnostics.push(
                    @lux.ConversionDiagnostic::unsupported(
                      "content.image",
                      Some(
                        "file_uri image source not supported by openai-responses",
                      ),
                    ),
                  )
              }
            File(mm) =>
              // 文件：仅支持 Inline（base64 data URI）；url/file_uri 无对应载体，显式诊断
              match mm.source {
                Inline(data) =>
                  content_parts.push(
                    "{\"type\":\"input_file\",\"file_data\":\"data:" +
                    @internal.json_escape(mm.media_type) +
                    ";base64," +
                    @internal.json_escape(data) +
                    "\"}",
                  )
                Url(url) => {
                  @lux.push_unsupported(
                    "content.file", "url file source not supported by openai-responses",
                    diagnostics,
                  )
                  let _ = url
                }
                FileUri(_) =>
                  @lux.push_unsupported(
                    "content.file", "file_uri file source not supported by openai-responses",
                    diagnostics,
                  )
              }
            _ => ()
          }
          j = j + 1
        }
        items.push(
          "{\"type\":\"message\",\"role\":\"" +
          @internal.json_escape(role_str) +
          "\",\"content\":[" +
          content_parts.join(",") +
          "]}",
        )
      }
      ToolCall(tu) =>
        items.push(
          "{\"type\":\"function_call\",\"id\":\"" +
          @internal.json_escape(tu.id) +
          "\",\"call_id\":\"" +
          @internal.json_escape(tu.id) +
          "\",\"name\":\"" +
          @internal.json_escape(tu.name) +
          "\",\"arguments\":\"" +
          @internal.json_escape(tu.arguments_json) +
          "\"}",
        )
      ToolResult(tr) =>
        items.push(
          "{\"type\":\"function_call_output\",\"call_id\":\"" +
          @internal.json_escape(tr.tool_use_id) +
          "\",\"output\":\"" +
          @internal.json_escape(@lux.lucent_content_to_text(tr.content)) +
          "\"}",
        )
      Reasoning(th) => {
        let summary_parts : Array[String] = []
        match th.summary {
          Some(arr) => {
            let mut k = 0
            while k < arr.length() {
              match arr[k] {
                Text(t, _) =>
                  summary_parts.push(
                    "{\"type\":\"summary_text\",\"text\":\"" +
                    @internal.json_escape(t) +
                    "\"}",
                  )
                _ => ()
              }
              k = k + 1
            }
          }
          None => ()
        }
        let mut r_item = "{\"type\":\"reasoning\""
        if summary_parts.length() > 0 {
          r_item = r_item + ",\"summary\":[" + summary_parts.join(",") + "]"
        }
        match th.signature {
          Some(s) =>
            r_item = r_item +
              ",\"signature\":\"" +
              @internal.json_escape(s) +
              "\""
          None => ()
        }
        items.push(r_item + "}")
      }
      AgentAction(_) => ()
    }
    i = i + 1
  }
  parts.push("\"input\":[" + items.join(",") + "]")
  // tools
  match req.tools {
    Some(tools) => {
      let tools_json : Array[String] = []
      let mut j = 0
      while j < tools.length() {
        let t = tools[j]
        let desc_part = match t.description {
          Some(d) => ",\"description\":\"" + @internal.json_escape(d) + "\""
          None => ""
        }
        match t.kind {
          Function =>
            tools_json.push(
              "{\"type\":\"function\",\"name\":\"" +
              @internal.json_escape(t.name) +
              "\"" +
              desc_part +
              ",\"parameters\":" +
              t.parameters_json +
              "}",
            )
          FileSearch =>
            tools_json.push(
              "{\"type\":\"file_search\",\"name\":\"" +
              @internal.json_escape(t.name) +
              "\"" +
              desc_part +
              "}",
            )
          WebSearch =>
            tools_json.push(
              "{\"type\":\"web_search\",\"name\":\"" +
              @internal.json_escape(t.name) +
              "\"" +
              desc_part +
              "}",
            )
          CodeInterpreter =>
            tools_json.push(
              "{\"type\":\"code_interpreter\",\"name\":\"" +
              @internal.json_escape(t.name) +
              "\"" +
              desc_part +
              "}",
            )
          ComputerUse =>
            tools_json.push(
              "{\"type\":\"computer_use\",\"name\":\"" +
              @internal.json_escape(t.name) +
              "\"" +
              desc_part +
              "}",
            )
          MCP => {
            // mcp_server 引用无法从 IR 重建 → Degraded 诊断（不伪装 Exact）
            diagnostics.push(
              @lux.ConversionDiagnostic::degraded(
                "tools.mcp",
                Some("mcp_server reference not preserved"),
              ),
            )
            tools_json.push(
              "{\"type\":\"mcp\",\"name\":\"" +
              @internal.json_escape(t.name) +
              "\"" +
              desc_part +
              "}",
            )
          }
          Native(tag) =>
            tools_json.push(
              "{\"type\":\"" +
              @internal.json_escape(tag) +
              "\",\"name\":\"" +
              @internal.json_escape(t.name) +
              "\"" +
              desc_part +
              "}",
            )
          CodeExecution | Shell | ApplyPatch =>
            // Responses 无对应原生工具类型：不静默降级为 function，显式 Unsupported
            @lux.push_unsupported(
              "tools.kind", "tool kind not supported by openai-responses", diagnostics,
            )
        }
        j = j + 1
      }
      parts.push("\"tools\":[" + tools_json.join(",") + "]")
    }
    None => ()
  }
  // options
  let opts = req.options
  match opts.max_output_tokens {
    Some(n) => parts.push("\"max_output_tokens\":" + n.to_string())
    None => ()
  }
  match opts.temperature {
    Some(t) => parts.push("\"temperature\":" + t.to_string())
    None => ()
  }
  match opts.top_p {
    Some(p) => parts.push("\"top_p\":" + p.to_string())
    None => ()
  }
  if opts.stream {
    parts.push("\"stream\":true")
  }
  // reasoning config
  match req.reasoning {
    Some(rc) => {
      let mut rf = ""
      if rc.enabled {
        match rc.effort {
          Some(Low) => rf = "\"effort\":\"low\""
          Some(Medium) => rf = "\"effort\":\"medium\""
          Some(High) => rf = "\"effort\":\"high\""
          Some(XHigh) => rf = "\"effort\":\"xhigh\""
          None => ()
        }
        match rc.summary {
          Some(Auto) => rf = append_field(rf, "\"summary\":\"auto\"")
          Some(Concise) => rf = append_field(rf, "\"summary\":\"concise\"")
          Some(Detailed) => rf = append_field(rf, "\"summary\":\"detailed\"")
          None => ()
        }
      }
      if rf != "" {
        parts.push("\"reasoning\":{" + rf + "}")
      }
    }
    None => ()
  }
  // structured output
  match opts.structured_output {
    Some(JsonObject) =>
      parts.push("\"text\":{\"format\":{\"type\":\"json_object\"}}")
    Some(Text) => parts.push("\"text\":{\"format\":{\"type\":\"text\"}}")
    Some(JsonSchema(schema)) =>
      parts.push(
        "\"text\":{\"format\":{\"type\":\"json_schema\",\"schema\":" +
        schema +
        "}}",
      )
    None => ()
  }
  match opts.store {
    Some(b) => parts.push("\"store\":" + b.to_string())
    None => ()
  }
  // disable_parallel_tool_use（Anthropic 系）→ parallel_tool_calls（语义反向，标准 §2）
  // extras 中透传的 disable_parallel_tool_use 由本分支消费，不落入输出 JSON。
  // previous_response_id 保留在 extras 中原样透传（responses → responses 往返）。
  let mut merged_extras = opts.extras
  match opts.extras {
    Some(m) =>
      match m.get("disable_parallel_tool_use") {
        Some(True) => {
          parts.push("\"parallel_tool_calls\":false")
          merged_extras = extras_without(
            opts.extras,
            "disable_parallel_tool_use",
          )
        }
        Some(False) => {
          parts.push("\"parallel_tool_calls\":true")
          merged_extras = extras_without(
            opts.extras,
            "disable_parallel_tool_use",
          )
        }
        _ => ()
      }
    None => ()
  }
  @internal.merge_extras_json(parts, merged_extras)
  let result = @lux.ConversionResult::new("{" + parts.join(",") + "}")
  Ok(result.with_diagnostics(diagnostics))
}
