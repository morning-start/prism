///|
/// G5 跨协议差分属性 — 同一 IR 经 4 端点 encode→decode 回 IR 归一化一致
///
/// 依据：.agent-workplace/docs/design/formal-verification-design.md G5 ↔ M3；
/// AGENTS.md「归一化到 IR 优先，不写两两直连」。
/// 断言：公共交集无损子集（gen_text_req / gen_text_resp）内，
///   encode(req) → decode → req' 对 4 端点成立，且四者互相相等（Eq）。
/// 语义：无论从哪个端点进出，得到的 IR 必须相同 —— IR 归一化不变量。
/// 补充：现有 cross_protocol_test.mbt（实例级 812 例）与本属性互为补充。

///|
/// 单端点请求 round-trip：encode → decode，返回解码后的 IR（任一步失败为 None）
fn roundtrip_req(
  encode : (@lux.LucentRequest) -> Result[@lux.ConversionResult[String], String],
  decode : (String) -> Result[@lux.ConversionResult[@lux.LucentRequest], String],
  req : @lux.LucentRequest,
) -> @lux.LucentRequest? {
  match encode(req) {
    Err(_) => None
    Ok(cr) =>
      match decode(cr.value()) {
        Err(_) => None
        Ok(dcr) => Some(dcr.value())
      }
  }
}

///|
/// 单端点响应 round-trip：encode → decode，返回解码后的 IR（任一步失败为 None）
fn roundtrip_resp(
  encode : (@lux.LucentResponse) -> Result[
    @lux.ConversionResult[String],
    String,
  ],
  decode : (String) -> Result[
    @lux.ConversionResult[@lux.LucentResponse],
    String,
  ],
  resp : @lux.LucentResponse,
) -> @lux.LucentResponse? {
  match encode(resp) {
    Err(_) => None
    Ok(cr) =>
      match decode(cr.value()) {
        Err(_) => None
        Ok(dcr) => Some(dcr.value())
      }
  }
}

///|
/// 请求差分属性：4 端点 round-trip 的 IR 全部成功且互相相等
fn cross_protocol_diff_req_ok(req : @lux.LucentRequest) -> Bool {
  let a = roundtrip_req(
    @openai.lux_request_to_openai, @openai.openai_to_lux_request, req,
  )
  let b = roundtrip_req(
    @messages.lux_request_to_messages, @messages.messages_to_lux_request, req,
  )
  let c = roundtrip_req(
    @responses.lux_request_to_responses, @responses.responses_to_lux_request, req,
  )
  let d = roundtrip_req(
    @gemini.lux_request_to_gemini, @gemini.gemini_to_lux_request, req,
  )
  let ok = match (a, b, c, d) {
    (Some(x), Some(y), Some(z), Some(w)) => x == y && y == z && z == w
    _ => false
  }
  ok
}

///|
/// 响应差分属性：4 端点 round-trip 的 IR 全部成功且互相相等
fn cross_protocol_diff_resp_ok(resp : @lux.LucentResponse) -> Bool {
  let a = roundtrip_resp(
    @openai.lux_response_to_openai, @openai.openai_to_lux_response, resp,
  )
  let b = roundtrip_resp(
    @messages.lux_response_to_messages, @messages.messages_to_lux_response, resp,
  )
  let c = roundtrip_resp(
    @responses.lux_response_to_responses, @responses.responses_to_lux_response, resp,
  )
  let d = roundtrip_resp(
    @gemini.lux_response_to_gemini, @gemini.gemini_to_lux_response, resp,
  )
  match (a, b, c, d) {
    (Some(x), Some(y), Some(z), Some(w)) => x == y && y == z && z == w
    _ => false
  }
}

///|
test "qc G5 cross-protocol diff - request (text subset)" {
  @qc.quick_check(@qc.forall(gen_text_req(), cross_protocol_diff_req_ok))
}

///|
test "qc G5 cross-protocol diff - response (text subset)" {
  @qc.quick_check(@qc.forall(gen_text_resp(), cross_protocol_diff_resp_ok))
}
