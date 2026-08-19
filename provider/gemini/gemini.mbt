///|
/// Google Gemini 适配器 — 对齐 Lux IR v1
///
/// 依据：docs/lux-ir-design.md §10（6-Function 契约）
/// 依据：docs/protocols/04-google-gemini.md（协议映射）
///
/// 关键差异（vs 其他协议）：
///   - contents[] 角色：model 而非 assistant，tool（相同）
///   - systemInstruction 是顶层对象（含 role + parts）
///   - tools[].functionDeclarations[] 是嵌套数组
///   - 工具参数 args 是 JSON 对象（需 stringify）
///   - thought: true 是布尔标记而非独立 block 类型
///   - finishReason 全大写字符串 "STOP" / "SAFETY" 等
///   - 流式使用完整帧（每行独立 JSON）而非 delta 增量
///   - generationConfig 嵌套所有生成参数
///   - usageMetadata 字段名不同

///|
/// === JSON 辅助（私有）===

///|

///|
/// 解析单个 part → 可能产生多个 LucentContent（thought:true 同时发 Text + Thinking）
/// call_seq 生成 functionCall id；resp_cursor 消费配对序号（按函数名）。
fn parse_part(
  part : Json,
  call_seq : Map[String, Int],
  resp_cursor : Map[String, Int],
  diagnostics : Array[@lux.ConversionDiagnostic],
) -> Array[@lux.LucentContent] {
  // text
  match @internal.field_str(part, "text") {
    Some(t) =>
      // 检查是否为 thought part
      match @internal.obj_get(part, "thought") {
        Some(True) => {
          // thought:true → 仅发 Thinking，不伪装成文本
          let th = @lux.LucentThinking::visible(t, None)
          [Thinking(th)]
        }
        Some(String(_)) => {
          let th = @lux.LucentThinking::visible(t, None)
          [Thinking(th)]
        }
        _ => [@lux.LucentContent::text(t)]
      }
    None =>
      // functionCall
      match @internal.obj_get(part, "functionCall") {
        Some(fc) => {
          let name = @internal.field_str(fc, "name").unwrap_or("")
          let args = match @internal.obj_get(fc, "args") {
            Some(a) => a.stringify()
            None => "{}"
          }
          let n = match call_seq.get(name) {
            Some(v) => v
            None => 0
          }
          call_seq[name] = n + 1
          let id = "fc_" + name + "_" + n.to_string()
          [@lux.LucentContent::tool_use(id, name, args, None)]
        }
        None =>
          // functionResponse
          match @internal.obj_get(part, "functionResponse") {
            Some(fr) => {
              let name = @internal.field_str(fr, "name").unwrap_or("")
              let response = @internal.obj_get(fr, "response")
              let content_str = match response {
                Some(r) => {
                  let c = @internal.obj_get(r, "content")
                  match c {
                    Some(v) => v.stringify()
                    None => "{}"
                  }
                }
                None => "{}"
              }
              // 配对：消费该函数名下一个未配对的 functionCall 序号
              let n = match resp_cursor.get(name) {
                Some(v) => v
                None => 0
              }
              resp_cursor[name] = n + 1
              let id = "fc_" + name + "_" + n.to_string()
              [
                @lux.LucentContent::tool_result(id, [
                  @lux.LucentContent::text(content_str),
                ]),
              ]
            }
            None =>
              // inlineData / fileData → 精确映射为 LucentMultimedia（Image）
              match @internal.obj_get(part, "inlineData") {
                Some(id) => {
                  let media_type = @internal.field_str(id, "mimeType")
                  match @internal.field_str(id, "data") {
                    Some(data) =>
                      [
                        @lux.LucentContent::image(
                          media_type.unwrap_or(""),
                          Inline(data),
                        ),
                      ]
                    None => {
                      diagnostics.push(
                        @lux.ConversionDiagnostic::degraded(
                          "part.inline_data",
                          Some("inlineData missing data field"),
                        ),
                      )
                      []
                    }
                  }
                }
                None =>
                  match @internal.obj_get(part, "fileData") {
                    Some(fd) => {
                      let media_type = @internal.field_str(fd, "mimeType")
                      match @internal.field_str(fd, "fileUri") {
                        Some(uri) =>
                          [
                            @lux.LucentContent::image(
                              media_type.unwrap_or(""),
                              FileUri(uri),
                            ),
                          ]
                        None => {
                          diagnostics.push(
                            @lux.ConversionDiagnostic::degraded(
                              "part.file_data",
                              Some("fileData missing fileUri field"),
                            ),
                          )
                          []
                        }
                      }
                    }
                    None => [] // thought-only marker, skip
                  }
              }
          }
      }
  }
}

///|
/// 解析 contents[] 中单个 content 的 parts[] → Array[LucentContent]
fn parse_parts(
  arr : Array[Json],
  call_seq : Map[String, Int],
  resp_cursor : Map[String, Int],
  diagnostics : Array[@lux.ConversionDiagnostic],
) -> Array[@lux.LucentContent] {
  let result : Array[@lux.LucentContent] = []
  let mut i = 0
  while i < arr.length() {
    let parts = parse_part(arr[i], call_seq, resp_cursor, diagnostics)
    for p in parts {
      result.push(p)
    }
    i = i + 1
  }
  result
}

///|
/// 解析 contents[] → Array[LucentConversationItem]
fn parse_contents(
  jv : Json,
  call_seq : Map[String, Int],
  resp_cursor : Map[String, Int],
  diagnostics : Array[@lux.ConversionDiagnostic],
) -> Array[@lux.LucentConversationItem] {
  let result : Array[@lux.LucentConversationItem] = []
  match @internal.field_arr(jv, "contents") {
    Some(contents) => {
      let mut i = 0
      while i < contents.length() {
        let role_str = @internal.field_str(contents[i], "role").unwrap_or(
          "user",
        )
        let role = match role_str {
          "user" => @lux.User
          "model" => Assistant // Gemini model → IR Assistant
          "tool" => Tool
          _ => User
        }
        // 先检查是否含 functionResponse → 解码为 Item::ToolResult
        // （避免先跑 parse_parts 重复消费配对游标）
        let has_tool_result = {
          let mut found = false
          match @internal.field_arr(contents[i], "parts") {
            Some(arr) => {
              let mut j = 0
              while j < arr.length() {
                match @internal.obj_get(arr[j], "functionResponse") {
                  Some(_) => found = true
                  None => ()
                }
                j = j + 1
              }
            }
            None => ()
          }
          found
        }
        if has_tool_result {
          // Extract ToolResult from parts
          match @internal.field_arr(contents[i], "parts") {
            Some(arr) => {
              let mut j = 0
              while j < arr.length() {
                match @internal.obj_get(arr[j], "functionResponse") {
                  Some(fr) => {
                    let name = @internal.field_str(fr, "name").unwrap_or("")
                    let response = @internal.obj_get(fr, "response")
                    let content_str = match response {
                      Some(r) =>
                        match @internal.obj_get(r, "content") {
                          Some(c) => c.stringify()
                          None => "{}"
                        }
                      None => "{}"
                    }
                    // 配对：消费该函数名下一个未配对的 functionCall 序号
                    let n = match resp_cursor.get(name) {
                      Some(v) => v
                      None => 0
                    }
                    resp_cursor[name] = n + 1
                    let id = "fc_" + name + "_" + n.to_string()
                    let tr = @lux.LucentToolResult::ok(id, [
                      @lux.LucentContent::text(content_str),
                    ])
                    result.push(@lux.LucentConversationItem::tool_result(tr))
                  }
                  None => ()
                }
                j = j + 1
              }
            }
            None => ()
          }
        } else {
          let parts = match @internal.field_arr(contents[i], "parts") {
            Some(arr) => parse_parts(arr, call_seq, resp_cursor, diagnostics)
            None => []
          }
          let msg = @lux.LucentMessage::new(role, parts)
          result.push(@lux.LucentConversationItem::message(msg))
        }
        i = i + 1
      }
    }
    None => ()
  }
  result
}

///|
/// 解析 systemInstruction → Array[LucentContent]
fn parse_system_instruction(jv : Json) -> Array[@lux.LucentContent] {
  let result : Array[@lux.LucentContent] = []
  match @internal.obj_get(jv, "systemInstruction") {
    Some(si) =>
      match @internal.field_arr(si, "parts") {
        Some(parts) => {
          let mut i = 0
          while i < parts.length() {
            match @internal.field_str(parts[i], "text") {
              Some(t) => result.push(@lux.LucentContent::text(t))
              None => ()
            }
            i = i + 1
          }
        }
        None => ()
      }
    None => ()
  }
  result
}

///|
/// 解析 tools[].functionDeclarations[] → Array[LucentTool]
fn parse_tools(jv : Json) -> Array[@lux.LucentTool] {
  let result : Array[@lux.LucentTool] = []
  match @internal.field_arr(jv, "tools") {
    Some(tools) => {
      let mut i = 0
      while i < tools.length() {
        match @internal.field_arr(tools[i], "functionDeclarations") {
          Some(decls) => {
            let mut j = 0
            while j < decls.length() {
              let d = decls[j]
              let name = @internal.field_str(d, "name").unwrap_or("")
              let desc = @internal.field_str(d, "description")
              let params = match @internal.obj_get(d, "parameters") {
                Some(p) => p.stringify()
                None => "{}"
              }
              result.push(
                @lux.LucentTool::new(name, desc, params, None, Function),
              )
              j = j + 1
            }
          }
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
/// 解析 generationConfig → LucentOptions
fn parse_generation_config(jv : Json) -> @lux.LucentOptions {
  match @internal.obj_get(jv, "generationConfig") {
    Some(gc) => {
      let extras = @internal.collect_extra_fields(gc, [
        "temperature", "topP", "topK", "maxOutputTokens", "stopSequences", "candidateCount",
        "thinkingConfig",
      ])
      @lux.LucentOptions::new(
        @internal.field_num(gc, "temperature"),
        @internal.field_num(gc, "topP"),
        @internal.field_int(gc, "topK"),
        @internal.field_int(gc, "maxOutputTokens"),
        match @internal.field_arr(gc, "stopSequences") {
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
        },
        false, // stream
        @internal.field_int(gc, "candidateCount"),
        None,
        None,
        None,
        extras,
      )
    }
    None => @lux.LucentOptions::default()
  }
}

///|
/// 解析 toolConfig.functionCallingConfig.mode → LucentToolChoice
fn parse_tool_config(jv : Json) -> @lux.LucentToolChoice? {
  match @internal.obj_get(jv, "toolConfig") {
    Some(tc) =>
      match @internal.obj_get(tc, "functionCallingConfig") {
        Some(fcc) =>
          match @internal.field_str(fcc, "mode") {
            Some("AUTO") => Some(Auto)
            Some("ANY") => Some(Required)
            Some("NONE") => Some(None)
            _ => None
          }
        None => None
      }
    None => None
  }
}

///|
/// 解析 thinkingConfig → LucentReasoningConfig
fn parse_thinking_config(jv : Json) -> @lux.LucentReasoningConfig? {
  match @internal.obj_get(jv, "generationConfig") {
    Some(gc) =>
      match @internal.obj_get(gc, "thinkingConfig") {
        Some(tc) =>
          match @internal.field_bool(tc, "includeThoughts") {
            Some(true) => {
              let budget = @internal.field_int(tc, "thinkingBudget")
              Some(@lux.LucentReasoningConfig::enabled(budget))
            }
            _ => Some(@lux.LucentReasoningConfig::disabled())
          }
        None => None
      }
    None => None
  }
}

///|
/// 1. gemini_to_lux_request — 请求解码
pub fn gemini_to_lux_request(
  json_str : String,
) -> Result[@lux.ConversionResult[@lux.LucentRequest], String] {
  let jv = match @internal.parse_protocol_json(json_str) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let diagnostics : Array[@lux.ConversionDiagnostic] = []
  let model = @internal.field_str(jv, "model").unwrap_or("")
  let instructions = parse_system_instruction(jv)
  let instr_opt = if instructions.length() > 0 {
    Some(instructions)
  } else {
    None
  }
  // functionCall 序号生成 + functionResponse 配对游标（按函数名）
  let call_seq : Map[String, Int] = Map([])
  let resp_cursor : Map[String, Int] = Map([])
  let conversation = parse_contents(jv, call_seq, resp_cursor, diagnostics)
  let tools_list = parse_tools(jv)
  let tools = if tools_list.length() > 0 { Some(tools_list) } else { None }
  let tool_choice = parse_tool_config(jv)
  let opts = parse_generation_config(jv)
  let reasoning = parse_thinking_config(jv)
  let result = @lux.ConversionResult::new(
    @lux.LucentRequest::new(
      model,
      instr_opt,
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
            ToolResult(tr) =>
              content_parts.push(
                "{\"functionResponse\":{\"name\":\"" +
                @internal.json_escape(tr.tool_use_id) +
                "\",\"response\":{\"name\":\"" +
                @internal.json_escape(tr.tool_use_id) +
                "\",\"content\":" +
                @lux.lucent_content_to_text(tr.content) +
                "}}}",
              )
            Thinking(th) =>
              content_parts.push(
                "{\"text\":\"" +
                @internal.json_escape(th.text) +
                "\",\"thought\":true}",
              )
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
      ToolResult(tr) =>
        contents.push(
          "{\"role\":\"tool\",\"parts\":[{\"functionResponse\":{\"name\":\"" +
          @internal.json_escape(tr.tool_use_id) +
          "\",\"response\":{\"name\":\"" +
          @internal.json_escape(tr.tool_use_id) +
          "\",\"content\":" +
          @internal.json_escape(@lux.lucent_content_to_text(tr.content)) +
          "}}}]}",
        )
      Reasoning(th) =>
        contents.push(
          "{\"role\":\"model\",\"parts\":[{\"text\":\"" +
          @internal.json_escape(th.text) +
          "\",\"thought\":true}]}",
        )
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
  // thinking config
  match req.reasoning {
    Some(rc) =>
      if rc.enabled {
        let budget_part = match rc.budget_tokens {
          Some(n) => ",\"thinkingBudget\":" + n.to_string()
          None => ""
        }
        gc_parts.push(
          "\"thinkingConfig\":{\"includeThoughts\":true" + budget_part + "}",
        )
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
  match opts.extras {
    Some(m) =>
      for k, v in m {
        gc_parts.push("\"" + @internal.json_escape(k) + "\":" + v.stringify())
      }
    None => ()
  }
  if gc_parts.length() > 0 {
    parts.push("\"generationConfig\":{" + gc_parts.join(",") + "}")
  }
  let result = @lux.ConversionResult::new("{" + parts.join(",") + "}")
  Ok(result.with_diagnostics(diagnostics))
}

///|
/// 3. gemini_to_lux_response — 响应解码
pub fn gemini_to_lux_response(
  json_str : String,
) -> Result[@lux.ConversionResult[@lux.LucentResponse], String] {
  let jv = match @internal.parse_protocol_json(json_str) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let diagnostics : Array[@lux.ConversionDiagnostic] = []
  let id = @internal.field_str(jv, "model").unwrap_or("")
  let model = @internal.field_str(jv, "modelVersion").unwrap_or(id)
  // candidates
  let choices : Array[@lux.LucentChoice] = []
  match @internal.field_arr(jv, "candidates") {
    Some(cands) => {
      let mut i = 0
      while i < cands.length() {
        let idx = @internal.field_int(cands[i], "index").unwrap_or(i)
        match @internal.obj_get(cands[i], "content") {
          Some(content) => {
            let parts = match @internal.field_arr(content, "parts") {
              Some(arr) => parse_parts(arr, Map([]), Map([]), diagnostics)
              None => []
            }
            let msg = @lux.LucentMessage::new(Assistant, parts)
            let finish = match @internal.field_str(cands[i], "finishReason") {
              Some("STOP") => @lux.Stop
              Some("MAX_TOKENS") => Length
              Some("SAFETY") => Safety
              Some("RECITATION") => Recitation
              Some("MALFORMED_FUNCTION_CALL") => MalformedToolCall
              Some(other) => @lux.LucentFinishReason::from_string(other)
              None => Stop
            }
            // safety ratings
            let ratings = match @internal.field_arr(cands[i], "safetyRatings") {
              Some(ratings) => {
                let result : Array[@lux.LucentSafetyRating] = []
                let mut k = 0
                while k < ratings.length() {
                  let cat = @internal.field_str(ratings[k], "category").unwrap_or(
                    "",
                  )
                  let prob = @internal.field_str(ratings[k], "probability").unwrap_or(
                    "",
                  )
                  result.push(@lux.LucentSafetyRating::new(cat, prob))
                  k = k + 1
                }
                Some(result)
              }
              None => None
            }
            choices.push(@lux.LucentChoice::new(idx, msg, finish, ratings))
          }
          None => ()
        }
        i = i + 1
      }
    }
    None => ()
  }
  if choices.length() == 0 {
    return Err("response has no candidates")
  }
  // usage
  let usage = match @internal.obj_get(jv, "usageMetadata") {
    Some(u) => {
      let pt = @internal.field_int(u, "promptTokenCount").unwrap_or(0)
      let ct = @internal.field_int(u, "candidatesTokenCount").unwrap_or(0)
      let tt = @internal.field_int(u, "totalTokenCount").unwrap_or(pt + ct)
      @lux.LucentUsage::new(pt, ct, tt)
    }
    None => @lux.LucentUsage::new(0, 0, 0)
  }
  let result = @lux.ConversionResult::new(
    @lux.LucentResponse::new(id, model, None, choices, Some(usage), None),
  )
  Ok(result.with_diagnostics(diagnostics))
}

///|
/// 4. lux_response_to_gemini — 响应编码
pub fn lux_response_to_gemini(
  resp : @lux.LucentResponse,
) -> Result[@lux.ConversionResult[String], String] {
  if resp.choices.length() == 0 {
    return Err("response has no choices")
  }
  let diagnostics : Array[@lux.ConversionDiagnostic] = []
  let cands : Array[String] = []
  let mut i = 0
  while i < resp.choices.length() {
    let c = resp.choices[i]
    let parts : Array[String] = []
    // 消息级 reasoning 优先（vLLM/DeepSeek 入站 → IR → Gemini 出站），前置为 thought:true part
    match c.message.reasoning {
      Some(th) =>
        parts.push(
          "{\"text\":\"" +
          @internal.json_escape(th.text) +
          "\",\"thought\":true}",
        )
      None => ()
    }
    let mut j = 0
    while j < c.message.content.length() {
      // 双载体并存：消息级 reasoning 已输出，content 中 Thinking part 跳过 → Degraded
      match c.message.content[j] {
        Thinking(_) =>
          match c.message.reasoning {
            Some(_) => {
              diagnostics.push(
                @lux.ConversionDiagnostic::degraded(
                  "reasoning.dual_carrier",
                  Some(
                    "both message.reasoning and content Thinking present; using message.reasoning",
                  ),
                ),
              )
              j = j + 1
              continue
            }
            None => ()
          }
        _ => ()
      }
      match c.message.content[j] {
        Text(s, _) =>
          parts.push("{\"text\":\"" + @internal.json_escape(s) + "\"}")
        ToolUse(tu) =>
          parts.push(
            "{\"functionCall\":{\"name\":\"" +
            @internal.json_escape(tu.name) +
            "\",\"args\":" +
            tu.arguments_json +
            "}}",
          )
        Thinking(th) =>
          parts.push(
            "{\"text\":\"" +
            @internal.json_escape(th.text) +
            "\",\"thought\":true}",
          )
        File(mm) =>
          parts.push(
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
    let finish_str = match c.finish_reason {
      Stop => "STOP"
      Length => "MAX_TOKENS"
      ToolCalls => "STOP"
      Safety => "SAFETY"
      Recitation => "RECITATION"
      MalformedToolCall => "MALFORMED_FUNCTION_CALL"
      Error => "OTHER"
      _ => "STOP"
    }
    let mut cand = "{\"index\":" +
      c.index.to_string() +
      ",\"content\":{\"role\":\"model\",\"parts\":[" +
      parts.join(",") +
      "]}"
    cand = cand + ",\"finishReason\":\"" + finish_str + "\""
    match c.safety_ratings {
      Some(ratings) => {
        let rs : Array[String] = []
        let mut k = 0
        while k < ratings.length() {
          rs.push(
            "{\"category\":\"" +
            @internal.json_escape(ratings[k].category) +
            "\",\"probability\":\"" +
            @internal.json_escape(ratings[k].probability) +
            "\"}",
          )
          k = k + 1
        }
        cand = cand + ",\"safetyRatings\":[" + rs.join(",") + "]"
      }
      None => ()
    }
    cands.push(cand + "}")
    i = i + 1
  }
  let usage_part = match resp.usage {
    Some(u) =>
      ",\"usageMetadata\":{\"promptTokenCount\":" +
      u.prompt_tokens.to_string() +
      ",\"candidatesTokenCount\":" +
      u.completion_tokens.to_string() +
      ",\"totalTokenCount\":" +
      u.total_tokens.to_string() +
      "}"
    None => ""
  }
  let result = @lux.ConversionResult::new(
    "{\"candidates\":[" + cands.join(",") + "]" + usage_part + "}",
  )
  Ok(result.with_diagnostics(diagnostics))
}

///|
/// 5. gemini_sse_to_events — 流解码
///
/// Gemini 流式格式：每行一个 data: {...} 完整帧
/// 适配层做 diff，发 BlockDiscard 旧帧 + BlockDelta 新内容
pub fn gemini_sse_to_events(
  sse_str : String,
) -> Result[@lux.ConversionResult[Array[@lux.LucentStreamEvent]], String] {
  let events : Array[@lux.LucentStreamEvent] = []
  let lines = sse_str.split("\n").to_array()
  let mut has_text_block = false
  let mut current_text = ""
  let mut text_block_index = 0
  let mut i = 0
  while i < lines.length() {
    let l_str = lines[i].to_owned()
    let is_data = l_str.length() >= 6 &&
      l_str[0] == 'd' &&
      l_str[1] == 'a' &&
      l_str[2] == 't' &&
      l_str[3] == 'a' &&
      l_str[4] == ':' &&
      l_str[5] == ' '
    if is_data {
      let mut payload_str = ""
      let mut k = 6
      while k < l_str.length() {
        let ch = Int::unsafe_to_char(l_str[k].to_int())
        payload_str = payload_str + "\{ch}"
        k = k + 1
      }
      let payload = payload_str.trim().to_owned()
      if payload == "" {
        i = i + 1
        continue
      }
      let jv = @json.parse(payload) catch {
        _ => {
          i = i + 1
          continue
        }
      }
      // 每一帧都是完整 candidates 数组
      // 对 text 部分做简单 diff：检测新文本增量
      match @internal.field_arr(jv, "candidates") {
        Some(cands) =>
          if cands.length() > 0 {
            match @internal.obj_get(cands[0], "content") {
              Some(content) =>
                match @internal.field_arr(content, "parts") {
                  Some(parts) => {
                    let mut j = 0
                    while j < parts.length() {
                      match @internal.field_str(parts[j], "text") {
                        Some(t) => {
                          if !has_text_block {
                            events.push(BlockStart(text_block_index, Text))
                            has_text_block = true
                          }
                          // Gemini 每帧是完整文本，非增量
                          // 简单方式：丢弃旧文本，发新文本
                          if current_text != "" {
                            events.push(BlockDiscard(text_block_index))
                          }
                          current_text = t
                          events.push(
                            BlockDelta(
                              text_block_index,
                              @lux.LucentBlockDelta::text_delta(t),
                            ),
                          )
                        }
                        None => ()
                      }
                      // functionCall（全量返回，一次性完成）
                      match @internal.obj_get(parts[j], "functionCall") {
                        Some(fc) => {
                          let name = @internal.field_str(fc, "name").unwrap_or(
                            "",
                          )
                          let args = match @internal.obj_get(fc, "args") {
                            Some(a) => a.stringify()
                            None => "{}"
                          }
                          if has_text_block {
                            events.push(BlockEnd(text_block_index))
                            has_text_block = false
                          }
                          text_block_index = text_block_index + 1
                          events.push(
                            BlockStart(
                              text_block_index,
                              @lux.LucentBlockType::tool_call(
                                "fc_" +
                                name +
                                "_" +
                                text_block_index.to_string(),
                                name,
                              ),
                            ),
                          )
                          events.push(
                            BlockDelta(
                              text_block_index,
                              @lux.LucentBlockDelta::tool_arguments_delta(args),
                            ),
                          )
                          events.push(BlockEnd(text_block_index))
                          text_block_index = text_block_index + 1
                        }
                        None => ()
                      }
                      // thought part → 独立 Thinking 块（不静默丢弃，不伪装成 Text）
                      match @internal.obj_get(parts[j], "thought") {
                        Some(True) =>
                          match @internal.field_str(parts[j], "text") {
                            Some(t) => {
                              if has_text_block {
                                events.push(BlockEnd(text_block_index))
                                has_text_block = false
                              }
                              text_block_index = text_block_index + 1
                              events.push(
                                BlockStart(text_block_index, Thinking),
                              )
                              events.push(
                                BlockDelta(
                                  text_block_index,
                                  @lux.LucentBlockDelta::thinking_delta(t),
                                ),
                              )
                              events.push(BlockEnd(text_block_index))
                              text_block_index = text_block_index + 1
                            }
                            None => ()
                          }
                        _ => ()
                      }
                      j = j + 1
                    }
                  }
                  None => ()
                }
              None => ()
            }
            // finishReason
            match @internal.field_str(cands[0], "finishReason") {
              Some(fr) => {
                if has_text_block {
                  events.push(BlockEnd(text_block_index))
                  has_text_block = false
                }
                events.push(Finish(@lux.LucentFinishReason::from_string(fr)))
              }
              None => ()
            }
          }
        None => ()
      }
      // usageMetadata（最后一帧含 finishReason）
      match @internal.obj_get(jv, "usageMetadata") {
        Some(u) => {
          let pt = @internal.field_int(u, "promptTokenCount").unwrap_or(0)
          let ct = @internal.field_int(u, "candidatesTokenCount").unwrap_or(0)
          let tt = @internal.field_int(u, "totalTokenCount").unwrap_or(pt + ct)
          events.push(Usage(@lux.LucentUsage::new(pt, ct, tt)))
          events.push(Done)
        }
        None => ()
      }
    }
    i = i + 1
  }
  if has_text_block {
    events.push(BlockEnd(text_block_index))
  }
  Ok(@lux.ConversionResult::new(events))
}

///|
/// 6. lux_events_to_gemini_sse — 流编码
pub fn lux_events_to_gemini_sse(
  events : Array[@lux.LucentStreamEvent],
) -> Result[@lux.ConversionResult[String], String] {
  // Gemini 流式是完整帧格式，块周期事件需要合并为完整 candidates
  // 简化实现：累加文本内容，每帧发送完整文本
  let lines : Array[String] = []
  let mut acc_text = ""
  let mut last_text = ""
  let mut blocks_with_args : Array[String] = []
  let mut i = 0
  while i < events.length() {
    match events[i] {
      BlockDelta(_, TextDelta(s)) => {
        acc_text = acc_text + s
        if acc_text != last_text {
          lines.push(
            "data: {\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"text\":\"" +
            @internal.json_escape(acc_text) +
            "\"}]}}]}",
          )
          last_text = acc_text
        }
      }
      BlockDelta(_, ToolArgumentsDelta(s)) => blocks_with_args.push(s)
      BlockStart(_, ToolCall(_, name)) => {
        let args = if blocks_with_args.length() > 0 {
          blocks_with_args.join("")
        } else {
          "{}"
        }
        lines.push(
          "data: {\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"functionCall\":{\"name\":\"" +
          @internal.json_escape(name) +
          "\",\"args\":" +
          args +
          "}}]}}]}",
        )
        blocks_with_args = []
      }
      Finish(fr) => {
        let finish_str = match fr {
          Stop => "STOP"
          Length => "MAX_TOKENS"
          ToolCalls => "STOP"
          Safety => "SAFETY"
          Recitation => "RECITATION"
          MalformedToolCall => "MALFORMED_FUNCTION_CALL"
          Error => "OTHER"
          _ => "STOP"
        }
        lines.push(
          "data: {\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"text\":\"" +
          @internal.json_escape(acc_text) +
          "\"}]},\"finishReason\":\"" +
          finish_str +
          "\"}]}",
        )
      }
      Usage(u) =>
        lines.push(
          "data: {\"candidates\":[],\"usageMetadata\":{\"promptTokenCount\":" +
          u.prompt_tokens.to_string() +
          ",\"candidatesTokenCount\":" +
          u.completion_tokens.to_string() +
          ",\"totalTokenCount\":" +
          u.total_tokens.to_string() +
          "}}",
        )
      _ => ()
    }
    i = i + 1
  }
  Ok(@lux.ConversionResult::new(lines.join("\n") + "\n"))
}

///|
/// capability — 适配器能力声明
pub fn capability() -> @lux.ProviderCapability {
  @lux.ProviderCapability::new(
    "gemini-*",
    "google",
    @lux.LucentCapabilities::create(
      true,
      true,
      true,
      true,
      true,
      [Text, Image, Audio, Video, Pdf],
      [Text],
    ),
    None,
  )
}
