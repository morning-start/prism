///|
/// Anthropic Messages — 请求编码
///
/// LucentRequest → Anthropic Messages API JSON

///|
/// LucentThinking → Anthropic thinking block JSON（消息级 reasoning 出站复用）
fn thinking_to_block(th : @lux.LucentThinking) -> String {
  if th.redacted {
    "{\"type\":\"redacted_thinking\",\"signature\":" +
    (match th.signature {
      Some(s) => "\"" + @internal.json_escape(s) + "\""
      None => "null"
    }) +
    "}"
  } else {
    "{\"type\":\"thinking\",\"thinking\":\"" +
    @internal.json_escape(th.text) +
    "\"" +
    (match th.signature {
      Some(s) => ",\"signature\":\"" + @internal.json_escape(s) + "\""
      None => ""
    }) +
    "}"
  }
}

///|
/// 校验 tool_use 的 arguments_json 为合法 JSON，返回可内嵌的 input 片段。
/// 非法 JSON → Invalid 诊断 + None（调用方跳过该块，不输出非法请求体，标准 §11.2）。
fn tool_use_input_fragment(
  tu : @lux.LucentToolUse,
  diagnostics : Array[@lux.ConversionDiagnostic],
) -> String? {
  match @internal.parse_json_opt(tu.arguments_json) {
    Some(v) => Some(v.stringify())
    None => {
      diagnostics.push(
        @lux.ConversionDiagnostic::new(
          "content.tool_use.input",
          Invalid,
          Some("invalid JSON arguments cannot be sent to anthropic"),
        ),
      )
      None
    }
  }
}

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
/// 单个 LucentContent → Anthropic content block JSON 片段
/// 无法映射的媒体产生 Unsupported 诊断并返回空串（调用方跳过，不输出空块）
fn content_to_block(
  c : @lux.LucentContent,
  diagnostics : Array[@lux.ConversionDiagnostic],
) -> String {
  match c {
    Text(s, _) =>
      "{\"type\":\"text\",\"text\":\"" + @internal.json_escape(s) + "\"}"
    ToolUse(tu) =>
      match tool_use_input_fragment(tu, diagnostics) {
        Some(input_frag) =>
          "{\"type\":\"tool_use\",\"id\":\"" +
          @internal.json_escape(tu.id) +
          "\",\"name\":\"" +
          @internal.json_escape(tu.name) +
          "\",\"input\":" +
          input_frag +
          "}"
        None => ""
      }
    ToolResult(tr) =>
      "{\"type\":\"tool_result\",\"tool_use_id\":\"" +
      @internal.json_escape(tr.tool_use_id) +
      "\",\"content\":" +
      content_array_to_json(tr.content, diagnostics) +
      ",\"is_error\":" +
      (if tr.is_error { "true" } else { "false" }) +
      "}"
    Thinking(th) => thinking_to_block(th)
    Refusal(s) =>
      "{\"type\":\"text\",\"text\":\"" + @internal.json_escape(s) + "\"}"
    Image(mm) =>
      // 图片：优先精确映射为 anthropic image block
      match mm.source {
        Url(url) =>
          "{\"type\":\"image\",\"source\":{\"type\":\"url\",\"url\":\"" +
          @internal.json_escape(url) +
          "\"}}"
        Inline(data) =>
          "{\"type\":\"image\",\"source\":{\"type\":\"base64\",\"media_type\":\"" +
          @internal.json_escape(mm.media_type) +
          "\",\"data\":\"" +
          @internal.json_escape(data) +
          "\"}}"
        FileUri(_) => {
          diagnostics.push(
            @lux.ConversionDiagnostic::unsupported(
              "content.image",
              Some("file_uri image source not supported by anthropic"),
            ),
          )
          ""
        }
      }
    File(mm) =>
      // 文件（PDF 等）：精确映射为 anthropic document block
      match mm.source {
        Url(url) =>
          "{\"type\":\"document\",\"source\":{\"type\":\"url\",\"url\":\"" +
          @internal.json_escape(url) +
          "\"},\"media_type\":\"" +
          @internal.json_escape(mm.media_type) +
          "\"}"
        Inline(data) =>
          "{\"type\":\"document\",\"source\":{\"type\":\"base64\",\"media_type\":\"" +
          @internal.json_escape(mm.media_type) +
          "\",\"data\":\"" +
          @internal.json_escape(data) +
          "\"}}"
        FileUri(_) => {
          @lux.push_unsupported(
            "content.file", "file_uri file source not supported by anthropic", diagnostics,
          )
          ""
        }
      }
    Audio(_) => {
      @lux.push_unsupported_content("audio", "anthropic", diagnostics)
      ""
    }
    Video(_) => {
      @lux.push_unsupported_content("video", "anthropic", diagnostics)
      ""
    }
    Native(tag, _) => {
      @lux.push_unsupported(
        "content.native",
        "native content (" + tag + ") not supported by anthropic",
        diagnostics,
      )
      ""
    }
  }
}

///|
/// LucentMessage → Anthropic message JSON
///
/// Claude 无 tool 角色（标准 §11.3/§11.4 硬规则）：
/// - role=Tool 的消息必须输出为 role:"user" + tool_result block
/// - 同一 user 消息中 tool_result 必须排在文本前面
fn message_to_json(
  msg : @lux.LucentMessage,
  diagnostics : Array[@lux.ConversionDiagnostic],
) -> String {
  let is_user_like = match msg.role {
    User | Tool => true
    _ => false
  }
  let role_str = if is_user_like { "user" } else { msg.role.to_string() }
  let blocks : Array[String] = []
  if is_user_like {
    // tool_result 块前置，其余块后置（Claude 顺序硬规则）
    let mut i = 0
    while i < msg.content.length() {
      match msg.content[i] {
        ToolResult(_) => {
          let block = content_to_block(msg.content[i], diagnostics)
          if block != "" {
            blocks.push(block)
          }
        }
        _ => ()
      }
      i = i + 1
    }
    let mut j = 0
    while j < msg.content.length() {
      match msg.content[j] {
        ToolResult(_) => ()
        _ => {
          let block = content_to_block(msg.content[j], diagnostics)
          if block != "" {
            blocks.push(block)
          }
        }
      }
      j = j + 1
    }
  } else {
    let mut k = 0
    while k < msg.content.length() {
      let block = content_to_block(msg.content[k], diagnostics)
      if block != "" {
        blocks.push(block)
      }
      k = k + 1
    }
  }
  "{\"role\":\"" +
  @internal.json_escape(role_str) +
  "\",\"content\":[" +
  blocks.join(",") +
  "]}"
}

///|
/// 内容块数组 → JSON 字符串（用于 tool_result.content）
fn content_array_to_json(
  content : Array[@lux.LucentContent],
  diagnostics : Array[@lux.ConversionDiagnostic],
) -> String {
  let blocks : Array[String] = []
  let mut i = 0
  while i < content.length() {
    let block = content_to_block(content[i], diagnostics)
    if block != "" {
      blocks.push(block)
    }
    i = i + 1
  }
  "[" + blocks.join(",") + "]"
}

///|
/// 2. lux_request_to_messages — 请求编码
pub fn lux_request_to_messages(
  req : @lux.LucentRequest,
) -> Result[@lux.ConversionResult[String], String] {
  let parts : Array[String] = []
  let diagnostics : Array[@lux.ConversionDiagnostic] = []
  parts.push("\"model\":\"" + @internal.json_escape(req.model) + "\"")
  // system 指令（顶层）
  match req.instructions {
    Some(instrs) => {
      let texts : Array[String] = []
      let mut i = 0
      while i < instrs.length() {
        match instrs[i] {
          Text(s, _) => texts.push(s)
          _ => ()
        }
        i = i + 1
      }
      if texts.length() == 1 {
        parts.push("\"system\":\"" + @internal.json_escape(texts[0]) + "\"")
      } else if texts.length() > 1 {
        let blocks : Array[String] = []
        let mut j = 0
        while j < texts.length() {
          blocks.push(
            "{\"type\":\"text\",\"text\":\"" +
            @internal.json_escape(texts[j]) +
            "\"}",
          )
          j = j + 1
        }
        parts.push("\"system\":[" + blocks.join(",") + "]")
      }
    }
    None => ()
  }
  // messages / conversation
  let msgs_json : Array[String] = []
  let items = req.conversation
  let mut i = 0
  while i < items.length() {
    match items[i] {
      Message(m) => msgs_json.push(message_to_json(m, diagnostics))
      ToolCall(tu) =>
        // 独立 ToolCall → assistant 消息含 tool_use（arguments 须为合法 JSON）
        match tool_use_input_fragment(tu, diagnostics) {
          Some(input_frag) =>
            msgs_json.push(
              "{\"role\":\"assistant\",\"content\":[{\"type\":\"tool_use\",\"id\":\"" +
              @internal.json_escape(tu.id) +
              "\",\"name\":\"" +
              @internal.json_escape(tu.name) +
              "\",\"input\":" +
              input_frag +
              "}]}",
            )
          None => ()
        }
      ToolResult(tr) =>
        // ToolResult → user 消息含 tool_result content block
        msgs_json.push(
          "{\"role\":\"user\",\"content\":[{\"type\":\"tool_result\",\"tool_use_id\":\"" +
          @internal.json_escape(tr.tool_use_id) +
          "\",\"content\":" +
          content_array_to_json(tr.content, diagnostics) +
          ",\"is_error\":" +
          (if tr.is_error { "true" } else { "false" }) +
          "}]}",
        )
      Reasoning(th) =>
        // Reasoning → assistant 消息含 thinking block（复用 thinking_to_block）
        msgs_json.push(
          "{\"role\":\"assistant\",\"content\":[" + thinking_to_block(th) + "]}",
        )
      AgentAction(_) => ()
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
        let desc_part = match t.description {
          Some(d) => ",\"description\":\"" + @internal.json_escape(d) + "\""
          None => ""
        }
        match t.kind {
          // custom 工具：name + input_schema（Anthropic 默认无 type 字段）
          Function =>
            tools_json.push(
              "{\"name\":\"" +
              @internal.json_escape(t.name) +
              "\"" +
              desc_part +
              ",\"input_schema\":" +
              t.parameters_json +
              "}",
            )
          CodeExecution =>
            // code_execution_20250522 无 name/schema，只有 type
            tools_json.push("{\"type\":\"code_execution_20250522\"}")
          Shell =>
            tools_json.push(
              "{\"type\":\"bash_20250124\",\"name\":\"" +
              @internal.json_escape(t.name) +
              "\"" +
              desc_part +
              "}",
            )
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
          _ =>
            // Anthropic 无对应原生工具类型：不静默降级为 custom，显式 Unsupported
            diagnostics.push(
              @lux.ConversionDiagnostic::unsupported(
                "tools.kind",
                Some("tool kind not supported by anthropic"),
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
    Some(Auto) => parts.push("\"tool_choice\":{\"type\":\"auto\"}")
    Some(Required) => parts.push("\"tool_choice\":{\"type\":\"any\"}")
    Some(SpecificTool(name)) =>
      parts.push(
        "\"tool_choice\":{\"type\":\"tool\",\"name\":\"" +
        @internal.json_escape(name) +
        "\"}",
      )
    _ => ()
  }
  // options
  let opts = req.options
  match opts.max_output_tokens {
    Some(n) => parts.push("\"max_tokens\":" + n.to_string())
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
  match opts.top_k {
    Some(k) => parts.push("\"top_k\":" + k.to_string())
    None => ()
  }
  // structured output → output_config.format
  match opts.structured_output {
    Some(JsonObject) =>
      parts.push(
        "\"output_config\":{\"format\":{\"type\":\"json_schema\",\"schema\":{}}}",
      )
    Some(JsonSchema(schema)) =>
      parts.push(
        "\"output_config\":{\"format\":{\"type\":\"json_schema\",\"schema\":" +
        schema +
        "}}",
      )
    _ => ()
  }
  match opts.stop {
    Some(arr) => {
      let stops : Array[String] = []
      let mut k = 0
      while k < arr.length() {
        stops.push("\"" + @internal.json_escape(arr[k]) + "\"")
        k = k + 1
      }
      parts.push("\"stop_sequences\":[" + stops.join(",") + "]")
    }
    None => ()
  }
  if opts.stream {
    parts.push("\"stream\":true")
  }
  // reasoning config → thinking
  match req.reasoning {
    Some(rc) =>
      if rc.enabled {
        let budget_part = match rc.budget_tokens {
          Some(n) => ",\"budget_tokens\":" + n.to_string()
          None => ""
        }
        parts.push("\"thinking\":{\"type\":\"enabled\"" + budget_part + "}")
      } else {
        parts.push("\"thinking\":{\"type\":\"disabled\"}")
      }
    None => ()
  }
  // metadata
  match req.metadata {
    Some(meta) => {
      let fields : Array[String] = []
      for entry in meta {
        match entry {
          (k, v) =>
            fields.push(
              "\"" +
              @internal.json_escape(k) +
              "\":\"" +
              @internal.json_escape(v) +
              "\"",
            )
        }
      }
      parts.push("\"metadata\":{" + fields.join(",") + "}")
    }
    None => ()
  }
  // store：Anthropic 无原生 store 字段 → Unsupported 诊断
  match opts.store {
    Some(_) =>
      diagnostics.push(
        @lux.ConversionDiagnostic::unsupported(
          "options.store",
          Some("anthropic has no store field"),
        ),
      )
    None => ()
  }
  // parallel_tool_calls（OpenAI 系）→ disable_parallel_tool_use（语义反向，标准 §2）
  // extras 中透传的 parallel_tool_calls 由本分支消费，不落入输出 JSON。
  let mut merged_extras = opts.extras
  match opts.extras {
    Some(m) =>
      match m.get("parallel_tool_calls") {
        Some(True) => {
          parts.push("\"disable_parallel_tool_use\":true")
          merged_extras = extras_without(opts.extras, "parallel_tool_calls")
        }
        Some(False) => {
          parts.push("\"disable_parallel_tool_use\":false")
          merged_extras = extras_without(opts.extras, "parallel_tool_calls")
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
              "previous_response_id without conversation history cannot be converted to anthropic-messages",
            )
          }
          diagnostics.push(
            @lux.ConversionDiagnostic::unsupported(
              "options.previous_response_id",
              Some("previous_response_id not preserved by anthropic-messages"),
            ),
          )
          merged_extras = extras_without(merged_extras, "previous_response_id")
        }
        None => ()
      }
    None => ()
  }
  // extras：合并进请求 JSON 顶层
  @internal.merge_extras_json(parts, merged_extras)
  let result = @lux.ConversionResult::new("{" + parts.join(",") + "}")
  Ok(result.with_diagnostics(diagnostics))
}
