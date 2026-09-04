///|
/// OpenAI Chat Completions — 请求编码
///
/// LucentRequest → OpenAI Chat Completions JSON

/// === 请求编码：LucentRequest → OpenAI Chat JSON ===

///|
fn role_to_string(role : @lux.LucentRole) -> String {
  role.to_string()
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
/// extras 查询辅助（只读，不消费）
fn merged_extras_lookup(extras : Map[String, Json]?, key : String) -> Json? {
  match extras {
    Some(m) => m.get(key)
    None => None
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
              "\"reasoning_effort\":\"" +
              @lux.LucentReasoningEffort::to_string(e) +
              "\"",
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
    // name/strict 从 extras 透传的 json_schema_name / json_schema_strict 消费（标准 §6）
    // 缺省 name="response"、strict 不发（模型默认），严格客户端可按需声明
    Some(JsonSchema(schema)) => {
      let name_part = match
        merged_extras_lookup(opts.extras, "json_schema_name") {
        Some(String(n)) => "\"name\":\"" + @internal.json_escape(n) + "\""
        _ => "\"name\":\"response\""
      }
      let strict_part = match
        merged_extras_lookup(opts.extras, "json_schema_strict") {
        Some(True) => ",\"strict\":true"
        Some(False) => ",\"strict\":false"
        _ => ""
      }
      parts.push(
        "\"response_format\":{\"type\":\"json_schema\",\"json_schema\":{" +
        name_part +
        strict_part +
        ",\"schema\":" +
        schema +
        "}}",
      )
    }
    None => ()
  }
  match opts.store {
    Some(b) => parts.push("\"store\":" + b.to_string())
    None => ()
  }
  // disable_parallel_tool_use（Anthropic 系）→ parallel_tool_calls（语义反向，标准 §2）
  // extras 中透传的 disable_parallel_tool_use 由本分支消费，不落入输出 JSON。
  let mut merged_extras = opts.extras
  match opts.extras {
    Some(m) =>
      match m.get("disable_parallel_tool_use") {
        Some(True) => {
          parts.push("\"parallel_tool_calls\":false")
          merged_extras = @internal.extras_without(
            opts.extras,
            "disable_parallel_tool_use",
          )
        }
        Some(False) => {
          parts.push("\"parallel_tool_calls\":true")
          merged_extras = @internal.extras_without(
            opts.extras,
            "disable_parallel_tool_use",
          )
        }
        _ => ()
      }
    None => ()
  }
  // previous_response_id：仅 Responses 有语义；跨端出站时若无可恢复历史必须拒绝（标准 §3.2）
  match merged_extras {
    Some(m) =>
      match m.get("previous_response_id") {
        Some(_) => {
          if req.conversation.length() == 0 {
            return Err(
              "previous_response_id without conversation history cannot be converted to openai-chat",
            )
          }
          diagnostics.push(
            @lux.ConversionDiagnostic::unsupported(
              "options.previous_response_id",
              Some("previous_response_id not preserved by openai-chat"),
            ),
          )
          merged_extras = @internal.extras_without(
            merged_extras, "previous_response_id",
          )
        }
        None => ()
      }
    None => ()
  }
  @internal.merge_extras_json(parts, merged_extras)
  let result = @lux.ConversionResult::new("{" + parts.join(",") + "}")
  Ok(result.with_diagnostics(diagnostics))
}
