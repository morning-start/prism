///|
/// 标准 LucentOptions 字段 × 4 目标的「有表示 / 有诊断 / 静默丢弃」契约测试
///
/// 背景：audit 发现 11 个静默丢弃格 —— 标准 options 字段在无法承载它的目标上
/// 被整体丢弃且无任何诊断，违反 AGENTS.md 硬规则「不支持的能力必须显式报错，
/// 绝不静默丢弃」。本文件把 4×N 矩阵变成可执行断言。
///
/// 判定口径（与 docs/fidelity-matrix.md 的 Exact/Degraded/Unsupported 一致）：
///   - 目标原生支持 → 输出中出现对应 wire 字段（EXACT）
///   - 目标不支持   → 输出中不出现，但 diagnostics 含该字段的 Degraded/Unsupported
///   - 二者皆无     → 断言失败（静默丢弃）

///|
/// 构造最小请求（单条 user 文本），options 由调用方给定。
fn mtx_req(opts : @lux.LucentOptions) -> @lux.LucentRequest {
  @lux.LucentRequest::new(
    "gpt-4o",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [@lux.LucentContent::text("Hi")]),
      ),
    ],
    None,
    None,
    opts,
    None,
    None,
    None,
    None,
  )
}

///|
/// 构造指定 options 的请求（只设需测字段，其余缺省）。
fn mtx_opts(
  top_k : Int32?,
  candidate_count : Int32?,
  stop : Array[String]?,
  so : @lux.LucentStructuredOutput?,
) -> @lux.LucentOptions {
  @lux.LucentOptions::new(
    None,
    None,
    top_k,
    None,
    stop,
    false,
    candidate_count,
    so,
    None,
    None,
  )
}

///|
/// 输出中是否含任一 marker（原生表示）
fn mtx_represented(out : String, markers : Array[String]) -> Bool {
  for m in markers {
    if out.contains(m) {
      return true
    }
  }
  false
}

///|
/// diagnostics 中是否有 field 含 token 的非 Exact 诊断
fn mtx_diagnosed(cr : @lux.ConversionResult[String], token : String) -> Bool {
  for d in cr.diagnostics() {
    if d.field.contains(token) {
      match d.status() {
        Degraded | Unsupported => return true
        _ => ()
      }
    }
  }
  false
}

///|
/// 「有表示或有诊断」断言：target 名仅用于失败信息。
///
/// `Err` 也算通过：拒绝（如 previous_response_id 无历史时）是比诊断更强的
/// 显式响应，同样满足「绝不静默丢弃」。只有「Ok 但既无 wire 字段又无诊断」
/// 才判为静默丢弃。
fn mtx_assert(
  label : String,
  target : String,
  res : Result[@lux.ConversionResult[String], String],
  markers : Array[String],
  token : String,
) -> Unit raise {
  match res {
    Err(_) => ()
    Ok(cr) => {
      let ok = mtx_represented(cr.value(), markers) || mtx_diagnosed(cr, token)
      if !ok {
        fail(
          label +
          " silently dropped at " +
          target +
          " (no wire field, no diagnostic): " +
          cr.value(),
        )
      }
    }
  }
}

///|
/// 对 4 个目标统一断言「top_k 有表示或有诊断」。
test "options matrix - top_k is never silently dropped" {
  let req = mtx_req(mtx_opts(Some(40), None, None, None))
  let markers = ["\"top_k\":40", "\"topK\":40"]
  mtx_assert(
    "top_k",
    "openai",
    @openai.lux_request_to_openai(req),
    markers,
    "top_k",
  )
  mtx_assert(
    "top_k",
    "responses",
    @responses.lux_request_to_responses(req),
    markers,
    "top_k",
  )
  mtx_assert(
    "top_k",
    "messages",
    @messages.lux_request_to_messages(req),
    markers,
    "top_k",
  )
  mtx_assert(
    "top_k",
    "gemini",
    @gemini.lux_request_to_gemini(req),
    markers,
    "top_k",
  )
}

///|
/// candidate_count：openai 有原生对等参数 `n`，gemini 有 `candidateCount`，
/// responses/messages 无载体 → 必须有诊断。
test "options matrix - candidate_count maps to n or is diagnosed" {
  let req = mtx_req(mtx_opts(None, Some(3), None, None))
  // openai：`n` 与 candidate_count 同义（官方 spec: "How many chat completion
  // choices to generate for each input message"）→ 精确映射，无诊断
  match @openai.lux_request_to_openai(req) {
    Ok(cr) => assert_true(cr.value().contains("\"n\":3"))
    Err(e) => fail("openai encode failed: " + e)
  }
  let markers = ["\"n\":3", "\"candidateCount\":3"]
  mtx_assert(
    "candidate_count",
    "responses",
    @responses.lux_request_to_responses(req),
    markers,
    "candidate_count",
  )
  mtx_assert(
    "candidate_count",
    "messages",
    @messages.lux_request_to_messages(req),
    markers,
    "candidate_count",
  )
  mtx_assert(
    "candidate_count",
    "gemini",
    @gemini.lux_request_to_gemini(req),
    markers,
    "candidate_count",
  )
}

///|
/// stop：openai(`stop`)/messages(`stop_sequences`)/gemini(`stopSequences`) 有载体；
/// responses 无 → 必须诊断。
test "options matrix - stop is never silently dropped" {
  let req = mtx_req(mtx_opts(None, None, Some(["END"]), None))
  let markers = ["\"stop\":[", "\"stop_sequences\":[", "\"stopSequences\":["]
  mtx_assert(
    "stop",
    "openai",
    @openai.lux_request_to_openai(req),
    markers,
    "stop",
  )
  mtx_assert(
    "stop",
    "responses",
    @responses.lux_request_to_responses(req),
    markers,
    "stop",
  )
  mtx_assert(
    "stop",
    "messages",
    @messages.lux_request_to_messages(req),
    markers,
    "stop",
  )
  mtx_assert(
    "stop",
    "gemini",
    @gemini.lux_request_to_gemini(req),
    markers,
    "stop",
  )
}

///|
/// structured_output = Native(tag)：4 个目标都没有该原生值的载体 →
/// 4 个目标都必须有诊断（此前 messages/gemini 静默丢弃）。
test "options matrix - native structured_output is diagnosed everywhere" {
  let req = mtx_req(mtx_opts(None, None, None, Some(Native("yaml"))))
  let markers : Array[String] = []
  let token = "structured_output"
  mtx_assert(
    "so=Native",
    "openai",
    @openai.lux_request_to_openai(req),
    markers,
    token,
  )
  mtx_assert(
    "so=Native",
    "responses",
    @responses.lux_request_to_responses(req),
    markers,
    token,
  )
  mtx_assert(
    "so=Native",
    "messages",
    @messages.lux_request_to_messages(req),
    markers,
    token,
  )
  mtx_assert(
    "so=Native",
    "gemini",
    @gemini.lux_request_to_gemini(req),
    markers,
    token,
  )
}

///|
/// structured_output = Text：gemini 无显式 text 模式（默认即 text）→ 必须诊断。
test "options matrix - structured_output text diagnosed at gemini" {
  let req = mtx_req(mtx_opts(None, None, None, Some(Text)))
  mtx_assert(
    "so=Text",
    "gemini",
    @gemini.lux_request_to_gemini(req),
    [],
    "structured_output",
  )
}

///|
/// structured_output = JsonObject：messages 无"任意 JSON 对象"模式 →
/// 必须诊断，且产出的 schema 必须是合法 JSON Schema（不能是空 `{}`）。
test "options matrix - messages JsonObject widens to legal schema with diagnostic" {
  let req = mtx_req(mtx_opts(None, None, None, Some(JsonObject)))
  match @messages.lux_request_to_messages(req) {
    Err(e) => fail("messages encode failed: " + e)
    Ok(cr) => {
      let s = cr.value()
      // 不是伪造的空 schema
      assert_false(s.contains("\"schema\":{}"))
      // 是合法的最宽 schema
      assert_true(s.contains("\"schema\":{\"type\":\"object\"}"))
      // 且带诊断
      assert_true(mtx_diagnosed(cr, "structured_output"))
    }
  }
}

///|
/// === 解码侧：extras 泄漏修复 ===
///
/// 缺陷：源协议 wire 专属字段（IR 无载体）会落入 `options.extras`，而
/// `extras` 在编码任何目标时都被原样回写 → 目标协议收到自己不认识的字段
/// （可能 400），且跨端时源协议的 `messages`/`input` 之类还会与目标自产键
/// 撞名。修复方式：IR **有**同名同义标准字段时提升为字段而非留在 extras。
///
/// 断言：`top_k`（OpenAI 兼容网关普遍支持）与 `n`（= candidate_count）
/// 在解码后落入标准字段，extras 中不再残留。

///|
/// openai 解码：top_k 提升为标准字段，n → candidate_count
test "options decode - openai top_k and n become standard fields" {
  let src = "{\"model\":\"gpt-4o\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"top_k\":40,\"n\":3}"
  match @openai.openai_to_lux_request(src) {
    Err(e) => fail("openai decode failed: " + e)
    Ok(cr) => {
      assert_eq(cr.value().options.top_k, Some(40))
      assert_eq(cr.value().options.candidate_count, Some(3))
      // 二者都不应再出现在 extras 里（否则会被原样回写到其它协议）
      match cr.value().options.extras {
        Some(m) => {
          assert_false(m.contains("top_k"))
          assert_false(m.contains("n"))
        }
        None => ()
      }
    }
  }
}

///|
/// openai 解码 → messages 目标：top_k 必须是 messages 的原生字段（不是 extras 回写）
test "options decode - openai top_k reaches messages as native field" {
  let src = "{\"model\":\"gpt-4o\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"top_k\":40}"
  match @openai.openai_to_lux_request(src) {
    Err(e) => fail("decode failed: " + e)
    Ok(cr) =>
      match @messages.lux_request_to_messages(cr.value()) {
        Err(e) => fail("encode failed: " + e)
        Ok(out) => {
          assert_true(out.value().contains("\"top_k\":40"))
          // 不能出现在 extras 诊断里（说明没走 extras 回写路径）
          for d in out.diagnostics() {
            assert_false(d.field.contains("extras.top_k"))
          }
        }
      }
  }
}

///|
/// openai 解码 → responses 目标：top_k 无载体 → 必须显式诊断（不再静默经 extras 泄漏）
test "options decode - openai top_k is diagnosed at responses instead of leaking" {
  let src = "{\"model\":\"gpt-4o\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"top_k\":40}"
  match @openai.openai_to_lux_request(src) {
    Err(e) => fail("decode failed: " + e)
    Ok(cr) =>
      match @responses.lux_request_to_responses(cr.value()) {
        Err(e) => fail("encode failed: " + e)
        Ok(out) => {
          // 不得出现在请求体里
          assert_false(out.value().contains("\"top_k\""))
          assert_true(mtx_diagnosed(out, "top_k"))
        }
      }
  }
}

///|
/// openai 解码 → openai 目标：n 往返必须稳定为 n（不变成 extras 里的裸键）
test "options decode - openai n round-trips as n" {
  let src = "{\"model\":\"gpt-4o\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"n\":3}"
  match @openai.openai_to_lux_request(src) {
    Err(e) => fail("decode failed: " + e)
    Ok(cr) => {
      assert_eq(cr.value().options.candidate_count, Some(3))
      match @openai.lux_request_to_openai(cr.value()) {
        Err(e) => fail("encode failed: " + e)
        Ok(out) => assert_true(out.value().contains("\"n\":3"))
      }
    }
  }
}

///|
/// responses 解码：top_k 提升为标准字段（OpenAI 兼容网关普遍接受）
test "options decode - responses top_k becomes a standard field" {
  let src = "{\"model\":\"m\",\"input\":\"hi\",\"top_k\":40}"
  match @responses.responses_to_lux_request(src) {
    Err(e) => fail("responses decode failed: " + e)
    Ok(cr) => {
      assert_eq(cr.value().options.top_k, Some(40))
      match cr.value().options.extras {
        Some(m) => assert_false(m.contains("top_k"))
        None => ()
      }
    }
  }
}

///|
/// responses 解码 → messages 目标：top_k 走原生字段而非 extras 回写
test "options decode - responses top_k reaches messages natively" {
  let src = "{\"model\":\"m\",\"input\":\"hi\",\"top_k\":40}"
  match @responses.responses_to_lux_request(src) {
    Err(e) => fail("decode failed: " + e)
    Ok(cr) =>
      match @messages.lux_request_to_messages(cr.value()) {
        Err(e) => fail("encode failed: " + e)
        Ok(out) => {
          assert_true(out.value().contains("\"top_k\":40"))
          for d in out.diagnostics() {
            assert_false(d.field.contains("extras.top_k"))
          }
        }
      }
  }
}

///|
/// === 扩展诊断契约 ===

///|
/// gemini：`stream` 不在请求体（由端点路径 streamGenerateContent 决定），
/// 属"有载体但在体外"→ 必须显式 Exact 告知，不能静默。
test "options matrix - gemini stream reports its path-carried carrier" {
  let req = mtx_req(
    @lux.LucentOptions::new(
      None,
      None,
      None,
      None,
      None,
      true,
      None,
      None,
      None,
      None,
    ),
  )
  match @gemini.lux_request_to_gemini(req) {
    Err(e) => fail("gemini encode failed: " + e)
    Ok(cr) => {
      // body 里不得出现 `stream`（Gemini 无该 body 字段）
      assert_false(cr.value().contains("\"stream\":true"))
      // 必须带一条 Exact 诊断说明真实落点
      let mut found = false
      for d in cr.diagnostics() {
        if d.field == "options.stream" {
          match d.status() {
            Exact => found = true
            _ => ()
          }
        }
      }
      assert_true(found)
    }
  }
}

///|
/// gemini：Native tool_choice 无 functionCallingConfig mode 对应项 →
/// 显式 Unsupported（而非静默回退 Auto）。
test "tool_choice native is diagnosed at gemini instead of silently falling back" {
  let tc : @lux.LucentToolChoice = Native("vendor_mode")
  let req = @lux.LucentRequest::new(
    "gemini-2.5-pro",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [@lux.LucentContent::text("Hi")]),
      ),
    ],
    None,
    Some(tc),
    @lux.LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
  match @gemini.lux_request_to_gemini(req) {
    Err(e) => fail("gemini encode failed: " + e)
    Ok(cr) => {
      // 不得静默回退成 AUTO
      assert_false(cr.value().contains("\"mode\":\"AUTO\""))
      let mut found = false
      for d in cr.diagnostics() {
        if d.field == "tool_choice" && d.status() is Unsupported {
          found = true
        }
      }
      assert_true(found)
    }
  }
}

///|
/// openai：Native tool_choice 无对应项 → 显式 Unsupported 并回退 "auto"
/// （回退必须伴随诊断，不得静默）。
test "tool_choice native is diagnosed at openai instead of silently falling back" {
  let tc : @lux.LucentToolChoice = Native("vendor_mode")
  let req = @lux.LucentRequest::new(
    "gpt-4o",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [@lux.LucentContent::text("Hi")]),
      ),
    ],
    None,
    Some(tc),
    @lux.LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
  match @openai.lux_request_to_openai(req) {
    Err(e) => fail("openai encode failed: " + e)
    Ok(cr) => {
      // 回退到 auto 必须伴随诊断
      assert_true(cr.value().contains("\"tool_choice\":\"auto\""))
      let mut found = false
      for d in cr.diagnostics() {
        if d.field == "tool_choice" && d.status() is Unsupported {
          found = true
        }
      }
      assert_true(found)
    }
  }
}
