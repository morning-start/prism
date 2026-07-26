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
/// === JSON 辅助（私有）===

///|
fn obj_get(jv : Json, key : String) -> Json? {
  match jv {
    Object(m) => {
      for entry in m {
        match entry {
          (k, v) => if k == key { return Some(v) }
        }
      }
      None
    }
    _ => None
  }
}

///|
fn field_str(jv : Json, key : String) -> String? {
  match obj_get(jv, key) {
    Some(String(s)) => Some(s)
    _ => None
  }
}

///|
fn field_arr(jv : Json, key : String) -> Array[Json]? {
  match obj_get(jv, key) {
    Some(Array(a)) => Some(a)
    _ => None
  }
}

///|
fn field_bool(jv : Json, key : String) -> Bool? {
  match obj_get(jv, key) {
    Some(True) => Some(true)
    Some(False) => Some(false)
    _ => None
  }
}

///|
fn field_num(jv : Json, key : String) -> Double? {
  match obj_get(jv, key) {
    Some(Number(n, ..)) => Some(n)
    _ => None
  }
}

///|
fn field_int(jv : Json, key : String) -> Int? {
  match obj_get(jv, key) {
    Some(Number(n, ..)) => Some(n.to_int())
    _ => None
  }
}

///|
/// JSON 字符串转义
fn json_escape(s : String) -> String {
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
      let ch = Char::from_int(cp.to_int())
      r = r + "\{ch}"
    }
    i = i + 1
  }
  r
}

///|
/// 解析 input Item → LucentConversationItem
fn parse_input_item(item : Json) -> @lux.LucentConversationItem? {
  match field_str(item, "type") {
    Some("message") => {
      let role_str = field_str(item, "role").unwrap_or("user")
      let role = match role_str {
        "user" => @lux.User
        "assistant" => @lux.Assistant
        "developer" => @lux.Developer
        _ => @lux.User
      }
      let content = match field_arr(item, "content") {
        Some(parts) => {
          let result : Array[@lux.LucentContent] = []
          let mut i = 0
          while i < parts.length() {
            match field_str(parts[i], "type") {
              Some("input_text") =>
                match field_str(parts[i], "text") {
                  Some(t) => result.push(@lux.LucentContent::text(t))
                  None => ()
                }
              Some("input_image") => () // stub
              Some("input_file") => () // stub
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
      let id = field_str(item, "id").unwrap_or("")
      let name = field_str(item, "name").unwrap_or("")
      let args = field_str(item, "arguments").unwrap_or("{}")
      let tu = @lux.LucentToolUse::new(id, name, args, None)
      Some(@lux.LucentConversationItem::tool_call(tu))
    }
    Some("function_call_output") => {
      let call_id = field_str(item, "call_id").unwrap_or("")
      let output = field_str(item, "output").unwrap_or("")
      let tr = @lux.LucentToolResult::ok(call_id, [
        @lux.LucentContent::text(output),
      ])
      Some(@lux.LucentConversationItem::tool_result(tr))
    }
    Some("reasoning") => {
      let summary = match field_arr(item, "summary") {
        Some(arr) => {
          let texts : Array[@lux.LucentContent] = []
          let mut i = 0
          while i < arr.length() {
            match field_str(arr[i], "text") {
              Some(t) => texts.push(@lux.LucentContent::text(t))
              None => ()
            }
            i = i + 1
          }
          Some(texts)
        }
        None => None
      }
      let signature = field_str(item, "signature")
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
fn parse_input(jv : Json) -> Array[@lux.LucentConversationItem] {
  let result : Array[@lux.LucentConversationItem] = []
  match field_arr(jv, "input") {
    Some(items) => {
      let mut i = 0
      while i < items.length() {
        match parse_input_item(items[i]) {
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
  match field_arr(jv, "tools") {
    Some(tools) => {
      let result : Array[@lux.LucentTool] = []
      let mut i = 0
      while i < tools.length() {
        let t = tools[i]
        let name = field_str(t, "name").unwrap_or("")
        let desc = field_str(t, "description")
        let params = match obj_get(t, "parameters") {
          Some(p) => p.stringify()
          None => "{}"
        }
        result.push(@lux.LucentTool::new(name, desc, params, None, None))
        i = i + 1
      }
      result
    }
    None => []
  }
}

///|
/// 解析 reasoning 配置
fn parse_reasoning(jv : Json) -> @lux.LucentReasoningConfig? {
  match obj_get(jv, "reasoning") {
    _ => None
  }
}

///|
/// 解析 text.format → LucentStructuredOutput
fn parse_text_format(jv : Json) -> @lux.LucentStructuredOutput? {
  match obj_get(jv, "text") {
    Some(obj) =>
      match obj_get(obj, "format") {
        Some(fmt) =>
          match field_str(fmt, "type") {
            Some("text") => Some(@lux.Text)
            Some("json_object") => Some(@lux.JsonObject)
            Some("json_schema") =>
              match obj_get(fmt, "schema") {
                Some(s) =>
                  Some(@lux.LucentStructuredOutput::JsonSchema(s.stringify()))
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
) -> Result[@lux.LucentRequest, String] {
  let jv = @json.parse(json_str) catch { _ => return Err("json parse error") }
  let model = field_str(jv, "model").unwrap_or("")
  let instructions = match field_str(jv, "instructions") {
    Some(s) => Some([@lux.LucentContent::text(s)])
    None => None
  }
  let conversation = parse_input(jv)
  let tools_list = parse_tools(jv)
  let tools = if tools_list.length() > 0 { Some(tools_list) } else { None }
  let tool_choice = match field_str(jv, "tool_choice") {
    Some("auto") => Some(@lux.LucentToolChoice::Auto)
    Some("none") => Some(@lux.None)
    Some("required") => Some(@lux.Required)
    _ => None
  }
  let temperature = field_num(jv, "temperature")
  let top_p = field_num(jv, "top_p")
  let max_tokens = field_int(jv, "max_output_tokens")
  let stream = field_bool(jv, "stream").unwrap_or(false)
  let reasoning = parse_reasoning(jv)
  let structured = parse_text_format(jv)
  let opts = @lux.LucentOptions::new(
    temperature,
    top_p,
    None,
    max_tokens,
    None,
    stream,
    None,
    None,
    structured,
    None,
    None,
  )
  // metadata: previous_response_id → extra
  let extra = match field_str(jv, "previous_response_id") {
    Some(_id) => None // previous_response_id → metadata, skip extra for now
    None => None
  }
  Ok(
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
}

///|
/// 2. lux_request_to_openai_responses — 请求编码
pub fn lux_request_to_openai_responses(
  req : @lux.LucentRequest,
) -> Result[String, String] {
  let parts : Array[String] = []
  parts.push("\"model\":\"" + json_escape(req.model) + "\"")
  // instructions
  match req.instructions {
    Some(instrs) => {
      let text = @lux.lucent_content_to_text(instrs)
      if text != "" {
        parts.push("\"instructions\":\"" + json_escape(text) + "\"")
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
                "{\"type\":\"input_text\",\"text\":\"" + json_escape(s) + "\"}",
              )
            Image(_) => () // stub
            _ => ()
          }
          j = j + 1
        }
        items.push(
          "{\"type\":\"message\",\"role\":\"" +
          json_escape(role_str) +
          "\",\"content\":[" +
          content_parts.join(",") +
          "]}",
        )
      }
      ToolCall(tu) =>
        items.push(
          "{\"type\":\"function_call\",\"id\":\"" +
          json_escape(tu.id) +
          "\",\"call_id\":\"" +
          json_escape(tu.id) +
          "\",\"name\":\"" +
          json_escape(tu.name) +
          "\",\"arguments\":\"" +
          json_escape(tu.arguments_json) +
          "\"}",
        )
      ToolResult(tr) =>
        items.push(
          "{\"type\":\"function_call_output\",\"call_id\":\"" +
          json_escape(tr.tool_use_id) +
          "\",\"output\":\"" +
          json_escape(@lux.lucent_content_to_text(tr.content)) +
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
                    json_escape(t) +
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
            r_item = r_item + ",\"signature\":\"" + json_escape(s) + "\""
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
          Some(d) => ",\"description\":\"" + json_escape(d) + "\""
          None => ""
        }
        tools_json.push(
          "{\"type\":\"function\",\"name\":\"" +
          json_escape(t.name) +
          "\"" +
          desc_part +
          ",\"parameters\":" +
          t.parameters_json +
          "}",
        )
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
          Some(Low) => rf = ",\"effort\":\"low\""
          Some(Medium) => rf = ",\"effort\":\"medium\""
          Some(High) => rf = ",\"effort\":\"high\""
          Some(XHigh) => rf = ",\"effort\":\"xhigh\""
          None => ()
        }
        match rc.summary {
          Some(Auto) => rf = rf + ",\"summary\":\"auto\""
          Some(Concise) => rf = rf + ",\"summary\":\"concise\""
          Some(Detailed) => rf = rf + ",\"summary\":\"detailed\""
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
  Ok("{" + parts.join(",") + "}")
}

///|
/// 解析 output Item 为 LucentContent[]
fn parse_output_content(output_item : Json) -> Array[@lux.LucentContent] {
  match field_str(output_item, "type") {
    Some("message") => {
      let content = match field_arr(output_item, "content") {
        Some(parts) => {
          let result : Array[@lux.LucentContent] = []
          let mut i = 0
          while i < parts.length() {
            match field_str(parts[i], "type") {
              Some("output_text") =>
                match field_str(parts[i], "text") {
                  Some(t) => result.push(@lux.LucentContent::text(t))
                  None => ()
                }
              Some("refusal") =>
                match field_str(parts[i], "text") {
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
      let id = field_str(output_item, "id").unwrap_or("")
      let name = field_str(output_item, "name").unwrap_or("")
      let args = field_str(output_item, "arguments").unwrap_or("{}")
      [@lux.LucentContent::tool_use(id, name, args, None)]
    }
    Some("reasoning") => {
      let summary = match field_arr(output_item, "summary") {
        Some(arr) => {
          let texts : Array[@lux.LucentContent] = []
          let mut i = 0
          while i < arr.length() {
            match field_str(arr[i], "text") {
              Some(t) => texts.push(@lux.LucentContent::text(t))
              None => ()
            }
            i = i + 1
          }
          Some(texts)
        }
        None => None
      }
      let signature = field_str(output_item, "signature")
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
) -> Result[@lux.LucentResponse, String] {
  let jv = @json.parse(json_str) catch { _ => return Err("json parse error") }
  let id = field_str(jv, "id").unwrap_or("")
  let model = field_str(jv, "model").unwrap_or("")
  let created = field_int(jv, "created_at")
  // output items → choices[0].message.content
  let content : Array[@lux.LucentContent] = []
  match field_arr(jv, "output") {
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
  let msg = @lux.LucentMessage::new(@lux.Assistant, content)
  let finish = match field_str(jv, "status") {
    Some("completed") => @lux.Stop
    Some("incomplete") => @lux.Length
    Some("failed") => @lux.Error
    Some(other) => @lux.LucentFinishReason::from_string(other)
    None => @lux.Stop
  }
  let choice = @lux.LucentChoice::new(0, msg, finish, None)
  // usage
  let usage = match obj_get(jv, "usage") {
    Some(u) => {
      let pt = field_int(u, "input_tokens").unwrap_or(0)
      let ct = field_int(u, "output_tokens").unwrap_or(0)
      let tt = field_int(u, "total_tokens").unwrap_or(pt + ct)
      @lux.LucentUsage::new(pt, ct, tt)
    }
    None => @lux.LucentUsage::new(0, 0, 0)
  }
  Ok(@lux.LucentResponse::new(id, model, created, [choice], Some(usage), None))
}

///|
/// 4. lux_response_to_openai_responses — 响应编码
pub fn lux_response_to_openai_responses(
  resp : @lux.LucentResponse,
) -> Result[String, String] {
  if resp.choices.length() == 0 {
    return Err("response has no choices")
  }
  let choice = resp.choices[0]
  // build output items
  let output_items : Array[String] = []
  let mut i = 0
  while i < choice.message.content.length() {
    match choice.message.content[i] {
      Text(s, _) =>
        output_items.push(
          "{\"type\":\"message\",\"id\":\"msg_" +
          i.to_string() +
          "\",\"role\":\"assistant\",\"status\":\"completed\",\"content\":[" +
          "{\"type\":\"output_text\",\"text\":\"" +
          json_escape(s) +
          "\",\"annotations\":[]}]}",
        )
      ToolUse(tu) =>
        output_items.push(
          "{\"type\":\"function_call\",\"id\":\"" +
          json_escape(tu.id) +
          "\",\"call_id\":\"call_" +
          json_escape(tu.id) +
          "\",\"name\":\"" +
          json_escape(tu.name) +
          "\",\"arguments\":\"" +
          json_escape(tu.arguments_json) +
          "\",\"status\":\"completed\"}",
        )
      Thinking(th) => {
        let summary = match th.summary {
          Some(arr) => {
            let parts : Array[String] = []
            let mut k = 0
            while k < arr.length() {
              match arr[k] {
                Text(t, _) =>
                  parts.push(
                    "{\"type\":\"summary_text\",\"text\":\"" +
                    json_escape(t) +
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
          Some(s) => ",\"signature\":\"" + json_escape(s) + "\""
          None => ""
        }
        output_items.push(
          "{\"type\":\"reasoning\",\"id\":\"rs_" +
          i.to_string() +
          "\"" +
          summary +
          sig_part +
          "}",
        )
      }
      Refusal(s) =>
        output_items.push(
          "{\"type\":\"message\",\"id\":\"ref_" +
          i.to_string() +
          "\",\"role\":\"assistant\",\"status\":\"completed\",\"content\":[" +
          "{\"type\":\"refusal\",\"refusal\":\"" +
          json_escape(s) +
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
    json_escape(resp.id) +
    "\",\"object\":\"response\"" +
    created_part +
    ",\"status\":" +
    status_str +
    ",\"model\":\"" +
    json_escape(resp.model) +
    "\",\"output\":[" +
    output_items.join(",") +
    "]" +
    usage_json +
    "}"
  Ok(body)
}

///|
/// 5. openai_responses_sse_to_events — 流解码
pub fn openai_responses_sse_to_events(
  sse_str : String,
) -> Result[Array[@lux.LucentStreamEvent], String] {
  let events : Array[@lux.LucentStreamEvent] = []
  let messages = sse_str.split("\n\n").to_array()
  let mut event_type = ""
  let mut i = 0
  while i < messages.length() {
    let msg = messages[i].to_owned()
    if msg == "" {
      i = i + 1
      continue
    }
    let lines = msg.split("\n").to_array()
    let mut data_str = ""
    let mut j = 0
    while j < lines.length() {
      let l_str = lines[j].to_owned()
      let is_event = l_str.length() >= 7 &&
        l_str[0] == 'e' &&
        l_str[1] == 'v' &&
        l_str[2] == 'e' &&
        l_str[3] == 'n' &&
        l_str[4] == 't' &&
        l_str[5] == ':' &&
        l_str[6] == ' '
      let is_data = l_str.length() >= 6 &&
        l_str[0] == 'd' &&
        l_str[1] == 'a' &&
        l_str[2] == 't' &&
        l_str[3] == 'a' &&
        l_str[4] == ':' &&
        l_str[5] == ' '
      if is_event {
        event_type = ""
        let mut k = 7
        while k < l_str.length() {
          let ch = Char::from_int(l_str[k].to_int())
          event_type = event_type + "\{ch}"
          k = k + 1
        }
      } else if is_data {
        data_str = ""
        let mut k = 6
        while k < l_str.length() {
          let ch = Char::from_int(l_str[k].to_int())
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
    let jv = @json.parse(data_str) catch {
      _ => {
        i = i + 1
        continue
      }
    }
    match event_type {
      "response.created" =>
        match obj_get(jv, "response") {
          Some(r) => {
            let rid = field_str(r, "id")
            let rmodel = field_str(r, "model")
            events.push(
              @lux.ConversationStart(
                @lux.LucentConversationMeta::new(rid, rmodel, None),
              ),
            )
          }
          None => ()
        }
      "response.output_item.added" => {
        let idx = field_int(jv, "output_index").unwrap_or(0)
        match obj_get(jv, "item") {
          Some(item) =>
            match parse_input_item(item) {
              Some(ci) => events.push(@lux.ItemStart(idx, ci))
              None => ()
            }
          None => ()
        }
      }
      "response.content_part.added" => {
        let idx = field_int(jv, "content_index").unwrap_or(0)
        match obj_get(jv, "part") {
          Some(part) =>
            match field_str(part, "type") {
              Some("output_text") =>
                events.push(@lux.BlockStart(idx, @lux.Text))
              Some("refusal") => events.push(@lux.BlockStart(idx, @lux.Refusal))
              _ => ()
            }
          None => ()
        }
      }
      "response.output_text.delta" => {
        let idx = field_int(jv, "content_index").unwrap_or(0)
        match field_str(jv, "delta") {
          Some(t) =>
            events.push(
              @lux.BlockDelta(idx, @lux.LucentBlockDelta::text_delta(t)),
            )
          None => ()
        }
      }
      "response.output_text.done" => {
        let idx = field_int(jv, "content_index").unwrap_or(0)
        events.push(@lux.BlockEnd(idx))
      }
      "response.reasoning_summary_text.delta" => {
        let idx = field_int(jv, "content_index").unwrap_or(0)
        match field_str(jv, "delta") {
          Some(t) =>
            events.push(
              @lux.BlockDelta(idx, @lux.LucentBlockDelta::thinking_delta(t)),
            )
          None => ()
        }
      }
      "response.reasoning_summary_text.done" => {
        let idx = field_int(jv, "content_index").unwrap_or(0)
        events.push(@lux.BlockEnd(idx))
      }
      "response.function_call_arguments.delta" => {
        let idx = field_int(jv, "output_index").unwrap_or(0)
        match field_str(jv, "delta") {
          Some(a) =>
            events.push(
              @lux.BlockDelta(
                idx,
                @lux.LucentBlockDelta::tool_arguments_delta(a),
              ),
            )
          None => ()
        }
      }
      "response.function_call_arguments.done" => {
        let idx = field_int(jv, "output_index").unwrap_or(0)
        events.push(@lux.BlockEnd(idx))
      }
      "response.completed" => {
        match obj_get(jv, "response") {
          Some(r) => {
            match field_str(r, "status") {
              Some(s) =>
                events.push(
                  @lux.Finish(@lux.LucentFinishReason::from_string(s)),
                )
              None => ()
            }
            match obj_get(r, "usage") {
              Some(u) => {
                let pt = field_int(u, "input_tokens").unwrap_or(0)
                let ct = field_int(u, "output_tokens").unwrap_or(0)
                let tt = field_int(u, "total_tokens").unwrap_or(pt + ct)
                events.push(@lux.Usage(@lux.LucentUsage::new(pt, ct, tt)))
              }
              None => ()
            }
          }
          None => ()
        }
        events.push(@lux.Done)
      }
      "error" =>
        match field_str(jv, "error") {
          Some(err_msg) =>
            events.push(@lux.Error(@lux.LucentError::simple(err_msg)))
          None => ()
        }
      _ => ()
    }
    i = i + 1
  }
  Ok(events)
}

///|
/// 6. lux_events_to_openai_responses_sse — 流编码
pub fn lux_events_to_openai_responses_sse(
  events : Array[@lux.LucentStreamEvent],
) -> Result[String, String] {
  let lines : Array[String] = []
  let mut i = 0
  while i < events.length() {
    // Track output_index for item_start events
    match events[i] {
      ConversationStart(meta) => {
        let mut fields = ""
        match meta.id {
          Some(id) => fields = "\"id\":\"" + json_escape(id) + "\""
          None => ()
        }
        match meta.model {
          Some(m) =>
            fields = fields +
              (if fields == "" { "" } else { "," }) +
              "\"model\":\"" +
              json_escape(m) +
              "\""
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
                    json_escape(t) +
                    "\"}",
                  )
                _ => ()
              }
              k = k + 1
            }
            "{\"type\":\"message\",\"role\":\"" +
            json_escape(role_str) +
            "\",\"content\":[" +
            cparts.join(",") +
            "]}"
          }
          ToolCall(tu) =>
            "{\"type\":\"function_call\",\"id\":\"" +
            json_escape(tu.id) +
            "\",\"name\":\"" +
            json_escape(tu.name) +
            "\"}"
          ToolResult(tr) =>
            "{\"type\":\"function_call_output\",\"call_id\":\"" +
            json_escape(tr.tool_use_id) +
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
                        json_escape(t) +
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
              Some(s) => ",\"signature\":\"" + json_escape(s) + "\""
              None => ""
            }
            "{\"type\":\"reasoning\"" + summary + sig + "}"
          }
          AgentAction(aa) =>
            "{\"type\":\"computer_call\",\"id\":\"" + json_escape(aa.id) + "\"}"
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
              json_escape(s) +
              "\"}",
            )
          ThinkingDelta(s) =>
            lines.push(
              "event: response.reasoning_summary_text.delta\ndata: {\"type\":\"response.reasoning_summary_text.delta\",\"output_index\":" +
              idx.to_string() +
              ",\"content_index\":" +
              idx.to_string() +
              ",\"delta\":\"" +
              json_escape(s) +
              "\"}",
            )
          ToolArgumentsDelta(s) =>
            lines.push(
              "event: response.function_call_arguments.delta\ndata: {\"type\":\"response.function_call_arguments.delta\",\"output_index\":" +
              idx.to_string() +
              ",\"delta\":\"" +
              json_escape(s) +
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
          json_escape(e.message) +
          "\"}",
        )
      Done => () // Responses 流以 response.completed 结束，无独立 done 事件
    }
    i = i + 1
  }
  Ok(lines.join("\n\n") + "\n\n")
}

///|
/// capability — 适配器能力声明
pub fn capability() -> @lux.ProviderCapability {
  @lux.ProviderCapability::new(
    "gpt-*,o*",
    "openai",
    @lux.LucentCapabilities::create(true, true, true, true, true,
      [@lux.Text, @lux.Image, @lux.Pdf], [@lux.Text]),
    None,
  )
}
