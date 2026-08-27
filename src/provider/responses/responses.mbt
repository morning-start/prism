///|
/// OpenAI Responses 适配器 — 对齐 Lux IR v1
///
/// 依据：docs/lux-ir-design.md §10（6-Function 契约）
/// 依据：docs/protocols/02-openai-responses.md（协议映射）
///
/// 关键差异（vs Chat Completions）：
///   - input[] 是 Item 数组而非 messages[]
///   - function_call / function_call_output 是独立 Item
///   - 流式使用 SSE event 命名而非 delta 增量
///   - 推理思考有 reasoning Item（summary + signature）

///|

///|
/// 拼接 JSON 对象字段（已有字段加逗号分隔）
fn append_field(base : String, field : String) -> String {
  if base == "" {
    field
  } else {
    base + "," + field
  }
}

///|
/// 从 Json 对象中提取非排除字段，构建 extra Json。
/// 排除的字段名通过 `exclude` 数组指定。
fn build_extra(jv : Json, exclude : Array[String]) -> Json? {
  match jv {
    Object(m) => {
      let extra_fields : Map[String, Json] = Map([])
      m.each(fn(k, v) {
        let mut excluded = false
        let mut j = 0
        while j < exclude.length() {
          if k == exclude[j] {
            excluded = true
          }
          j = j + 1
        }
        if !excluded {
          extra_fields[k] = v
        }
      })
      if extra_fields.is_empty() {
        None
      } else {
        Some(Json::object(extra_fields))
      }
    }
    _ => None
  }
}

///|
/// 解析 input Item → LucentConversationItem
fn parse_input_item(
  item : Json,
  diagnostics : Array[@lux.ConversionDiagnostic],
) -> @lux.LucentConversationItem? {
  match @internal.field_str(item, "type") {
    Some("message") => {
      let role_str = @internal.field_str(item, "role").unwrap_or("user")
      let role = match role_str {
        "user" => @lux.User
        "assistant" => Assistant
        "developer" => Developer
        _ => User
      }
      let content = match @internal.field_arr(item, "content") {
        Some(parts) => {
          let result : Array[@lux.LucentContent] = []
          let mut i = 0
          while i < parts.length() {
            match @internal.field_str(parts[i], "type") {
              Some("input_text") =>
                match @internal.field_str(parts[i], "text") {
                  Some(t) => result.push(@lux.LucentContent::text(t))
                  None => ()
                }
              Some("input_image") =>
                // 图片输入：精确映射为 multimedia（data URI 拆出 media_type + base64）
                match @internal.field_str(parts[i], "image_url") {
                  Some(u) =>
                    if u == "" {
                      ()
                    } else if u[0] == 'd' && u.length() > 5 && u[4] == ':' {
                      // data:image/png;base64,xxx → Inline(纯 base64) + media_type
                      let segs = u.split(";").to_array()
                      if segs.length() >= 2 {
                        let media_type_parts = segs[0].split(":").to_array()
                        let body_parts = segs[1].split(",").to_array()
                        let media_type = if media_type_parts.length() >= 2 {
                          media_type_parts[1].to_owned()
                        } else {
                          "image/png"
                        }
                        let data = if body_parts.length() >= 2 {
                          body_parts[1].to_owned()
                        } else {
                          ""
                        }
                        if data != "" {
                          result.push(
                            @lux.LucentContent::image(
                              media_type,
                              @lux.LucentMediaSource::inline(data),
                            ),
                          )
                        }
                      }
                    } else {
                      result.push(
                        @lux.LucentContent::image(
                          "",
                          @lux.LucentMediaSource::url(u),
                        ),
                      )
                    }
                  None => ()
                }
              Some("input_file") =>
                // 文件输入：file_data（data URI）精确映射为 File；file_id（服务器引用）显式 Degraded
                match @internal.field_str(parts[i], "file_data") {
                  Some(fd) =>
                    if fd == "" {
                      ()
                    } else if fd[0] == 'd' && fd.length() > 5 && fd[4] == ':' {
                      // data:application/pdf;base64,xxx → File(Inline)
                      let segs = fd.split(";").to_array()
                      if segs.length() >= 2 {
                        let media_type_parts = segs[0].split(":").to_array()
                        let body_parts = segs[1].split(",").to_array()
                        let media_type = if media_type_parts.length() >= 2 {
                          media_type_parts[1].to_owned()
                        } else {
                          "application/pdf"
                        }
                        let data = if body_parts.length() >= 2 {
                          body_parts[1].to_owned()
                        } else {
                          ""
                        }
                        if data != "" {
                          result.push(
                            @lux.LucentContent::file(
                              media_type,
                              @lux.LucentMediaSource::inline(data),
                            ),
                          )
                        }
                      }
                    } else {
                      // 非 data URI：file_data 通常必须是 data URI，否则显式诊断
                      diagnostics.push(
                        @lux.ConversionDiagnostic::degraded(
                          "input.file",
                          Some("file_data must be a data URI"),
                        ),
                      )
                    }
                  None =>
                    // 仅 file_id（服务器端文件引用）：跨协议无法映射，显式 Degraded
                    diagnostics.push(
                      @lux.ConversionDiagnostic::degraded(
                        "input.file",
                        Some("file_id not mapped to multimedia"),
                      ),
                    )
                }
              _ => ()
            }
            i = i + 1
          }
          result
        }
        None => []
      }
      let msg = @lux.LucentMessage::new(role, content)
      Some(@lux.LucentConversationItem::message(msg))
    }
    Some("function_call") => {
      let id = @internal.field_str(item, "id").unwrap_or("")
      let name = @internal.field_str(item, "name").unwrap_or("")
      let args = @internal.field_str(item, "arguments").unwrap_or("{}")
      let tu = @lux.LucentToolUse::new(id, name, args, None)
      Some(@lux.LucentConversationItem::tool_call(tu))
    }
    Some("function_call_output") => {
      let call_id = @internal.field_str(item, "call_id").unwrap_or("")
      let output = @internal.field_str(item, "output").unwrap_or("")
      let tr = @lux.LucentToolResult::ok(call_id, [
        @lux.LucentContent::text(output),
      ])
      Some(@lux.LucentConversationItem::tool_result(tr))
    }
    Some("reasoning") => {
      let summary = match @internal.field_arr(item, "summary") {
        Some(arr) => {
          let texts : Array[@lux.LucentContent] = []
          let mut i = 0
          while i < arr.length() {
            match @internal.field_str(arr[i], "text") {
              Some(t) => texts.push(@lux.LucentContent::text(t))
              None => ()
            }
            i = i + 1
          }
          Some(texts)
        }
        None => None
      }
      let signature = @internal.field_str(item, "signature")
      let th = @lux.LucentThinking::new(
        // thinking text from summary array
        match summary {
          Some(ref_summary) => @lux.lucent_content_to_text(ref_summary)
          None => ""
        },
        signature,
        false,
        summary,
      )
      Some(@lux.LucentConversationItem::reasoning(th))
    }
    _ => None
  }
}

///|
/// 解析 input[] → Array[LucentConversationItem]
fn parse_input(
  jv : Json,
  diagnostics : Array[@lux.ConversionDiagnostic],
) -> Array[@lux.LucentConversationItem] {
  let result : Array[@lux.LucentConversationItem] = []
  match @internal.field_arr(jv, "input") {
    Some(items) => {
      let mut i = 0
      while i < items.length() {
        match parse_input_item(items[i], diagnostics) {
          Some(item) => result.push(item)
          None => ()
        }
        i = i + 1
      }
    }
    None => ()
  }
  result
}

///|
/// 解析 tools[] → Array[LucentTool]
fn parse_tools(jv : Json) -> Array[@lux.LucentTool] {
  match @internal.field_arr(jv, "tools") {
    Some(tools) => {
      let result : Array[@lux.LucentTool] = []
      let mut i = 0
      while i < tools.length() {
        let t = tools[i]
        // OpenAI Responses tools[].type → LucentToolKind（非 function 不再静默降级）
        let kind : @lux.LucentToolKind = match @internal.field_str(t, "type") {
          Some("function") => Function
          Some("file_search") => FileSearch
          Some("web_search") => WebSearch
          Some("code_interpreter") => CodeInterpreter
          Some("computer_use") => ComputerUse
          Some("mcp") => MCP
          Some(other) => Native(other)
          _ => Function
        }
        let name = @internal.field_str(t, "name").unwrap_or("")
        let desc = @internal.field_str(t, "description")
        let params = match @internal.obj_get(t, "parameters") {
          Some(p) => p.stringify()
          None => "{}"
        }
        result.push(@lux.LucentTool::new(name, desc, params, None, kind))
        i = i + 1
      }
      result
    }
    None => []
  }
}

///|
/// 解析 reasoning 配置（当前为空实现：探测到字段即产生 Unsupported 诊断）
fn parse_reasoning(
  jv : Json,
  diagnostics : Array[@lux.ConversionDiagnostic],
) -> @lux.LucentReasoningConfig? {
  match @internal.obj_get(jv, "reasoning") {
    Some(_) => {
      diagnostics.push(
        @lux.ConversionDiagnostic::unsupported(
          "reasoning.config",
          Some("reasoning config not parsed by openai-responses"),
        ),
      )
      None
    }
    None => None
  }
}

///|
/// 解析 text.format → LucentStructuredOutput
fn parse_text_format(jv : Json) -> @lux.LucentStructuredOutput? {
  match @internal.obj_get(jv, "text") {
    Some(obj) =>
      match @internal.obj_get(obj, "format") {
        Some(fmt) =>
          match @internal.field_str(fmt, "type") {
            Some("text") => Some(Text)
            Some("json_object") => Some(JsonObject)
            Some("json_schema") =>
              match @internal.obj_get(fmt, "schema") {
                Some(s) => Some(JsonSchema(s.stringify()))
                None => None
              }
            _ => None
          }
        None => None
      }
    None => None
  }
}

///|
/// 1. openai_responses_to_lux_request — 请求解码
pub fn openai_responses_to_lux_request(
  json_str : String,
) -> Result[@lux.ConversionResult[@lux.LucentRequest], String] {
  let jv = match @internal.parse_protocol_json(json_str) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let diagnostics : Array[@lux.ConversionDiagnostic] = []
  let model = @internal.field_str(jv, "model").unwrap_or("")
  let instructions = match @internal.field_str(jv, "instructions") {
    Some(s) => Some([@lux.LucentContent::text(s)])
    None => None
  }
  let conversation = parse_input(jv, diagnostics)
  let tools_list = parse_tools(jv)
  let tools = if tools_list.length() > 0 { Some(tools_list) } else { None }
  let tool_choice = match @internal.field_str(jv, "tool_choice") {
    Some("auto") => Some(@lux.LucentToolChoice::Auto)
    Some("none") => Some(None)
    Some("required") => Some(Required)
    _ => None
  }
  let temperature = @internal.field_num(jv, "temperature")
  let top_p = @internal.field_num(jv, "top_p")
  let max_tokens = @internal.field_int(jv, "max_output_tokens")
  let stream = @internal.field_bool(jv, "stream").unwrap_or(false)
  let reasoning = parse_reasoning(jv, diagnostics)
  let structured = parse_text_format(jv)
  let store = @internal.field_bool(jv, "store")
  let extras = @internal.collect_extra_fields(jv, [
    "model", "instructions", "input", "tools", "tool_choice", "temperature", "top_p",
    "max_output_tokens", "stream", "reasoning", "text", "previous_response_id", "store",
  ])
  let opts = @lux.LucentOptions::new(
    temperature,
    top_p,
    None,
    max_tokens,
    None,
    stream,
    None,
    structured,
    store,
    extras,
  )
  // metadata: previous_response_id → extra
  let extra = match @internal.field_str(jv, "previous_response_id") {
    Some(_id) => None // previous_response_id → metadata, skip extra for now
    None => None
  }
  let result = @lux.ConversionResult::new(
    @lux.LucentRequest::new(
      model,
      instructions,
      conversation,
      tools,
      tool_choice,
      opts,
      None,
      reasoning,
      None,
      extra,
    ),
  )
  Ok(result.with_diagnostics(diagnostics))
}

///|
/// 2. lux_request_to_openai_responses — 请求编码
pub fn lux_request_to_openai_responses(
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
                  diagnostics.push(
                    @lux.ConversionDiagnostic::unsupported(
                      "content.file",
                      Some("url file source not supported by openai-responses"),
                    ),
                  )
                  let _ = url
                }
                FileUri(_) =>
                  diagnostics.push(
                    @lux.ConversionDiagnostic::unsupported(
                      "content.file",
                      Some(
                        "file_uri file source not supported by openai-responses",
                      ),
                    ),
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
            diagnostics.push(
              @lux.ConversionDiagnostic::unsupported(
                "tools.kind",
                Some("tool kind not supported by openai-responses"),
              ),
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
  match opts.extras {
    Some(m) =>
      for k, v in m {
        parts.push("\"" + @internal.json_escape(k) + "\":" + v.stringify())
      }
    None => ()
  }
  let result = @lux.ConversionResult::new("{" + parts.join(",") + "}")
  Ok(result.with_diagnostics(diagnostics))
}

///|
/// 解析 output Item 为 LucentContent[]
fn parse_output_content(output_item : Json) -> Array[@lux.LucentContent] {
  match @internal.field_str(output_item, "type") {
    Some("message") => {
      let content = match @internal.field_arr(output_item, "content") {
        Some(parts) => {
          let result : Array[@lux.LucentContent] = []
          let mut i = 0
          while i < parts.length() {
            match @internal.field_str(parts[i], "type") {
              Some("output_text") =>
                match @internal.field_str(parts[i], "text") {
                  Some(t) => result.push(@lux.LucentContent::text(t))
                  None => ()
                }
              Some("refusal") =>
                match @internal.field_str(parts[i], "text") {
                  Some(t) => result.push(@lux.LucentContent::refusal(t))
                  None => ()
                }
              _ => ()
            }
            i = i + 1
          }
          result
        }
        None => []
      }
      content
    }
    Some("function_call") => {
      let id = @internal.field_str(output_item, "id").unwrap_or("")
      let name = @internal.field_str(output_item, "name").unwrap_or("")
      let args = @internal.field_str(output_item, "arguments").unwrap_or("{}")
      [@lux.LucentContent::tool_use(id, name, args, None)]
    }
    Some("reasoning") => {
      let summary = match @internal.field_arr(output_item, "summary") {
        Some(arr) => {
          let texts : Array[@lux.LucentContent] = []
          let mut i = 0
          while i < arr.length() {
            match @internal.field_str(arr[i], "text") {
              Some(t) => texts.push(@lux.LucentContent::text(t))
              None => ()
            }
            i = i + 1
          }
          Some(texts)
        }
        None => None
      }
      let signature = @internal.field_str(output_item, "signature")
      let text = match summary {
        Some(ref_summary) => @lux.lucent_content_to_text(ref_summary)
        None => ""
      }
      [@lux.LucentContent::thinking(text, signature)]
    }
    _ => []
  }
}

///|
/// 3. openai_responses_to_lux_response — 响应解码
pub fn openai_responses_to_lux_response(
  json_str : String,
) -> Result[@lux.ConversionResult[@lux.LucentResponse], String] {
  let jv = match @internal.parse_protocol_json(json_str) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  openai_responses_json_to_lux_response(jv)
}

///|
/// 3b. 已解析 Json 的响应解码入口
///
/// 供薄封装子协议（如 Azure）复用：调用方已持有 `Json` 时可避免二次解析。
pub fn openai_responses_json_to_lux_response(
  jv : Json,
) -> Result[@lux.ConversionResult[@lux.LucentResponse], String] {
  let id = @internal.field_str(jv, "id").unwrap_or("")
  let model = @internal.field_str(jv, "model").unwrap_or("")
  let created = @internal.field_int(jv, "created_at")
  // output items → choices[0].message.content
  let content : Array[@lux.LucentContent] = []
  match @internal.field_arr(jv, "output") {
    Some(outputs) => {
      let mut i = 0
      while i < outputs.length() {
        let parts = parse_output_content(outputs[i])
        for p in parts {
          content.push(p)
        }
        i = i + 1
      }
    }
    None => ()
  }
  let msg = @lux.LucentMessage::new(Assistant, content)
  let finish = match @internal.field_str(jv, "status") {
    Some("completed") => @lux.Stop
    Some("incomplete") => Length
    Some("failed") => Error
    Some(other) => @lux.LucentFinishReason::from_string(other)
    None => Stop
  }
  let choice = @lux.LucentChoice::new(0, msg, finish, None)
  // usage
  let usage = match @internal.obj_get(jv, "usage") {
    Some(u) => {
      let pt = @internal.field_int(u, "input_tokens").unwrap_or(0)
      let ct = @internal.field_int(u, "output_tokens").unwrap_or(0)
      let tt = @internal.field_int(u, "total_tokens").unwrap_or(pt + ct)
      @lux.LucentUsage::new(pt, ct, tt)
    }
    None => @lux.LucentUsage::new(0, 0, 0)
  }
  Ok(
    @lux.ConversionResult::new(
      @lux.LucentResponse::new(id, model, created, [choice], Some(usage), None),
    ),
  )
}

///|
/// LucentThinking → OpenAI Responses reasoning item JSON（消息级 reasoning 出站复用）
fn thinking_to_reasoning_item(th : @lux.LucentThinking, id : Int) -> String {
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
  let sig_part = match th.signature {
    Some(s) => ",\"signature\":\"" + @internal.json_escape(s) + "\""
    None => ""
  }
  "{\"type\":\"reasoning\",\"id\":\"rs_" +
  id.to_string() +
  "\"" +
  summary +
  sig_part +
  "}"
}

///|
/// 4. lux_response_to_openai_responses — 响应编码
pub fn lux_response_to_openai_responses(
  resp : @lux.LucentResponse,
) -> Result[@lux.ConversionResult[String], String] {
  if resp.choices.length() == 0 {
    return Err("response has no choices")
  }
  let diagnostics : Array[@lux.ConversionDiagnostic] = []
  let choice = resp.choices[0]
  // build output items
  let output_items : Array[String] = []
  // 消息级 reasoning 优先（vLLM/DeepSeek 入站 → IR → openai-responses 出站），前置为 reasoning item
  match choice.message.reasoning {
    Some(th) => output_items.push(thinking_to_reasoning_item(th, 0))
    None => ()
  }
  let mut i = 0
  while i < choice.message.content.length() {
    // 双载体并存：消息级 reasoning 已输出，content 中 Thinking block 跳过 → Degraded
    match choice.message.content[i] {
      Thinking(_) =>
        match choice.message.reasoning {
          Some(_) => {
            diagnostics.push(
              @lux.ConversionDiagnostic::degraded(
                "reasoning.dual_carrier",
                Some(
                  "both message.reasoning and content Thinking present; using message.reasoning",
                ),
              ),
            )
            i = i + 1
            continue
          }
          None => ()
        }
      _ => ()
    }
    match choice.message.content[i] {
      Text(s, _) =>
        output_items.push(
          "{\"type\":\"message\",\"id\":\"msg_" +
          i.to_string() +
          "\",\"role\":\"assistant\",\"status\":\"completed\",\"content\":[" +
          "{\"type\":\"output_text\",\"text\":\"" +
          @internal.json_escape(s) +
          "\",\"annotations\":[]}]}",
        )
      ToolUse(tu) =>
        output_items.push(
          "{\"type\":\"function_call\",\"id\":\"" +
          @internal.json_escape(tu.id) +
          "\",\"call_id\":\"call_" +
          @internal.json_escape(tu.id) +
          "\",\"name\":\"" +
          @internal.json_escape(tu.name) +
          "\",\"arguments\":\"" +
          @internal.json_escape(tu.arguments_json) +
          "\",\"status\":\"completed\"}",
        )
      Thinking(th) => output_items.push(thinking_to_reasoning_item(th, i))
      Refusal(s) =>
        output_items.push(
          "{\"type\":\"message\",\"id\":\"ref_" +
          i.to_string() +
          "\",\"role\":\"assistant\",\"status\":\"completed\",\"content\":[" +
          "{\"type\":\"refusal\",\"refusal\":\"" +
          @internal.json_escape(s) +
          "\"}]}",
        )
      _ => ()
    }
    i = i + 1
  }
  let status_str = match choice.finish_reason {
    Stop => "\"completed\""
    Length => "\"incomplete\""
    Error => "\"failed\""
    _ => "\"completed\""
  }
  let usage_json = match resp.usage {
    Some(u) =>
      ",\"usage\":{\"input_tokens\":" +
      u.prompt_tokens.to_string() +
      ",\"output_tokens\":" +
      u.completion_tokens.to_string() +
      ",\"total_tokens\":" +
      u.total_tokens.to_string() +
      "}"
    None => ""
  }
  let created_part = match resp.created_at {
    Some(n) => ",\"created_at\":" + n.to_string()
    None => ""
  }
  let body = "{\"id\":\"" +
    @internal.json_escape(resp.id) +
    "\",\"object\":\"response\"" +
    created_part +
    ",\"status\":" +
    status_str +
    ",\"model\":\"" +
    @internal.json_escape(resp.model) +
    "\",\"output\":[" +
    output_items.join(",") +
    "]" +
    usage_json +
    "}"
  let result = @lux.ConversionResult::new(body)
  Ok(result.with_diagnostics(diagnostics))
}

///|
/// 5. openai_responses_sse_to_events — 流解码
///
/// 使用逐行状态机解析 SSE 流，正确处理：
/// - 多行 data: 字段（SSE 规范：用换行符合并）
/// - 心跳注释行（: keep-alive 等）
/// - data: 值内含换行符的 JSON（pretty-printed）
/// - CRLF 行尾
pub fn openai_responses_sse_to_events(
  sse_str : String,
) -> Result[@lux.ConversionResult[Array[@lux.LucentStreamEvent]], String] {
  let events : Array[@lux.LucentStreamEvent] = []
  let diagnostics : Array[@lux.ConversionDiagnostic] = []
  // 统一换行符：CRLF → LF
  let normalized = sse_str
    .replace(old="\r\n", new="\n")
    .replace(old="\r", new="\n")
  let all_lines = normalized.split("\n").to_array()
  let mut event_type = ""
  let mut data_lines : Array[String] = []
  let mut i = 0
  while i < all_lines.length() {
    let line = all_lines[i]
    // 空行 = 事件边界：处理已缓存的事件数据
    if line.trim() == "" {
      if data_lines.length() > 0 {
        // SSE 规范：多个 data: 行用换行符连接
        let data_str_raw = data_lines.join("\n")
        data_lines = []
        // 先清理心跳脏字符（含 \: keep-alive. 等无效转义），再修复其余无效转义
        let data_str = @internal.sanitize_json_escapes(
          @internal.clean_sse_heartbeat(data_str_raw.trim().to_owned()),
        )
        if data_str != "" {
          // 检测截断的 JSON（字符串未闭合、括号不匹配）
          if @internal.is_json_truncated(data_str) {
            diagnostics.push(
              @lux.ConversionDiagnostic::new(
                "sse.data",
                Invalid,
                Some(
                  "truncated JSON in SSE data (stream may be incomplete): " +
                  data_str,
                ),
              ),
            )
          } else {
            let jv = @json.parse(data_str) catch {
              _ => {
                diagnostics.push(
                  @lux.ConversionDiagnostic::new(
                    "sse.data",
                    Invalid,
                    Some("invalid JSON in SSE data: " + data_str),
                  ),
                )
                Json::null()
              }
            }
            // event: 行缺失时，从 JSON 的 type 字段回退推断事件类型
            let effective_type = if event_type == "" {
              @internal.field_str(jv, "type").unwrap_or(event_type)
            } else {
              event_type
            }
            match effective_type {
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
                    events.push(
                      BlockDelta(idx, @lux.LucentBlockDelta::text_delta(t)),
                    )
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
                      BlockDelta(
                        idx,
                        @lux.LucentBlockDelta::tool_arguments_delta(a),
                      ),
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
                        events.push(
                          Finish(@lux.LucentFinishReason::from_string(s)),
                        )
                      None => ()
                    }
                    match @internal.obj_get(r, "usage") {
                      Some(u) => {
                        let pt = @internal.field_int(u, "input_tokens").unwrap_or(
                          0,
                        )
                        let ct = @internal.field_int(u, "output_tokens").unwrap_or(
                          0,
                        )
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
                  Some(err_msg) =>
                    events.push(Error(@lux.LucentError::simple(err_msg)))
                  None => ()
                }
              _ => ()
            }
          }
        }
        event_type = ""
      }
      i = i + 1
      continue
    }
    // 跳过注释行（以 : 开头，如心跳 : keep-alive）
    if line.length() > 0 && line[0] == ':' {
      i = i + 1
      continue
    }
    // 解析 event: 行
    if line.length() >= 7 &&
      line[0] == 'e' &&
      line[1] == 'v' &&
      line[2] == 'e' &&
      line[3] == 'n' &&
      line[4] == 't' &&
      line[5] == ':' &&
      line[6] == ' ' {
      event_type = ""
      let mut k = 7
      while k < line.length() {
        let ch = Int::unsafe_to_char(line[k].to_int())
        event_type = event_type + "\{ch}"
        k = k + 1
      }
      i = i + 1
      continue
    }
    // 解析 data: 行（收集内容，多行合并）
    if line.length() >= 6 &&
      line[0] == 'd' &&
      line[1] == 'a' &&
      line[2] == 't' &&
      line[3] == 'a' &&
      line[4] == ':' &&
      line[5] == ' ' {
      let mut line_data = ""
      let mut k = 6
      while k < line.length() {
        let ch = Int::unsafe_to_char(line[k].to_int())
        line_data = line_data + "\{ch}"
        k = k + 1
      }
      data_lines.push(line_data)
    }
    i = i + 1
  }
  // 处理流末尾未以空行结束的最后一个事件
  if data_lines.length() > 0 {
    let data_str_raw = data_lines.join("\n")
    // 先清理心跳脏字符，再修复其余无效转义
    let data_str = @internal.sanitize_json_escapes(
      @internal.clean_sse_heartbeat(data_str_raw.trim().to_owned()),
    )
    if data_str != "" && !@internal.is_json_truncated(data_str) {
      let jv = @json.parse(data_str) catch { _ => Json::null() }
      match event_type {
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
        _ => ()
      }
    }
  }
  let result = @lux.ConversionResult::new(events)
  Ok(result.with_diagnostics(diagnostics))
}

///|
/// 6. lux_events_to_openai_responses_sse — 流编码
pub fn lux_events_to_openai_responses_sse(
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

///|
/// capability — 适配器能力声明
pub fn capability() -> @lux.ProviderCapability {
  @lux.ProviderCapability::new(
    "gpt-*,o*",
    "openai",
    @lux.LucentCapabilities::create(
      Full,
      Absent,
      Full,
      Full,
      Full,
      [Text, Image, Pdf],
      [Text],
    ),
    None,
  )
}
