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
