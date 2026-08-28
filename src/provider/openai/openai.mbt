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
/// 解析 data URI：data:image/png;base64,xxx → (media_type, base64_data)
fn parse_data_uri(url : String) -> (String, String)? {
  if url.length() < 5 || url[0] != 'd' || url[4] != ':' {
    return None
  }
  let segs = url.split(";").to_array()
  if segs.length() < 2 {
    return None
  }
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
  if data == "" { None } else { Some((media_type, data)) }
}

///|
/// 解析 image_url 类型的 content part → LucentContent::Image
fn parse_image_url_part(part : Json) -> @lux.LucentContent? {
  match @internal.obj_get(part, "image_url") {
    Some(url_obj) =>
      match @internal.field_str(url_obj, "url") {
        Some(u) =>
          if u == "" {
            None
          } else {
            match parse_data_uri(u) {
              Some((media_type, data)) =>
                Some(@lux.LucentContent::image(media_type, @lux.LucentMediaSource::inline(data)))
              None =>
                Some(@lux.LucentContent::image("image/png", @lux.LucentMediaSource::url(u)))
            }
          }
        None => None
      }
    None => None
  }
}

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
            match parse_image_url_part(part) {
              Some(img) => result.push(img)
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
              @lux.push_unsupported(
                "content.image", "file_uri image source not supported by openai-chat",
                diagnostics,
              )
          }
        Audio(_) =>
          @lux.push_unsupported_content("audio", "openai-chat", diagnostics)
        Video(_) =>
          @lux.push_unsupported_content("video", "openai-chat", diagnostics)
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
      @lux.push_unsupported_content("file", "openai-chat", diagnostics)
      None
    }
    Audio(_) => {
      @lux.push_unsupported_content("audio", "openai-chat", diagnostics)
      None
    }
    Video(_) => {
      @lux.push_unsupported_content("video", "openai-chat", diagnostics)
      None
    }
    Native(tag, _) => {
      @lux.push_unsupported(
        "content.native",
        "native content (" + tag + ") not supported by openai-chat",
        diagnostics,
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
