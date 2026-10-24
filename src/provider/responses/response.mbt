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
  // 映射抽到 @meta.responses_termination_reason（CR-006 §2.1）：流式解码此前
  // 只认 response.completed，response.incomplete / response.failed 全部静默
  // 丢弃，根因即「两路径各写一份映射」——这里改为两条路径共用同一函数。
  // 映射语义逐值不变（见 @meta/termination.mbt 的映射表）。
  //
  // `failed` 时的 `error` 对象（{code, message}，均 required）不能整体丢弃，
  // 补 Degraded 诊断显式带出。
  let status = @internal.field_str(jv, "status")
  let finish = @meta.responses_termination_reason(
    status.unwrap_or(""),
    match @internal.obj_get(jv, "incomplete_details") {
      Some(d) => @internal.field_str(d, "reason")
      None => None
    },
  )
  if status == Some("failed") {
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
  // 响应级扩展载体：vendored 官方 OpenAPI 的 Response 顶层非建模字段是
  // moderation（对称于请求侧 options.extras，出站按归属门控，见
  // @internal.split_provider_payload）。此前 provider_payload 恒为 None。
  // 载体形态与 openai 解码一致：键 = wire 字段名，值 = 原始 JSON。
  let provider_payload : Json? = match @internal.obj_get(jv, "moderation") {
    // Json 的 Object 构造器对外只读，沿用 openai 解码的「拼串再解析」模式
    Some(v) =>
      match @internal.parse_json_opt("{\"moderation\":" + v.stringify() + "}") {
        Some(wrapped) => Some(wrapped)
        None => None
      }
    None => None
  }
  let result = @lux.ConversionResult::new(
    @lux.LucentResponse::new(
      id,
      model,
      created,
      [choice],
      usage,
      provider_payload,
    ),
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
  // 与流式编码共用 `@meta.responses_status_json` / `responses_incomplete_reason`
  // —— 此前两处各写一份 match，是漂移的根源（流式曾把 Safety/ContentFilter
  // 全落进 `_ => "completed"`，把内容过滤伪装成成功完成）。
  //
  // ToolCalls → completed 是**语义对等**：Responses 用 output 里的
  // function_call item 承载工具调用，status 本就是 completed，收敛器不报警。
  let status_str = @meta.responses_status_json(
    choice.finish_reason,
    "choices",
    diagnostics,
  )
  let incomplete_part = match
    @meta.responses_incomplete_reason(choice.finish_reason) {
    Some(reason) =>
      ",\"incomplete_details\":{\"reason\":\"" +
      @internal.json_escape(reason) +
      "\"}"
    None => ""
  }
  // CR-005：`stop_sequence` 是 Anthropic 的响应侧概念，Responses 无自定义
  // 终止序列概念（status 与 incomplete_details.reason 均为封闭枚举）→ 显式诊断。
  match choice.stop_sequence {
    Some(v) =>
      diagnostics.push(
        @lux.ConversionDiagnostic::unsupported(
          "choices.stop_sequence",
          Some(
            "hit stop sequence \"" +
            v +
            "\" has no openai-responses carrier (no custom stop sequence concept); dropped",
          ),
        ),
      )
    None => ()
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
  // provider_payload 出站：响应级扩展载体（对称于请求侧 options.extras）。
  // reasoning_field 等编码旋钮由分拣自动跳过。
  let (payload_kept, payload_foreign) = @internal.split_provider_payload(
    resp.provider_payload,
    "responses",
  )
  @lux.push_extras_foreign_at("provider_payload", payload_foreign, diagnostics)
  let reserved : Array[String] = [
    "id", "object", "created_at", "status", "incomplete_details", "model", "output",
    "usage",
  ]
  let payload_collided : Array[String] = []
  match payload_kept {
    Some(m) =>
      for k, _ in m {
        if reserved.contains(k) {
          payload_collided.push(k)
        }
      }
    None => ()
  }
  let payload_clean = @internal.extras_without_keys(
    payload_kept, payload_collided,
  )
  @lux.push_extras_collisions_at(
    "provider_payload", payload_collided, diagnostics,
  )
  let payload_parts : Array[String] = []
  let _ = @internal.merge_extras_json_dedup(payload_parts, payload_clean)
  let payload_json = if payload_parts.length() > 0 {
    "," + payload_parts.join(",")
  } else {
    ""
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
    payload_json +
    "}"
  let result = @lux.ConversionResult::new(body)
  Ok(result.with_diagnostics(diagnostics))
}
