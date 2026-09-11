///|
/// Google Gemini — 请求编码
///
/// LucentRequest → Google Gemini API JSON（`GenerateContentRequest`）
///
/// 官方 schema 依据（v1beta discovery）：
///   - `Content.role` 只能是 `"user"` 或 `"model"`（"Must be either 'user' or
///     'model'"）→ 工具轮次必须用 `"user"`，不存在 `"tool"` / `"system"` 角色
///   - `systemInstruction` 是 `Content`，官方示例不带 `role`
///   - `Part` 媒体载体只有 `inlineData{mimeType,data}` 与 `fileData{mimeType,fileUri}`
///   - `ToolConfig.functionCallingConfig.mode` ∈ AUTO/ANY/NONE，
///     限定函数用 `allowedFunctionNames`（无独立 "specific tool" 模式）
///   - `GenerateContentRequest.model` 为 schema 字段（Format: `models/{model}`）；
///     正常由端点路径绑定，这里同时写入 body 以便调用方做跨协议中转时能取到目标模型

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
/// 多模态块 → gemini part。
///
/// Gemini 只接受两种媒体载体：
///   - `inlineData{mimeType,data}`：内联字节（base64）
///   - `fileData{mimeType,fileUri}`：File API / GCS URI
///
/// 普通 http(s) URL 不是合法 fileUri（Gemini 不会代抓），因此发 Degraded
/// 诊断后按 fileUri 透传，提示调用方先上传 File API。
fn media_part(
  mm : @lux.LucentMultimedia,
  field : String,
  diagnostics : Array[@lux.ConversionDiagnostic],
) -> String {
  match mm.source {
    Inline(data) =>
      "{\"inlineData\":{\"mimeType\":\"" +
      @internal.json_escape(mm.media_type) +
      "\",\"data\":\"" +
      @internal.json_escape(data) +
      "\"}}"
    FileUri(uri) =>
      "{\"fileData\":{\"mimeType\":\"" +
      @internal.json_escape(mm.media_type) +
      "\",\"fileUri\":\"" +
      @internal.json_escape(uri) +
      "\"}}"
    Url(u) => {
      diagnostics.push(
        @lux.ConversionDiagnostic::degraded(
          "content." + field + ".url",
          Some(
            "gemini 不直接抓取 http(s) URL 媒体：请先上传 File API 换取 fileUri，已按 fileUri 透传",
          ),
        ),
      )
      "{\"fileData\":{\"mimeType\":\"" +
      @internal.json_escape(mm.media_type) +
      "\",\"fileUri\":\"" +
      @internal.json_escape(u) +
      "\"}}"
    }
  }
}

///|
/// functionCall part。`id` 为官方可选字段：IR 侧存在调用 ID 时回填，
/// 使跨协议（OpenAI/Anthropic 入站）的 call↔response 配对精确而非仅按函数名+顺序。
fn function_call_part(tu : @lux.LucentToolUse) -> String {
  let id_part = if tu.id == "" {
    ""
  } else {
    ",\"id\":\"" + @internal.json_escape(tu.id) + "\""
  }
  "{\"functionCall\":{\"name\":\"" +
  @internal.json_escape(tu.name) +
  "\"" +
  id_part +
  ",\"args\":" +
  tu.arguments_json +
  "}}"
}

///|
/// functionResponse part。官方 `FunctionResponse.id` 用于匹配对应 functionCall，
/// 因此把 IR 的 tool_use_id 原样回填（官方要求两端 id 一致）。
fn function_response_part(
  tool_use_id : String,
  fn_name : String,
  content_text : String,
) -> String {
  let id_part = if tool_use_id == "" {
    ""
  } else {
    ",\"id\":\"" + @internal.json_escape(tool_use_id) + "\""
  }
  "{\"functionResponse\":{\"name\":\"" +
  @internal.json_escape(fn_name) +
  "\"" +
  id_part +
  ",\"response\":{\"name\":\"" +
  @internal.json_escape(fn_name) +
  "\",\"content\":\"" +
  @internal.json_escape(content_text) +
  "\"}}}"
}

///|
/// IR 角色 → Gemini `Content.role`。
///
/// 官方只允许 `user` / `model`：工具结果轮次属于 user 侧输入，
/// assistant 侧一律 model。System 角色在 contents 中无载体（应走
/// systemInstruction），降级为 user 并发 Degraded。
fn gemini_role(
  role : @lux.LucentRole,
  diagnostics : Array[@lux.ConversionDiagnostic],
) -> String {
  match role {
    Assistant | Model => "model"
    System => {
      diagnostics.push(
        @lux.ConversionDiagnostic::degraded(
          "contents.role",
          Some(
            "system-role message in contents has no gemini equivalent; mapped to \"user\" (prefer systemInstruction)",
          ),
        ),
      )
      "user"
    }
    _ => "user"
  }
}

///|
/// 2. lux_request_to_gemini — 请求编码
pub fn lux_request_to_gemini(
  req : @lux.LucentRequest,
) -> Result[@lux.ConversionResult[String], String] {
  let parts : Array[String] = []
  let diagnostics : Array[@lux.ConversionDiagnostic] = []
  // model 在 Gemini 中通过端点路径绑定，同时保留在 body 以备用
  parts.push("\"model\":\"" + @internal.json_escape(req.model) + "\"")
  // systemInstruction：官方是 Content，示例不带 role（Content.role 只允许 user/model）
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
          "\"systemInstruction\":{\"parts\":[" + text_parts.join(",") + "]}",
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
        let role_str = gemini_role(m.role, diagnostics)
        let content_parts : Array[String] = []
        let mut j = 0
        while j < m.content.length() {
          match m.content[j] {
            Text(s, anns) => {
              // annotations 是侧信道数据：gemini part 无注解载体，显式 Degraded
              match anns {
                Some(_) =>
                  diagnostics.push(
                    @lux.ConversionDiagnostic::degraded(
                      "content.annotations",
                      Some("text annotations not supported by gemini"),
                    ),
                  )
                None => ()
              }
              content_parts.push(
                "{\"text\":\"" + @internal.json_escape(s) + "\"}",
              )
            }
            ToolUse(tu) => content_parts.push(function_call_part(tu))
            ToolResult(tr) => {
              // functionResponse.name 必须是函数名：从 ToolCall 配对回查（Gemini 无调用 ID 概念）
              let fn_name = tool_response_name(
                tr.tool_use_id,
                tool_name_map,
                diagnostics,
              )
              content_parts.push(
                function_response_part(
                  tr.tool_use_id,
                  fn_name,
                  @lux.lucent_content_to_text(tr.content),
                ),
              )
            }
            Thinking(th) => {
              // thought part + thoughtSignature（Gemini 跨轮思考延续凭证）
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
            File(mm) => content_parts.push(media_part(mm, "file", diagnostics))
            Image(mm) =>
              content_parts.push(media_part(mm, "image", diagnostics))
            Audio(mm) =>
              content_parts.push(media_part(mm, "audio", diagnostics))
            Video(mm) =>
              content_parts.push(media_part(mm, "video", diagnostics))
            Refusal(text) =>
              // Gemini 无独立 refusal 内容块：不静默丢弃，显式 Unsupported
              diagnostics.push(
                @lux.ConversionDiagnostic::unsupported(
                  "content.refusal",
                  Some(
                    "gemini has no refusal content block; refusal text dropped: " +
                    text,
                  ),
                ),
              )
            Native(tag, _) =>
              diagnostics.push(
                @lux.ConversionDiagnostic::unsupported(
                  "content.native",
                  Some("native content (" + tag + ") not supported by gemini"),
                ),
              )
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
          "{\"role\":\"model\",\"parts\":[" + function_call_part(tu) + "]}",
        )
      ToolResult(tr) => {
        let fn_name = tool_response_name(
          tr.tool_use_id,
          tool_name_map,
          diagnostics,
        )
        contents.push(
          "{\"role\":\"user\",\"parts\":[" +
          function_response_part(
            tr.tool_use_id,
            fn_name,
            @lux.lucent_content_to_text(tr.content),
          ) +
          "]}",
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
      AgentAction(_) =>
        // Gemini 无 AgentAction 载体：不静默忽略，显式 Unsupported 诊断
        diagnostics.push(
          @lux.ConversionDiagnostic::unsupported(
            "conversation.agent_action",
            Some("agent_action not supported by gemini"),
          ),
        )
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
  // toolConfig：限定单一函数时用 mode=ANY + allowedFunctionNames
  // （官方无 "specific tool" 模式；旧实现把 SpecificTool 静默丢弃）
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
    Some(SpecificTool(name)) =>
      parts.push(
        "\"toolConfig\":{\"functionCallingConfig\":{\"mode\":\"ANY\",\"allowedFunctionNames\":[\"" +
        @internal.json_escape(name) +
        "\"]}}",
      )
    None => ()
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
  // store：官方 GenerateContentRequest.store 描述的是请求级日志行为，
  // 但生成端点不使用该语义 → 不静默丢弃，显式 Unsupported
  match opts.store {
    Some(_) =>
      diagnostics.push(
        @lux.ConversionDiagnostic::unsupported(
          "options.store",
          Some("gemini generateContent does not honor request-level store"),
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
