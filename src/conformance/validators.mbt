///|
/// 协议符合性验证器（Protocol Conformance）
///
/// 目的：验证各 provider 编码输出是否符合**目标协议 wire format**，
/// 而不是只做 round-trip 语义等价（后者测不出"编码出的 JSON 会被真实
/// API 拒绝"的问题，例如 responses 的 `id` 字段必须是非空字符串）。
///
/// 用法：对每个协议定义 check_*_request / check_*_response，输入编码后的
/// JSON 字符串，返回违规列表（空 = 通过）。
///
/// 校验维度：
///   1. 必含字段（缺失 → 违规）
///   2. 字段类型（string / number / array / object / bool）
///   3. 字段特征（id 非空、role 枚举合法、arguments 合法 JSON、object 标识等）
///
/// 本包仅依赖 core/json（纯校验，零 provider 依赖），供各测试子包复用。

///|
/// === JSON 访问辅助 ===
fn obj_get(jv : Json, key : String) -> Json? {
  match jv {
    Object(m) => m.get(key)
    _ => None
  }
}

///|
/// 取字符串字段；非字符串或缺失返回 None
fn field_str(jv : Json, key : String) -> String? {
  match obj_get(jv, key) {
    Some(String(s)) => Some(s)
    _ => None
  }
}

///|
/// 取数组字段；非数组或缺失返回 None
fn field_arr(jv : Json, key : String) -> Array[Json]? {
  match obj_get(jv, key) {
    Some(Array(a)) => Some(a)
    _ => None
  }
}

///|
/// 取数字字段；非数字或缺失返回 None
fn field_num(jv : Json, key : String) -> Double? {
  match obj_get(jv, key) {
    Some(Number(n, ..)) => Some(n)
    _ => None
  }
}

///|
/// 取对象字段；非对象或缺失返回 None
fn field_obj(jv : Json, key : String) -> Json? {
  match obj_get(jv, key) {
    Some(Object(_)) as v => v
    _ => None
  }
}

///|
/// 从已解构的 Map 中取字符串字段（用于嵌套对象校验）
fn map_str(m : Map[String, Json], key : String) -> String? {
  match m.get(key) {
    Some(String(s)) => Some(s)
    _ => None
  }
}

///|
/// 从已解构的 Map 中取对象字段
fn map_obj(m : Map[String, Json], key : String) -> Map[String, Json]? {
  match m.get(key) {
    Some(Object(o)) => Some(o)
    _ => None
  }
}

///|
/// 校验 Map 中字符串字段必含 + 非空
fn require_map_str(
  m : Map[String, Json],
  path : String,
  key : String,
  errors : Array[String],
) -> String? {
  match map_str(m, key) {
    Some(s) => {
      if s == "" {
        val_err(errors, path + "." + key, "must not be empty")
      }
      Some(s)
    }
    None => {
      match m.get(key) {
        Some(_) => type_err(errors, path + "." + key, "a string")
        None => miss(errors, path + "." + key)
      }
      None
    }
  }
}

///|
/// 记录违规：字段缺失（required 字段必须存在）
fn miss(errors : Array[String], path : String) -> Unit {
  errors.push(path + " is missing")
}

///|
/// 记录违规：字段类型错误
fn type_err(errors : Array[String], path : String, expected : String) -> Unit {
  errors.push(path + " must be " + expected)
}

///|
/// 记录违规：字段值特征不合法
fn val_err(errors : Array[String], path : String, detail : String) -> Unit {
  errors.push(path + " " + detail)
}

///|
/// 校验字符串字段必含 + 非空
fn require_str(
  jv : Json,
  path : String,
  key : String,
  errors : Array[String],
) -> String? {
  match field_str(jv, key) {
    Some(s) => {
      if s == "" {
        val_err(errors, path + "." + key, "must not be empty")
      }
      Some(s)
    }
    None => {
      match obj_get(jv, key) {
        Some(_) => type_err(errors, path + "." + key, "a string")
        None => miss(errors, path + "." + key)
      }
      None
    }
  }
}

///|
/// 校验数组字段必含
fn require_arr(
  jv : Json,
  path : String,
  key : String,
  errors : Array[String],
) -> Array[Json]? {
  match field_arr(jv, key) {
    Some(a) => Some(a)
    None => {
      match obj_get(jv, key) {
        Some(_) => type_err(errors, path + "." + key, "an array")
        None => miss(errors, path + "." + key)
      }
      None
    }
  }
}

///|
/// 校验枚举字段：必须是字符串且 ∈ allowed
fn require_enum(
  jv : Json,
  path : String,
  key : String,
  allowed : Array[String],
  errors : Array[String],
) -> String? {
  match field_str(jv, key) {
    Some(s) =>
      if allowed.contains(s) {
        Some(s)
      } else {
        val_err(
          errors,
          path + "." + key,
          "must be one of [" + allowed.join(", ") + "], got \"" + s + "\"",
        )
        None
      }
    None => {
      match obj_get(jv, key) {
        Some(_) => type_err(errors, path + "." + key, "a string")
        None => miss(errors, path + "." + key)
      }
      None
    }
  }
}

///|
/// 校验字符串字段是合法 JSON（用于 tool 参数 / arguments）
fn require_json_str(
  jv : Json,
  path : String,
  key : String,
  errors : Array[String],
) -> Unit {
  match field_str(jv, key) {
    Some(s) => {
      // @json.parse 失败会 raise，走 catch 记录违规
      let _ = @json.parse(s) catch {
        _ => {
          val_err(errors, path + "." + key, "must be valid JSON")
          return
        }
      }
    }
    _ => ()
  }
}

///|
/// === OpenAI Chat Completions 请求验证 ===
///
/// 必含字段：model(string), messages(array)
/// messages[i]: role(枚举), content(string 或 array)
/// tools[i]: type="function", function{name, parameters}
pub fn check_openai_request(json_str : String) -> Array[String] {
  let errors : Array[String] = []
  let jv = @json.parse(json_str) catch { _ => return ["invalid JSON"] }
  let _ = require_str(jv, "req", "model", errors)
  match require_arr(jv, "req", "messages", errors) {
    Some(msgs) => {
      let mut i = 0
      while i < msgs.length() {
        let path = "req.messages[" + i.to_string() + "]"
        let _ = require_enum(
          msgs[i],
          path,
          "role",
          ["system", "user", "assistant", "tool", "developer"],
          errors,
        )
        // content 必须是 string 或 array
        match obj_get(msgs[i], "content") {
          Some(String(_)) => ()
          Some(Array(_)) => ()
          Some(_) => type_err(errors, path + ".content", "a string or array")
          None => miss(errors, path + ".content")
        }
        // tool_calls[]（响应侧/历史助手消息）
        match field_arr(msgs[i], "tool_calls") {
          Some(calls) => {
            let mut k = 0
            while k < calls.length() {
              let tpath = path + ".tool_calls[" + k.to_string() + "]"
              let _ = require_str(calls[k], tpath, "id", errors)
              match field_obj(calls[k], "function") {
                Some(fn_jv) => {
                  let _ = require_str(
                    fn_jv,
                    tpath + ".function",
                    "name",
                    errors,
                  )
                  require_json_str(
                    fn_jv,
                    tpath + ".function",
                    "arguments",
                    errors,
                  )
                }
                None => miss(errors, tpath + ".function")
              }
              k = k + 1
            }
          }
          None => ()
        }
        i = i + 1
      }
    }
    None => ()
  }
  // tools[]
  match field_arr(jv, "tools") {
    Some(tools) => {
      let mut i = 0
      while i < tools.length() {
        let path = "req.tools[" + i.to_string() + "]"
        let _ = require_enum(tools[i], path, "type", ["function"], errors)
        match field_obj(tools[i], "function") {
          Some(fn_jv) => {
            let _ = require_str(fn_jv, path + ".function", "name", errors)
            match obj_get(fn_jv, "parameters") {
              Some(Object(_)) => ()
              Some(_) =>
                type_err(errors, path + ".function.parameters", "an object")
              None => miss(errors, path + ".function.parameters")
            }
          }
          None => miss(errors, path + ".function")
        }
        i = i + 1
      }
    }
    None => ()
  }
  // stream（若含必须是 bool）
  match obj_get(jv, "stream") {
    Some(True) | Some(False) => ()
    Some(_) => type_err(errors, "req.stream", "a boolean")
    None => ()
  }
  errors
}

///|
/// === OpenAI Chat Completions 响应验证 ===
///
/// 必含字段：id(string 非空), object="chat.completion", model(string),
/// choices(array 非空)；choices[i]: index(number), message{role, content},
/// finish_reason(枚举)
pub fn check_openai_response(json_str : String) -> Array[String] {
  let errors : Array[String] = []
  let jv = @json.parse(json_str) catch { _ => return ["invalid JSON"] }
  let _ = require_str(jv, "resp", "id", errors)
  let _ = require_enum(jv, "resp", "object", ["chat.completion"], errors)
  let _ = require_str(jv, "resp", "model", errors)
  match require_arr(jv, "resp", "choices", errors) {
    Some(choices) => {
      if choices.length() == 0 {
        val_err(errors, "resp.choices", "must not be empty")
      }
      let mut i = 0
      while i < choices.length() {
        let path = "resp.choices[" + i.to_string() + "]"
        match field_num(choices[i], "index") {
          Some(_) => ()
          None => miss(errors, path + ".index")
        }
        match field_obj(choices[i], "message") {
          Some(msg_jv) => {
            let _ = require_enum(
              msg_jv,
              path + ".message",
              "role",
              ["assistant", "system", "user", "tool"],
              errors,
            )
            // content 必须存在（string 或 null 都合法，但必须含字段）
            match obj_get(msg_jv, "content") {
              Some(String(_)) => ()
              Some(Null) => ()
              Some(Array(_)) => ()
              Some(_) =>
                type_err(
                  errors,
                  path + ".message.content",
                  "a string, null or array",
                )
              None => miss(errors, path + ".message.content")
            }
          }
          None => miss(errors, path + ".message")
        }
        let _ = require_enum(
          choices[i],
          path,
          "finish_reason",
          ["stop", "length", "tool_calls", "content_filter", "function_call"],
          errors,
        )
        i = i + 1
      }
    }
    None => ()
  }
  // usage（若含必须三字段齐全且为 number）
  match field_obj(jv, "usage") {
    Some(u) =>
      for key in ["prompt_tokens", "completion_tokens", "total_tokens"] {
        match field_num(u, key) {
          Some(_) => ()
          None => miss(errors, "resp.usage." + key)
        }
      }
    None => ()
  }
  errors
}

///|
/// === OpenAI Responses 请求验证 ===
///
/// 必含字段：model(string 非空), input(array)
/// input[i].type ∈ {message, function_call, function_call_output, reasoning}
/// function_call: id/call_id/name 非空字符串 + arguments 合法 JSON
/// function_call_output: call_id 非空字符串 + output 字符串
pub fn check_responses_request(json_str : String) -> Array[String] {
  let errors : Array[String] = []
  let jv = @json.parse(json_str) catch { _ => return ["invalid JSON"] }
  let _ = require_str(jv, "req", "model", errors)
  match require_arr(jv, "req", "input", errors) {
    Some(items) => {
      let mut i = 0
      while i < items.length() {
        let path = "req.input[" + i.to_string() + "]"
        let tp = match
          require_enum(
            items[i],
            path,
            "type",
            ["message", "function_call", "function_call_output", "reasoning"],
            errors,
          ) {
          Some(t) => t
          None => {
            i = i + 1
            continue
          }
        }
        match tp {
          "message" => {
            let _ = require_enum(
              items[i],
              path,
              "role",
              ["user", "assistant", "system", "developer"],
              errors,
            )
            match field_arr(items[i], "content") {
              Some(parts) => {
                let mut k = 0
                while k < parts.length() {
                  let cpath = path + ".content[" + k.to_string() + "]"
                  let _ = require_str(parts[k], cpath, "type", errors)
                  let _ = require_str(parts[k], cpath, "text", errors)
                  k = k + 1
                }
              }
              None => miss(errors, path + ".content")
            }
          }
          "function_call" => {
            // ★ bug 根源：id 必须是非空字符串
            let _ = require_str(items[i], path, "id", errors)
            let _ = require_str(items[i], path, "call_id", errors)
            let _ = require_str(items[i], path, "name", errors)
            require_json_str(items[i], path, "arguments", errors)
          }
          "function_call_output" => {
            let _ = require_str(items[i], path, "call_id", errors)
            let _ = require_str(items[i], path, "output", errors)
          }
          "reasoning" => ()
          _ => ()
        }
        i = i + 1
      }
    }
    None => ()
  }
  // tools[]
  match field_arr(jv, "tools") {
    Some(tools) => {
      let mut i = 0
      while i < tools.length() {
        let path = "req.tools[" + i.to_string() + "]"
        let _ = require_enum(
          tools[i],
          path,
          "type",
          [
            "function", "file_search", "web_search", "code_interpreter", "computer_use",
            "mcp",
          ],
          errors,
        )
        let _ = require_str(tools[i], path, "name", errors)
        i = i + 1
      }
    }
    None => ()
  }
  errors
}

///|
/// === OpenAI Responses 响应验证 ===
///
/// 必含字段：id(string 非空), object="response", status(枚举),
/// model(string), output(array)
/// output[i].type ∈ {message, function_call, reasoning, function_call_output}
pub fn check_responses_response(json_str : String) -> Array[String] {
  let errors : Array[String] = []
  let jv = @json.parse(json_str) catch { _ => return ["invalid JSON"] }
  let _ = require_str(jv, "resp", "id", errors)
  let _ = require_enum(jv, "resp", "object", ["response"], errors)
  let _ = require_enum(
    jv,
    "resp",
    "status",
    ["completed", "incomplete", "failed"],
    errors,
  )
  let _ = require_str(jv, "resp", "model", errors)
  match require_arr(jv, "resp", "output", errors) {
    Some(items) => {
      let mut i = 0
      while i < items.length() {
        let path = "resp.output[" + i.to_string() + "]"
        let tp = match
          require_enum(
            items[i],
            path,
            "type",
            ["message", "function_call", "reasoning", "function_call_output"],
            errors,
          ) {
          Some(t) => t
          None => {
            i = i + 1
            continue
          }
        }
        match tp {
          "message" => {
            let _ = require_str(items[i], path, "id", errors)
            let _ = require_enum(items[i], path, "role", ["assistant"], errors)
            match field_arr(items[i], "content") {
              Some(parts) => {
                let mut k = 0
                while k < parts.length() {
                  let cpath = path + ".content[" + k.to_string() + "]"
                  let _ = require_str(parts[k], cpath, "type", errors)
                  let _ = require_str(parts[k], cpath, "text", errors)
                  k = k + 1
                }
              }
              None => miss(errors, path + ".content")
            }
          }
          "function_call" => {
            // ★ id 必须是非空字符串
            let _ = require_str(items[i], path, "id", errors)
            let _ = require_str(items[i], path, "call_id", errors)
            let _ = require_str(items[i], path, "name", errors)
            require_json_str(items[i], path, "arguments", errors)
          }
          _ => ()
        }
        i = i + 1
      }
    }
    None => ()
  }
  errors
}

///|
/// === Anthropic Messages 请求验证 ===
///
/// 必含字段：model(string), max_tokens(number ≥ 1), messages(array)
/// messages[i]: role(枚举), content(string 或 blocks array)
/// tools[i]: name(string), input_schema(object)
pub fn check_messages_request(json_str : String) -> Array[String] {
  let errors : Array[String] = []
  let jv = @json.parse(json_str) catch { _ => return ["invalid JSON"] }
  let _ = require_str(jv, "req", "model", errors)
  match field_num(jv, "max_tokens") {
    Some(n) => if n < 1.0 { val_err(errors, "req.max_tokens", "must be >= 1") }
    None =>
      match obj_get(jv, "max_tokens") {
        Some(_) => type_err(errors, "req.max_tokens", "a number")
        None => miss(errors, "req.max_tokens")
      }
  }
  match require_arr(jv, "req", "messages", errors) {
    Some(msgs) => {
      let mut i = 0
      while i < msgs.length() {
        let path = "req.messages[" + i.to_string() + "]"
        let _ = require_enum(
          msgs[i],
          path,
          "role",
          ["user", "assistant"],
          errors,
        )
        // content：string 或 blocks array（block type 枚举校验）
        match obj_get(msgs[i], "content") {
          Some(String(_)) => ()
          Some(Array(blocks)) => {
            let mut k = 0
            while k < blocks.length() {
              let bpath = path + ".content[" + k.to_string() + "]"
              let bt = match
                require_enum(
                  blocks[k],
                  bpath,
                  "type",
                  ["text", "image", "tool_use", "tool_result", "thinking"],
                  errors,
                ) {
                Some(t) => t
                None => {
                  k = k + 1
                  continue
                }
              }
              match bt {
                "text" => {
                  let _ = require_str(blocks[k], bpath, "text", errors)
                }
                "tool_use" => {
                  let _ = require_str(blocks[k], bpath, "id", errors)
                  let _ = require_str(blocks[k], bpath, "name", errors)
                  match obj_get(blocks[k], "input") {
                    Some(Object(_)) => ()
                    Some(_) => type_err(errors, bpath + ".input", "an object")
                    None => miss(errors, bpath + ".input")
                  }
                }
                "tool_result" => {
                  let _ = require_str(blocks[k], bpath, "tool_use_id", errors)
                }
                _ => ()
              }
              k = k + 1
            }
          }
          Some(_) => type_err(errors, path + ".content", "a string or array")
          None => miss(errors, path + ".content")
        }
        i = i + 1
      }
    }
    None => ()
  }
  // tools[]：name + input_schema
  match field_arr(jv, "tools") {
    Some(tools) => {
      let mut i = 0
      while i < tools.length() {
        let path = "req.tools[" + i.to_string() + "]"
        let _ = require_str(tools[i], path, "name", errors)
        match obj_get(tools[i], "input_schema") {
          Some(Object(_)) => ()
          Some(_) => type_err(errors, path + ".input_schema", "an object")
          None => miss(errors, path + ".input_schema")
        }
        i = i + 1
      }
    }
    None => ()
  }
  errors
}

///|
/// === Anthropic Messages 响应验证 ===
///
/// 必含字段：id(string 非空), type="message", role="assistant",
/// model(string), content(array 非空), stop_reason(枚举)
pub fn check_messages_response(json_str : String) -> Array[String] {
  let errors : Array[String] = []
  let jv = @json.parse(json_str) catch { _ => return ["invalid JSON"] }
  let _ = require_str(jv, "resp", "id", errors)
  let _ = require_enum(jv, "resp", "type", ["message"], errors)
  let _ = require_enum(jv, "resp", "role", ["assistant"], errors)
  let _ = require_str(jv, "resp", "model", errors)
  match require_arr(jv, "resp", "content", errors) {
    Some(blocks) => {
      let mut i = 0
      while i < blocks.length() {
        let bpath = "resp.content[" + i.to_string() + "]"
        let bt = match
          require_enum(
            blocks[i],
            bpath,
            "type",
            ["text", "tool_use", "thinking"],
            errors,
          ) {
          Some(t) => t
          None => {
            i = i + 1
            continue
          }
        }
        match bt {
          "text" => {
            let _ = require_str(blocks[i], bpath, "text", errors)
          }
          "tool_use" => {
            let _ = require_str(blocks[i], bpath, "id", errors)
            let _ = require_str(blocks[i], bpath, "name", errors)
          }
          _ => ()
        }
        i = i + 1
      }
    }
    None => ()
  }
  let _ = require_enum(
    jv,
    "resp",
    "stop_reason",
    ["end_turn", "max_tokens", "stop_sequence", "tool_use", "refusal"],
    errors,
  )
  errors
}

///|
/// === Google Gemini 请求验证 ===
///
/// 必含字段：contents(array)；contents[i]: role(枚举), parts(array)
/// parts[i]: text(string) 或 functionCall{name, args} / functionResponse
pub fn check_gemini_request(json_str : String) -> Array[String] {
  let errors : Array[String] = []
  let jv = @json.parse(json_str) catch { _ => return ["invalid JSON"] }
  match require_arr(jv, "req", "contents", errors) {
    Some(contents) => {
      let mut i = 0
      while i < contents.length() {
        let path = "req.contents[" + i.to_string() + "]"
        let _ = require_enum(
          contents[i],
          path,
          "role",
          ["user", "model", "tool"],
          errors,
        )
        match require_arr(contents[i], path, "parts", errors) {
          Some(parts) => {
            let mut k = 0
            while k < parts.length() {
              let ppath = path + ".parts[" + k.to_string() + "]"
              // part 必须含 text / functionCall / functionResponse / inlineData / fileData 之一
              match obj_get(parts[k], "text") {
                Some(String(_)) => ()
                Some(_) => type_err(errors, ppath + ".text", "a string")
                None => ()
              }
              match obj_get(parts[k], "functionCall") {
                Some(Object(fc)) => {
                  // name/args 在 functionCall 子对象内部
                  let _ = require_map_str(
                    fc,
                    ppath + ".functionCall",
                    "name",
                    errors,
                  )
                  // args 是 JSON 对象（非字符串）
                  match map_obj(fc, "args") {
                    Some(_) => ()
                    None =>
                      match fc.get("args") {
                        Some(_) =>
                          type_err(
                            errors,
                            ppath + ".functionCall.args",
                            "an object",
                          )
                        None => miss(errors, ppath + ".functionCall.args")
                      }
                  }
                }
                Some(_) =>
                  type_err(errors, ppath + ".functionCall", "an object")
                None => ()
              }
              match obj_get(parts[k], "functionResponse") {
                Some(Object(fr)) => {
                  // name/response 在 functionResponse 子对象内部
                  let _ = require_map_str(
                    fr,
                    ppath + ".functionResponse",
                    "name",
                    errors,
                  )
                  match map_obj(fr, "response") {
                    Some(_) => ()
                    None =>
                      match fr.get("response") {
                        Some(_) =>
                          type_err(
                            errors,
                            ppath + ".functionResponse.response",
                            "an object",
                          )
                        None =>
                          miss(errors, ppath + ".functionResponse.response")
                      }
                  }
                }
                Some(_) =>
                  type_err(errors, ppath + ".functionResponse", "an object")
                None => ()
              }
              match obj_get(parts[k], "inlineData") {
                Some(Object(_)) => ()
                Some(_) => type_err(errors, ppath + ".inlineData", "an object")
                None => ()
              }
              match obj_get(parts[k], "fileData") {
                Some(Object(_)) => ()
                Some(_) => type_err(errors, ppath + ".fileData", "an object")
                None => ()
              }
              k = k + 1
            }
          }
          None => ()
        }
        i = i + 1
      }
    }
    None => ()
  }
  errors
}

///|
/// === Google Gemini 响应验证 ===
///
/// 必含字段：candidates(array 非空)
/// candidates[i]: content{parts(array)}, finishReason(枚举)
pub fn check_gemini_response(json_str : String) -> Array[String] {
  let errors : Array[String] = []
  let jv = @json.parse(json_str) catch { _ => return ["invalid JSON"] }
  match require_arr(jv, "resp", "candidates", errors) {
    Some(cands) => {
      if cands.length() == 0 {
        val_err(errors, "resp.candidates", "must not be empty")
      }
      let mut i = 0
      while i < cands.length() {
        let path = "resp.candidates[" + i.to_string() + "]"
        match field_obj(cands[i], "content") {
          Some(content_jv) =>
            match field_arr(content_jv, "parts") {
              Some(parts) => {
                let mut k = 0
                while k < parts.length() {
                  let ppath = path + ".content.parts[" + k.to_string() + "]"
                  match obj_get(parts[k], "text") {
                    Some(String(_)) => ()
                    Some(_) => type_err(errors, ppath + ".text", "a string")
                    None => ()
                  }
                  match obj_get(parts[k], "functionCall") {
                    Some(Object(_)) => ()
                    Some(_) =>
                      type_err(errors, ppath + ".functionCall", "an object")
                    None => ()
                  }
                  k = k + 1
                }
              }
              None => miss(errors, path + ".content.parts")
            }
          None => miss(errors, path + ".content")
        }
        let _ = require_enum(
          cands[i],
          path,
          "finishReason",
          ["STOP", "MAX_TOKENS", "SAFETY", "RECITATION", "OTHER"],
          errors,
        )
        i = i + 1
      }
    }
    None => ()
  }
  errors
}
