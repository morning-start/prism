///|
/// WASM string-ABI conversion layer — branch-coverage tests for the ERROR /
/// degradation arms of the `convert.mbt` wrappers and the open `stream.mbt`
/// slots that the existing blackbox suite (`wasm_test.mbt`,
/// `stream_session_test.mbt`, `abi_version_test.mbt`) does not reach.
///
/// A WASM export cannot raise, so every wrapper catches and returns an error
/// VALUE (`{"error": ...}`). These tests drive those arms with:
///   - an unknown / unsupported provider name,
///   - a syntactically VALID but semantically wrong JSON document
///     (`@json.parse` RAISES on malformed input, so rejection is asserted on a
///      well-formed document the layer then refuses),
///   - a valid request/response whose semantics the encoder must reject,
///   - stream event kinds no static provider emits on the happy path.
///
/// Every test is prefixed `wasm convert - ` so `moon test -f "*wasm convert*"`
/// selects the whole file. Blackbox: only the public String-in/String-out
/// surface of `@wasm` is exercised (never the `memory.mbt` scratch/log ABI).

///|
/// === 辅助 ===

///|
/// 从信封取 number 字段（句柄等）；失败返回 None
fn cb_env_num(envelope : String, key : String) -> Int32? {
  let jv = @json.parse(envelope) catch { _ => Json::null() }
  match jv {
    Object(map) =>
      match map.get(key) {
        Some(Number(n, ..)) => Some(n.to_int())
        _ => None
      }
    _ => None
  }
}

///|
/// 收集信封 value 数组中每个事件对象的 "type" 字段（供事件种类断言）
fn cb_event_types(envelope : String) -> Array[String] {
  let types : Array[String] = []
  let jv = @json.parse(envelope) catch { _ => Json::null() }
  match jv {
    Object(map) =>
      match map.get("value") {
        Some(Array(items)) =>
          for item in items {
            match item {
              Object(ev) =>
                match ev.get("type") {
                  Some(String(t)) => types.push(t)
                  _ => ()
                }
              _ => ()
            }
          }
        _ => ()
      }
    _ => ()
  }
  types
}

///|
/// === LucentRequest / LucentResponse from_json 拒绝非对象（convert.mbt:46, 83）===

///|
/// 合法但非对象的 JSON（数组 / 数字 / 字符串）→ LucentRequest::from_json 与
/// LucentResponse::from_json 均走 `_ => Err("expected object ...")` 臂。
/// 覆盖 wasm_lux_request_to_provider:46 与 wasm_lux_response_to_provider:83。
test "wasm convert - lux_to_provider rejects non-object JSON" {
  let non_objects = ["[]", "123", "\"text\""]
  for input in non_objects {
    let req_result = @wasm.wasm_lux_request_to_provider("openai", input)
    assert_true(req_result.contains("error"))
    assert_true(req_result.contains("expected object for LucentRequest"))
    let resp_result = @wasm.wasm_lux_response_to_provider("openai", input)
    assert_true(resp_result.contains("error"))
    assert_true(resp_result.contains("expected object for LucentResponse"))
  }
}

///|
/// === 请求编码拒绝 previous_response_id 无历史（convert.mbt:42）===

///|
/// 合法 LucentRequest（from_json 成功）携带 previous_response_id 但会话为空 →
/// openai-chat 编码器显式拒绝（Responses 有状态续接无法降级到无状态端点）。
/// 覆盖 wasm_lux_request_to_provider:42 的 request_encode Err 臂。
test "wasm convert - request encode rejects previous_response_id without history" {
  let opts = @lux.LucentOptions::default().with_previous_response_id(
    Some("resp_prev"),
  )
  let req = @lux.LucentRequest::new(
    "gpt-4o",
    None,
    [],
    None,
    None,
    opts,
    None,
    None,
    None,
    None,
  )
  let json_str = req.to_json().stringify()
  let result = @wasm.wasm_lux_request_to_provider("openai", json_str)
  assert_true(result.contains("error"))
  assert_true(result.contains("previous_response_id"))
}

///|
/// === 响应解码错误（convert.mbt:58）===

///|
/// 已知 provider + 畸形 JSON → openai_to_lux_response 的 parse_protocol_json
/// 返回 Err（不 raise）→ wasm_to_lux_response 的 response_decode Err 臂。
/// 覆盖 wasm_to_lux_response:58。
test "wasm convert - to_lux_response decode error on malformed JSON" {
  let bad = ["{invalid}", "not json", "{\"a\":}"]
  for input in bad {
    let result = @wasm.wasm_to_lux_response("openai", input)
    assert_true(result.contains("error"))
    assert_true(result.contains("json parse error"))
  }
}

///|
/// === 响应编码拒绝空 choices（convert.mbt:79）===

///|
/// 合法 LucentResponse（from_json 成功）但 choices 为空 → Anthropic 编码器
/// 显式拒绝（空响应无法映射为 message）。覆盖 wasm_lux_response_to_provider:79
/// 的 response_encode Err 臂。
test "wasm convert - response encode rejects empty choices" {
  let resp = @lux.LucentResponse::new("r", "m", None, [], None, None)
  let json_str = resp.to_json().stringify()
  let result = @wasm.wasm_lux_response_to_provider("messages", json_str)
  assert_true(result.contains("error"))
  assert_true(result.contains("no choices"))
}

///|
/// === events_to_sse：未知 provider（convert.mbt:127）与非数组（convert.mbt:130）===

///|
/// 合法事件数组 + 未知 provider：每个事件都能 from_json，循环走完后才到
/// lookup → None 臂（既有 "unknown provider" 用例用的是无法解析的
/// `{"Done":{}}`，在事件解析处就返回，到不了 127）。覆盖 wasm_events_to_sse:127。
test "wasm convert - events_to_sse unknown provider with valid events" {
  let meta = @lux.LucentConversationMeta::new(Some("r1"), Some("gpt-4o"), None)
  let bt = @lux.LucentBlockType::text()
  let events : Array[@lux.LucentStreamEvent] = [
    ConversationStart(meta),
    BlockStart(0, bt),
    BlockDelta(0, @lux.LucentBlockDelta::text_delta("hi")),
    BlockEnd(0),
    Finish(Stop),
    Done,
  ]
  let json_arr = events.map(fn(ev) { ev.to_json() })
  let json_str = "[" + json_arr.map(fn(j) { j.stringify() }).join(",") + "]"
  let result = @wasm.wasm_events_to_sse("invalid-provider", json_str)
  assert_true(result.contains("error"))
  assert_true(result.contains("unknown provider"))
}

///|
/// 合法但非数组 JSON（对象 / 数字 / 字符串）→ match jv 的 `_` 臂。
/// 覆盖 wasm_events_to_sse:130（既有 "invalid JSON" 用例的 "not-array" 在
/// @json.parse 处就 raise-catch 返回，到不了 130）。
test "wasm convert - events_to_sse rejects non-array JSON" {
  let non_arrays = ["{}", "123", "\"text\""]
  for input in non_arrays {
    let result = @wasm.wasm_events_to_sse("openai", input)
    assert_true(result.contains("error"))
    assert_true(result.contains("expected array for stream events"))
  }
}

///|
/// === sdk_decode_sse：prism_event_to_json 的事件分支（convert.mbt:196,201,215,219）===

///|
/// 单条 openai SSE 依次产出 Thinking（reasoning_content）、ToolCall
/// （tool_calls + arguments，arguments_json 为合法 JSON → parse 成功，不走
/// catch 降级）、Finish(tool_calls)。一次 decode_sse 覆盖 ToolCall/Thinking/
/// Finish 三个 prism_event_to_json 臂及其 arguments 解析行。
test "wasm convert - sdk_decode_sse emits tool_call thinking finish" {
  let sse = "data: {\"id\":\"c\",\"object\":\"chat.completion.chunk\",\"choices\":[{\"index\":0,\"delta\":{\"reasoning_content\":\"pondering\"},\"finish_reason\":null}]}\n\n" +
    "data: {\"id\":\"c\",\"object\":\"chat.completion.chunk\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"call_1\",\"type\":\"function\",\"function\":{\"name\":\"lookup\",\"arguments\":\"{\\\"q\\\":1}\"}}]},\"finish_reason\":null}]}\n\n" +
    "data: {\"id\":\"c\",\"object\":\"chat.completion.chunk\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"tool_calls\"}]}\n\n" +
    "data: [DONE]\n\n"
  let result = @wasm.wasm_sdk_decode_sse("openai", sse)
  let types = cb_event_types(result)
  assert_true(types.contains("thinking"))
  assert_true(types.contains("tool_call"))
  assert_true(types.contains("finish"))
  // tool_call 的 name 与 arguments 解析出的对象键均在信封中
  assert_true(result.contains("lookup"))
  assert_true(result.contains("pondering"))
  // finish reason "tool_calls" 由 ToolCalls 变体映射而来
  assert_true(result.contains("\"reason\":\"tool_calls\""))
}

///|
/// === sdk_decode_sse：ToolResult 分支（convert.mbt:205, 212）===

///|
/// responses provider 的 function_call_output item → ItemStart(ToolResult) →
/// PrismEvent::ToolResult（is_error 恒为 false：responses 解码只产 ok 结果）。
/// 覆盖 prism_event_to_json 的 ToolResult 臂（205）与 is_error=false 分支（212）。
/// 注：is_error=true（210）无任何静态 provider 的流能产出，见报告。
test "wasm convert - sdk_decode_sse emits tool_result" {
  let sse = "event: response.output_item.added\n" +
    "data: {\"type\":\"response.output_item.added\",\"output_index\":0,\"item\":{\"type\":\"function_call_output\",\"call_id\":\"call_9\",\"output\":\"the answer\"}}\n\n"
  let result = @wasm.wasm_sdk_decode_sse("responses", sse)
  assert_true(result.contains("\"tool_result\""))
  assert_true(result.contains("call_9"))
  assert_true(result.contains("the answer"))
  // is_error=false 分支（Json::boolean(false)）
  assert_true(result.contains("\"is_error\":false"))
}

///|
/// ToolCall 的 arguments_json 非法（非 JSON 文本）→ @json.parse 的 catch 臂
/// 降级为原始字符串。覆盖 prism_event_to_json:202（成功解析路径由上一条测试的
/// 合法 arguments 覆盖 201）。工具块需闭合（finish）才会发射 ToolCall 事件。
test "wasm convert - sdk_decode_sse degrades invalid tool arguments" {
  let sse = "data: {\"id\":\"c\",\"object\":\"chat.completion.chunk\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"call_1\",\"type\":\"function\",\"function\":{\"name\":\"lookup\",\"arguments\":\"not-json\"}}]},\"finish_reason\":null}]}\n\n" +
    "data: {\"id\":\"c\",\"object\":\"chat.completion.chunk\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"tool_calls\"}]}\n\n" +
    "data: [DONE]\n\n"
  let result = @wasm.wasm_sdk_decode_sse("openai", sse)
  assert_true(result.contains("\"tool_call\""))
  // 非法 arguments 未解析为对象，降级保留原始字符串
  assert_true(result.contains("not-json"))
}

///|
/// openai finish_reason → LucentFinishReason → PrismFinishReason → prism
/// reason 字符串。逐变体驱动 Finish match 的每个臂，覆盖 convert.mbt:223
/// (Stop) 与 226 (ContentFilter)（Length/ToolCalls/Error 已由其它路径覆盖，
/// 一并回归）。
test "wasm convert - sdk_decode_sse finish reason variants" {
  let cases = [
    ("stop", "stop"),
    ("length", "length"),
    ("content_filter", "content_filter"),
    ("tool_calls", "tool_calls"),
    ("error", "error"),
  ]
  for pair in cases {
    let sse = "data: {\"id\":\"c\",\"object\":\"chat.completion.chunk\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"" +
      pair.0 +
      "\"}]}\n\n"
    let result = @wasm.wasm_sdk_decode_sse("openai", sse)
    assert_true(result.contains("\"reason\":\"" + pair.1 + "\""))
  }
}

///|
/// === convert_response / convert_stream 未知 provider（convert.mbt:270, 283）===

///|
/// source 或 target 未知 → resolve_pair 提前返回 Err。
/// 覆盖 wasm_convert_response:270（既有用例只覆盖了成功路径）。
test "wasm convert - convert_response unknown provider returns error" {
  let cases = [
    ("nope-source", "{}", "messages"),
    ("openai", "{}", "nope-target"),
  ]
  for case in cases {
    let result = @wasm.wasm_convert_response(case.0, case.1, case.2)
    assert_true(result.contains("error"))
    assert_true(result.contains("unknown provider"))
  }
}

///|
/// 覆盖 wasm_convert_stream:283（convert_stream 自身的 Err 臂；注意
/// wasm_convert_stream_event 复用 convert_stream 但是另一条代码路径）。
test "wasm convert - convert_stream unknown provider returns error" {
  let cases = [
    ("nope-source", "data: {}\n\n", "messages"),
    ("openai", "data: {}\n\n", "nope-target"),
  ]
  for case in cases {
    let result = @wasm.wasm_convert_stream(case.0, case.1, case.2)
    assert_true(result.contains("error"))
    assert_true(result.contains("unknown provider"))
  }
}

///|
/// === wasm_list_providers（convert.mbt:320）===

///|
/// 该导出在既有黑盒套件中无任何调用 → 整个函数体未覆盖。返回裸 JSON 数组
/// （无信封）。覆盖 wasm_list_providers:320。
test "wasm convert - list_providers returns JSON array" {
  let result = @wasm.wasm_list_providers()
  let jv = @json.parse(result) catch { _ => Json::null() }
  match jv {
    Array(items) => {
      let names : Array[String] = []
      for item in items {
        match item {
          String(s) => names.push(s)
          _ => ()
        }
      }
      assert_true(names.contains("openai"))
      assert_true(names.contains("responses"))
      assert_true(names.contains("messages"))
      assert_true(names.contains("gemini"))
    }
    _ => fail("expected JSON array of provider names")
  }
}

///|
/// === stream.mbt：分配器扫描已占用槽位（stream.mbt:29）===

///|
/// 连续分配两个会话，释放第二个，再分配第三个：第三次分配从索引 0 扫描，
/// 必先经过仍被占用的第一个槽位（alloc_stream_slot 的 `Some(_) => ()` 臂），
/// 再复用刚释放的第二个槽位。既有 "freed slot is reused" 用例释放的是首个
/// 槽位，扫描立即命中 None，到不了 29。覆盖 alloc_stream_slot:29。
test "wasm convert - stream allocator scans occupied slot before reuse" {
  let a = @wasm.wasm_stream_new("openai", "messages")
  let ha = match cb_env_num(a, "value") {
    Some(n) => n
    None => fail("expected handle a")
  }
  let b = @wasm.wasm_stream_new("openai", "messages")
  let hb = match cb_env_num(b, "value") {
    Some(n) => n
    None => fail("expected handle b")
  }
  // 释放第二个会话（其槽位索引必大于第一个，见下方复用断言）
  let _ = @wasm.wasm_stream_free(hb)
  let c = @wasm.wasm_stream_new("openai", "messages")
  let hc = match cb_env_num(c, "value") {
    Some(n) => n
    None => fail("expected handle c")
  }
  // 第三次分配复用的正是刚释放的第二个槽位（第一个槽位仍占用，扫描必经过它）
  assert_eq(hc, hb)
  // 清理，避免向全局会话表遗留占用槽位
  let _ = @wasm.wasm_stream_free(ha)
  let _ = @wasm.wasm_stream_free(hc)
}

///|
/// === stream.mbt：free 越界句柄（stream.mbt:96）===

///|
/// wasm_stream_free 的越界守卫（handle < 0 或 >= 长度）提前返回错误。
/// 既有 "invalid handle" 用例只覆盖了 feed/finish 的 None 臂，未覆盖 free 的
/// 越界臂。覆盖 wasm_stream_free:96。
test "wasm convert - stream_free invalid handle returns error" {
  let too_big = @wasm.wasm_stream_free(1_000_000)
  assert_true(too_big.contains("\"error\""))
  let negative = @wasm.wasm_stream_free(-1)
  assert_true(negative.contains("\"error\""))
}
