///|
/// 属性测试（@qc）— M2 round-trip 可逆性：decode(encode(x)) ≡ x
///
/// 依据：report/20260909-formal-verification-feasibility-report.md（L3 P0 试点）
/// 原则（遵循项目约定）：
///   1. 生成器基于 IR 构造器（@lux.*），不手写 JSON
///   2. 生成域限制在「公共交集 · 无损子集」：纯文本请求、单 Text/消息、
///      默认 options、无工具/能力/扩展字段 —— 该子集内 round-trip 应为恒等
///   3. 语义相等用派生 Eq 直接比较（LucentRequest derive(Eq, Debug)）

///|
/// 文本请求生成器：model 随机、instructions 0~1 条 Text、conversation 1~3 条
/// User/Assistant 文本消息（每条恰好一个 Text 块，避免 encode 侧多 Text 拼接致损）
fn gen_text_req() -> @gen.Gen[@lux.LucentRequest] {
  Gen(fn(size, r0) {
    let r1 = r0.split()
    let r2 = r1.split()
    let r3 = r2.split()
    let r4 = r3.split()
    // model：从固定池按随机串长度取模（长度恒非负，避免负下标）
    let models = ["gpt-4o", "gpt-4o-mini", "gpt-4.1"]
    let mstr : String = @coreqc.Arbitrary::arbitrary(size, r0)
    let model = models[mstr.length() % models.length()]
    // instructions：None 或单条 Text；文本非空（responses 端点丢弃空
    // instructions 属端点归一化差异，空文本不在公共交集无损子集内）
    let has_instr : Bool = @coreqc.Arbitrary::arbitrary(size, r1)
    let istr : String = @coreqc.Arbitrary::arbitrary(size, r2)
    let instr_text = if istr == "" { "hi" } else { istr }
    let instructions = if has_instr {
      Some([@lux.LucentContent::text(instr_text)])
    } else {
      None
    }
    // max_output_tokens 显式化：anthropic 编码在 None 时注入默认 4096，
    // 破坏 G5 跨端点差分一致性（无损子集要求该字段显式）
    let max_str : String = @coreqc.Arbitrary::arbitrary(size, r2.split())
    let max_tokens = Some(1 + max_str.length() % 4096)
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
    // conversation：1~3 条 User/Assistant 文本消息
    let nstr : String = @coreqc.Arbitrary::arbitrary(size, r3)
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
      let txt = if txt == "" { "hi" } else { txt }
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
/// 属性：openai Chat 请求 encode → decode 回 IR 后与原值相等（Eq 语义相等）
fn roundtrip_openai_req_ok(req : @lux.LucentRequest) -> Bool {
  match @openai.lux_request_to_openai(req) {
    Err(_) => false
    Ok(cr) =>
      match @openai.openai_to_lux_request(cr.value()) {
        Err(_) => false
        Ok(decoded) => decoded.value() == req
      }
  }
}

///|
test "qc round-trip openai request - text subset" {
  @qc.quick_check(@qc.forall(gen_text_req(), roundtrip_openai_req_ok))
}
