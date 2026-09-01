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
  // 响应级元数据 → provider_payload（system_fingerprint / service_tier / logprobs 归属等，
  // 标准 §9：不进 IR 字段的响应级信息保留给调用方，不静默丢弃）
  let payload_fields : Array[String] = []
  match @internal.field_str(jv, "system_fingerprint") {
    Some(fp) =>
      payload_fields.push(
        "\"system_fingerprint\":\"" + @internal.json_escape(fp) + "\"",
      )
    None => ()
  }
  match @internal.field_str(jv, "service_tier") {
    Some(tier) =>
      payload_fields.push(
        "\"service_tier\":\"" + @internal.json_escape(tier) + "\"",
      )
    None => ()
  }
  let provider_payload : Json? = if payload_fields.length() > 0 {
    match @internal.parse_json_opt("{" + payload_fields.join(",") + "}") {
      Some(v) => Some(v)
      None => None
    }
  } else {
    None
  }
  // usage（含 reasoning/cached 细化用量，标准 §9）
  let usage = match @internal.obj_get(jv, "usage") {
    Some(u) => {
      let (pt, ct, tt) = @internal.parse_usage_json(
        u,
        "prompt_tokens",
        "completion_tokens",
        Some("total_tokens"),
      )
      let reasoning = @internal.parse_reasoning_tokens(u, [
        "completion_tokens_details",
      ])
      let cached = @internal.parse_cached_tokens(u, ["prompt_tokens_details"])
      Some(@lux.LucentUsage::full(pt, ct, tt, reasoning, cached, None))
    }
    None => None
  }
  Ok(
    @lux.ConversionResult::new(
      @lux.LucentResponse::new(
        id, model, created, choices, usage, provider_payload,
      ),
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
    Some(u) => {
      let mut s = ",\"usage\":{\"prompt_tokens\":" +
        u.prompt_tokens.to_string() +
        ",\"completion_tokens\":" +
        u.completion_tokens.to_string() +
        ",\"total_tokens\":" +
        u.total_tokens.to_string()
      // 细化用量：IR 有值时输出 details 子对象（o-series prompt caching / reasoning）
      match u.reasoning_tokens {
        Some(n) =>
          s = s +
            ",\"completion_tokens_details\":{\"reasoning_tokens\":" +
            n.to_string() +
            "}"
        None => ()
      }
      match u.cached_tokens {
        Some(n) =>
          s = s +
            ",\"prompt_tokens_details\":{\"cached_tokens\":" +
            n.to_string() +
            "}"
        None => ()
      }
      s + "}"
    }
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
