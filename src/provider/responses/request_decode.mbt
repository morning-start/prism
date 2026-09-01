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
      // encrypted_content（include: ["reasoning.encrypted_content"] 的无状态推理延续凭证）
      // IR LucentThinking v1 无载体 → 显式 Degraded 诊断，不静默丢弃。
      // IR 演进项：为 Reasoning item 增加 provider 续传凭证旁路（见 IR 治理清单）。
      let encrypted = @internal.field_str(item, "encrypted_content")
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
      if encrypted != None {
        diagnostics.push(
          @lux.ConversionDiagnostic::degraded(
            "input.reasoning.encrypted_content",
            Some(
              "encrypted_content (stateless reasoning continuation) not preserved by lux-ir v1",
            ),
          ),
        )
      }
      Some(@lux.LucentConversationItem::reasoning(th))
    }
    _ =>
      // 无 type 字段：某些客户端省略 type，默认当作 message 处理
      match @internal.field_str(item, "role") {
        Some(role_str) => {
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
                  _ => ()
                }
                i = i + 1
              }
              result
            }
            None =>
              // content 也可能是字符串
              match @internal.field_str(item, "content") {
                Some(s) => [@lux.LucentContent::text(s)]
                None => []
              }
          }
          Some(
            @lux.LucentConversationItem::message(
              @lux.LucentMessage::new(role, content),
            ),
          )
        }
        None => None
      }
  }
}

///|
/// 解析 input → Array[LucentConversationItem]
///
/// Responses API 的 input 字段有两种形态：
///   - string → 单个用户消息（简化格式）
///   - array  → Item 数组（标准格式）
fn parse_input(
  jv : Json,
  diagnostics : Array[@lux.ConversionDiagnostic],
) -> Array[@lux.LucentConversationItem] {
  let result : Array[@lux.LucentConversationItem] = []
  match @internal.obj_get(jv, "input") {
    Some(String(s)) =>
      // 简化格式：input 为字符串 → 包装为单条 user 消息
      result.push(
        @lux.LucentConversationItem::message(
          @lux.LucentMessage::new(User, [@lux.LucentContent::text(s)]),
        ),
      )
    Some(Array(items)) => {
      let mut i = 0
      while i < items.length() {
        match parse_input_item(items[i], diagnostics) {
          Some(item) => result.push(item)
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
      @lux.push_unsupported(
        "reasoning.config", "reasoning config not parsed by openai-responses", diagnostics,
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
/// 1. responses_to_lux_request — 请求解码
pub fn responses_to_lux_request(
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
    "max_output_tokens", "stream", "reasoning", "text", "store",
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
  // previous_response_id 保留在 extras 中（不再静默丢弃）：
  // - responses → responses 原样透传（merge_extras）
  // - responses → chat/messages 出站时由目标端编码器拒绝或降级（标准 §3.2）
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
      None,
    ),
  )
  Ok(result.with_diagnostics(diagnostics))
}

///|
