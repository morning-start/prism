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
fn encode_req(f : (@lux.LucentRequest) -> Result[String, String], s : String) -> String {
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
fn encode_resp(f : (@lux.LucentResponse) -> Result[String, String], s : String) -> String {
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
fn encode_events(f : (Array[@lux.LucentStreamEvent]) -> Result[String, String], s : String) -> String {
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
/// 纯转换（String → String），错误转 JSON
fn convert(f : (String) -> Result[String, String], s : String) -> String {
  match f(s) {
    Ok(v) => v
    Err(e) => to_error(e)
  }
}

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
