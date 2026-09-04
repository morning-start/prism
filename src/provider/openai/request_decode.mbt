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
  if data == "" {
    None
  } else {
    Some((media_type, data))
  }
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
                Some(
                  @lux.LucentContent::image(
                    media_type,
                    @lux.LucentMediaSource::inline(data),
                  ),
                )
              None =>
                Some(
                  @lux.LucentContent::image(
                    "image/png",
                    @lux.LucentMediaSource::url(u),
                  ),
                )
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
  // reasoning_effort 非常规档位的降级诊断标志
  let mut push_degraded = false
  let mut ignored_effort : String? = None
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
  let stop = @internal.parse_string_array(jv, "stop")
  let store = @internal.field_bool(jv, "store")
  // reasoning_effort → IR reasoning.effort（o-series / gpt-5 推理控制）
  // "minimal" 在 IR 无对等档位 → 降级为 Low + 诊断（IR 演进项：补 Minimal）
  let reasoning_effort : @lux.LucentReasoningEffort? = match
    @internal.field_str(jv, "reasoning_effort") {
    Some("low") => Some(Low)
    Some("medium") => Some(Medium)
    Some("high") => Some(High)
    Some("xhigh") => Some(XHigh)
    Some("minimal") => {
      push_degraded = true
      Some(Low)
    }
    Some(other) => {
      push_degraded = true
      ignored_effort = Some(other)
      None
    }
    None => None
  }
  let reasoning : @lux.LucentReasoningConfig? = match reasoning_effort {
    Some(effort) => Some(@lux.LucentReasoningConfig::new(Some(effort), None))
    None => None
  }
  let extras = @internal.collect_extra_fields(jv, [
    "model", "messages", "tools", "tool_choice", "temperature", "top_p", "max_completion_tokens",
    "max_tokens", "stream", "stop", "response_format", "store", "reasoning_effort",
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
  // 诊断组装：reasoning_effort 降级信息
  let diagnostics : Array[@lux.ConversionDiagnostic] = []
  if push_degraded {
    diagnostics.push(
      @lux.ConversionDiagnostic::degraded(
        "reasoning_effort",
        Some(
          "reasoning_effort \"minimal\" downgraded to Low (lux-ir v1 has no Minimal)",
        ),
      ),
    )
  }
  match ignored_effort {
    Some(v) =>
      diagnostics.push(
        @lux.ConversionDiagnostic::degraded(
          "reasoning_effort",
          Some("unknown reasoning_effort \"" + v + "\" ignored"),
        ),
      )
    None => ()
  }
  let result = @lux.ConversionResult::new(
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
      reasoning,
      None,
      None,
    ),
  )
  Ok(result.with_diagnostics(diagnostics))
}

///|
