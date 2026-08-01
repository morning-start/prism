///|
/// OpenAI Chat Completions 适配器 — 对齐 Lux IR v1
///
/// 依据：docs/lux-ir-design.md §10（6-Function 契约）
/// 依据：docs/protocols/01-openai-completions.md（协议映射）
///
/// 6 函数：
///   1. openai_chat_to_lux_request      请求解码
///   2. lux_request_to_openai_chat      请求编码
///   3. openai_chat_to_lux_response     响应解码
///   4. lux_response_to_openai_chat     响应编码
///   5. openai_chat_sse_to_events       流解码
///   6. lux_events_to_openai_chat_sse   流编码

///|

///|
/// === 请求解码：OpenAI Chat JSON → LucentRequest ===

///|
/// 解析 content：string → [Text]；array → content parts（text/image_url）
fn parse_content_parts(msg_jv : Json) -> Array[@lux.LucentContent] {
  match @internal.obj_get(msg_jv, "content") {
    Some(String(s)) => [@lux.LucentContent::text(s)]
    Some(Array(parts)) => {
      let result : Array[@lux.LucentContent] = []
      let mut i = 0
      while i < parts.length() {
        let part = parts[i]
        match @internal.field_str(part, "type") {
          Some("text") =>
            match @internal.field_str(part, "text") {
              Some(t) => result.push(@lux.LucentContent::text(t))
              _ => ()
            }
          Some("image_url") =>
            // stub：简化处理，仅当 url 以 data: 开头时识别为 inline，否则为 url
            match @internal.obj_get(part, "image_url") {
              Some(url_obj) =>
                match @internal.field_str(url_obj, "url") {
                  Some(u) =>
                    if u == "" {
                      ()
                    } else if u[0] == 'd' && u.length() > 5 && u[5] == ':' {
                      // data:image/... 简化：不解析内部细节，整体作为 inline
                      result.push(
                        @lux.LucentContent::image(
                          "image/png",
                          @lux.LucentMediaSource::inline(u),
                        ),
                      )
                    } else {
                      result.push(
                        @lux.LucentContent::image(
                          "image/png",
                          @lux.LucentMediaSource::url(u),
                        ),
                      )
                    }
                  None => ()
                }
              None => ()
            }
          _ => ()
        }
        i = i + 1
      }
      result
    }
    _ => []
  }
}

///|
/// 解析 assistant 消息的 tool_calls[] → ToolUse content
fn append_tool_calls(
  msg_jv : Json,
  result : Array[@lux.LucentContent],
) -> Array[@lux.LucentContent] {
  match @internal.field_arr(msg_jv, "tool_calls") {
    Some(calls) => {
      let mut i = 0
      while i < calls.length() {
        let tc = calls[i]
        let id = @internal.field_str(tc, "id").unwrap_or("")
        match @internal.obj_get(tc, "function") {
          Some(fn_obj) => {
            let name = @internal.field_str(fn_obj, "name").unwrap_or("")
            let args = @internal.field_str(fn_obj, "arguments").unwrap_or("{}")
            result.push(@lux.LucentContent::tool_use(id, name, args, None))
          }
          _ => ()
        }
        i = i + 1
      }
      result
    }
    _ => result
  }
}

///|
/// 解析单条 message → LucentMessage（role + content blocks）
/// system/developer 角色消息由上层抽出为 instructions，不在本函数处理
fn parse_message(msg_jv : Json) -> @lux.LucentMessage? {
  let role_str = @internal.field_str(msg_jv, "role")
  match role_str {
    Some(s) =>
      match @lux.LucentRole::from_string(s) {
        Some(role) =>
          // tool 角色：tool_call_id + content → ToolResult content
          match @internal.field_str(msg_jv, "tool_call_id") {
            Some(id) => {
              let content = @internal.field_str(msg_jv, "content").unwrap_or("")
              let tr = @lux.LucentContent::tool_result(id, [
                @lux.LucentContent::text(content),
              ])
              Some(@lux.LucentMessage::new(role, [tr]))
            }
            None => {
              // 非 tool 角色：普通 content 解析 + tool_calls 解析
              let mut parts = parse_content_parts(msg_jv)
              parts = append_tool_calls(msg_jv, parts)
              Some(@lux.LucentMessage::new(role, parts))
            }
          }
        _ => None
      }
    _ => None
  }
}

///|
/// 解析 tools[] → LucentTool[]
fn parse_tools(jv : Json) -> Array[@lux.LucentTool] {
  match @internal.field_arr(jv, "tools") {
    Some(tools) => {
      let result : Array[@lux.LucentTool] = []
      let mut i = 0
      while i < tools.length() {
        let tool = tools[i]
        match @internal.obj_get(tool, "function") {
          Some(fn_obj) => {
            let name = @internal.field_str(fn_obj, "name").unwrap_or("")
            let desc = @internal.field_str(fn_obj, "description")
            let params = match @internal.obj_get(fn_obj, "parameters") {
              Some(p) => p.stringify()
              _ => "{}"
            }
            let strict = @internal.field_bool(fn_obj, "strict")
            result.push(
              @lux.LucentTool::new(name, desc, params, strict, @lux.Function),
            )
          }
          _ => ()
        }
        i = i + 1
      }
      result
    }
    _ => []
  }
}

///|
/// 解析 tool_choice → LucentToolChoice
fn parse_tool_choice(jv : Json) -> @lux.LucentToolChoice? {
  match @internal.obj_get(jv, "tool_choice") {
    Some(String("auto")) => Some(@lux.LucentToolChoice::Auto)
    Some(String("none")) => Some(@lux.LucentToolChoice::None)
    Some(String("required")) => Some(@lux.LucentToolChoice::Required)
    Some(Object(_)) =>
      // {"type":"function","function":{"name":"x"}}
      match @internal.obj_get(jv, "tool_choice") {
        Some(tc_obj) =>
          match @internal.field_str(tc_obj, "type") {
            Some("function") =>
              match @internal.obj_get(tc_obj, "function") {
                Some(fn_obj) =>
                  match @internal.field_str(fn_obj, "name") {
                    Some(n) => Some(@lux.LucentToolChoice::SpecificTool(n))
                    None => None
                  }
                None => None
              }
            _ => None
          }
        None => None
      }
    _ => None
  }
}

///|
/// 1. openai_chat_to_lux_request — 请求解码
pub fn openai_chat_to_lux_request(
  json_str : String,
) -> Result[@lux.ConversionResult[@lux.LucentRequest], String] {
  let jv = @json.parse(json_str) catch { _ => return Err("json parse error") }
  let model = @internal.field_str(jv, "model").unwrap_or("")
  // 系统指令：role=system/developer 的消息抽出为 instructions
  let instructions : Array[@lux.LucentContent] = []
  let business_msgs : Array[@lux.LucentMessage] = []
  match @internal.field_arr(jv, "messages") {
    Some(msgs) => {
      let mut i = 0
      while i < msgs.length() {
        let m = msgs[i]
        match @internal.field_str(m, "role") {
          Some("system") | Some("developer") =>
            // 系统指令内容抽出
            for c in parse_content_parts(m) {
              instructions.push(c)
            }
          _ =>
            match parse_message(m) {
              Some(lm) => business_msgs.push(lm)
              None => ()
            }
        }
        i = i + 1
      }
    }
    None => ()
  }
  let instr_opt = if instructions.length() > 0 {
    Some(instructions)
  } else {
    None
  }
  let tools_list = parse_tools(jv)
  let tools = if tools_list.length() > 0 { Some(tools_list) } else { None }
  let tool_choice = parse_tool_choice(jv)
  // options
  let temperature = @internal.field_num(jv, "temperature")
  let top_p = @internal.field_num(jv, "top_p")
  // 优先 max_completion_tokens，回退 max_tokens
  let max_tokens = match @internal.field_int(jv, "max_completion_tokens") {
    Some(n) => Some(n)
    None => @internal.field_int(jv, "max_tokens")
  }
  let stream = @internal.field_bool(jv, "stream").unwrap_or(false)
  let stop = match @internal.obj_get(jv, "stop") {
    Some(String(s)) => Some([s])
    Some(Array(arr)) => {
      let stops : Array[String] = []
      let mut i = 0
      while i < arr.length() {
        match arr[i] {
          String(s) => stops.push(s)
          _ => ()
        }
        i = i + 1
      }
      Some(stops)
    }
    _ => None
  }
  let seed = @internal.field_int(jv, "seed")
  // response_format → structured_output
  let structured = match @internal.obj_get(jv, "response_format") {
    Some(rf) =>
      match @internal.field_str(rf, "type") {
        Some("json_object") => Some(@lux.LucentStructuredOutput::JsonObject)
        Some("text") => Some(@lux.LucentStructuredOutput::Text)
        Some("json_schema") =>
          match @internal.obj_get(rf, "json_schema") {
            Some(js_obj) =>
              match @internal.obj_get(js_obj, "schema") {
                Some(schema) =>
                  Some(
                    @lux.LucentStructuredOutput::JsonSchema(schema.stringify()),
                  )
                None => None
              }
            None => None
          }
        _ => None
      }
    None => None
  }
  Ok(
    @lux.ConversionResult::new(
      @lux.LucentRequest::from_messages(
        model,
        instr_opt,
        business_msgs,
        tools,
        tool_choice,
        @lux.LucentOptions::new(
          temperature,
          top_p,
          None,
          max_tokens,
          stop,
          stream,
          None,
          seed,
          structured,
          None,
          None,
        ),
        None,
        None,
        None,
        None,
      ),
    ),
  )
}

///|
/// === 请求编码：LucentRequest → OpenAI Chat JSON ===

///|
fn role_to_string(role : @lux.LucentRole) -> String {
  role.to_string()
}

///|
/// JSON 字符串转义 — 用 from_codepoint 转换 UInt16 为字符串
fn escape_json(s : String) -> String {
  let mut r = ""
  let mut i = 0
  while i < s.length() {
    let cp = s[i]
    if cp == '"' {
      r = r + "\\\""
    } else if cp == '\\' {
      r = r + "\\\\"
    } else if cp == '\n' {
      r = r + "\\n"
    } else if cp == '\t' {
      r = r + "\\t"
    } else if cp == '\r' {
      r = r + "\\r"
    } else {
      let ch = Int::unsafe_to_char(cp.to_int())
      r = r + "\{ch}"
    }
    i = i + 1
  }
  r
}

///|
/// 工具选择 → JSON 片段
fn tool_choice_to_json(tc : @lux.LucentToolChoice) -> String {
  match tc {
    Auto => "\"auto\""
    None => "\"none\""
    Required => "\"required\""
    SpecificTool(name) =>
      "{\"type\":\"function\",\"function\":{\"name\":\"" +
      escape_json(name) +
      "\"}}"
  }
}

///|
/// 单个 content part → 文本片段（用于 messages[].content 字符串拼接）
/// 返回 Some(fragment) 表示该 part 需入 content；None 表示不入 content
/// 注意：Text 返回原始文本，由调用方统一 escape_json 转义
fn content_part_to_json(
  c : @lux.LucentContent,
  out_tool_calls : Array[String],
  out_refusal : Array[String],
  diagnostics : Array[@lux.ConversionDiagnostic],
) -> String? {
  match c {
    Text(s, _) => Some(s)
    ToolUse(tu) => {
      // 工具调用入 tool_calls 数组，不入 content
      out_tool_calls.push(
        "{\"id\":\"" +
        escape_json(tu.id) +
        "\",\"type\":\"function\",\"function\":{\"name\":\"" +
        escape_json(tu.name) +
        "\",\"arguments\":\"" +
        escape_json(tu.arguments_json) +
        "\"}}",
      )
      None
    }
    ToolResult(_) => None // tool 结果走独立 tool 角色消息
    Thinking(_) => None // OpenAI Chat 无原生 thinking，编码时忽略
    Refusal(s) => {
      out_refusal.push(s)
      None
    }
    Image(_) => {
      // OpenAI Chat 无媒体载体：不静默丢弃，显式 Unsupported 诊断
      diagnostics.push(
        @lux.ConversionDiagnostic::new(
          "content.image",
          @lux.Unsupported,
          Some("image content not supported by openai-chat"),
        ),
      )
      None
    }
    Audio(_) => {
      diagnostics.push(
        @lux.ConversionDiagnostic::new(
          "content.audio",
          @lux.Unsupported,
          Some("audio content not supported by openai-chat"),
        ),
      )
      None
    }
    Video(_) => {
      diagnostics.push(
        @lux.ConversionDiagnostic::new(
          "content.video",
          @lux.Unsupported,
          Some("video content not supported by openai-chat"),
        ),
      )
      None
    }
    Native(tag, _) => {
      diagnostics.push(
        @lux.ConversionDiagnostic::new(
          "content.native",
          @lux.Unsupported,
          Some("native content (" + tag + ") not supported by openai-chat"),
        ),
      )
      None
    }
  }
}

///|
/// LucentMessage → OpenAI message JSON 片段
fn message_to_json(
  msg : @lux.LucentMessage,
  diagnostics : Array[@lux.ConversionDiagnostic],
) -> String {
  let role = role_to_string(msg.role)
  let tool_calls : Array[String] = []
  let refusal_buf : Array[String] = []
  // tool 角色：输出 {role:"tool",tool_call_id:...,content:...}
  match msg.role {
    Tool => {
      // content 中找 ToolResult
      let mut tcid = ""
      let mut content_str = ""
      let mut i = 0
      while i < msg.content.length() {
        match msg.content[i] {
          ToolResult(tr) => {
            tcid = tr.tool_use_id
            content_str = @lux.lucent_content_to_text(tr.content)
          }
          _ => ()
        }
        i = i + 1
      }
      "{\"role\":\"tool\",\"tool_call_id\":\"" +
      escape_json(tcid) +
      "\",\"content\":\"" +
      escape_json(content_str) +
      "\"}"
    }
    _ => {
      // 普通 role：content 拼为字符串；tool_calls 入数组；refusal 入字段
      let content_parts : Array[String] = []
      let mut i = 0
      while i < msg.content.length() {
        match
          content_part_to_json(
            msg.content[i],
            tool_calls,
            refusal_buf,
            diagnostics,
          ) {
          Some(s) => content_parts.push(s)
          None => ()
        }
        i = i + 1
      }
      let content_str = content_parts.join("")
      let mut msg_obj = "{\"role\":\"" +
        escape_json(role) +
        "\",\"content\":\"" +
        escape_json(content_str) +
        "\""
      if tool_calls.length() > 0 {
        msg_obj = msg_obj + ",\"tool_calls\":[" + tool_calls.join(",") + "]"
      }
      if refusal_buf.length() > 0 {
        msg_obj = msg_obj +
          ",\"refusal\":\"" +
          escape_json(refusal_buf[0]) +
          "\""
      }
      msg_obj + "}"
    }
  }
}

///|
/// 2. lux_request_to_openai_chat — 请求编码
pub fn lux_request_to_openai_chat(
  req : @lux.LucentRequest,
) -> Result[@lux.ConversionResult[String], String] {
  let parts : Array[String] = []
  parts.push("\"model\":\"" + escape_json(req.model) + "\"")
  // instructions → system 消息（前置）
  let msgs_json : Array[String] = []
  match req.instructions {
    Some(instrs) => {
      let instr_text = @lux.lucent_content_to_text(instrs)
      msgs_json.push(
        "{\"role\":\"system\",\"content\":\"" + escape_json(instr_text) + "\"}",
      )
    }
    None => ()
  }
  // conversation items → messages
  let items = req.conversation
  let mut i = 0
  let diagnostics : Array[@lux.ConversionDiagnostic] = []
  while i < items.length() {
    match items[i] {
      Message(m) => msgs_json.push(message_to_json(m, diagnostics))
      ToolCall(tu) =>
        // 独立 tool_call → assistant 消息含 tool_calls
        msgs_json.push(
          "{\"role\":\"assistant\",\"content\":null,\"tool_calls\":[" +
          "{\"id\":\"" +
          escape_json(tu.id) +
          "\",\"type\":\"function\",\"function\":{\"name\":\"" +
          escape_json(tu.name) +
          "\",\"arguments\":\"" +
          escape_json(tu.arguments_json) +
          "\"}}]}",
        )
      ToolResult(tr) =>
        msgs_json.push(
          "{\"role\":\"tool\",\"tool_call_id\":\"" +
          escape_json(tr.tool_use_id) +
          "\",\"content\":\"" +
          escape_json(@lux.lucent_content_to_text(tr.content)) +
          "\"}",
        )
      Reasoning(_) =>
        // OpenAI Chat 无原生 reasoning：不静默忽略，显式 Unsupported 诊断
        diagnostics.push(
          @lux.ConversionDiagnostic::new(
            "conversation.reasoning",
            @lux.Unsupported,
            Some("reasoning not supported by openai-chat"),
          ),
        )
      AgentAction(_) =>
        // OpenAI Chat 无 AgentAction 载体：不静默忽略，显式 Unsupported 诊断
        diagnostics.push(
          @lux.ConversionDiagnostic::new(
            "conversation.agent_action",
            @lux.Unsupported,
            Some("agent_action not supported by openai-chat"),
          ),
        )
    }
    i = i + 1
  }
  parts.push("\"messages\":[" + msgs_json.join(",") + "]")
  // tools
  match req.tools {
    Some(tools) => {
      let tools_json : Array[String] = []
      let mut j = 0
      while j < tools.length() {
        let t = tools[j]
        // parameters 应为 JSON object 字符串，嵌入为对象而非字符串
        // 但为简化（且 parameters_json 本身就是 JSON 字符串），直接嵌入
        let desc_part = match t.description {
          Some(d) => ",\"description\":\"" + escape_json(d) + "\""
          None => ""
        }
        let fn_str = "\"function\":{" +
          "\"name\":\"" +
          escape_json(t.name) +
          "\"" +
          desc_part +
          ",\"parameters\":" +
          t.parameters_json + // 直接嵌入 JSON
          "}"
        tools_json.push("{\"type\":\"function\"," + fn_str + "}")
        j = j + 1
      }
      parts.push("\"tools\":[" + tools_json.join(",") + "]")
    }
    None => ()
  }
  // tool_choice
  match req.tool_choice {
    Some(tc) => parts.push("\"tool_choice\":" + tool_choice_to_json(tc))
    None => ()
  }
  // options
  let opts = req.options
  match opts.temperature {
    Some(t) => parts.push("\"temperature\":" + t.to_string())
    None => ()
  }
  match opts.top_p {
    Some(p) => parts.push("\"top_p\":" + p.to_string())
    None => ()
  }
  match opts.max_output_tokens {
    Some(n) => parts.push("\"max_tokens\":" + n.to_string())
    None => ()
  }
  match opts.stop {
    Some(arr) => {
      let stops : Array[String] = []
      let mut k = 0
      while k < arr.length() {
        stops.push("\"" + escape_json(arr[k]) + "\"")
        k = k + 1
      }
      parts.push("\"stop\":[" + stops.join(",") + "]")
    }
    None => ()
  }
  if opts.stream {
    parts.push("\"stream\":true")
  }
  match opts.seed {
    Some(n) => parts.push("\"seed\":" + n.to_string())
    None => ()
  }
  match opts.structured_output {
    Some(JsonObject) =>
      parts.push("\"response_format\":{\"type\":\"json_object\"}")
    Some(Text) => parts.push("\"response_format\":{\"type\":\"text\"}")
    Some(JsonSchema(schema)) =>
      parts.push(
        "\"response_format\":{\"type\":\"json_schema\",\"json_schema\":{\"schema\":" +
        schema +
        "}}",
      )
    None => ()
  }
  let mut result = @lux.ConversionResult::new("{" + parts.join(",") + "}")
  for d in diagnostics {
    result = result.with_diagnostic(d)
  }
  Ok(result)
}

///|
/// === 响应解码：OpenAI Chat JSON → LucentResponse ===

///|
/// 解析 choices[] → LucentChoice[]
fn parse_choices(jv : Json) -> Array[@lux.LucentChoice] {
  match @internal.field_arr(jv, "choices") {
    Some(choices) => {
      let result : Array[@lux.LucentChoice] = []
      let mut i = 0
      while i < choices.length() {
        let c = choices[i]
        let idx = @internal.field_int(c, "index").unwrap_or(0)
        match @internal.obj_get(c, "message") {
          Some(msg_jv) => {
            let role = match @internal.field_str(msg_jv, "role") {
              Some("assistant") => @lux.Assistant
              _ => @lux.Assistant
            }
            let content : Array[@lux.LucentContent] = []
            // content 字符串
            match @internal.field_str(msg_jv, "content") {
              Some(s) => content.push(@lux.LucentContent::text(s))
              None => ()
            }
            // tool_calls[]
            match @internal.field_arr(msg_jv, "tool_calls") {
              Some(calls) => {
                let mut k = 0
                while k < calls.length() {
                  let tc = calls[k]
                  let id = @internal.field_str(tc, "id").unwrap_or("")
                  match @internal.obj_get(tc, "function") {
                    Some(fn_obj) => {
                      let name = @internal.field_str(fn_obj, "name").unwrap_or(
                        "",
                      )
                      let args = @internal.field_str(fn_obj, "arguments").unwrap_or(
                        "{}",
                      )
                      content.push(
                        @lux.LucentContent::tool_use(id, name, args, None),
                      )
                    }
                    None => ()
                  }
                  k = k + 1
                }
              }
              None => ()
            }
            // refusal
            match @internal.field_str(msg_jv, "refusal") {
              Some(r) => content.push(@lux.LucentContent::refusal(r))
              None => ()
            }
            let finish = match @internal.field_str(c, "finish_reason") {
              Some(fr) => @lux.LucentFinishReason::from_string(fr)
              None => @lux.Stop
            }
            result.push(
              @lux.LucentChoice::new(
                idx,
                @lux.LucentMessage::new(role, content),
                finish,
                None,
              ),
            )
          }
          None => ()
        }
        i = i + 1
      }
      result
    }
    None => []
  }
}

///|
/// 3. openai_chat_to_lux_response — 响应解码
pub fn openai_chat_to_lux_response(
  json_str : String,
) -> Result[@lux.ConversionResult[@lux.LucentResponse], String] {
  let jv = @json.parse(json_str) catch { _ => return Err("json parse error") }
  let id = @internal.field_str(jv, "id").unwrap_or("")
  let model = @internal.field_str(jv, "model").unwrap_or("")
  let created = @internal.field_int(jv, "created")
  let choices = parse_choices(jv)
  // usage
  let usage = match @internal.obj_get(jv, "usage") {
    Some(u) =>
      Some(
        @lux.LucentUsage::new(
          @internal.field_int(u, "prompt_tokens").unwrap_or(0),
          @internal.field_int(u, "completion_tokens").unwrap_or(0),
          @internal.field_int(u, "total_tokens").unwrap_or(0),
        ),
      )
    None => None
  }
  Ok(
    @lux.ConversionResult::new(
      @lux.LucentResponse::new(id, model, created, choices, usage, None),
    ),
  )
}

///|
/// === 响应编码：LucentResponse → OpenAI Chat JSON ===

///|
/// 4. lux_response_to_openai_chat — 响应编码
pub fn lux_response_to_openai_chat(
  resp : @lux.LucentResponse,
) -> Result[@lux.ConversionResult[String], String] {
  let choices_json : Array[String] = []
  let diagnostics : Array[@lux.ConversionDiagnostic] = []
  let mut i = 0
  while i < resp.choices.length() {
    let c = resp.choices[i]
    let role = role_to_string(c.message.role)
    // content 拼为字符串；tool_calls 入数组；refusal 入字段
    let tool_calls : Array[String] = []
    let refusal_buf : Array[String] = []
    let content_parts : Array[String] = []
    let mut j = 0
    while j < c.message.content.length() {
      match
        content_part_to_json(
          c.message.content[j],
          tool_calls,
          refusal_buf,
          diagnostics,
        ) {
        Some(s) => content_parts.push(s)
        None => ()
      }
      j = j + 1
    }
    let content_str = content_parts.join("")
    let mut msg_obj = "\"index\":" +
      c.index.to_string() +
      ",\"message\":{\"role\":\"" +
      escape_json(role) +
      "\",\"content\":\"" +
      escape_json(content_str) +
      "\""
    if tool_calls.length() > 0 {
      msg_obj = msg_obj + ",\"tool_calls\":[" + tool_calls.join(",") + "]"
    }
    if refusal_buf.length() > 0 {
      msg_obj = msg_obj + ",\"refusal\":\"" + escape_json(refusal_buf[0]) + "\""
    }
    msg_obj = msg_obj +
      "},\"finish_reason\":\"" +
      escape_json(c.finish_reason.to_string()) +
      "\""
    choices_json.push("{" + msg_obj + "}")
    i = i + 1
  }
  let usage_obj = match resp.usage {
    Some(u) =>
      ",\"usage\":{\"prompt_tokens\":" +
      u.prompt_tokens.to_string() +
      ",\"completion_tokens\":" +
      u.completion_tokens.to_string() +
      ",\"total_tokens\":" +
      u.total_tokens.to_string() +
      "}"
    None => ""
  }
  let created_part = match resp.created_at {
    Some(n) => ",\"created\":" + n.to_string()
    None => ""
  }
  let body = "{\"id\":\"" +
    escape_json(resp.id) +
    "\",\"object\":\"chat.completion\",\"model\":\"" +
    escape_json(resp.model) +
    "\"" +
    created_part +
    ",\"choices\":[" +
    choices_json.join(",") +
    "]" +
    usage_obj +
    "}"
  let mut result = @lux.ConversionResult::new(body)
  for d in diagnostics {
    result = result.with_diagnostic(d)
  }
  Ok(result)
}

///|
/// === 流解码：OpenAI Chat SSE → LucentStreamEvent[] ===

///|
/// 5. openai_chat_sse_to_events — 流解码
///
/// OpenAI Chat SSE 格式：
///   data: {"choices":[{"delta":{"role":"assistant"|"content":"..."|"tool_calls":[...]},"finish_reason":null|"stop"|...}]}
///   data: [DONE]
///
/// 块生命周期合成规则（OpenAI 无显式边界，需凭空造）：
/// - delta.role → ConversationStart + Role 隐式
/// - delta.content → BlockStart(0,Text)（首次）+ BlockDelta(TextDelta) + 隐式 BlockEnd
/// - delta.tool_calls[i].index 切换 → 切换块索引，BlockEnd 旧块 + BlockStart 新块
/// - finish_reason → Finish
/// - usage → Usage（最后一帧）
/// - [DONE] → Done
pub fn openai_chat_sse_to_events(
  sse_str : String,
) -> Result[@lux.ConversionResult[Array[@lux.LucentStreamEvent]], String] {
  let events : Array[@lux.LucentStreamEvent] = []
  let lines = sse_str.split("\n").to_array()
  let mut text_block_open = false // 是否有未闭合的文本块
  let mut current_tool_block = -1 // 当前工具调用块索引（-1 表示无）
  let mut i = 0
  while i < lines.length() {
    let line = lines[i]
    let line_str = line.to_owned()
    // 检查是否为 data: 行（逐字符比较，因为 MoonBit String 无 startsWith 方法）
    let is_data = if line_str.length() >= 5 {
      line_str[0] == 'd' &&
      line_str[1] == 'a' &&
      line_str[2] == 't' &&
      line_str[3] == 'a' &&
      line_str[4] == ':'
    } else {
      false
    }
    if is_data {
      // 提取 data: 后的内容
      let mut payload = ""
      let mut p = 5
      while p < line_str.length() {
        let ch = Int::unsafe_to_char(line_str[p].to_int())
        payload = payload + "\{ch}"
        p = p + 1
      }
      payload = payload.trim().to_owned()
      if payload == "[DONE]" {
        // 闭合未关闭的块
        if text_block_open {
          events.push(@lux.BlockEnd(0))
          text_block_open = false
        }
        if current_tool_block >= 0 {
          events.push(@lux.BlockEnd(current_tool_block))
          current_tool_block = -1
        }
        events.push(@lux.Done)
        i = i + 1
        continue
      }
      let jv = @json.parse(payload) catch {
        _ => {
          i = i + 1
          continue
        }
      }
      // usage 帧（choices 空的最后一帧）
      match @internal.obj_get(jv, "usage") {
        Some(u) => {
          let pt = @internal.field_int(u, "prompt_tokens").unwrap_or(0)
          let ct = @internal.field_int(u, "completion_tokens").unwrap_or(0)
          let tt = @internal.field_int(u, "total_tokens").unwrap_or(0)
          events.push(@lux.Usage(@lux.LucentUsage::new(pt, ct, tt)))
        }
        None => ()
      }
      // choices[0].delta
      match @internal.field_arr(jv, "choices") {
        Some(choices) =>
          if choices.length() > 0 {
            match @internal.obj_get(choices[0], "delta") {
              Some(delta) => {
                // role
                match @internal.field_str(delta, "role") {
                  Some("assistant") =>
                    events.push(
                      @lux.ConversationStart(
                        @lux.LucentConversationMeta::new(None, None, None),
                      ),
                    )
                  _ => ()
                }
                // content
                match @internal.field_str(delta, "content") {
                  Some(s) => {
                    if !text_block_open {
                      events.push(@lux.BlockStart(0, @lux.Text))
                      text_block_open = true
                    }
                    events.push(
                      @lux.BlockDelta(0, @lux.LucentBlockDelta::text_delta(s)),
                    )
                  }
                  None => ()
                }
                // tool_calls
                match @internal.field_arr(delta, "tool_calls") {
                  Some(tcs) => {
                    let mut k = 0
                    while k < tcs.length() {
                      let tc = tcs[k]
                      let idx = @internal.field_int(tc, "index").unwrap_or(0)
                      // 切换块：若旧块未关闭，先关旧块
                      if current_tool_block >= 0 && current_tool_block != idx {
                        events.push(@lux.BlockEnd(current_tool_block))
                      }
                      if current_tool_block != idx {
                        // 新工具调用块开始：id + function.name（首帧）
                        let id = @internal.field_str(tc, "id").unwrap_or("")
                        let name = match @internal.obj_get(tc, "function") {
                          Some(fn_obj) =>
                            @internal.field_str(fn_obj, "name").unwrap_or("")
                          None => ""
                        }
                        events.push(
                          @lux.BlockStart(
                            idx,
                            @lux.LucentBlockType::tool_call(id, name),
                          ),
                        )
                        current_tool_block = idx
                      }
                      // arguments 增量
                      match @internal.obj_get(tc, "function") {
                        Some(fn_obj) =>
                          match @internal.field_str(fn_obj, "arguments") {
                            Some(args) =>
                              events.push(
                                @lux.BlockDelta(
                                  idx,
                                  @lux.LucentBlockDelta::tool_arguments_delta(
                                    args,
                                  ),
                                ),
                              )
                            None => ()
                          }
                        None => ()
                      }
                      k = k + 1
                    }
                  }
                  None => ()
                }
              }
              None => ()
            }
            // finish_reason
            match @internal.field_str(choices[0], "finish_reason") {
              Some(fr) => {
                // 闭合未关闭的块
                if text_block_open {
                  events.push(@lux.BlockEnd(0))
                  text_block_open = false
                }
                if current_tool_block >= 0 {
                  events.push(@lux.BlockEnd(current_tool_block))
                  current_tool_block = -1
                }
                events.push(
                  @lux.Finish(@lux.LucentFinishReason::from_string(fr)),
                )
              }
              None => ()
            }
          }
        None => ()
      }
    }
    i = i + 1
  }
  Ok(@lux.ConversionResult::new(events))
}

///|
/// === 流编码：LucentStreamEvent[] → OpenAI Chat SSE ===

///|
/// 6. lux_events_to_openai_chat_sse — 流编码
///
/// 把 Lux 事件流编码为 OpenAI Chat SSE 格式：
/// - ConversationStart → data: {"choices":[{"delta":{"role":"assistant"}}]}
/// - BlockDelta(TextDelta) → data: {"choices":[{"delta":{"content":"..."}]}]}
/// - BlockDelta(ToolArgumentsDelta) → data: {"choices":[{"delta":{"tool_calls":[{"index":N,"function":{"arguments":"..."}}]}]}
/// - BlockStart(ToolCall(id,name)) → data: {"choices":[{"delta":{"tool_calls":[{"index":N,"id":"...","type":"function","function":{"name":"..."}}]}]}
/// - Finish(reason) → data: {"choices":[{"delta":{},"finish_reason":"..."}]}
/// - Usage(u) → data: {"usage":{...}}
/// - Done → data: [DONE]
pub fn lux_events_to_openai_chat_sse(
  events : Array[@lux.LucentStreamEvent],
) -> Result[@lux.ConversionResult[String], String] {
  let out : Array[String] = []
  let mut i = 0
  while i < events.length() {
    match events[i] {
      ConversationStart(_) =>
        out.push("data: {\"choices\":[{\"delta\":{\"role\":\"assistant\"}}]}")
      ItemStart(_, _) | ItemEnd(_) | BlockDiscard(_) | Annotations(_, _) => ()
      // 块边界在 OpenAI Chat 流中不显式（无 BlockStart/BlockEnd 对应）
      // 但 ToolCall 的 BlockStart 携带 id/name，需编码为 tool_calls 首帧
      BlockStart(idx, bt) =>
        match bt {
          ToolCall(id, name) =>
            out.push(
              "data: {\"choices\":[{\"delta\":{\"tool_calls\":[" +
              "{\"index\":" +
              idx.to_string() +
              ",\"id\":\"" +
              escape_json(id) +
              "\",\"type\":\"function\",\"function\":{\"name\":\"" +
              escape_json(name) +
              "\"}}]}}]}",
            )
          _ => ()
        }
      BlockEnd(_) => ()
      BlockDelta(idx, delta) =>
        match delta {
          TextDelta(s) =>
            out.push(
              "data: {\"choices\":[{\"delta\":{\"content\":\"" +
              escape_json(s) +
              "\"}}]}",
            )
          ToolArgumentsDelta(s) =>
            out.push(
              "data: {\"choices\":[{\"delta\":{\"tool_calls\":[" +
              "{\"index\":" +
              idx.to_string() +
              ",\"function\":{\"arguments\":\"" +
              escape_json(s) +
              "\"}}]}}]}",
            )
          ThinkingDelta(_) | SignatureDelta(_) | RefusalDelta(_) => ()
          // OpenAI Chat 流无原生 thinking/refusal 增量，编码时忽略
          NativeDelta(_, _) => ()
        }
      Finish(fr) =>
        out.push(
          "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"" +
          escape_json(fr.to_string()) +
          "\"}]}",
        )
      Usage(u) =>
        out.push(
          "data: {\"usage\":{\"prompt_tokens\":" +
          u.prompt_tokens.to_string() +
          ",\"completion_tokens\":" +
          u.completion_tokens.to_string() +
          ",\"total_tokens\":" +
          u.total_tokens.to_string() +
          "}}",
        )
      Error(e) =>
        out.push(
          "data: {\"error\":{\"message\":\"" + escape_json(e.message) + "\"}}",
        )
      Done => out.push("data: [DONE]")
    }
    i = i + 1
  }
  Ok(@lux.ConversionResult::new(out.join("\n\n") + "\n\n"))
}

///|
/// capability — 适配器能力声明
pub fn capability() -> @lux.ProviderCapability {
  @lux.ProviderCapability::new(
    "gpt-*,o*",
    "openai-chat",
    @lux.LucentCapabilities::create(
      true,
      true,
      true,
      true,
      true,
      [@lux.Text, @lux.Image],
      [@lux.Text],
    ),
    None,
  )
}
