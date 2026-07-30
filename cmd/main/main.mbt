///|
/// Prism WASM 导出入口
///
/// 编译后所有 `pub fn` 函数都会成为 WASM exports。
///
/// 6 个通用 IR 转换 + 5 个高层 SDK API：
/// 每个函数 String 进出，错误以 {"error": "message"} 返回。

///|
fn to_error(e : String) -> String {
  "{\"error\":\"" + e + "\"}"
}

///|
fn lookup(provider : String) -> @sdk.ProviderRegistration? {
  @sdk.match_provider_name(provider)
}

///|
/// provider JSON → LucentRequest JSON（decode request）
pub fn wasm_to_lux_req(provider : String, json_str : String) -> String {
  match lookup(provider) {
    Some(reg) =>
      match (reg.request_decode)(json_str) {
        Ok(req) => @lux.LucentRequest::to_json(req).stringify()
        Err(e) => to_error(e)
      }
    None => to_error("unknown provider: " + provider)
  }
}

///|
/// LucentRequest JSON → provider JSON（encode request）
pub fn wasm_lux_req_to_provider(provider : String, json_str : String) -> String {
  let jv = @json.parse(json_str) catch {
    _ => return to_error("json parse error")
  }
  match @lux.LucentRequest::from_json(jv) {
    Ok(req) =>
      match lookup(provider) {
        Some(reg) =>
          match (reg.request_encode)(req) {
            Ok(v) => v
            Err(e) => to_error(e)
          }
        None => to_error("unknown provider: " + provider)
      }
    Err(e) => to_error(e)
  }
}

///|
/// provider JSON → LucentResponse JSON（decode response）
pub fn wasm_to_lux_resp(provider : String, json_str : String) -> String {
  match lookup(provider) {
    Some(reg) =>
      match (reg.response_decode)(json_str) {
        Ok(resp) => @lux.LucentResponse::to_json(resp).stringify()
        Err(e) => to_error(e)
      }
    None => to_error("unknown provider: " + provider)
  }
}

///|
/// LucentResponse JSON → provider JSON（encode response）
pub fn wasm_lux_resp_to_provider(provider : String, json_str : String) -> String {
  let jv = @json.parse(json_str) catch {
    _ => return to_error("json parse error")
  }
  match @lux.LucentResponse::from_json(jv) {
    Ok(resp) =>
      match lookup(provider) {
        Some(reg) =>
          match (reg.response_encode)(resp) {
            Ok(v) => v
            Err(e) => to_error(e)
          }
        None => to_error("unknown provider: " + provider)
      }
    Err(e) => to_error(e)
  }
}

///|
/// SSE 文本 → StreamEvent JSON 数组（decode SSE）
pub fn wasm_sse_to_events(provider : String, sse_str : String) -> String {
  match lookup(provider) {
    Some(reg) =>
      match (reg.events_decode)(sse_str) {
        Ok(events) => {
          let json_arr : Array[Json] = events.map(fn(ev) { ev.to_json() })
          "[" + json_arr.map(fn(j) { j.stringify() }).join(",") + "]"
        }
        Err(e) => to_error(e)
      }
    None => to_error("unknown provider: " + provider)
  }
}

///|
/// StreamEvent JSON 数组 → SSE 文本（encode SSE）
pub fn wasm_events_to_sse(provider : String, json_str : String) -> String {
  let jv = @json.parse(json_str) catch {
    _ => return to_error("json parse error")
  }
  match jv {
    Array(arr) => {
      let events : Array[@lux.LucentStreamEvent] = []
      let mut i = 0
      while i < arr.length() {
        match @lux.LucentStreamEvent::from_json(arr[i]) {
          Ok(ev) => events.push(ev)
          Err(e) => return to_error("event " + i.to_string() + ": " + e)
        }
        i = i + 1
      }
      match lookup(provider) {
        Some(reg) =>
          match (reg.events_encode)(events) {
            Ok(v) => v
            Err(e) => to_error(e)
          }
        None => to_error("unknown provider: " + provider)
      }
    }
    _ => to_error("expected array for stream events")
  }
}

///|
/// === SDK 层 API ===

///|
/// 对文本请求进行编码（provider JSON 出），Host 发送 HTTP
pub fn wasm_sdk_encode_req(provider : String, text : String) -> String {
  let prism = @sdk.Prism::new().with_provider(provider)
  match prism.encode_request(text, @sdk.PrismOptions::default()) {
    Ok(v) => v
    Err(e) => to_error(e)
  }
}

///|
/// 解码提供商响应 JSON → 纯文本
pub fn wasm_sdk_decode_resp(provider : String, resp_json : String) -> String {
  let prism = @sdk.Prism::new().with_provider(provider)
  match prism.decode_response(resp_json) {
    Ok(v) => v
    Err(e) => to_error(e)
  }
}

///|
/// 对文本请求进行流式编码（provider JSON 出），Host 发送 HTTP
pub fn wasm_sdk_encode_stream(provider : String, text : String) -> String {
  let prism = @sdk.Prism::new().with_provider(provider)
  match prism.encode_stream_request(text, @sdk.PrismOptions::default()) {
    Ok(v) => v
    Err(e) => to_error(e)
  }
}

///|
/// 解码提供商 SSE → PrismEvent JSON 数组
pub fn wasm_sdk_decode_sse(provider : String, sse_str : String) -> String {
  let prism = @sdk.Prism::new().with_provider(provider)
  match prism.decode_sse(sse_str) {
    Ok(events) => {
      let parts : Array[String] = []
      for ev in events {
        parts.push(prism_event_json(ev))
      }
      "[" + parts.join(",") + "]"
    }
    Err(e) => to_error(e)
  }
}

///|
/// PrismEvent → JSON 字符串（WASM 序列化）
fn prism_event_json(ev : @sdk.PrismEvent) -> String {
  match ev {
    TextDelta(s) =>
      "{\"type\":\"text_delta\",\"text\":\"" + json_escape_sdk(s) + "\"}"
    ToolCall(tc) =>
      "{\"type\":\"tool_call\",\"id\":\"" +
      json_escape_sdk(tc.id) +
      "\",\"name\":\"" +
      json_escape_sdk(tc.name) +
      "\",\"arguments\":" +
      tc.arguments_json +
      "}"
    ToolResult(tr) =>
      "{\"type\":\"tool_result\",\"tool_use_id\":\"" +
      json_escape_sdk(tr.tool_use_id) +
      "\",\"content\":\"" +
      json_escape_sdk(tr.content) +
      "\",\"is_error\":" +
      (if tr.is_error { "true" } else { "false" }) +
      "}"
    Thinking(th) =>
      "{\"type\":\"thinking\",\"text\":\"" + json_escape_sdk(th.text) + "\"}"
    Finish(fr) => {
      let r = match fr {
        Stop => "stop"
        Length => "length"
        ToolCalls => "tool_calls"
        ContentFilter => "content_filter"
        Error => "error"
      }
      "{\"type\":\"finish\",\"reason\":\"" + r + "\"}"
    }
  }
}

///|
/// JSON 字符串转义（WASM 层用）
fn json_escape_sdk(s : String) -> String {
  let mut r = ""
  let mut i = 0
  while i < s.length() {
    let cp = s[i]
    if cp == '"' {
      r = r + "\\\""
    } else if cp == '\\' {
      r = r + "\\\\"
    } else if cp == '\n' {
      r = r + "\\n"
    } else if cp == '\t' {
      r = r + "\\t"
    } else {
      r = r + "\{Int::unsafe_to_char(cp.to_int())}"
    }
    i = i + 1
  }
  r
}

///|
/// 查询 provider 能力声明
pub fn wasm_sdk_capability(provider : String) -> String {
  let prism = @sdk.Prism::new().with_provider(provider)
  match prism.capability(provider) {
    Some(c) => "{\"provider\":\"" + c.provider + "\"}"
    None => to_error("unknown provider")
  }
}

///|
fn main {
  let _ = @sdk.list_provider_names()
}
