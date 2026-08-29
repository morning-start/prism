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
      let json_arr : Array[Json] = events.map(fn(ev) { prism_event_to_json(ev) })
      wasm_envelope(Json::array(json_arr))
    }
    Err(e) => wasm_envelope_err(e)
  }
}

///|
/// PrismEvent → Json（直接构造，避免拼字符串后再解析）
fn prism_event_to_json(ev : @sdk.PrismEvent) -> Json {
  let m : Map[String, Json] = Map([])
  match ev {
    TextDelta(s) => {
      m["type"] = Json::string("text_delta")
      m["text"] = Json::string(s)
    }
    ToolCall(tc) => {
      m["type"] = Json::string("tool_call")
      m["id"] = Json::string(tc.id)
      m["name"] = Json::string(tc.name)
      // arguments_json 已是 JSON 文本；解析失败则降级为原始字符串
      m["arguments"] = @json.parse(tc.arguments_json) catch {
        _ => Json::string(tc.arguments_json)
      }
    }
    ToolResult(tr) => {
      m["type"] = Json::string("tool_result")
      m["tool_use_id"] = Json::string(tr.tool_use_id)
      m["content"] = Json::string(tr.content)
      m["is_error"] = if tr.is_error {
        Json::boolean(true)
      } else {
        Json::boolean(false)
      }
    }
    Thinking(th) => {
      m["type"] = Json::string("thinking")
      m["text"] = Json::string(th.text)
    }
    Finish(fr) => {
      m["type"] = Json::string("finish")
      m["reason"] = Json::string(
        match fr {
          Stop => "stop"
          Length => "length"
          ToolCalls => "tool_calls"
          ContentFilter => "content_filter"
          Error => "error"
        },
      )
    }
  }
  Json::object(m)
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
/// 单事件流转换：一个 SSE 事件文本 → 目标协议 SSE 事件文本
///
/// 与 wasm_convert_stream 的区别：
/// - 输入是单个 SSE 事件（如 "data: {...}\n\n"），不是完整事件流
/// - 输出是单个目标协议 SSE 事件
/// - 无状态，可高频逐事件调用
///
/// 输入要求：
/// - 必须包含完整的事件文本（含结尾 \n\n）
/// - data: [DONE] 事件应输出目标协议的流结束事件
///
/// 错误处理：
/// - 解析失败返回 {"error": "...", "diagnostics": []}
/// - 空事件（无 data: 行）返回 {"value": "", "diagnostics": []}
pub fn wasm_convert_stream_event(
  source : String,
  sse_event : String,
  target : String,
) -> String {
  // 复用现有的 convert_stream，它已支持单事件输入
  match @sdk.convert_stream(source, sse_event, target) {
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
