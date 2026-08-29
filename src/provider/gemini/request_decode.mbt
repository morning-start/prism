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
        @internal.parse_string_array(gc, "stopSequences"),
        false, // stream
        @internal.field_int(gc, "candidateCount"),
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
/// Gemini thinkingLevel → LucentReasoningEffort（Gemini 3，替代 thinkingBudget）
/// 返回 (effort, 是否降级)。minimal 在 IR 无对等档位，降级为 Low。
fn gemini_thinking_level_to_effort(
  level : String,
) -> (@lux.LucentReasoningEffort, Bool) {
  match level {
    "low" => (Low, false)
    "medium" => (Medium, false)
    "high" => (High, false)
    _ => (Low, true)
  }
}

///|
/// LucentReasoningEffort → Gemini thinkingLevel
/// 返回 (level, 是否降级)。XHigh 在 Gemini 无对等档位，降级为 high。
fn lux_effort_to_gemini_level(e : @lux.LucentReasoningEffort) -> (String, Bool) {
  match e {
    Low => ("low", false)
    Medium => ("medium", false)
    High => ("high", false)
    XHigh => ("high", true)
  }
}

///|
/// 解析 thinkingConfig → LucentReasoningConfig
/// 优先 Gemini 3 的 thinkingLevel（映射到 effort），回退 legacy 的 thinkingBudget
fn parse_thinking_config(
  jv : Json,
  diagnostics : Array[@lux.ConversionDiagnostic],
) -> @lux.LucentReasoningConfig? {
  match @internal.obj_get(jv, "generationConfig") {
    Some(gc) =>
      match @internal.obj_get(gc, "thinkingConfig") {
        Some(tc) =>
          match @internal.field_str(tc, "thinkingLevel") {
            Some(level) => {
              let (effort, degraded) = gemini_thinking_level_to_effort(level)
              if degraded {
                diagnostics.push(
                  @lux.ConversionDiagnostic::degraded(
                    "generationConfig.thinkingConfig.thinkingLevel",
                    Some(
                      "gemini thinkingLevel \"" +
                      level +
                      "\" 降级映射为 LucentReasoningEffort",
                    ),
                  ),
                )
              }
              Some(@lux.LucentReasoningConfig::new(Some(effort), None))
            }
            None =>
              match @internal.field_bool(tc, "includeThoughts") {
                Some(true) => {
                  let budget = @internal.field_int(tc, "thinkingBudget")
                  Some(@lux.LucentReasoningConfig::enabled(budget))
                }
                _ => Some(@lux.LucentReasoningConfig::disabled())
              }
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
  let reasoning = parse_thinking_config(jv, diagnostics)
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
