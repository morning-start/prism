///|
/// 解析 output Item 为 LucentContent[]
///
/// 官方 `RefusalContent` 的形态是 `{"type":"refusal","refusal":"<text>"}`
/// （vendored `schemas/endpoints/openai-openapi.yaml` `RefusalContent`，`refusal`
/// 是 required 字段）—— **不是** `text`。此前只读 `text`，导致官方形态的
/// refusal 内容块被**整体静默丢弃**（无 block、无诊断），这是最能说明「解码
/// 侧缺矩阵审计」的一例。现在两种键都读，`refusal` 优先，`text` 作为兼容回退。
///
/// 未知 server-side item（web_search_call / file_search_call 等）不发诊断——
/// 本函数无诊断通道，由 responses_json_to_lux_response 的 output 级扫描兜底。
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
                // 官方键是 `refusal`；`text` 仅作历史/兼容回退
                match @internal.field_str(parts[i], "refusal") {
                  Some(t) => result.push(@lux.LucentContent::refusal(t))
                  None =>
                    match @internal.field_str(parts[i], "text") {
                      Some(t) => result.push(@lux.LucentContent::refusal(t))
                      None => ()
                    }
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
/// 扫描 output[] 中的 server-side 动作 item（web_search_call 等）→ AgentAction 诊断提示
///
/// Responses 的 typed output 将服务器工具执行记录为独立 item。lux-ir v1 的
/// LucentAgentAction 占位已存在但对话外无法进入 LucentResponse（响应仅承载
/// choices[].message），故解码时以 Unsupported 诊断显式暴露，不静默丢弃。
fn scan_server_tool_items(
  jv : Json,
  diagnostics : Array[@lux.ConversionDiagnostic],
) -> Unit {
  match @internal.field_arr(jv, "output") {
    Some(outputs) => {
      let mut i = 0
      while i < outputs.length() {
        match @internal.field_str(outputs[i], "type") {
          Some(t) =>
            if t != "message" &&
              t != "function_call" &&
              t != "reasoning" &&
              t != "function_call_output" {
              diagnostics.push(
                @lux.ConversionDiagnostic::unsupported(
                  "response.output." + t,
                  Some(
                    "server-side output item preserved only as diagnostic in lux-ir v1",
                  ),
                ),
              )
            }
          None => ()
        }
        i = i + 1
      }
    }
    None => ()
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
  let diagnostics : Array[@lux.ConversionDiagnostic] = []
  // server-side 动作 item（web_search_call 等）显式暴露，不静默丢弃
  scan_server_tool_items(jv, diagnostics)
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
  // status → finish_reason
  //
  // `status: "incomplete"` 此前一律映射为 Length —— 但 vendored 官方 OpenAPI 的
  // `incomplete_details.reason`（Response 级）枚举是
  // `max_output_tokens` / `max_messages` / `content_filter` / `steered`，
  // 其中 **content_filter 是被内容过滤截断**，与「达到 token 上限」是完全不同
  // 的语义，压成 Length 会让调用方误以为只是没写完。
  //
  // `failed` 时的 `error` 对象（{code, message}，均 required）此前被整体丢弃，
  // 调用方只知道失败了、不知道为什么 —— 补 Degraded 诊断显式带出。
  let finish = match @internal.field_str(jv, "status") {
    Some("completed") => @lux.Stop
    Some("incomplete") =>
      match @internal.obj_get(jv, "incomplete_details") {
        Some(d) =>
          match @internal.field_str(d, "reason") {
            // 内容过滤截断 ≠ token 上限截断
            Some("content_filter") => ContentFilter
            // 官方 reason 枚举里其余的「限额」类原因都是 Length 语义
            Some("max_output_tokens") => Length
            Some("max_messages") => Length
            // `steered`（安全边界主动停）等无 IR 对等值 → 原样保留，不丢数据
            Some(other) => @lux.LucentFinishReason::from_string(other)
            // reason 缺失（Response 级为可选字段）→ 保持保守默认 Length
            None => Length
          }
        // incomplete_details 缺失 → 保持保守默认 Length
        None => Length
      }
    Some("failed") => {
      match @internal.obj_get(jv, "error") {
        Some(err) => {
          let code = @internal.field_str(err, "code").unwrap_or("")
          let message = @internal.field_str(err, "message").unwrap_or("")
          if code != "" || message != "" {
            diagnostics.push(
              @lux.ConversionDiagnostic::degraded(
                "response.error",
                Some("response failed (code: " + code + "): " + message),
              ),
            )
          }
        }
        None => ()
      }
      Error
    }
    Some(other) => @lux.LucentFinishReason::from_string(other)
    None => Stop
  }
  let choice = @lux.LucentChoice::new(0, msg, finish, None)
  // usage（含 reasoning/cached 细化用量，标准 §9）
  let usage = match @internal.obj_get(jv, "usage") {
    Some(u) => {
      let (pt, ct, tt) = @internal.parse_usage_json(
        u,
        "input_tokens",
        "output_tokens",
        Some("total_tokens"),
      )
      let reasoning = @internal.parse_reasoning_tokens(u, [
        "output_tokens_details",
      ])
      let cached = @internal.parse_cached_tokens(u, ["input_tokens_details"])
      Some(@lux.LucentUsage::full(pt, ct, tt, reasoning, cached, None))
    }
    None => None
  }
  let result = @lux.ConversionResult::new(
    @lux.LucentResponse::new(id, model, created, [choice], usage, None),
  )
  Ok(result.with_diagnostics(diagnostics))
}

///|
/// LucentThinking.summary 中单个 Text → summary_text block JSON
/// 供 request_encode / response / stream_encode 三处 reasoning 序列化复用
fn summary_text_item(t : String) -> String {
  "{\"type\":\"summary_text\",\"text\":\"" + @internal.json_escape(t) + "\"}"
}

///|
/// LucentThinking.signature → signature 字段片段（无则返回空串）
/// 供三处 reasoning 序列化复用，保证转义一致
fn thinking_signature_field(s : String) -> String {
  ",\"signature\":\"" + @internal.json_escape(s) + "\""
}

///|
/// LucentThinking → OpenAI Responses reasoning item JSON（消息级 reasoning 出站复用）
fn thinking_to_reasoning_item(th : @lux.LucentThinking, id : Int32) -> String {
  let summary = match th.summary {
    Some(arr) => {
      let parts : Array[String] = []
      let mut k = 0
      while k < arr.length() {
        match arr[k] {
          Text(t, _) => parts.push(summary_text_item(t))
          _ => ()
        }
        k = k + 1
      }
      ",\"summary\":[" + parts.join(",") + "]"
    }
    None => ""
  }
  let sig_part = match th.signature {
    Some(s) => thinking_signature_field(s)
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
  // OpenAI Responses 的 `output` 是**单一**结果（无 candidate 概念），因此只能
  // 承载 choices[0]；choices[1..] 此前被静默丢弃。显式诊断，不静默。
  if resp.choices.length() > 1 {
    diagnostics.push(
      @lux.ConversionDiagnostic::unsupported(
        "response.choices",
        Some(
          "openai-responses carries a single output; " +
          (resp.choices.length() - 1).to_string() +
          " additional choice(s) dropped",
        ),
      ),
    )
  }
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
  // status + incomplete_details
  //
  // vendored 官方 OpenAPI（Response 级）：`status` 枚举为
  // completed / failed / in_progress / cancelled / queued / incomplete；
  // `incomplete_details.reason` 枚举为
  // max_output_tokens / max_messages / content_filter / steered。
  //
  // 此前 ContentFilter 落进 `_ => "completed"` 分支 —— 一个被内容过滤截断的
  // 响应被报告为**成功完成**。现映射为 incomplete + reason=content_filter。
  // Length 补上 reason=max_output_tokens（此前裸 incomplete 缺原因）。
  //
  // ToolCalls → completed 是**语义对等**：Responses 用 output 里的
  // function_call item 承载工具调用，status 本就是 completed，不诊断。
  let mut status_str = "\"completed\""
  let mut incomplete_part = ""
  match choice.finish_reason {
    Stop => ()
    ToolCalls => ()
    Length => {
      status_str = "\"incomplete\""
      incomplete_part = ",\"incomplete_details\":{\"reason\":\"max_output_tokens\"}"
    }
    ContentFilter => {
      status_str = "\"incomplete\""
      incomplete_part = ",\"incomplete_details\":{\"reason\":\"content_filter\"}"
    }
    Error => status_str = "\"failed\""
    Native(s) =>
      diagnostics.push(
        @lux.ConversionDiagnostic::unsupported(
          "choices.finish_reason",
          Some(
            "finish_reason \"" +
            s +
            "\" has no openai-responses equivalent; emitted \"completed\" instead",
          ),
        ),
      )
    other =>
      diagnostics.push(
        @lux.ConversionDiagnostic::unsupported(
          "choices.finish_reason",
          Some(
            "finish_reason \"" +
            other.to_string() +
            "\" has no openai-responses equivalent; emitted \"completed\" instead",
          ),
        ),
      )
  }
  let usage_json = match resp.usage {
    Some(u) => {
      let mut s = ",\"usage\":{\"input_tokens\":" +
        u.prompt_tokens.to_string() +
        ",\"output_tokens\":" +
        u.completion_tokens.to_string() +
        ",\"total_tokens\":" +
        u.total_tokens.to_string()
      match u.reasoning_tokens {
        Some(n) =>
          s = s +
            ",\"output_tokens_details\":{\"reasoning_tokens\":" +
            n.to_string() +
            "}"
        None => ()
      }
      match u.cached_tokens {
        Some(n) =>
          s = s +
            ",\"input_tokens_details\":{\"cached_tokens\":" +
            n.to_string() +
            "}"
        None => ()
      }
      s + "}"
    }
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
    incomplete_part +
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
