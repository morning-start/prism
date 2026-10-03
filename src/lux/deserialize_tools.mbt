///|
/// Lucent IR — 工具与结构化输出反序列化（LucentTool / LucentToolChoice / LucentStructuredOutput）
///
/// 共享 helper 见 deserialize_helpers；内容段见 deserialize_content；
/// 生成参数段见 deserialize_options。

///|
/// === LucentTool ===
pub fn LucentTool::from_json(jv : Json) -> Result[LucentTool, String] {
  match jv {
    Object(m) => {
      let name = match get_str(m, "name") {
        Ok(s) => s
        Err(e) => return Err(e)
      }
      let description = get_str_opt(m, "description")
      let parameters_json = match m.get("parameters") {
        Some(p) => p.stringify()
        None => return Err("missing parameters")
      }
      let strict = get_bool_opt(m, "strict")
      let kind = match get_str_opt(m, "kind") {
        Some("function") => Function
        Some("file_search") => FileSearch
        Some("web_search") => WebSearch
        Some("code_interpreter") => CodeInterpreter
        Some("computer_use") => ComputerUse
        Some("code_execution") => CodeExecution
        Some("shell") => Shell
        Some("apply_patch") => ApplyPatch
        Some("mcp") => MCP
        Some(s) => Native(s)
        _ => Function
      }
      Ok({ name, description, parameters_json, strict, kind, })
    }
    _ => Err("expected object for LucentTool")
  }
}

///|
/// === LucentToolChoice ===
pub fn LucentToolChoice::from_json(
  jv : Json,
) -> Result[LucentToolChoice, String] {
  match jv {
    String(s) =>
      match s {
        "auto" => Ok(Auto)
        "none" => Ok(None)
        "required" => Ok(Required)
        // 未知字符串值 → Native 原样保留（治理：未知值不得丢失；此前直接
        // Err，再被 request 层软失败吞成 None=无约束，语义反转）
        other => Ok(Native(other))
      }
    Object(m) =>
      match m.get("type") {
        Some(String(tp)) if tp == "specific_tool" =>
          match m.get("name") {
            Some(String(name)) => Ok(SpecificTool(name))
            Some(_) => Err("expected string for name")
            None => Err("missing name for specific_tool")
          }
        Some(String(other)) =>
          // 未知对象 type：保留 type 串（name 若有则并入，逗号分隔）
          match m.get("name") {
            Some(String(nm)) => Ok(Native(other + "," + nm))
            _ => Ok(Native(other))
          }
        Some(_) => Err("expected string for type in tool_choice object")
        None => Err("missing type in tool_choice object")
      }
    _ => Err("expected string or object for LucentToolChoice")
  }
}

///|
/// === LucentStructuredOutput ===
pub fn LucentStructuredOutput::from_json(
  jv : Json,
) -> Result[LucentStructuredOutput, String] {
  match jv {
    String(s) =>
      match s {
        "json_object" => Ok(JsonObject)
        "text" => Ok(Text)
        // 未知字符串值 → Native 原样保留（此前 Err → 被 options 层软失败
        // 吞成 None，结构化输出配置静默消失）
        other => Ok(Native(other))
      }
    Object(m) =>
      match m.get("type") {
        Some(String(tp)) if tp == "json_schema" =>
          match m.get("schema") {
            Some(schema) => Ok(JsonSchema(schema.stringify()))
            None => Err("missing schema for json_schema")
          }
        Some(String(other)) =>
          // 未知对象 type：保留 type 串，schema 若存在则附在冒号后
          match m.get("schema") {
            Some(schema) => Ok(Native(other + ":" + schema.stringify()))
            None => Ok(Native(other))
          }
        Some(_) => Err("expected string for type in structured_output object")
        None => Err("missing type in structured_output object")
      }
    _ => Err("expected string or object for LucentStructuredOutput")
  }
}
