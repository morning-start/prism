///|
/// Prism WASM 导出层
///
/// 6 个通用转换函数（通过 SDK 注册表分发）+ 5 个高层 SDK API。
/// 所有函数 String 进出，错误以 JSON 格式返回：{"error": "message"}
///
/// 新增 Provider 时只需在 `sdk/provider_capability.mbt` 注册，
/// WASM 层自动支持，无需修改。

///|
/// === 辅助 ===

///|
/// 错误信封：{"error":"...","diagnostics":[]}（与成功信封的诊断字段一致）
fn wasm_envelope_err(e : String) -> String {
  "{\"error\":\"" + e + "\",\"diagnostics\":[]}"
}

///|
/// 通过 SDK 注册表查找 provider
fn lookup(provider : String) -> @sdk.ProviderRegistration? {
  @sdk.match_provider_name(provider)
}

///|
/// === 6 个通用 IR 转换函数 ===

///|
/// provider JSON → LucentRequest JSON（decode request，带诊断信封）
pub fn wasm_to_lux_request(provider : String, json_str : String) -> String {
  match lookup(provider) {
    Some(reg) =>
      match (reg.request_decode)(json_str) {
        Ok(cr) =>
          cr.envelope_json(@lux.LucentRequest::to_json(cr.value())).stringify()
        Err(e) => wasm_envelope_err(e)
      }
    None => wasm_envelope_err("unknown provider: " + provider)
  }
}

///|
/// LucentRequest JSON → provider JSON（encode request，带诊断信封）
pub fn wasm_lux_request_to_provider(
  provider : String,
  json_str : String,
) -> String {
  let jv = @json.parse(json_str) catch {
    _ => return wasm_envelope_err("json parse error")
  }
  match @lux.LucentRequest::from_json(jv) {
    Ok(req) =>
      match lookup(provider) {
        Some(reg) =>
          match (reg.request_encode)(req) {
            Ok(cr) => cr.envelope_json(Json::string(cr.value())).stringify()
            Err(e) => wasm_envelope_err(e)
          }
        None => wasm_envelope_err("unknown provider: " + provider)
      }
    Err(e) => wasm_envelope_err(e)
  }
}

///|
/// provider JSON → LucentResponse JSON（decode response，带诊断信封）
pub fn wasm_to_lux_response(provider : String, json_str : String) -> String {
  match lookup(provider) {
    Some(reg) =>
      match (reg.response_decode)(json_str) {
        Ok(cr) =>
          cr.envelope_json(@lux.LucentResponse::to_json(cr.value())).stringify()
        Err(e) => wasm_envelope_err(e)
      }
    None => wasm_envelope_err("unknown provider: " + provider)
  }
}

///|
/// LucentResponse JSON → provider JSON（encode response，带诊断信封）
pub fn wasm_lux_response_to_provider(
  provider : String,
  json_str : String,
) -> String {
  let jv = @json.parse(json_str) catch {
    _ => return wasm_envelope_err("json parse error")
  }
  match @lux.LucentResponse::from_json(jv) {
    Ok(resp) =>
      match lookup(provider) {
        Some(reg) =>
          match (reg.response_encode)(resp) {
            Ok(cr) => cr.envelope_json(Json::string(cr.value())).stringify()
            Err(e) => wasm_envelope_err(e)
          }
        None => wasm_envelope_err("unknown provider: " + provider)
      }
    Err(e) => wasm_envelope_err(e)
  }
}

///|
/// SSE 文本 → StreamEvent JSON 数组（decode SSE，带诊断信封）
pub fn wasm_sse_to_events(provider : String, sse_str : String) -> String {
  match lookup(provider) {
    Some(reg) =>
      match (reg.events_decode)(sse_str) {
        Ok(cr) => {
          let json_arr : Array[Json] = cr.value().map(fn(ev) { ev.to_json() })
          cr.envelope_json(Json::array(json_arr)).stringify()
        }
        Err(e) => wasm_envelope_err(e)
      }
    None => wasm_envelope_err("unknown provider: " + provider)
  }
}

///|
/// StreamEvent JSON 数组 → SSE 文本（encode SSE，带诊断信封）
pub fn wasm_events_to_sse(provider : String, json_str : String) -> String {
  let jv = @json.parse(json_str) catch {
    _ => return wasm_envelope_err("json parse error")
  }
  match jv {
    Array(arr) => {
      let events : Array[@lux.LucentStreamEvent] = []
      let mut i = 0
      while i < arr.length() {
        match @lux.LucentStreamEvent::from_json(arr[i]) {
          Ok(ev) => events.push(ev)
          Err(e) =>
            return wasm_envelope_err("event " + i.to_string() + ": " + e)
        }
        i = i + 1
      }
      match lookup(provider) {
        Some(reg) =>
          match (reg.events_encode)(events) {
            Ok(cr) => cr.envelope_json(Json::string(cr.value())).stringify()
            Err(e) => wasm_envelope_err(e)
          }
        None => wasm_envelope_err("unknown provider: " + provider)
      }
    }
    _ => wasm_envelope_err("expected array for stream events")
  }
}

///|
/// 无诊断信封：{"value":...,"diagnostics":[]}（形状与带诊断信封一致）
fn wasm_envelope(value : Json) -> String {
  let fields : Map[String, Json] = {
    "value": value,
    "diagnostics": Json::array([]),
  }
  Json::object(fields).stringify()
}

///|
/// === SDK 层 API ===

///|
/// 对文本请求进行编码（provider JSON 出，带诊断信封），Host 发送 HTTP
pub fn wasm_sdk_encode_request(provider : String, text : String) -> String {
  let prism = @sdk.Prism::new().with_provider(provider)
  match
    prism.encode_request_with_diagnostics(text, @sdk.PrismOptions::default()) {
    Ok(cr) => cr.envelope_json(Json::string(cr.value())).stringify()
    Err(e) => wasm_envelope_err(e)
  }
}

///|
/// 解码提供商响应 JSON → 纯文本（带诊断信封）
pub fn wasm_sdk_decode_response(
  provider : String,
  resp_json : String,
) -> String {
  let prism = @sdk.Prism::new().with_provider(provider)
  match prism.decode_response_with_diagnostics(resp_json) {
    Ok(cr) => cr.envelope_json(Json::string(cr.value().get_text())).stringify()
    Err(e) => wasm_envelope_err(e)
  }
}

///|
/// 对文本请求进行流式编码（provider JSON 出，无诊断源 → diagnostics: []）
pub fn wasm_sdk_encode_stream(provider : String, text : String) -> String {
  let prism = @sdk.Prism::new().with_provider(provider)
  match prism.encode_stream_request(text, @sdk.PrismOptions::default()) {
    Ok(v) => wasm_envelope(Json::string(v))
    Err(e) => wasm_envelope_err(e)
  }
}

///|
/// 解码提供商 SSE → PrismEvent JSON 数组（无诊断源 → diagnostics: []）
pub fn wasm_sdk_decode_sse(provider : String, sse_str : String) -> String {
  let prism = @sdk.Prism::new().with_provider(provider)
  match prism.decode_sse(sse_str) {
    Ok(events) => {
      let json_arr : Array[Json] = events.map(fn(ev) {
        @json.parse(prism_event_json(ev)) catch {
          _ => Json::null()
        }
      })
      wasm_envelope(Json::array(json_arr))
    }
    Err(e) => wasm_envelope_err(e)
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
/// 查询 provider 能力声明（无诊断源 → diagnostics: []）
pub fn wasm_sdk_capability(provider : String) -> String {
  let prism = @sdk.Prism::new().with_provider(provider)
  match prism.capability(provider) {
    Some(c) => wasm_envelope(c.to_json())
    None => wasm_envelope_err("unknown provider")
  }
}

///|
/// === 中转站协议转发（convert_* 组合入口）===

///|
/// 请求：source 协议 JSON → target 协议 JSON（带诊断信封）
pub fn wasm_convert_request(
  source : String,
  json_str : String,
  target : String,
) -> String {
  match @sdk.convert_request(source, json_str, target) {
    Ok(cr) => cr.envelope_json(Json::string(cr.value())).stringify()
    Err(e) => wasm_envelope_err(e)
  }
}

///|
/// 响应：source 协议 JSON → target 协议 JSON（带诊断信封）
pub fn wasm_convert_response(
  source : String,
  json_str : String,
  target : String,
) -> String {
  match @sdk.convert_response(source, json_str, target) {
    Ok(cr) => cr.envelope_json(Json::string(cr.value())).stringify()
    Err(e) => wasm_envelope_err(e)
  }
}

///|
/// 流式：source 协议 SSE → target 协议 SSE（带诊断信封）
pub fn wasm_convert_stream(
  source : String,
  sse_str : String,
  target : String,
) -> String {
  match @sdk.convert_stream(source, sse_str, target) {
    Ok(cr) => cr.envelope_json(Json::string(cr.value())).stringify()
    Err(e) => wasm_envelope_err(e)
  }
}

///|
/// === 查询 ===

///|
/// 全部 provider 主名称的 JSON 数组
pub fn wasm_list_providers() -> String {
  let names = @sdk.list_provider_names()
  let arr : Array[Json] = names.map(fn(n) { Json::string(n) })
  Json::array(arr).stringify()
}
