///|
/// G4 诊断完备性属性测试 — 扩展字段绝不静默丢弃
///
/// 依据：AGENTS.md 硬规则「不支持的能力必须显式报错，绝不静默丢弃」；
/// 设计：.agent-workplace/docs/design/formal-verification-design.md G4 ↔ M1/M5。
/// 断言：对 4 个 adapter，输入 IR 含扩展内容块 K 时，encode 成功后
///   「输出 JSON 含 K 的表示 ∨ diagnostics 含 Degraded/Unsupported 且 field 提及 K」。
/// 输入域：gen_extended_req()（首条消息必含 1 个扩展块：thinking/audio/native/
///   file_uri 图片/annotations 文本，其余为文本）。

///|
/// 诊断数组中是否存在 field 含 token 的 Degraded/Unsupported
fn has_diag(diags : Array[@lux.ConversionDiagnostic], token : String) -> Bool {
  let mut i = 0
  while i < diags.length() {
    let d = diags[i]
    match d.status() {
      Degraded | Unsupported => if d.field.contains(token) { return true }
      _ => ()
    }
    i = i + 1
  }
  false
}

///|
/// thinking 块：adapter 原生支持（输出含结构性标记）或诊断
/// 结构性标记用 `"type":"..."` 精确匹配，避免随机文本误报
fn thinking_ok(
  out : String,
  diags : Array[@lux.ConversionDiagnostic],
  adapter : String,
) -> Bool {
  let marker = match adapter {
    "messages" => "\"type\":\"thinking\""
    "responses" => "\"type\":\"reasoning\""
    "gemini" => "\"thought\":true"
    _ => "" // openai-chat：请求无原生 thinking carrier，必须诊断
  }
  (marker != "" && out.contains(marker)) || has_diag(diags, "thinking")
}

///|
/// 非 Function 工具类型在输出中的结构性标记（`"type":"<wire>"`），
/// 用于判定 adapter 是否原生编码该工具（避免与工具名字符串误匹配）
fn tool_kind_marker(kind : @lux.LucentToolKind) -> String {
  match kind {
    WebSearch => "\"type\":\"web_search\""
    CodeInterpreter => "\"type\":\"code_interpreter\""
    FileSearch => "\"type\":\"file_search\""
    ComputerUse => "\"type\":\"computer_use\""
    MCP => "\"type\":\"mcp\""
    CodeExecution => "\"type\":\"code_execution\""
    Shell => "\"type\":\"shell\""
    ApplyPatch => "\"type\":\"apply_patch\""
    Native(tag) => "\"type\":\"" + tag + "\""
    _ => ""
  }
}

///|
/// 请求中所有扩展内容块 / AgentAction 会话项 / server tools 是否均「有表示或有诊断」
fn req_ext_ok(
  req : @lux.LucentRequest,
  out : String,
  diags : Array[@lux.ConversionDiagnostic],
  adapter : String,
) -> Bool {
  let mut ok = true
  for item in req.conversation {
    match item {
      Message(m) =>
        for c in m.content {
          let c_ok = match c {
            Thinking(_) => thinking_ok(out, diags, adapter)
            Audio(_) => out.contains("audio") || has_diag(diags, "audio")
            Native(tag, _) => out.contains(tag) || has_diag(diags, "native")
            Image(mm) =>
              match mm.source {
                FileUri(_) => out.contains("image") || has_diag(diags, "image")
                _ => true
              }
            Text(_, Some(_)) =>
              out.contains("annotation") || has_diag(diags, "annotation")
            _ => true
          }
          if !c_ok {
            ok = false
          }
        }
      AgentAction(_) =>
        // AgentAction 是 v1 占位：除 openai-responses 外各端点均无载体，
        // 必须显式诊断（不静默丢弃）
        if !(out.contains("agent_action") || has_diag(diags, "agent_action")) {
          ok = false
        }
      _ => ()
    }
  }
  // server tools：非 Function 工具类型必须原生编码（输出含 `"type":"<wire>"`）
  // 或显式诊断（tools.kind / tools.mcp），绝不静默丢弃
  match req.tools {
    Some(tools) =>
      for t in tools {
        match t.kind {
          Function => ()
          _ => {
            let marker = tool_kind_marker(t.kind)
            if marker == "" {
              ok = false
            } else if !(out.contains(marker) ||
              has_diag(diags, "tools.kind") ||
              has_diag(diags, "tools.mcp")) {
              ok = false
            }
          }
        }
      }
    None => ()
  }
  ok
}

///|
fn g4_openai_ok(req : @lux.LucentRequest) -> Bool {
  match @openai.lux_request_to_openai(req) {
    Err(_) => false
    Ok(cr) => req_ext_ok(req, cr.value(), cr.diagnostics(), "openai")
  }
}

///|
fn g4_messages_ok(req : @lux.LucentRequest) -> Bool {
  match @messages.lux_request_to_messages(req) {
    Err(_) => false
    Ok(cr) => req_ext_ok(req, cr.value(), cr.diagnostics(), "messages")
  }
}

///|
fn g4_responses_ok(req : @lux.LucentRequest) -> Bool {
  match @responses.lux_request_to_responses(req) {
    Err(_) => false
    Ok(cr) => req_ext_ok(req, cr.value(), cr.diagnostics(), "responses")
  }
}

///|
fn g4_gemini_ok(req : @lux.LucentRequest) -> Bool {
  match @gemini.lux_request_to_gemini(req) {
    Err(_) => false
    Ok(cr) => req_ext_ok(req, cr.value(), cr.diagnostics(), "gemini")
  }
}

///|
test "qc G4 diagnostics completeness - openai" {
  @qc.quick_check(@qc.forall(gen_extended_req(), g4_openai_ok))
}

///|
test "qc G4 diagnostics completeness - messages" {
  @qc.quick_check(@qc.forall(gen_extended_req(), g4_messages_ok))
}

///|
test "qc G4 diagnostics completeness - responses" {
  @qc.quick_check(@qc.forall(gen_extended_req(), g4_responses_ok))
}

///|
test "qc G4 diagnostics completeness - gemini" {
  @qc.quick_check(@qc.forall(gen_extended_req(), g4_gemini_ok))
}
