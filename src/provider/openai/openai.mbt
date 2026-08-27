///|
/// OpenAI Chat Completions 适配器 — 对齐 Lux IR v1
///
/// 依据：docs/lux-ir-design.md §10（6-Function 契约）
/// 依据：docs/protocols/01-openai-completions.md（协议映射）
///
/// 6 函数：
///   1. openai_to_lux_request      请求解码
///   2. lux_request_to_openai      请求编码
///   3. openai_to_lux_response     响应解码
///   4. lux_response_to_openai     响应编码
///   5. openai_sse_to_events       流解码
///   6. lux_events_to_openai_sse   流编码

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
                    } else if u[0] == 'd' && u.length() > 5 && u[4] == ':' {
                      // data:image/png;base64,xxx → 拆出 media_type + 纯 base64 存 Inline
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
              @lux.LucentTool::new(name, desc, params, strict, Function),
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
    Some(String("auto")) => Some(Auto)
    Some(String("none")) => Some(None)
    Some(String("required")) => Some(Required)
    Some(Object(_)) =>
      // {"type":"function","function":{"name":"x"}}
      match @internal.obj_get(jv, "tool_choice") {
        Some(tc_obj) =>
          match @internal.field_str(tc_obj, "type") {
            Some("function") =>
              match @internal.obj_get(tc_obj, "function") {
                Some(fn_obj) =>
                  match @internal.field_str(fn_obj, "name") {
                    Some(n) => Some(SpecificTool(n))
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
/// 1. openai_to_lux_request — 请求解码
pub fn openai_to_lux_request(
  json_str : String,
) -> Result[@lux.ConversionResult[@lux.LucentRequest], String] {
  let jv = match @internal.parse_protocol_json(json_str) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
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
  let store = @internal.field_bool(jv, "store")
  let extras = @internal.collect_extra_fields(jv, [
    "model", "messages", "tools", "tool_choice", "temperature", "top_p", "max_completion_tokens",
    "max_tokens", "stream", "stop", "response_format", "store",
  ])
  // response_format → structured_output
  let structured = match @internal.obj_get(jv, "response_format") {
    Some(rf) =>
      match @internal.field_str(rf, "type") {
        Some("json_object") => Some(@lux.LucentStructuredOutput::JsonObject)
        Some("text") => Some(Text)
        Some("json_schema") =>
          match @internal.obj_get(rf, "json_schema") {
            Some(js_obj) =>
              match @internal.obj_get(js_obj, "schema") {
                Some(schema) => Some(JsonSchema(schema.stringify()))
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
          structured,
          store,
          extras,
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
/// LucentReasoningEffort → OpenAI reasoning_effort 字符串
fn reasoning_effort_to_string(e : @lux.LucentReasoningEffort) -> String {
  match e {
    Low => "low"
    Medium => "medium"
    High => "high"
    XHigh => "xhigh"
  }
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
      @internal.json_escape(name) +
      "\"}}"
  }
}

///|
/// 构造 messages[].content 字段：含图片时用数组形式（image_url），否则字符串形式。
/// 返回 `"content":...` 片段（含键名与值，调用方直接拼接）。
fn content_field_to_json(
  content : Array[@lux.LucentContent],
  diagnostics : Array[@lux.ConversionDiagnostic],
) -> String {
  let mut needs_array = false
  let mut i = 0
  while i < content.length() {
    match content[i] {
      Image(_) | Audio(_) | Video(_) => needs_array = true
      _ => ()
    }
    i = i + 1
  }
  if needs_array {
    let parts : Array[String] = []
    let mut j = 0
    while j < content.length() {
      match content[j] {
        Text(s, _) =>
          parts.push(
            "{\"type\":\"text\",\"text\":\"" + @internal.json_escape(s) + "\"}",
          )
        Image(mm) =>
          match mm.source {
            Url(url) =>
              parts.push(
                "{\"type\":\"image_url\",\"image_url\":{\"url\":\"" +
                @internal.json_escape(url) +
                "\"}}",
              )
            Inline(data) =>
              parts.push(
                "{\"type\":\"image_url\",\"image_url\":{\"url\":\"data:" +
                @internal.json_escape(mm.media_type) +
                ";base64," +
                @internal.json_escape(data) +
                "\"}}",
              )
            FileUri(_) =>
              diagnostics.push(
                @lux.ConversionDiagnostic::unsupported(
                  "content.image",
                  Some("file_uri image source not supported by openai-chat"),
                ),
              )
          }
        Audio(_) =>
          diagnostics.push(
            @lux.ConversionDiagnostic::unsupported(
              "content.audio",
              Some("audio content not supported by openai-chat"),
            ),
          )
        Video(_) =>
          diagnostics.push(
            @lux.ConversionDiagnostic::unsupported(
              "content.video",
              Some("video content not supported by openai-chat"),
            ),
          )
        _ => ()
      }
      j = j + 1
    }
    "\"content\":[" + parts.join(",") + "]"
  } else {
    let text_parts : Array[String] = []
    let mut k = 0
    while k < content.length() {
      match content[k] {
        Text(s, _) => text_parts.push(s)
        _ => ()
      }
      k = k + 1
    }
    "\"content\":\"" + @internal.json_escape(text_parts.join("")) + "\""
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
        @internal.json_escape(tu.id) +
        "\",\"type\":\"function\",\"function\":{\"name\":\"" +
        @internal.json_escape(tu.name) +
        "\",\"arguments\":\"" +
        @internal.json_escape(tu.arguments_json) +
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
    Image(_) => None // 图片由 content_field_to_json 以数组形式（image_url）编码
    File(_) => {
      // OpenAI Chat 无文件载体（仅图片 image_url 与工具），显式 Unsupported 诊断
      diagnostics.push(
        @lux.ConversionDiagnostic::unsupported(
          "content.file",
          Some("file content not supported by openai-chat"),
        ),
      )
      None
    }
    Audio(_) => {
      diagnostics.push(
        @lux.ConversionDiagnostic::unsupported(
          "content.audio",
          Some("audio content not supported by openai-chat"),
        ),
      )
      None
    }
    Video(_) => {
      diagnostics.push(
        @lux.ConversionDiagnostic::unsupported(
          "content.video",
          Some("video content not supported by openai-chat"),
        ),
      )
      None
    }
    Native(tag, _) => {
      diagnostics.push(
        @lux.ConversionDiagnostic::unsupported(
          "content.native",
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
      @internal.json_escape(tcid) +
      "\",\"content\":\"" +
      @internal.json_escape(content_str) +
      "\"}"
    }
    _ => {
      // 普通 role：content 由 content_field_to_json 统一构造（含图片时数组形式）；
      // tool_calls 入数组；refusal 入字段
      let mut i = 0
      while i < msg.content.length() {
        let _ = content_part_to_json(
          msg.content[i],
          tool_calls,
          refusal_buf,
          diagnostics,
        )
        i = i + 1
      }
      let content_field = content_field_to_json(msg.content, diagnostics)
      let mut msg_obj = "{\"role\":\"" +
        @internal.json_escape(role) +
        "\"," +
        content_field
      if tool_calls.length() > 0 {
        msg_obj = msg_obj + ",\"tool_calls\":[" + tool_calls.join(",") + "]"
      }
      if refusal_buf.length() > 0 {
        msg_obj = msg_obj +
          ",\"refusal\":\"" +
          @internal.json_escape(refusal_buf[0]) +
          "\""
      }
      msg_obj + "}"
    }
  }
}

///|
/// 2. lux_request_to_openai — 请求编码
pub fn lux_request_to_openai(
  req : @lux.LucentRequest,
) -> Result[@lux.ConversionResult[String], String] {
  let parts : Array[String] = []
  parts.push("\"model\":\"" + @internal.json_escape(req.model) + "\"")
  // instructions → system 消息（前置）
  let msgs_json : Array[String] = []
  match req.instructions {
    Some(instrs) => {
      let instr_text = @lux.lucent_content_to_text(instrs)
      msgs_json.push(
        "{\"role\":\"system\",\"content\":\"" +
        @internal.json_escape(instr_text) +
        "\"}",
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
          @internal.json_escape(tu.id) +
          "\",\"type\":\"function\",\"function\":{\"name\":\"" +
          @internal.json_escape(tu.name) +
          "\",\"arguments\":\"" +
          @internal.json_escape(tu.arguments_json) +
          "\"}}]}",
        )
      ToolResult(tr) =>
        msgs_json.push(
          "{\"role\":\"tool\",\"tool_call_id\":\"" +
          @internal.json_escape(tr.tool_use_id) +
          "\",\"content\":\"" +
          @internal.json_escape(@lux.lucent_content_to_text(tr.content)) +
          "\"}",
        )
      Reasoning(_) =>
        // OpenAI Chat 无原生 reasoning：不静默忽略，显式 Unsupported 诊断
        diagnostics.push(
          @lux.ConversionDiagnostic::unsupported(
            "conversation.reasoning",
            Some("reasoning not supported by openai-chat"),
          ),
        )
      AgentAction(_) =>
        // OpenAI Chat 无 AgentAction 载体：不静默忽略，显式 Unsupported 诊断
        diagnostics.push(
          @lux.ConversionDiagnostic::unsupported(
            "conversation.agent_action",
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
        match t.kind {
          Function => {
            // parameters 应为 JSON object 字符串，嵌入为对象而非字符串
            // 但为简化（且 parameters_json 本身就是 JSON 字符串），直接嵌入
            let desc_part = match t.description {
              Some(d) => ",\"description\":\"" + @internal.json_escape(d) + "\""
              None => ""
            }
            let fn_str = "\"function\":{" +
              "\"name\":\"" +
              @internal.json_escape(t.name) +
              "\"" +
              desc_part +
              ",\"parameters\":" +
              t.parameters_json + // 直接嵌入 JSON
              "}"
            tools_json.push("{\"type\":\"function\"," + fn_str + "}")
          }
          _ =>
            // OpenAI Chat 仅支持 function 工具：不静默降级为 function，显式 Unsupported
            diagnostics.push(
              @lux.ConversionDiagnostic::unsupported(
                "tools.kind",
                Some("tool kind not supported by openai-chat"),
              ),
            )
        }
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
        stops.push("\"" + @internal.json_escape(arr[k]) + "\"")
        k = k + 1
      }
      parts.push("\"stop\":[" + stops.join(",") + "]")
    }
    None => ()
  }
  if opts.stream {
    parts.push("\"stream\":true")
  }
  // reasoning config → reasoning_effort（o-series 标准参数）
  match req.reasoning {
    Some(rc) =>
      if rc.enabled {
        match rc.effort {
          Some(e) =>
            parts.push(
              "\"reasoning_effort\":\"" + reasoning_effort_to_string(e) + "\"",
            )
          None => () // enabled 无 effort：省略（模型默认）
        }
      } else {
        // disabled：OpenAI o-series 无 reasoning_effort 禁用值；gpt-5.1+ 支持
        // "none"，此处保守省略（模型默认行为）
        ()
      }
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
              _ => Assistant
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
            // reasoning（vLLM: message.reasoning；DeepSeek/Fireworks: message.reasoning_content）
            let reasoning : @lux.LucentThinking? = match
              @internal.field_str(msg_jv, "reasoning") {
              Some(text) => Some(@lux.LucentThinking::visible(text, None))
              None =>
                match @internal.field_str(msg_jv, "reasoning_content") {
                  Some(text) => Some(@lux.LucentThinking::visible(text, None))
                  None => None
                }
            }
            let finish = match @internal.field_str(c, "finish_reason") {
              Some(fr) => @lux.LucentFinishReason::from_string(fr)
              None => Stop
            }
            let msg = match reasoning {
              Some(th) =>
                @lux.LucentMessage::with_reasoning(role, content, Some(th))
              None => @lux.LucentMessage::new(role, content)
            }
            result.push(@lux.LucentChoice::new(idx, msg, finish, None))
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
/// 3. openai_to_lux_response — 响应解码
pub fn openai_to_lux_response(
  json_str : String,
) -> Result[@lux.ConversionResult[@lux.LucentResponse], String] {
  let jv = match @internal.parse_protocol_json(json_str) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
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
/// 4. lux_response_to_openai — 响应编码
pub fn lux_response_to_openai(
  resp : @lux.LucentResponse,
) -> Result[@lux.ConversionResult[String], String] {
  let choices_json : Array[String] = []
  let diagnostics : Array[@lux.ConversionDiagnostic] = []
  let mut i = 0
  while i < resp.choices.length() {
    let c = resp.choices[i]
    let role = role_to_string(c.message.role)
    // content 由 content_field_to_json 统一构造（含图片时数组形式）；tool_calls 入数组；refusal 入字段
    let tool_calls : Array[String] = []
    let refusal_buf : Array[String] = []
    let mut j = 0
    while j < c.message.content.length() {
      let _ = content_part_to_json(
        c.message.content[j],
        tool_calls,
        refusal_buf,
        diagnostics,
      )
      j = j + 1
    }
    let content_field = content_field_to_json(c.message.content, diagnostics)
    // reasoning：消息级 reasoning → message.reasoning 字段
    // 字段名默认 "reasoning"（vLLM）；经 provider_payload.reasoning_field 声明 "reasoning_content" 时切换
    let reasoning_field = match c.message.reasoning {
      Some(th) => {
        let field_name = match resp.provider_payload {
          Some(Object(m)) =>
            match m.get("reasoning_field") {
              Some(String(s)) if s == "reasoning_content" => s
              _ => "reasoning"
            }
          _ => "reasoning"
        }
        ",\"" + field_name + "\":\"" + @internal.json_escape(th.text) + "\""
      }
      None => ""
    }
    let mut msg_obj = "\"index\":" +
      c.index.to_string() +
      ",\"message\":{\"role\":\"" +
      @internal.json_escape(role) +
      "\"," +
      content_field +
      reasoning_field
    if tool_calls.length() > 0 {
      msg_obj = msg_obj + ",\"tool_calls\":[" + tool_calls.join(",") + "]"
    }
    if refusal_buf.length() > 0 {
      msg_obj = msg_obj +
        ",\"refusal\":\"" +
        @internal.json_escape(refusal_buf[0]) +
        "\""
    }
    msg_obj = msg_obj +
      "},\"finish_reason\":\"" +
      @internal.json_escape(c.finish_reason.to_string()) +
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
    @internal.json_escape(resp.id) +
    "\",\"object\":\"chat.completion\",\"model\":\"" +
    @internal.json_escape(resp.model) +
    "\"" +
    created_part +
    ",\"choices\":[" +
    choices_json.join(",") +
    "]" +
    usage_obj +
    "}"
  let result = @lux.ConversionResult::new(body)
  Ok(result.with_diagnostics(diagnostics))
}

///|
/// === 流解码：OpenAI Chat SSE → LucentStreamEvent[] ===

///|
/// 5. openai_sse_to_events — 流解码
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
pub fn openai_sse_to_events(
  sse_str : String,
) -> Result[@lux.ConversionResult[Array[@lux.LucentStreamEvent]], String] {
  let events : Array[@lux.LucentStreamEvent] = []
  let messages = @internal.parse_sse_messages(sse_str)
  let mut text_block_open = false // 是否有未闭合的文本块
  let mut current_tool_block = -1 // 当前工具调用块索引（-1 表示无）
  let mut i = 0
  while i < messages.length() {
    let payload_raw = messages[i].data.trim().to_owned()
    // [DONE] 终止信号
    if payload_raw == "[DONE]" {
      if text_block_open {
        events.push(BlockEnd(0))
        text_block_open = false
      }
      if current_tool_block >= 0 {
        events.push(BlockEnd(current_tool_block))
        current_tool_block = -1
      }
      events.push(Done)
      i = i + 1
      continue
    }
    // 清理心跳、截断检测、转义清理
    let payload = @internal.sanitize_json_escapes(
      @internal.clean_sse_heartbeat(payload_raw),
    )
    if @internal.is_json_truncated(payload) {
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
        events.push(Usage(@lux.LucentUsage::new(pt, ct, tt)))
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
                    ConversationStart(
                      @lux.LucentConversationMeta::new(None, None, None),
                    ),
                  )
                _ => ()
              }
              // content
              match @internal.field_str(delta, "content") {
                Some(s) => {
                  if !text_block_open {
                    events.push(BlockStart(0, Text))
                    text_block_open = true
                  }
                  events.push(
                    BlockDelta(0, @lux.LucentBlockDelta::text_delta(s)),
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
                    if current_tool_block >= 0 && current_tool_block != idx {
                      events.push(BlockEnd(current_tool_block))
                    }
                    if current_tool_block != idx {
                      let id = @internal.field_str(tc, "id").unwrap_or("")
                      let name = match @internal.obj_get(tc, "function") {
                        Some(fn_obj) =>
                          @internal.field_str(fn_obj, "name").unwrap_or("")
                        None => ""
                      }
                      events.push(
                        BlockStart(
                          idx,
                          @lux.LucentBlockType::tool_call(id, name),
                        ),
                      )
                      current_tool_block = idx
                    }
                    match @internal.obj_get(tc, "function") {
                      Some(fn_obj) =>
                        match @internal.field_str(fn_obj, "arguments") {
                          Some(args) =>
                            events.push(
                              BlockDelta(
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
              if text_block_open {
                events.push(BlockEnd(0))
                text_block_open = false
              }
              if current_tool_block >= 0 {
                events.push(BlockEnd(current_tool_block))
                current_tool_block = -1
              }
              events.push(Finish(@lux.LucentFinishReason::from_string(fr)))
            }
            None => ()
          }
        }
      None => ()
    }
    i = i + 1
  }
  Ok(@lux.ConversionResult::new(events))
}

///|
/// === 流编码：LucentStreamEvent[] → OpenAI Chat SSE ===

///|
/// 6. lux_events_to_openai_sse — 流编码
///
/// 把 Lux 事件流编码为 OpenAI Chat SSE 格式：
/// - ConversationStart → data: {"choices":[{"delta":{"role":"assistant"}}]}
/// - BlockDelta(TextDelta) → data: {"choices":[{"delta":{"content":"..."}]}]}
/// - BlockDelta(ToolArgumentsDelta) → data: {"choices":[{"delta":{"tool_calls":[{"index":N,"function":{"arguments":"..."}}]}]}
/// - BlockStart(ToolCall(id,name)) → data: {"choices":[{"delta":{"tool_calls":[{"index":N,"id":"...","type":"function","function":{"name":"..."}}]}]}
/// - Finish(reason) → data: {"choices":[{"delta":{},"finish_reason":"..."}]}
/// - Usage(u) → data: {"usage":{...}}
/// - Done → data: [DONE]

///|
/// 每个 chunk 的公共前缀：id / object / created / model
fn chunk_prefix(id : String, model : String, created : Int) -> String {
  "data: {\"id\":\"" +
  @internal.json_escape(id) +
  "\",\"object\":\"chat.completion.chunk\",\"created\":" +
  created.to_string() +
  ",\"model\":\"" +
  @internal.json_escape(model) +
  "\","
}

///|
pub fn lux_events_to_openai_sse(
  events : Array[@lux.LucentStreamEvent],
) -> Result[@lux.ConversionResult[String], String] {
  let out : Array[String] = []
  let mut i = 0
  // 从 ConversationStart 提取，注入每个 chunk
  let mut chat_id = ""
  let mut chat_model = ""
  let mut chat_created : Int = 0
  while i < events.length() {
    match events[i] {
      ConversationStart(meta) => {
        chat_id = meta.id.unwrap_or("chatcmpl-0")
        chat_model = meta.model.unwrap_or("")
        chat_created = meta.created_at.unwrap_or(0)
        out.push(
          chunk_prefix(chat_id, chat_model, chat_created) +
          "\"choices\":[{\"delta\":{\"role\":\"assistant\"}}]}",
        )
      }
      ItemStart(_, _) | ItemEnd(_) | BlockDiscard(_) | Annotations(_, _) => ()
      // 块边界在 OpenAI Chat 流中不显式（无 BlockStart/BlockEnd 对应）
      // 但 ToolCall 的 BlockStart 携带 id/name，需编码为 tool_calls 首帧
      BlockStart(idx, bt) =>
        match bt {
          ToolCall(id, name) =>
            out.push(
              chunk_prefix(chat_id, chat_model, chat_created) +
              "\"choices\":[{\"delta\":{\"tool_calls\":[" +
              "{\"index\":" +
              idx.to_string() +
              ",\"id\":\"" +
              @internal.json_escape(id) +
              "\",\"type\":\"function\",\"function\":{\"name\":\"" +
              @internal.json_escape(name) +
              "\"}}]}}]}",
            )
          _ => ()
        }
      BlockEnd(_) => ()
      BlockDelta(idx, delta) =>
        match delta {
          TextDelta(s) =>
            out.push(
              chunk_prefix(chat_id, chat_model, chat_created) +
              "\"choices\":[{\"delta\":{\"content\":\"" +
              @internal.json_escape(s) +
              "\"}}]}",
            )
          ToolArgumentsDelta(s) =>
            out.push(
              chunk_prefix(chat_id, chat_model, chat_created) +
              "\"choices\":[{\"delta\":{\"tool_calls\":[" +
              "{\"index\":" +
              idx.to_string() +
              ",\"function\":{\"arguments\":\"" +
              @internal.json_escape(s) +
              "\"}}]}}]}",
            )
          ThinkingDelta(_) | SignatureDelta(_) | RefusalDelta(_) => ()
          // 标准 OpenAI Chat 流无原生 thinking/refusal 增量（vLLM 扩展由 openai_vllm 子协议承载）
          // OpenAI Chat 流无原生 signature/refusal 增量，编码时忽略
          NativeDelta(_, _) => ()
        }
      Finish(fr) =>
        out.push(
          chunk_prefix(chat_id, chat_model, chat_created) +
          "\"choices\":[{\"delta\":{},\"finish_reason\":\"" +
          @internal.json_escape(fr.to_string()) +
          "\"}]}",
        )
      Usage(u) =>
        // 附带空 choices 保证 Chat Completions 格式合法
        out.push(
          chunk_prefix(chat_id, chat_model, chat_created) +
          "\"choices\":[],\"usage\":{\"prompt_tokens\":" +
          u.prompt_tokens.to_string() +
          ",\"completion_tokens\":" +
          u.completion_tokens.to_string() +
          ",\"total_tokens\":" +
          u.total_tokens.to_string() +
          "}}",
        )
      Error(e) =>
        out.push(
          chunk_prefix(chat_id, chat_model, chat_created) +
          "\"error\":{\"message\":\"" +
          @internal.json_escape(e.message) +
          "\"}}",
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
    "openai",
    @lux.LucentCapabilities::create(
      Full,
      Absent,
      Full,
      Full,
      Full,
      [Text, Image],
      [Text],
    ),
    None,
  )
}
