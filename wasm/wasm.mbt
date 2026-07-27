///|
/// Prism WASM 导出层
///
/// 24 个导出函数（6 函数 × 4 适配器），纯函数，String 进出。
/// 所有错误以 JSON 格式返回：{"error": "message"}

///|
/// === 辅助 ===

///|
fn to_error(e : String) -> String {
  "{\"error\":\"" + e + "\"}"
}

///|
/// 解析 JSON → LucentRequest，再调用编码函数
fn encode_req(
  f : (@lux.LucentRequest) -> Result[String, String],
  s : String,
) -> String {
  let jv = @json.parse(s) catch { _ => return to_error("json parse error") }
  match @lux.LucentRequest::from_json(jv) {
    Ok(req) =>
      match f(req) {
        Ok(v) => v
        Err(e) => to_error(e)
      }
    Err(e) => to_error(e)
  }
}

///|
/// 解析 JSON → LucentResponse，再调用编码函数
fn encode_resp(
  f : (@lux.LucentResponse) -> Result[String, String],
  s : String,
) -> String {
  let jv = @json.parse(s) catch { _ => return to_error("json parse error") }
  match @lux.LucentResponse::from_json(jv) {
    Ok(resp) =>
      match f(resp) {
        Ok(v) => v
        Err(e) => to_error(e)
      }
    Err(e) => to_error(e)
  }
}

///|
/// 解析 JSON 数组 → Array[LucentStreamEvent]，再调用编码函数
fn encode_events(
  f : (Array[@lux.LucentStreamEvent]) -> Result[String, String],
  s : String,
) -> String {
  let jv = @json.parse(s) catch { _ => return to_error("json parse error") }
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
      match f(events) {
        Ok(v) => v
        Err(e) => to_error(e)
      }
    }
    _ => to_error("expected array for stream events")
  }
}

///|
/// @deprecated 保留未用
// fn convert(f : (String) -> Result[String, String], s : String) -> String {
//   match f(s) {
//     Ok(v) => v
//     Err(e) => to_error(e)
//   }
// }

///|
/// === OpenAI Chat（6 函数）===

///|
pub fn wasm_openai_chat_to_lux_request(json_str : String) -> String {
  match @openai_chat.openai_chat_to_lux_request(json_str) {
    Ok(req) => @lux.LucentRequest::to_json(req).stringify()
    Err(e) => to_error(e)
  }
}

///|
pub fn wasm_lux_request_to_openai_chat(json_str : String) -> String {
  encode_req(@openai_chat.lux_request_to_openai_chat, json_str)
}

///|
pub fn wasm_openai_chat_to_lux_response(json_str : String) -> String {
  match @openai_chat.openai_chat_to_lux_response(json_str) {
    Ok(resp) => @lux.LucentResponse::to_json(resp).stringify()
    Err(e) => to_error(e)
  }
}

///|
pub fn wasm_lux_response_to_openai_chat(json_str : String) -> String {
  encode_resp(@openai_chat.lux_response_to_openai_chat, json_str)
}

///|
pub fn wasm_openai_chat_sse_to_events(sse_str : String) -> String {
  match @openai_chat.openai_chat_sse_to_events(sse_str) {
    Ok(events) => {
      let json_arr : Array[Json] = events.map(fn(ev) { ev.to_json() })
      "[" + json_arr.map(fn(j) { j.stringify() }).join(",") + "]"
    }
    Err(e) => to_error(e)
  }
}

///|
pub fn wasm_lux_events_to_openai_chat_sse(json_str : String) -> String {
  encode_events(@openai_chat.lux_events_to_openai_chat_sse, json_str)
}

///|
/// === Anthropic Messages（6 函数）===

///|
pub fn wasm_anthropic_to_lux_request(json_str : String) -> String {
  match @anthropic.anthropic_to_lux_request(json_str) {
    Ok(req) => @lux.LucentRequest::to_json(req).stringify()
    Err(e) => to_error(e)
  }
}

///|
pub fn wasm_lux_request_to_anthropic(json_str : String) -> String {
  encode_req(@anthropic.lux_request_to_anthropic, json_str)
}

///|
pub fn wasm_anthropic_to_lux_response(json_str : String) -> String {
  match @anthropic.anthropic_to_lux_response(json_str) {
    Ok(resp) => @lux.LucentResponse::to_json(resp).stringify()
    Err(e) => to_error(e)
  }
}

///|
pub fn wasm_lux_response_to_anthropic(json_str : String) -> String {
  encode_resp(@anthropic.lux_response_to_anthropic, json_str)
}

///|
pub fn wasm_anthropic_sse_to_events(sse_str : String) -> String {
  match @anthropic.anthropic_sse_to_events(sse_str) {
    Ok(events) => {
      let json_arr : Array[Json] = events.map(fn(ev) { ev.to_json() })
      "[" + json_arr.map(fn(j) { j.stringify() }).join(",") + "]"
    }
    Err(e) => to_error(e)
  }
}

///|
pub fn wasm_lux_events_to_anthropic_sse(json_str : String) -> String {
  encode_events(@anthropic.lux_events_to_anthropic_sse, json_str)
}

///|
/// === OpenAI Responses（6 函数）===

///|
pub fn wasm_openai_responses_to_lux_request(json_str : String) -> String {
  match @openai_responses.openai_responses_to_lux_request(json_str) {
    Ok(req) => @lux.LucentRequest::to_json(req).stringify()
    Err(e) => to_error(e)
  }
}

///|
pub fn wasm_lux_request_to_openai_responses(json_str : String) -> String {
  encode_req(@openai_responses.lux_request_to_openai_responses, json_str)
}

///|
pub fn wasm_openai_responses_to_lux_response(json_str : String) -> String {
  match @openai_responses.openai_responses_to_lux_response(json_str) {
    Ok(resp) => @lux.LucentResponse::to_json(resp).stringify()
    Err(e) => to_error(e)
  }
}

///|
pub fn wasm_lux_response_to_openai_responses(json_str : String) -> String {
  encode_resp(@openai_responses.lux_response_to_openai_responses, json_str)
}

///|
pub fn wasm_openai_responses_sse_to_events(sse_str : String) -> String {
  match @openai_responses.openai_responses_sse_to_events(sse_str) {
    Ok(events) => {
      let json_arr : Array[Json] = events.map(fn(ev) { ev.to_json() })
      "[" + json_arr.map(fn(j) { j.stringify() }).join(",") + "]"
    }
    Err(e) => to_error(e)
  }
}

///|
pub fn wasm_lux_events_to_openai_responses_sse(json_str : String) -> String {
  encode_events(@openai_responses.lux_events_to_openai_responses_sse, json_str)
}

///|
/// === Google Gemini（6 函数）===

///|
pub fn wasm_gemini_to_lux_request(json_str : String) -> String {
  match @gemini.gemini_to_lux_request(json_str) {
    Ok(req) => @lux.LucentRequest::to_json(req).stringify()
    Err(e) => to_error(e)
  }
}

///|
pub fn wasm_lux_request_to_gemini(json_str : String) -> String {
  encode_req(@gemini.lux_request_to_gemini, json_str)
}

///|
pub fn wasm_gemini_to_lux_response(json_str : String) -> String {
  match @gemini.gemini_to_lux_response(json_str) {
    Ok(resp) => @lux.LucentResponse::to_json(resp).stringify()
    Err(e) => to_error(e)
  }
}

///|
pub fn wasm_lux_response_to_gemini(json_str : String) -> String {
  encode_resp(@gemini.lux_response_to_gemini, json_str)
}

///|
pub fn wasm_gemini_sse_to_events(sse_str : String) -> String {
  match @gemini.gemini_sse_to_events(sse_str) {
    Ok(events) => {
      let json_arr : Array[Json] = events.map(fn(ev) { ev.to_json() })
      "[" + json_arr.map(fn(j) { j.stringify() }).join(",") + "]"
    }
    Err(e) => to_error(e)
  }
}

///|
pub fn wasm_lux_events_to_gemini_sse(json_str : String) -> String {
  encode_events(@gemini.lux_events_to_gemini_sse, json_str)
}

///|
/// === OpenAI Codex（6 函数）===

///|
pub fn wasm_openai_codex_to_lux_request(json_str : String) -> String {
  match @openai_codex.codex_to_lux_request(json_str) {
    Ok(req) => @lux.LucentRequest::to_json(req).stringify()
    Err(e) => to_error(e)
  }
}

///|
pub fn wasm_lux_request_to_openai_codex(json_str : String) -> String {
  encode_req(@openai_codex.lux_request_to_codex, json_str)
}

///|
pub fn wasm_openai_codex_to_lux_response(json_str : String) -> String {
  match @openai_codex.codex_to_lux_response(json_str) {
    Ok(resp) => @lux.LucentResponse::to_json(resp).stringify()
    Err(e) => to_error(e)
  }
}

///|
pub fn wasm_lux_response_to_openai_codex(json_str : String) -> String {
  encode_resp(@openai_codex.lux_response_to_codex, json_str)
}

///|
pub fn wasm_openai_codex_sse_to_events(sse_str : String) -> String {
  match @openai_codex.codex_sse_to_events(sse_str) {
    Ok(events) => {
      let json_arr : Array[Json] = events.map(fn(ev) { ev.to_json() })
      "[" + json_arr.map(fn(j) { j.stringify() }).join(",") + "]"
    }
    Err(e) => to_error(e)
  }
}

///|
pub fn wasm_lux_events_to_openai_codex_sse(json_str : String) -> String {
  encode_events(@openai_codex.lux_events_to_codex_sse, json_str)
}

///|
/// === Azure OpenAI Responses（6 函数）===

///|
pub fn wasm_azure_to_lux_request(json_str : String) -> String {
  match @openai_azure.azure_to_lux_request(json_str) {
    Ok(req) => @lux.LucentRequest::to_json(req).stringify()
    Err(e) => to_error(e)
  }
}

///|
pub fn wasm_lux_request_to_azure(json_str : String) -> String {
  encode_req(@openai_azure.lux_request_to_azure, json_str)
}

///|
pub fn wasm_azure_to_lux_response(json_str : String) -> String {
  match @openai_azure.azure_to_lux_response(json_str) {
    Ok(resp) => @lux.LucentResponse::to_json(resp).stringify()
    Err(e) => to_error(e)
  }
}

///|
pub fn wasm_lux_response_to_azure(json_str : String) -> String {
  encode_resp(@openai_azure.lux_response_to_azure, json_str)
}

///|
pub fn wasm_azure_sse_to_events(sse_str : String) -> String {
  match @openai_azure.azure_sse_to_events(sse_str) {
    Ok(events) => {
      let json_arr : Array[Json] = events.map(fn(ev) { ev.to_json() })
      "[" + json_arr.map(fn(j) { j.stringify() }).join(",") + "]"
    }
    Err(e) => to_error(e)
  }
}

///|
pub fn wasm_lux_events_to_azure_sse(json_str : String) -> String {
  encode_events(@openai_azure.lux_events_to_azure_sse, json_str)
}

///|
/// === Google Vertex AI（6 函数）===

///|
pub fn wasm_vertex_to_lux_request(json_str : String) -> String {
  match @gemini_vertex.vertex_to_lux_request(json_str) {
    Ok(req) => @lux.LucentRequest::to_json(req).stringify()
    Err(e) => to_error(e)
  }
}

///|
pub fn wasm_lux_request_to_vertex(json_str : String) -> String {
  encode_req(@gemini_vertex.lux_request_to_vertex, json_str)
}

///|
pub fn wasm_vertex_to_lux_response(json_str : String) -> String {
  match @gemini_vertex.vertex_to_lux_response(json_str) {
    Ok(resp) => @lux.LucentResponse::to_json(resp).stringify()
    Err(e) => to_error(e)
  }
}

///|
pub fn wasm_lux_response_to_vertex(json_str : String) -> String {
  encode_resp(@gemini_vertex.lux_response_to_vertex, json_str)
}

///|
pub fn wasm_vertex_sse_to_events(sse_str : String) -> String {
  match @gemini_vertex.vertex_sse_to_events(sse_str) {
    Ok(events) => {
      let json_arr : Array[Json] = events.map(fn(ev) { ev.to_json() })
      "[" + json_arr.map(fn(j) { j.stringify() }).join(",") + "]"
    }
    Err(e) => to_error(e)
  }
}

///|
pub fn wasm_lux_events_to_vertex_sse(json_str : String) -> String {
  encode_events(@gemini_vertex.lux_events_to_vertex_sse, json_str)
}

///|
/// === SDK 层 API ===

///|
/// 对文本请求进行编码（provider JSON 出），Host 发送 HTTP
pub fn wasm_sdk_encode_request(
  provider : String,
  text : String,
) -> String {
  let prism = @sdk.Prism::new().with_provider(provider)
  match prism.encode_request(text, @sdk.PrismOptions::default()) {
    Ok(v) => v
    Err(e) => to_error(e)
  }
}

///|
/// 解码提供商响应 JSON → 纯文本
pub fn wasm_sdk_decode_response(
  provider : String,
  resp_json : String,
) -> String {
  let prism = @sdk.Prism::new().with_provider(provider)
  match prism.decode_response(resp_json) {
    Ok(v) => v
    Err(e) => to_error(e)
  }
}

///|
/// 对文本请求进行流式编码（provider JSON 出），Host 发送 HTTP
pub fn wasm_sdk_encode_stream(
  provider : String,
  text : String,
) -> String {
  let prism = @sdk.Prism::new().with_provider(provider)
  match prism.encode_stream_request(text, @sdk.PrismOptions::default()) {
    Ok(v) => v
    Err(e) => to_error(e)
  }
}

///|
/// 解码提供商 SSE → PrismEvent JSON 数组
pub fn wasm_sdk_decode_sse(
  provider : String,
  sse_str : String,
) -> String {
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
    TextDelta(s) => "{\"type\":\"text_delta\",\"text\":\"" + json_escape_sdk(s) + "\"}"
    ToolCall(tc) => "{\"type\":\"tool_call\",\"id\":\"" + json_escape_sdk(tc.id) +
      "\",\"name\":\"" + json_escape_sdk(tc.name) +
      "\",\"arguments\":" + tc.arguments_json + "}"
    ToolResult(tr) => "{\"type\":\"tool_result\",\"tool_use_id\":\"" +
      json_escape_sdk(tr.tool_use_id) + "\",\"content\":\"" +
      json_escape_sdk(tr.content) + "\",\"is_error\":" +
      (if tr.is_error { "true" } else { "false" }) + "}"
    Thinking(th) => "{\"type\":\"thinking\",\"text\":\"" + json_escape_sdk(th.text) +
      "\"}"
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
    if cp == '"' { r = r + "\\\"" }
    else if cp == '\\' { r = r + "\\\\" }
    else if cp == '\n' { r = r + "\\n" }
    else if cp == '\t' { r = r + "\\t" }
    else { r = r + "\{Int::unsafe_to_char(cp.to_int())}" }
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
