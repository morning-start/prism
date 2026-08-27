///|
/// Anthropic Messages 适配器 — 对齐 Lux IR v1
///
/// 依据：docs/lux-ir-design.md §10（6-Function 契约）
/// 依据：docs/protocols/03-anthropic-messages.md（协议映射）
///
/// 6 函数：
///   1. messages_to_lux_request      请求解码
///   2. lux_request_to_messages      请求编码
///   3. messages_to_lux_response     响应解码
///   4. lux_response_to_messages     响应编码
///   5. messages_sse_to_events       流解码
///   6. lux_events_to_messages_sse   流编码
///
/// 关键差异（vs OpenAI Chat）：
///   - 无 tool 角色：工具结果由 user 角色发送，内含 tool_result content block
///   - 系统指令：顶层 system 字段，可以是 content block 数组
///   - input 是 JSON 对象（非字符串）：适配层 JSON.stringify(arguments)
///   - input_schema 非 parameters：字段名不同，语义同构
///   - 流式使用 content_block_start/delta/stop 块生命周期（与 Lux IR 同构）
///   - 思考块有 signature 完整性校验，redacted_thinking 表示被隐藏

///|
/// 解析 content block → LucentContent
fn parse_content_block(block : Json) -> Result[@lux.LucentContent, String] {
  match @internal.field_str(block, "type") {
    Some("text") =>
      match @internal.field_str(block, "text") {
        Some(t) => Ok(@lux.LucentContent::text(t))
        None => Err("text block missing 'text' field")
      }
    Some("tool_use") => {
      let id = @internal.field_str(block, "id").unwrap_or("")
      let name = @internal.field_str(block, "name").unwrap_or("")
      // input 是 JSON 对象 → 需 stringify 为 arguments_json
      let args_json = match @internal.obj_get(block, "input") {
        Some(input_jv) => input_jv.stringify()
        None => "{}"
      }
      Ok(@lux.LucentContent::tool_use(id, name, args_json, None))
    }
    Some("tool_result") => {
      let tool_use_id = @internal.field_str(block, "tool_use_id").unwrap_or("")
      let is_error = @internal.field_bool(block, "is_error").unwrap_or(false)
      let content = match @internal.field_arr(block, "content") {
        Some(parts) => {
          let result : Array[@lux.LucentContent] = []
          let mut i = 0
          while i < parts.length() {
            match parse_content_block(parts[i]) {
              Ok(c) => result.push(c)
              Err(_) => ()
            }
            i = i + 1
          }
          result
        }
        None => []
      }
      if is_error {
        Ok(@lux.LucentContent::tool_result_error(tool_use_id, content))
      } else {
        Ok(@lux.LucentContent::tool_result(tool_use_id, content))
      }
    }
    Some("thinking") => {
      let text = @internal.field_str(block, "thinking").unwrap_or("")
      let signature = @internal.field_str(block, "signature")
      Ok(@lux.LucentContent::thinking(text, signature))
    }
    Some("redacted_thinking") => {
      let signature = @internal.field_str(block, "signature")
      Ok(@lux.LucentContent::redacted_thinking(signature))
    }
    Some("image") =>
      // image content block：source 支持 url / base64 两种
      match @internal.obj_get(block, "source") {
        Some(source_jv) =>
          match @internal.field_str(source_jv, "type").unwrap_or("") {
            "url" => {
              let url = @internal.field_str(source_jv, "url").unwrap_or("")
              Ok(
                @lux.LucentContent::image("", @lux.LucentMediaSource::url(url)),
              )
            }
            "base64" => {
              let media_type = @internal.field_str(source_jv, "media_type").unwrap_or(
                "image/png",
              )
              let data = @internal.field_str(source_jv, "data").unwrap_or("")
              Ok(
                @lux.LucentContent::image(
                  media_type,
                  @lux.LucentMediaSource::inline(data),
                ),
              )
            }
            other => Err("image block with unknown source type: " + other)
          }
        None => Err("image block missing 'source' field")
      }
    Some("document") =>
      // document content block（PDF 等文件）：source 支持 url / base64 两种
      match @internal.obj_get(block, "source") {
        Some(source_jv) => {
          let media_type = @internal.field_str(block, "media_type").unwrap_or(
            "application/pdf",
          )
          match @internal.field_str(source_jv, "type").unwrap_or("") {
            "url" => {
              let url = @internal.field_str(source_jv, "url").unwrap_or("")
              Ok(
                @lux.LucentContent::file(
                  media_type,
                  @lux.LucentMediaSource::url(url),
                ),
              )
            }
            "base64" => {
              let data = @internal.field_str(source_jv, "data").unwrap_or("")
              Ok(
                @lux.LucentContent::file(
                  media_type,
                  @lux.LucentMediaSource::inline(data),
                ),
              )
            }
            other => Err("document block with unknown source type: " + other)
          }
        }
        None => Err("document block missing 'source' field")
      }
    Some(other) => Err("unknown content block type: " + other)
    None => Err("content block missing 'type' field")
  }
}

///|
/// 解析单条 Anthropic message → LucentConversationItem
/// 注意：Anthropic 的 user 消息若含 tool_result block，本函数仅提取 tool_result 并
/// 丢弃同消息中的其他 content blocks。这是已知的有损行为（Degraded），
/// 因为 Anthropic 实际使用中 user 消息通常只有一个 tool_result。
/// 若消费方需完整记录，应在外层使用 ConversionDiagnostic 记录该字段丢失。
fn parse_message(msg_jv : Json) -> Result[@lux.LucentConversationItem, String] {
  let role = @internal.field_str(msg_jv, "role")
  match role {
    Some("user") => {
      // 检查是否含 tool_result → 解码为 Item::ToolResult
      let content_arr = match @internal.field_arr(msg_jv, "content") {
        Some(arr) => arr
        None => return Err("message missing content array")
      }
      let has_tool_result = {
        let mut found = false
        let mut i = 0
        while i < content_arr.length() {
          match @internal.field_str(content_arr[i], "type") {
            Some("tool_result") => found = true
            _ => ()
          }
          i = i + 1
        }
        found
      }
      if has_tool_result {
        // 提取 tool_result block
        let mut i = 0
        while i < content_arr.length() {
          match @internal.field_str(content_arr[i], "type") {
            Some("tool_result") =>
              match parse_content_block(content_arr[i]) {
                Ok(tr) =>
                  match tr {
                    ToolResult(tr_data) =>
                      return Ok(
                        @lux.LucentConversationItem::tool_result(tr_data),
                      )
                    _ => ()
                  }
                Err(_) => ()
              }
            _ => ()
          }
          i = i + 1
        }
      }
      // 普通 user 消息：解析所有 content blocks
      let parts = parse_content_blocks(content_arr)
      let msg = @lux.LucentMessage::new(User, parts)
      Ok(@lux.LucentConversationItem::message(msg))
    }
    Some("assistant") => {
      let content_arr = match @internal.field_arr(msg_jv, "content") {
        Some(arr) => arr
        None => return Err("assistant message missing content array")
      }
      let parts = parse_content_blocks(content_arr)
      let msg = @lux.LucentMessage::new(Assistant, parts)
      Ok(@lux.LucentConversationItem::message(msg))
    }
    Some(other) => Err("unknown message role: " + other)
    None => Err("message missing 'role' field")
  }
}

///|
/// 解析 content blocks 数组 → Array[LucentContent]
fn parse_content_blocks(arr : Array[Json]) -> Array[@lux.LucentContent] {
  let result : Array[@lux.LucentContent] = []
  let mut i = 0
  while i < arr.length() {
    match parse_content_block(arr[i]) {
      Ok(c) => result.push(c)
      Err(_) => ()
    }
    i = i + 1
  }
  result
}

///|
/// 解析 system 字段 → Array[LucentContent]
fn parse_system(jv : Json) -> Array[@lux.LucentContent] {
  let result : Array[@lux.LucentContent] = []
  match @internal.obj_get(jv, "system") {
    Some(String(s)) => result.push(@lux.LucentContent::text(s))
    Some(Array(arr)) => {
      let mut i = 0
      while i < arr.length() {
        match @internal.field_str(arr[i], "text") {
          Some(t) => result.push(@lux.LucentContent::text(t))
          None => ()
        }
        i = i + 1
      }
    }
    _ => ()
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
        // Anthropic tools[].type（custom / code_execution_20250522 / bash_20250124）→ kind
        let kind : @lux.LucentToolKind = match @internal.field_str(t, "type") {
          Some("code_execution_20250522") => CodeExecution
          Some("bash_20250124") => Shell
          Some("custom") => Function
          Some(other) => Native(other)
          _ => Function
        }
        let name = @internal.field_str(t, "name").unwrap_or("")
        let desc = @internal.field_str(t, "description")
        // Anthropic 用 input_schema 而非 parameters
        let params = match @internal.obj_get(t, "input_schema") {
          Some(schema) => schema.stringify()
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
/// 解析 tool_choice → LucentToolChoice?
fn parse_tool_choice(jv : Json) -> @lux.LucentToolChoice? {
  match @internal.obj_get(jv, "tool_choice") {
    Some(Object(m)) =>
      match m.get("type") {
        Some(String("auto")) => Some(Auto)
        Some(String("any")) => Some(Required)
        Some(String("tool")) =>
          match m.get("name") {
            Some(String(n)) => Some(SpecificTool(n))
            _ => None
          }
        _ => None
      }
    _ => None
  }
}

///|
/// 解析 thinking 配置 → LucentReasoningConfig?
fn parse_reasoning(jv : Json) -> @lux.LucentReasoningConfig? {
  match @internal.obj_get(jv, "thinking") {
    Some(Object(m)) =>
      match m.get("type") {
        Some(String("enabled")) => {
          let budget = match m.get("budget_tokens") {
            Some(Number(n, ..)) => Some(n.to_int())
            _ => None
          }
          Some(@lux.LucentReasoningConfig::enabled(budget))
        }
        _ => Some(@lux.LucentReasoningConfig::disabled())
      }
    _ => None
  }
}

///|
/// 解析 output_config.format → LucentStructuredOutput（Anthropic 结构化输出）
fn parse_output_config(jv : Json) -> @lux.LucentStructuredOutput? {
  match @internal.obj_get(jv, "output_config") {
    Some(oc) =>
      match @internal.obj_get(oc, "format") {
        Some(fmt) =>
          match @internal.field_str(fmt, "type") {
            Some("json_schema") =>
              match @internal.obj_get(fmt, "schema") {
                Some(schema) => {
                  let s = schema.stringify()
                  if s == "{}" {
                    Some(JsonObject)
                  } else {
                    Some(JsonSchema(s))
                  }
                }
                None => Some(JsonObject)
              }
            Some("text") => Some(Text)
            _ => None
          }
        None => None
      }
    None => None
  }
}

///|
/// 1. messages_to_lux_request — 请求解码
pub fn messages_to_lux_request(
  json_str : String,
) -> Result[@lux.ConversionResult[@lux.LucentRequest], String] {
  let jv = match @internal.parse_protocol_json(json_str) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let model = @internal.field_str(jv, "model").unwrap_or("")
  // system 指令
  let instructions = parse_system(jv)
  let instr_opt = if instructions.length() > 0 {
    Some(instructions)
  } else {
    None
  }
  // messages → conversation
  let conversation : Array[@lux.LucentConversationItem] = []
  match @internal.field_arr(jv, "messages") {
    Some(msgs) => {
      let mut i = 0
      while i < msgs.length() {
        match parse_message(msgs[i]) {
          Ok(item) => conversation.push(item)
          Err(_) => ()
        }
        i = i + 1
      }
    }
    None => ()
  }
  // tools
  let tools_list = parse_tools(jv)
  let tools = if tools_list.length() > 0 { Some(tools_list) } else { None }
  let tool_choice = parse_tool_choice(jv)
  // options
  let temperature = @internal.field_num(jv, "temperature")
  let top_p = @internal.field_num(jv, "top_p")
  let top_k = @internal.field_int(jv, "top_k")
  let max_tokens = @internal.field_int(jv, "max_tokens")
  let stream = @internal.field_bool(jv, "stream").unwrap_or(false)
  let stop = match @internal.field_arr(jv, "stop_sequences") {
    Some(arr) => {
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
    None => None
  }
  // metadata
  let metadata = match @internal.obj_get(jv, "metadata") {
    Some(Object(m)) => {
      let meta : Map[String, String] = Map([])
      for entry in m {
        match entry {
          (k, v) =>
            match v {
              String(s) => meta[k] = s
              _ => ()
            }
        }
      }
      Some(meta)
    }
    _ => None
  }
  let reasoning = parse_reasoning(jv)
  let extras = @internal.collect_extra_fields(jv, [
    "model", "system", "messages", "tools", "tool_choice", "temperature", "top_p",
    "top_k", "max_tokens", "stream", "stop_sequences", "metadata", "thinking", "output_config",
  ])
  let structured_output = parse_output_config(jv)
  let opts = @lux.LucentOptions::new(
    temperature,
    top_p,
    top_k,
    max_tokens,
    stop,
    stream,
    None,
    structured_output,
    None,
    extras,
  )
  Ok(
    @lux.ConversionResult::new(
      @lux.LucentRequest::new(
        model,
        instr_opt,
        conversation,
        tools,
        tool_choice,
        opts,
        None,
        reasoning,
        metadata,
        None,
      ),
    ),
  )
}

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
      "{\"type\":\"tool_use\",\"id\":\"" +
      @internal.json_escape(tu.id) +
      "\",\"name\":\"" +
      @internal.json_escape(tu.name) +
      "\",\"input\":" +
      tu.arguments_json +
      "}"
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
          diagnostics.push(
            @lux.ConversionDiagnostic::unsupported(
              "content.file",
              Some("file_uri file source not supported by anthropic"),
            ),
          )
          ""
        }
      }
    Audio(_) => {
      diagnostics.push(
        @lux.ConversionDiagnostic::unsupported(
          "content.audio",
          Some("audio content not supported by anthropic"),
        ),
      )
      ""
    }
    Video(_) => {
      diagnostics.push(
        @lux.ConversionDiagnostic::unsupported(
          "content.video",
          Some("video content not supported by anthropic"),
        ),
      )
      ""
    }
    Native(tag, _) => {
      diagnostics.push(
        @lux.ConversionDiagnostic::unsupported(
          "content.native",
          Some("native content (" + tag + ") not supported by anthropic"),
        ),
      )
      ""
    }
  }
}

///|
/// LucentMessage → Anthropic message JSON
fn message_to_json(
  msg : @lux.LucentMessage,
  diagnostics : Array[@lux.ConversionDiagnostic],
) -> String {
  let role_str = msg.role.to_string()
  let blocks : Array[String] = []
  let mut i = 0
  while i < msg.content.length() {
    let block = content_to_block(msg.content[i], diagnostics)
    if block != "" {
      blocks.push(block)
    }
    i = i + 1
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
        // 独立 ToolCall → assistant 消息含 tool_use
        msgs_json.push(
          "{\"role\":\"assistant\",\"content\":[{\"type\":\"tool_use\",\"id\":\"" +
          @internal.json_escape(tu.id) +
          "\",\"name\":\"" +
          @internal.json_escape(tu.name) +
          "\",\"input\":" +
          tu.arguments_json +
          "}]}",
        )
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
        // Reasoning → assistant 消息含 thinking block
        if th.redacted {
          msgs_json.push(
            "{\"role\":\"assistant\",\"content\":[{\"type\":\"redacted_thinking\"" +
            (match th.signature {
              Some(s) => ",\"signature\":\"" + @internal.json_escape(s) + "\""
              None => ""
            }) +
            "}]}",
          )
        } else {
          msgs_json.push(
            "{\"role\":\"assistant\",\"content\":[{\"type\":\"thinking\",\"thinking\":\"" +
            @internal.json_escape(th.text) +
            "\"" +
            (match th.signature {
              Some(s) => ",\"signature\":\"" + @internal.json_escape(s) + "\""
              None => ""
            }) +
            "}]}",
          )
        }
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
        "}",
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
  // extras：合并进请求 JSON 顶层
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
/// 3. messages_to_lux_response — 响应解码
pub fn messages_to_lux_response(
  json_str : String,
) -> Result[@lux.ConversionResult[@lux.LucentResponse], String] {
  let jv = match @internal.parse_protocol_json(json_str) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let id = @internal.field_str(jv, "id").unwrap_or("")
  let model = @internal.field_str(jv, "model").unwrap_or("")
  // content blocks → assistant message content
  let content = match @internal.field_arr(jv, "content") {
    Some(blocks) => parse_content_blocks(blocks)
    None => []
  }
  let msg = @lux.LucentMessage::new(Assistant, content)
  // stop_reason → finish_reason
  let finish = match @internal.field_str(jv, "stop_reason") {
    Some("end_turn") => @lux.Stop
    Some("max_tokens") => Length
    Some("tool_use") => ToolCalls
    Some("stop_sequence") => Stop
    Some(other) => @lux.LucentFinishReason::from_string(other)
    None => Stop
  }
  let choice = @lux.LucentChoice::new(0, msg, finish, None)
  // usage（cached_tokens / cache_creation_tokens 可选，暂不传）
  let usage = match @internal.obj_get(jv, "usage") {
    Some(u) => {
      let pt = @internal.field_int(u, "input_tokens").unwrap_or(0)
      let ct = @internal.field_int(u, "output_tokens").unwrap_or(0)
      let tt = pt + ct
      Some(@lux.LucentUsage::new(pt, ct, tt))
    }
    None => None
  }
  Ok(
    @lux.ConversionResult::new(
      @lux.LucentResponse::new(id, model, None, [choice], usage, None),
    ),
  )
}

///|
/// 4. lux_response_to_messages — 响应编码
pub fn lux_response_to_messages(
  resp : @lux.LucentResponse,
) -> Result[@lux.ConversionResult[String], String] {
  if resp.choices.length() == 0 {
    return Err("response has no choices")
  }
  let diagnostics : Array[@lux.ConversionDiagnostic] = []
  let choice = resp.choices[0]
  // content blocks
  let content_blocks : Array[String] = []
  // 消息级 reasoning 优先（vLLM/DeepSeek 入站 → IR → Anthropic 出站），前置为 thinking block
  match choice.message.reasoning {
    Some(th) => content_blocks.push(thinking_to_block(th))
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
    let block = content_to_block(choice.message.content[i], diagnostics)
    if block != "" {
      content_blocks.push(block)
    }
    i = i + 1
  }
  let content_json = "[" + content_blocks.join(",") + "]"
  // stop_reason
  let stop_reason = match choice.finish_reason {
    Stop => "\"end_turn\""
    Length => "\"max_tokens\""
    ToolCalls => "\"tool_use\""
    ContentFilter => "\"content_filter\""
    Safety => "\"end_turn\""
    Recitation => "\"end_turn\""
    MalformedToolCall => "\"end_turn\""
    Error => "\"end_turn\""
    Native(s) => "\"" + @internal.json_escape(s) + "\""
  }
  // usage
  let usage_json = match resp.usage {
    Some(u) =>
      ",\"usage\":{\"input_tokens\":" +
      u.prompt_tokens.to_string() +
      ",\"output_tokens\":" +
      u.completion_tokens.to_string() +
      "}"
    None => ""
  }
  let body = "{\"id\":\"" +
    @internal.json_escape(resp.id) +
    "\",\"type\":\"message\",\"role\":\"assistant\",\"model\":\"" +
    @internal.json_escape(resp.model) +
    "\",\"content\":" +
    content_json +
    ",\"stop_reason\":" +
    stop_reason +
    ",\"stop_sequence\":null" +
    usage_json +
    "}"
  let result = @lux.ConversionResult::new(body)
  Ok(result.with_diagnostics(diagnostics))
}

///|
/// 5. messages_sse_to_events — 流解码
///
/// Anthropic SSE 格式：
///   event: X
///   data: {...}
///
/// 用 \n\n 分隔 SSE 消息，再逐条解析 event/data 行
pub fn messages_sse_to_events(
  sse_str : String,
) -> Result[@lux.ConversionResult[Array[@lux.LucentStreamEvent]], String] {
  let events : Array[@lux.LucentStreamEvent] = []
  let messages = sse_str.split("\n\n").to_array()
  let mut i = 0
  while i < messages.length() {
    let msg = messages[i].to_owned()
    if msg == "" {
      i = i + 1
      continue
    }
    let lines = msg.split("\n").to_array()
    let mut event_type = ""
    let mut data_str = ""
    let mut j = 0
    while j < lines.length() {
      let l_str = lines[j].to_owned()
      // 跳过注释行（以 : 开头，如心跳 : keep-alive）
      if l_str.length() > 0 && l_str[0] == ':' {
        j = j + 1
        continue
      }
      // 检查 "event: " 前缀（前 7 个字符）
      let is_event = l_str.length() >= 7 &&
        l_str[0] == 'e' &&
        l_str[1] == 'v' &&
        l_str[2] == 'e' &&
        l_str[3] == 'n' &&
        l_str[4] == 't' &&
        l_str[5] == ':' &&
        l_str[6] == ' '
      // 检查 "data: " 前缀（前 6 个字符，含空格）
      let is_data = l_str.length() >= 6 &&
        l_str[0] == 'd' &&
        l_str[1] == 'a' &&
        l_str[2] == 't' &&
        l_str[3] == 'a' &&
        l_str[4] == ':' &&
        l_str[5] == ' '
      if is_event {
        // 提取 "event: " 后的内容（从第 7 个字符开始）
        event_type = ""
        let mut k = 7
        while k < l_str.length() {
          let ch = Int::unsafe_to_char(l_str[k].to_int())
          event_type = event_type + "\{ch}"
          k = k + 1
        }
      } else if is_data {
        // 提取 "data: " 后的内容（从第 6 个字符开始）
        data_str = ""
        let mut k = 6
        while k < l_str.length() {
          let ch = Int::unsafe_to_char(l_str[k].to_int())
          data_str = data_str + "\{ch}"
          k = k + 1
        }
      }
      j = j + 1
    }
    data_str = data_str.trim().to_owned()
    if data_str == "" {
      i = i + 1
      continue
    }
    // 清理 SSE 心跳标记（如 : keep-alive）
    data_str = @internal.clean_sse_heartbeat(data_str)
    // 检测截断的 JSON（字符串未闭合、括号不匹配）
    if @internal.is_json_truncated(data_str) {
      // 截断的事件，跳过
      i = i + 1
      continue
    }
    // 清理无效转义序列（某些 API 可能包含非标准转义）
    data_str = @internal.sanitize_json_escapes(data_str)
    let jv = @json.parse(data_str) catch {
      _ => {
        i = i + 1
        continue
      }
    }
    match event_type {
      "message_start" =>
        match @internal.obj_get(jv, "message") {
          Some(msg_jv) => {
            let id = @internal.field_str(msg_jv, "id")
            let model = @internal.field_str(msg_jv, "model")
            let usage_input = match @internal.obj_get(msg_jv, "usage") {
              Some(u) => @internal.field_int(u, "input_tokens")
              None => None
            }
            events.push(
              ConversationStart(
                @lux.LucentConversationMeta::new(id, model, usage_input),
              ),
            )
          }
          None => ()
        }
      "content_block_start" => {
        let idx = @internal.field_int(jv, "index").unwrap_or(0)
        match @internal.obj_get(jv, "content_block") {
          Some(block) =>
            match @internal.field_str(block, "type") {
              Some("text") => events.push(BlockStart(idx, Text))
              Some("thinking") => events.push(BlockStart(idx, Thinking))
              Some("tool_use") => {
                let tc_id = @internal.field_str(block, "id").unwrap_or("")
                let tc_name = @internal.field_str(block, "name").unwrap_or("")
                events.push(
                  BlockStart(
                    idx,
                    @lux.LucentBlockType::tool_call(tc_id, tc_name),
                  ),
                )
              }
              _ => ()
            }
          None => ()
        }
      }
      "content_block_delta" => {
        let idx = @internal.field_int(jv, "index").unwrap_or(0)
        match @internal.obj_get(jv, "delta") {
          Some(delta) =>
            match @internal.field_str(delta, "type") {
              Some("text_delta") =>
                match @internal.field_str(delta, "text") {
                  Some(t) =>
                    events.push(
                      BlockDelta(idx, @lux.LucentBlockDelta::text_delta(t)),
                    )
                  None => ()
                }
              Some("thinking_delta") =>
                match @internal.field_str(delta, "thinking") {
                  Some(t) =>
                    events.push(
                      BlockDelta(idx, @lux.LucentBlockDelta::thinking_delta(t)),
                    )
                  None => ()
                }
              Some("signature_delta") =>
                match @internal.field_str(delta, "signature") {
                  Some(s) =>
                    events.push(
                      BlockDelta(idx, @lux.LucentBlockDelta::signature_delta(s)),
                    )
                  None => ()
                }
              Some("input_json_delta") =>
                match @internal.field_str(delta, "partial_json") {
                  Some(j_str) =>
                    events.push(
                      BlockDelta(
                        idx,
                        @lux.LucentBlockDelta::tool_arguments_delta(j_str),
                      ),
                    )
                  None => ()
                }
              _ => ()
            }
          None => ()
        }
      }
      "content_block_stop" => {
        let idx = @internal.field_int(jv, "index").unwrap_or(0)
        events.push(BlockEnd(idx))
      }
      "message_delta" => {
        match @internal.obj_get(jv, "delta") {
          Some(delta) =>
            match @internal.field_str(delta, "stop_reason") {
              Some(reason) =>
                events.push(
                  Finish(@lux.LucentFinishReason::from_string(reason)),
                )
              None => ()
            }
          None => ()
        }
        match @internal.obj_get(jv, "usage") {
          Some(u) => {
            let ot = @internal.field_int(u, "output_tokens").unwrap_or(0)
            events.push(Usage(@lux.LucentUsage::new(0, ot, ot)))
          }
          None => ()
        }
      }
      "message_stop" => events.push(Done)
      "error" =>
        match @internal.field_str(jv, "error") {
          Some(e_msg) => events.push(Error(@lux.LucentError::simple(e_msg)))
          None => ()
        }
      _ => ()
    }
    i = i + 1
  }
  Ok(@lux.ConversionResult::new(events))
}

///|
/// 6. lux_events_to_messages_sse — 流编码
///
/// 把 Lux 事件流编码为 Anthropic SSE 格式（同 chromic_sse_to_events 的逆过程）
pub fn lux_events_to_messages_sse(
  events : Array[@lux.LucentStreamEvent],
) -> Result[@lux.ConversionResult[String], String] {
  let lines : Array[String] = []
  let mut i = 0
  while i < events.length() {
    match events[i] {
      ConversationStart(meta) => {
        let mut fields = "\"type\":\"message_start\""
        match meta.id {
          Some(id) =>
            fields = fields + ",\"id\":\"" + @internal.json_escape(id) + "\""
          None => ()
        }
        match meta.model {
          Some(m) =>
            fields = fields + ",\"model\":\"" + @internal.json_escape(m) + "\""
          None => ()
        }
        match meta.usage_input {
          Some(n) =>
            fields = fields +
              ",\"usage\":{\"input_tokens\":" +
              n.to_string() +
              "}"
          None => ()
        }
        lines.push(
          "event: message_start\ndata: {\"type\":\"message_start\",\"message\":{" +
          fields +
          "}}",
        )
      }
      ItemStart(_, _) | ItemEnd(_) | BlockDiscard(_) | Annotations(_, _) => ()
      BlockStart(idx, bt) => {
        let block_json = match bt {
          Text => "{\"type\":\"text\",\"text\":\"\"}"
          Thinking => "{\"type\":\"thinking\",\"thinking\":\"\"}"
          ToolCall(id, name) =>
            "{\"type\":\"tool_use\",\"id\":\"" +
            @internal.json_escape(id) +
            "\",\"name\":\"" +
            @internal.json_escape(name) +
            "\",\"input\":{}}"
          Refusal => "{\"type\":\"text\",\"text\":\"\"}"
          Image | Audio | Video => "{\"type\":\"text\",\"text\":\"\"}"
          Native(tag) => "{\"type\":\"" + @internal.json_escape(tag) + "\"}"
        }
        lines.push(
          "event: content_block_start\ndata: {\"type\":\"content_block_start\",\"index\":" +
          idx.to_string() +
          ",\"content_block\":" +
          block_json +
          "}",
        )
      }
      BlockDelta(idx, delta) => {
        let delta_json = match delta {
          TextDelta(s) =>
            "{\"type\":\"text_delta\",\"text\":\"" +
            @internal.json_escape(s) +
            "\"}"
          ThinkingDelta(s) =>
            "{\"type\":\"thinking_delta\",\"thinking\":\"" +
            @internal.json_escape(s) +
            "\"}"
          SignatureDelta(s) =>
            "{\"type\":\"signature_delta\",\"signature\":\"" +
            @internal.json_escape(s) +
            "\"}"
          ToolArgumentsDelta(s) =>
            "{\"type\":\"input_json_delta\",\"partial_json\":\"" +
            @internal.json_escape(s) +
            "\"}"
          RefusalDelta(s) =>
            "{\"type\":\"text_delta\",\"text\":\"" +
            @internal.json_escape(s) +
            "\"}"
          NativeDelta(tag, _) =>
            "{\"type\":\"" + @internal.json_escape(tag) + "\"}"
        }
        lines.push(
          "event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":" +
          idx.to_string() +
          ",\"delta\":" +
          delta_json +
          "}",
        )
      }
      BlockEnd(idx) =>
        lines.push(
          "event: content_block_stop\ndata: {\"type\":\"content_block_stop\",\"index\":" +
          idx.to_string() +
          "}",
        )
      Finish(fr) =>
        lines.push(
          "event: message_delta\ndata: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"" +
          @internal.json_escape(fr.to_string()) +
          "\"}}",
        )
      Usage(u) =>
        lines.push(
          "event: message_delta\ndata: {\"type\":\"message_delta\",\"usage\":{\"output_tokens\":" +
          u.completion_tokens.to_string() +
          "}}",
        )
      Error(e) =>
        lines.push(
          "event: error\ndata: {\"type\":\"error\",\"error\":{\"message\":\"" +
          @internal.json_escape(e.message) +
          "\"}}",
        )
      Done =>
        lines.push("event: message_stop\ndata: {\"type\":\"message_stop\"}")
    }
    i = i + 1
  }
  Ok(@lux.ConversionResult::new(lines.join("\n\n") + "\n\n"))
}

///|
/// capability — 适配器能力声明
pub fn capability() -> @lux.ProviderCapability {
  @lux.ProviderCapability::new(
    "claude-*",
    "messages",
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
