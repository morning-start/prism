///|
/// 解析 output Item 为 LucentContent[]
fn parse_output_content(output_item : Json) -> Array[@lux.LucentContent] {
  match @internal.field_str(output_item, "type") {
    Some("message") => {
      let content = match @internal.field_arr(output_item, "content") {
        Some(parts) => {
          let result : Array[@lux.LucentContent] = []
          let mut i = 0
          while i < parts.length() {
            match @internal.field_str(parts[i], "type") {
              Some("output_text") =>
                match @internal.field_str(parts[i], "text") {
                  Some(t) => result.push(@lux.LucentContent::text(t))
                  None => ()
                }
              Some("refusal") =>
                match @internal.field_str(parts[i], "text") {
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
      let id = @internal.field_str(output_item, "id").unwrap_or("")
      let name = @internal.field_str(output_item, "name").unwrap_or("")
      let args = @internal.field_str(output_item, "arguments").unwrap_or("{}")
      [@lux.LucentContent::tool_use(id, name, args, None)]
    }
    Some("reasoning") => {
      let summary = match @internal.field_arr(output_item, "summary") {
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
      let signature = @internal.field_str(output_item, "signature")
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
/// 3. responses_to_lux_response — 响应解码
pub fn responses_to_lux_response(
  json_str : String,
) -> Result[@lux.ConversionResult[@lux.LucentResponse], String] {
  let jv = match @internal.parse_protocol_json(json_str) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  responses_json_to_lux_response(jv)
}

///|
/// 3b. 已解析 Json 的响应解码入口
///
/// 供薄封装子协议（如 Azure）复用：调用方已持有 `Json` 时可避免二次解析。
pub fn responses_json_to_lux_response(
  jv : Json,
) -> Result[@lux.ConversionResult[@lux.LucentResponse], String] {
  let id = @internal.field_str(jv, "id").unwrap_or("")
  let model = @internal.field_str(jv, "model").unwrap_or("")
  let created = @internal.field_int(jv, "created_at")
  // output items → choices[0].message.content
  let content : Array[@lux.LucentContent] = []
  match @internal.field_arr(jv, "output") {
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
  let msg = @lux.LucentMessage::new(Assistant, content)
  let finish = match @internal.field_str(jv, "status") {
    Some("completed") => @lux.Stop
    Some("incomplete") => Length
    Some("failed") => Error
    Some(other) => @lux.LucentFinishReason::from_string(other)
    None => Stop
  }
  let choice = @lux.LucentChoice::new(0, msg, finish, None)
  // usage
  let usage = match @internal.obj_get(jv, "usage") {
    Some(u) => {
      let (pt, ct, tt) = @internal.parse_usage_json(
        u,
        "input_tokens",
        "output_tokens",
        Some("total_tokens"),
      )
      @lux.LucentUsage::new(pt, ct, tt)
    }
    None => @lux.LucentUsage::new(0, 0, 0)
  }
  Ok(
    @lux.ConversionResult::new(
      @lux.LucentResponse::new(id, model, created, [choice], Some(usage), None),
    ),
  )
}

///|
/// LucentThinking → OpenAI Responses reasoning item JSON（消息级 reasoning 出站复用）
fn thinking_to_reasoning_item(th : @lux.LucentThinking, id : Int) -> String {
  let summary = match th.summary {
    Some(arr) => {
      let parts : Array[String] = []
      let mut k = 0
      while k < arr.length() {
        match arr[k] {
          Text(t, _) =>
            parts.push(
              "{\"type\":\"summary_text\",\"text\":\"" +
              @internal.json_escape(t) +
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
    Some(s) => ",\"signature\":\"" + @internal.json_escape(s) + "\""
    None => ""
  }
  "{\"type\":\"reasoning\",\"id\":\"rs_" +
  id.to_string() +
  "\"" +
  summary +
  sig_part +
  "}"
}

///|
/// 4. lux_response_to_responses — 响应编码
pub fn lux_response_to_responses(
  resp : @lux.LucentResponse,
) -> Result[@lux.ConversionResult[String], String] {
  if resp.choices.length() == 0 {
    return Err("response has no choices")
  }
  let diagnostics : Array[@lux.ConversionDiagnostic] = []
  let choice = resp.choices[0]
  // build output items
  let output_items : Array[String] = []
  // 消息级 reasoning 优先（vLLM/DeepSeek 入站 → IR → openai-responses 出站），前置为 reasoning item
  match choice.message.reasoning {
    Some(th) => output_items.push(thinking_to_reasoning_item(th, 0))
    None => ()
  }
  let mut i = 0
  while i < choice.message.content.length() {
    // 双载体并存：消息级 reasoning 已输出，content 中 Thinking block 跳过 → Degraded
    if @lux.skip_thinking_when_dual_carrier(
        choice.message.content[i],
        choice.message.reasoning,
        diagnostics,
      ) {
      i = i + 1
      continue
    }
    match choice.message.content[i] {
      Text(s, _) =>
        output_items.push(
          "{\"type\":\"message\",\"id\":\"msg_" +
          i.to_string() +
          "\",\"role\":\"assistant\",\"status\":\"completed\",\"content\":[" +
          "{\"type\":\"output_text\",\"text\":\"" +
          @internal.json_escape(s) +
          "\",\"annotations\":[]}]}",
        )
      ToolUse(tu) =>
        output_items.push(
          "{\"type\":\"function_call\",\"id\":\"" +
          @internal.json_escape(tu.id) +
          "\",\"call_id\":\"call_" +
          @internal.json_escape(tu.id) +
          "\",\"name\":\"" +
          @internal.json_escape(tu.name) +
          "\",\"arguments\":\"" +
          @internal.json_escape(tu.arguments_json) +
          "\",\"status\":\"completed\"}",
        )
      Thinking(th) => output_items.push(thinking_to_reasoning_item(th, i))
      Refusal(s) =>
        output_items.push(
          "{\"type\":\"message\",\"id\":\"ref_" +
          i.to_string() +
          "\",\"role\":\"assistant\",\"status\":\"completed\",\"content\":[" +
          "{\"type\":\"refusal\",\"refusal\":\"" +
          @internal.json_escape(s) +
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
    @internal.json_escape(resp.id) +
    "\",\"object\":\"response\"" +
    created_part +
    ",\"status\":" +
    status_str +
    ",\"model\":\"" +
    @internal.json_escape(resp.model) +
    "\",\"output\":[" +
    output_items.join(",") +
    "]" +
    usage_json +
    "}"
  let result = @lux.ConversionResult::new(body)
  Ok(result.with_diagnostics(diagnostics))
}
