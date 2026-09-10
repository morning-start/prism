///|
/// 有损路径语义比较属性 — 端点归一化差异之外的核心语义必须保真
///
/// 依据：.agent-workplace/docs/design/formal-verification-design.md G5 ↔ M3/M4；
/// TD-FV-4（generator 域收窄导致有损路径无属性覆盖）。
/// 与 G5 全等属性互补：
///   - G5 无损子集：round-trip 后 IR 全等（Eq）
///   - 本文件有损路径：round-trip 后「核心语义投影」相等——文本内容、
///     角色、工具调用保真；仅允许文档化端点归一化差异：
///     * anthropic 注入 max_output_tokens 默认（None 时 4096）
///     * anthropic-messages 响应无 created_at 载体（丢失）
///     * messages/responses 仅编码第一个 choice（多 choice 截断）
///     * 空文本 / 空指令在各端点表示可能不同
/// 断言：放宽域生成的 IR，4 端点 round-trip 后核心投影全部一致。

///|
/// 有损请求生成器：max_output_tokens 可缺省、文本可空（放宽 G5 无损域）
fn gen_lossy_req() -> @gen.Gen[@lux.LucentRequest] {
  @gen.Gen(fn(size, r0) {
    let r1 = r0.split()
    let r2 = r1.split()
    let r3 = r2.split()
    let r4 = r3.split()
    let models = ["gpt-4o", "gpt-4o-mini", "gpt-4.1"]
    let mstr : String = @coreqc.Arbitrary::arbitrary(size, r0)
    let model = models[mstr.length() % models.length()]
    // instructions：None 或单条 Text（文本可空）
    let has_instr : Bool = @coreqc.Arbitrary::arbitrary(size, r1)
    let istr : String = @coreqc.Arbitrary::arbitrary(size, r2)
    let instructions = if has_instr {
      Some([@lux.LucentContent::text(istr)])
    } else {
      None
    }
    // max_output_tokens：可 None（anthropic 注入 4096）或显式
    let has_max : Bool = @coreqc.Arbitrary::arbitrary(size, r2.split())
    let max_str : String = @coreqc.Arbitrary::arbitrary(size, r3)
    let max_tokens = if has_max {
      Some(1 + max_str.length() % 4096)
    } else {
      None
    }
    let opts = @lux.LucentOptions::new(
      None,
      None,
      None,
      max_tokens,
      None,
      false,
      None,
      None,
      None,
      None,
    )
    // conversation：1~3 条消息（文本可空）
    let nstr : String = @coreqc.Arbitrary::arbitrary(size, r4)
    let n_msgs = 1 + nstr.length() % 3
    let conv : Array[@lux.LucentConversationItem] = []
    let mut i = 0
    while i < n_msgs {
      let r = r4.split()
      let r5 = r.split()
      let role_pick : String = @coreqc.Arbitrary::arbitrary(size, r)
      let role : @lux.LucentRole = if role_pick.length() % 2 == 0 {
        User
      } else {
        Assistant
      }
      let txt : String = @coreqc.Arbitrary::arbitrary(size, r5)
      conv.push(
        @lux.LucentConversationItem::message(
          @lux.LucentMessage::new(role, [@lux.LucentContent::text(txt)]),
        ),
      )
      i = i + 1
    }
    @lux.LucentRequest::new(
      model,
      instructions,
      conv,
      None,
      None,
      opts,
      None,
      None,
      None,
      None,
    )
  })
}

///|
/// 有损响应生成器：created_at 可缺省、多 choice（放宽 G5 无损域）
fn gen_lossy_resp() -> @gen.Gen[@lux.LucentResponse] {
  @gen.Gen(fn(size, r0) {
    let r1 = r0.split()
    let r2 = r1.split()
    let r3 = r2.split()
    let r4 = r3.split()
    let ids = ["resp-1", "chatcmpl-abc", "msg_123"]
    let models = ["gpt-4o", "claude-3-5-sonnet", "gemini-1.5-pro"]
    let idstr : String = @coreqc.Arbitrary::arbitrary(size, r0)
    let mstr : String = @coreqc.Arbitrary::arbitrary(size, r1)
    let has_created : Bool = @coreqc.Arbitrary::arbitrary(size, r2)
    let cint : Int = @coreqc.Arbitrary::arbitrary(size, r3)
    let created_at = if has_created {
      Some(cint.abs() % 2000000000)
    } else {
      None
    }
    let has_usage : Bool = @coreqc.Arbitrary::arbitrary(size, r4)
    let usint : Int = @coreqc.Arbitrary::arbitrary(size, r4.split())
    let usage = if has_usage {
      let p = usint.abs() % 10000
      Some(@lux.LucentUsage::new(p, p / 2, p + p / 2))
    } else {
      None
    }
    // choices：1~3 条（messages/responses 截断为第一个 → 有损路径）
    let nstr : String = @coreqc.Arbitrary::arbitrary(size, r4.split())
    let n_choices = 1 + nstr.length() % 3
    let choices : Array[@lux.LucentChoice] = []
    let mut i = 0
    while i < n_choices {
      let r = r4.split()
      let r_txt = r.split()
      let txt : String = @coreqc.Arbitrary::arbitrary(size, r_txt)
      let msg = @lux.LucentMessage::new(Assistant, [
        @lux.LucentContent::text(txt),
      ])
      choices.push(@lux.LucentChoice::new(i, msg, Stop, None))
      i = i + 1
    }
    @lux.LucentResponse::new(
      pick_str(idstr.length(), ids),
      pick_str(mstr.length(), models),
      created_at,
      choices,
      usage,
      None,
    )
  })
}

///|
/// 请求核心语义投影：model + instructions 文本 + 消息(角色:文本)序列。
/// 忽略 options（anthropic 注入 max_output_tokens 默认属归一化差异）
fn req_core_proj(req : @lux.LucentRequest) -> String {
  let parts : Array[String] = []
  parts.push("model:" + req.model)
  let instr = match req.instructions {
    Some(cs) => @lux.lucent_content_to_text(cs)
    None => ""
  }
  parts.push("instr:" + instr)
  for item in req.conversation {
    match item {
      Message(m) =>
        parts.push(
          m.role.to_string() + ":" + @lux.lucent_content_to_text(m.content),
        )
      _ => ()
    }
  }
  parts.join("|")
}

///|
/// 响应核心语义投影：id + model + 首 choice 的(角色:文本:finish_reason) +
/// usage。忽略 created_at（anthropic 无载体）与多余 choice（截断属归一化差异）
fn resp_core_proj(resp : @lux.LucentResponse) -> String {
  let parts : Array[String] = []
  parts.push("id:" + resp.id)
  parts.push("model:" + resp.model)
  if resp.choices.length() > 0 {
    let c = resp.choices[0]
    parts.push(
      "choice0:" +
      c.message.role.to_string() +
      ":" +
      @lux.lucent_content_to_text(c.message.content) +
      ":" +
      c.finish_reason.to_string(),
    )
  } else {
    parts.push("choice0:<none>")
  }
  match resp.usage {
    Some(u) =>
      parts.push(
        "usage:" +
        u.prompt_tokens.to_string() +
        "/" +
        u.completion_tokens.to_string() +
        "/" +
        u.total_tokens.to_string(),
      )
    None => parts.push("usage:<none>")
  }
  parts.join("|")
}

///|
/// 单端点有损 round-trip：encode → decode 后返回核心投影（任一步失败为空串）
fn lossy_req_proj(
  encode : (@lux.LucentRequest) -> Result[@lux.ConversionResult[String], String],
  decode : (String) -> Result[@lux.ConversionResult[@lux.LucentRequest], String],
  req : @lux.LucentRequest,
) -> String {
  match encode(req) {
    Err(_) => ""
    Ok(cr) =>
      match decode(cr.value()) {
        Err(_) => ""
        Ok(dcr) => req_core_proj(dcr.value())
      }
  }
}

///|
fn lossy_resp_proj(
  encode : (@lux.LucentResponse) -> Result[
    @lux.ConversionResult[String],
    String,
  ],
  decode : (String) -> Result[
    @lux.ConversionResult[@lux.LucentResponse],
    String,
  ],
  resp : @lux.LucentResponse,
) -> String {
  match encode(resp) {
    Err(_) => ""
    Ok(cr) =>
      match decode(cr.value()) {
        Err(_) => ""
        Ok(dcr) => resp_core_proj(dcr.value())
      }
  }
}

///|
/// 请求有损路径属性：4 端点 round-trip 核心投影全部一致且非空
fn lossy_req_ok(req : @lux.LucentRequest) -> Bool {
  let a = lossy_req_proj(
    @openai.lux_request_to_openai, @openai.openai_to_lux_request, req,
  )
  let b = lossy_req_proj(
    @messages.lux_request_to_messages, @messages.messages_to_lux_request, req,
  )
  let c = lossy_req_proj(
    @responses.lux_request_to_responses, @responses.responses_to_lux_request, req,
  )
  let d = lossy_req_proj(
    @gemini.lux_request_to_gemini, @gemini.gemini_to_lux_request, req,
  )
  a != "" && a == b && b == c && c == d
}

///|
/// 响应有损路径属性：4 端点 round-trip 核心投影全部一致且非空
fn lossy_resp_ok(resp : @lux.LucentResponse) -> Bool {
  let a = lossy_resp_proj(
    @openai.lux_response_to_openai, @openai.openai_to_lux_response, resp,
  )
  let b = lossy_resp_proj(
    @messages.lux_response_to_messages, @messages.messages_to_lux_response, resp,
  )
  let c = lossy_resp_proj(
    @responses.lux_response_to_responses, @responses.responses_to_lux_response, resp,
  )
  let d = lossy_resp_proj(
    @gemini.lux_response_to_gemini, @gemini.gemini_to_lux_response, resp,
  )
  a != "" && a == b && b == c && c == d
}

///|
test "qc lossy-path semantic eq - request (endpoint normalization allowed)" {
  @qc.quick_check(@qc.forall(gen_lossy_req(), lossy_req_ok))
}

///|
test "qc lossy-path semantic eq - response (endpoint normalization allowed)" {
  @qc.quick_check(@qc.forall(gen_lossy_resp(), lossy_resp_ok))
}
