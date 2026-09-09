///|
/// 属性级 conformance — 随机 IR 编码输出必须通过目标协议 wire-format 校验
///
/// 依据：.agent-workplace/docs/design/formal-verification-design.md G6 ↔ M6；
/// 现有 protocol_conformance_test.mbt 是固定夹具（std_request/std_response），
/// 本文件用 @qc 生成器把 conformance 升级为属性断言：
///   gen_text_req / gen_text_resp（公共交集无损子集）→ 4 adapter encode →
///   @conformance.check_*_request/response 违规列表必须为空。
/// 这能捕获 round-trip 与固定夹具都测不出的输出结构违规（如 id 缺失、
/// 字段类型错误、角色枚举越界）。

///|
/// openai request：encode 输出必须通过 chat.completions 校验器
fn conf_openai_req_ok(req : @lux.LucentRequest) -> Bool {
  match @openai.lux_request_to_openai(req) {
    Err(_) => false
    Ok(cr) => @conformance.check_openai_request(cr.value()).length() == 0
  }
}

///|
/// openai response：encode 输出必须通过 chat.completions 校验器
fn conf_openai_resp_ok(resp : @lux.LucentResponse) -> Bool {
  match @openai.lux_response_to_openai(resp) {
    Err(_) => false
    Ok(cr) => @conformance.check_openai_response(cr.value()).length() == 0
  }
}

///|
/// responses request
fn conf_responses_req_ok(req : @lux.LucentRequest) -> Bool {
  match @responses.lux_request_to_responses(req) {
    Err(_) => false
    Ok(cr) => @conformance.check_responses_request(cr.value()).length() == 0
  }
}

///|
/// responses response
fn conf_responses_resp_ok(resp : @lux.LucentResponse) -> Bool {
  match @responses.lux_response_to_responses(resp) {
    Err(_) => false
    Ok(cr) => @conformance.check_responses_response(cr.value()).length() == 0
  }
}

///|
/// messages request
fn conf_messages_req_ok(req : @lux.LucentRequest) -> Bool {
  match @messages.lux_request_to_messages(req) {
    Err(_) => false
    Ok(cr) => @conformance.check_messages_request(cr.value()).length() == 0
  }
}

///|
/// messages response
fn conf_messages_resp_ok(resp : @lux.LucentResponse) -> Bool {
  match @messages.lux_response_to_messages(resp) {
    Err(_) => false
    Ok(cr) => @conformance.check_messages_response(cr.value()).length() == 0
  }
}

///|
/// gemini request
fn conf_gemini_req_ok(req : @lux.LucentRequest) -> Bool {
  match @gemini.lux_request_to_gemini(req) {
    Err(_) => false
    Ok(cr) => @conformance.check_gemini_request(cr.value()).length() == 0
  }
}

///|
/// gemini response
fn conf_gemini_resp_ok(resp : @lux.LucentResponse) -> Bool {
  match @gemini.lux_response_to_gemini(resp) {
    Err(_) => false
    Ok(cr) => @conformance.check_gemini_response(cr.value()).length() == 0
  }
}

///|
test "qc conformance - openai request/response wire format (text subset)" {
  @qc.quick_check(@qc.forall(gen_text_req(), conf_openai_req_ok))
  @qc.quick_check(@qc.forall(gen_text_resp(), conf_openai_resp_ok))
}

///|
test "qc conformance - responses request/response wire format (text subset)" {
  @qc.quick_check(@qc.forall(gen_text_req(), conf_responses_req_ok))
  @qc.quick_check(@qc.forall(gen_text_resp(), conf_responses_resp_ok))
}

///|
test "qc conformance - messages request/response wire format (text subset)" {
  @qc.quick_check(@qc.forall(gen_text_req(), conf_messages_req_ok))
  @qc.quick_check(@qc.forall(gen_text_resp(), conf_messages_resp_ok))
}

///|
test "qc conformance - gemini request/response wire format (text subset)" {
  @qc.quick_check(@qc.forall(gen_text_req(), conf_gemini_req_ok))
  @qc.quick_check(@qc.forall(gen_text_resp(), conf_gemini_resp_ok))
}
