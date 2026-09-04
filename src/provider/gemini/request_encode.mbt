///|
/// Google Gemini — 请求编码
///
/// LucentRequest → Google Gemini API JSON

///|
/// 扫描 conversation 建立 tool_use_id → function name 映射。
///
/// Gemini functionResponse.name 必须是函数名（而非调用 ID），
/// 但 IR LucentToolResult 只携带 tool_use_id。跨协议转换时
/// （OpenAI call_abc123 / Anthropic toolu_xxx 入站），需回查
/// 同请求中 ToolCall/ToolUse 的 id → name 配对关系。
fn build_tool_name_map(
  items : Array[@lux.LucentConversationItem],
) -> Map[String, String] {
  let m : Map[String, String] = Map([])
  let mut i = 0
  while i < items.length() {
    match items[i] {
      ToolCall(tu) => m[tu.id] = tu.name
      Message(msg) => {
        let mut j = 0
        while j < msg.content.length() {
          match msg.content[j] {
            ToolUse(tu) => m[tu.id] = tu.name
            _ => ()
          }
          j = j + 1
        }
      }
      _ => ()
    }
    i = i + 1
  }
  m
}

///|
/// 按 tool_use_id 查函数名；查不到时发 Degraded 诊断并回退用 id 充当 name
/// （保持输出结构合法，Gemini 端最坏情况是配对失败而非请求被拒）。
fn tool_response_name(
  tool_use_id : String,
  name_map : Map[String, String],
  diagnostics : Array[@lux.ConversionDiagnostic],
) -> String {
  match name_map.get(tool_use_id) {
    Some(name) => name
    None => {
      diagnostics.push(
        @lux.ConversionDiagnostic::degraded(
          "content.tool_result.name",
          Some(
            "functionResponse.name resolved from tool_use_id without matching ToolCall: " +
            tool_use_id,
          ),
        ),
      )
      tool_use_id
    }
  }
}

///|
/// 2. lux_request_to_gemini — 请求编码
pub fn lux_request_to_gemini(
  req : @lux.LucentRequest,
) -> Result[@lux.ConversionResult[String], String] {
  let parts : Array[String] = []
  let diagnostics : Array[@lux.ConversionDiagnostic] = []
  // model 在 Gemini 中通过端点路径传递，非 JSON 体内，但仍保留以备用
  parts.push("\"model\":\"" + @internal.json_escape(req.model) + "\"")
  // systemInstruction
  match req.instructions {
    Some(instrs) => {
      let text_parts : Array[String] = []
      let mut i = 0
      while i < instrs.length() {
        match instrs[i] {
          Text(t, _) =>
            text_parts.push("{\"text\":\"" + @internal.json_escape(t) + "\"}")
          _ => ()
        }
        i = i + 1
      }
      if text_parts.length() > 0 {
        parts.push(
          "\"systemInstruction\":{\"role\":\"system\",\"parts\":[" +
          text_parts.join(",") +
          "]}",
        )
      }
    }
    None => ()
  }
  // contents
  let contents : Array[String] = []
  // functionResponse.name 需要函数名而非调用 ID：先全量扫描配对关系
  let tool_name_map = build_tool_name_map(req.conversation)
  let mut i = 0
  while i < req.conversation.length() {
    match req.conversation[i] {
      Message(m) => {
        let role_str = match m.role {
          Assistant => "model"
          Tool => "tool"
          _ => "user"
        }
        let content_parts : Array[String] = []
        let mut j = 0
        while j < m.content.length() {
          match m.content[j] {
            Text(s, _) =>
              content_parts.push(
                "{\"text\":\"" + @internal.json_escape(s) + "\"}",
              )
            ToolUse(tu) =>
              content_parts.push(
                "{\"functionCall\":{\"name\":\"" +
                @internal.json_escape(tu.name) +
                "\",\"args\":" +
                tu.arguments_json +
                "}}",
              )
            ToolResult(tr) => {
              // functionResponse.name 必须是函数名：从 ToolCall 配对回查（Gemini 无调用 ID 概念）
              let fn_name = tool_response_name(
                tr.tool_use_id,
                tool_name_map,
                diagnostics,
              )
              content_parts.push(
                "{\"functionResponse\":{\"name\":\"" +
                @internal.json_escape(fn_name) +
                "\",\"response\":{\"name\":\"" +
                @internal.json_escape(fn_name) +
                "\",\"content\":\"" +
                @internal.json_escape(@lux.lucent_content_to_text(tr.content)) +
                "\"}}}",
              )
            }
            Thinking(th) => {
              // thought part + thoughtSignature（Gemini 跨轮思考延续凭证，标准 §5）
              let sig_part = match th.signature {
                Some(s) =>
                  ",\"thoughtSignature\":\"" + @internal.json_escape(s) + "\""
                None => ""
              }
              content_parts.push(
                "{\"text\":\"" +
                @internal.json_escape(th.text) +
                "\",\"thought\":true" +
                sig_part +
                "}",
              )
            }
            File(mm) =>
              content_parts.push(
                "{\"fileData\":{\"mimeType\":\"" +
                @internal.json_escape(mm.media_type) +
                "\",\"fileUri\":\"" +
                @internal.json_escape(
                  match mm.source {
                    Url(u) => u
                    FileUri(u) => u
                    Inline(_) => ""
                  },
                ) +
                "\"}}",
              )
            _ => ()
          }
          j = j + 1
        }
        contents.push(
          "{\"role\":\"" +
          role_str +
          "\",\"parts\":[" +
          content_parts.join(",") +
          "]}",
        )
      }
      ToolCall(tu) =>
        contents.push(
          "{\"role\":\"model\",\"parts\":[{\"functionCall\":{\"name\":\"" +
          @internal.json_escape(tu.name) +
          "\",\"args\":" +
          tu.arguments_json +
          "}}]}",
        )
      ToolResult(tr) => {
        let fn_name = tool_response_name(
          tr.tool_use_id,
          tool_name_map,
          diagnostics,
        )
        contents.push(
          "{\"role\":\"tool\",\"parts\":[{\"functionResponse\":{\"name\":\"" +
          @internal.json_escape(fn_name) +
          "\",\"response\":{\"name\":\"" +
          @internal.json_escape(fn_name) +
          "\",\"content\":\"" +
          @internal.json_escape(@lux.lucent_content_to_text(tr.content)) +
          "\"}}}]}",
        )
      }
      Reasoning(th) => {
        // 独立 Reasoning item → model thought part（含 thoughtSignature）
        let sig_part = match th.signature {
          Some(s) =>
            ",\"thoughtSignature\":\"" + @internal.json_escape(s) + "\""
          None => ""
        }
        contents.push(
          "{\"role\":\"model\",\"parts\":[{\"text\":\"" +
          @internal.json_escape(th.text) +
          "\",\"thought\":true" +
          sig_part +
          "}]}",
        )
      }
      AgentAction(_) => ()
    }
    i = i + 1
  }
  parts.push("\"contents\":[" + contents.join(",") + "]")
  // tools
  match req.tools {
    Some(tools) => {
      let decls : Array[String] = []
      let mut j = 0
      while j < tools.length() {
        let t = tools[j]
        match t.kind {
          Function => {
            let desc_part = match t.description {
              Some(d) => ",\"description\":\"" + @internal.json_escape(d) + "\""
              None => ""
            }
            decls.push(
              "{\"name\":\"" +
              @internal.json_escape(t.name) +
              "\"" +
              desc_part +
              ",\"parameters\":" +
              t.parameters_json +
              "}",
            )
          }
          _ =>
            // Gemini 仅支持 functionDeclarations：不静默降级为 function，显式 Unsupported
            diagnostics.push(
              @lux.ConversionDiagnostic::unsupported(
                "tools.kind",
                Some("tool kind not supported by gemini"),
              ),
            )
        }
        j = j + 1
      }
      parts.push(
        "\"tools\":[{\"functionDeclarations\":[" + decls.join(",") + "]}]",
      )
    }
    None => ()
  }
  // toolConfig
  match req.tool_choice {
    Some(Auto) =>
      parts.push(
        "\"toolConfig\":{\"functionCallingConfig\":{\"mode\":\"AUTO\"}}",
      )
    Some(Required) =>
      parts.push(
        "\"toolConfig\":{\"functionCallingConfig\":{\"mode\":\"ANY\"}}",
      )
    Some(None) =>
      parts.push(
        "\"toolConfig\":{\"functionCallingConfig\":{\"mode\":\"NONE\"}}",
      )
    _ => ()
  }
  // generationConfig
  let gc_parts : Array[String] = []
  let opts = req.options
  match opts.temperature {
    Some(t) => gc_parts.push("\"temperature\":" + t.to_string())
    None => ()
  }
  match opts.top_p {
    Some(p) => gc_parts.push("\"topP\":" + p.to_string())
    None => ()
  }
  match opts.top_k {
    Some(k) => gc_parts.push("\"topK\":" + k.to_string())
    None => ()
  }
  match opts.max_output_tokens {
    Some(n) => gc_parts.push("\"maxOutputTokens\":" + n.to_string())
    None => ()
  }
  match opts.candidate_count {
    Some(n) => gc_parts.push("\"candidateCount\":" + n.to_string())
    None => ()
  }
  match opts.stop {
    Some(arr) => {
      let stops : Array[String] = []
      let mut k = 0
      while k < arr.length() {
        stops.push("\"" + @internal.json_escape(arr[k]) + "\"")
        k = k + 1
      }
      gc_parts.push("\"stopSequences\":[" + stops.join(",") + "]")
    }
    None => ()
  }
  // structured output
  match opts.structured_output {
    Some(JsonObject) =>
      gc_parts.push("\"responseMimeType\":\"application/json\"")
    Some(JsonSchema(schema)) => {
      gc_parts.push("\"responseMimeType\":\"application/json\"")
      gc_parts.push("\"responseSchema\":" + schema)
    }
    _ => ()
  }
  // thinking config（Gemini 3 优先 thinkingLevel；legacy 回退 thinkingBudget）
  match req.reasoning {
    Some(rc) =>
      if rc.enabled {
        match rc.effort {
          Some(effort) => {
            let (level, degraded) = lux_effort_to_gemini_level(effort)
            if degraded {
              diagnostics.push(
                @lux.ConversionDiagnostic::degraded(
                  "reasoning.effort",
                  Some(
                    "LucentReasoningEffort 无 gemini thinkingLevel 对等档位，降级为 \"high\"",
                  ),
                ),
              )
            }
            gc_parts.push(
              "\"thinkingConfig\":{\"includeThoughts\":true,\"thinkingLevel\":\"" +
              level +
              "\"}",
            )
          }
          None =>
            match rc.budget_tokens {
              Some(n) =>
                gc_parts.push(
                  "\"thinkingConfig\":{\"includeThoughts\":true,\"thinkingBudget\":" +
                  n.to_string() +
                  "}",
                )
              None =>
                gc_parts.push("\"thinkingConfig\":{\"includeThoughts\":true}")
            }
        }
      }
    None => ()
  }
  // store：Gemini 无原生 store 字段 → Unsupported 诊断
  match opts.store {
    Some(_) =>
      diagnostics.push(
        @lux.ConversionDiagnostic::unsupported(
          "options.store",
          Some("gemini has no store field"),
        ),
      )
    None => ()
  }
  // extras：合并进 generationConfig
  @internal.merge_extras_json(gc_parts, opts.extras)
  if gc_parts.length() > 0 {
    parts.push("\"generationConfig\":{" + gc_parts.join(",") + "}")
  }
  let result = @lux.ConversionResult::new("{" + parts.join(",") + "}")
  Ok(result.with_diagnostics(diagnostics))
}
