///|
/// 流式侧元数据扩展通道（`ConversationStart.extra`）的逐格契约。
///
/// ## 背景
///
/// 非流式路径的扩展载体（请求侧 `options.extras`/`request.extra`、响应侧
/// `provider_payload`）都已按归属门控修完；流式路径的 `ConversationStart.extra`
/// 却只有 responses **一家**在填、**一家**在读，且读的时候无门控。四个格子的
/// 实测形态：
///
/// | 协议 | decode 填 extra | encode 读 extra |
/// |---|---|---|
/// | openai | 丢弃 `system_fingerprint` 等 → None | 不读 |
/// | responses | 全量保留（无归属判定） | **无门控**直接展开 |
/// | messages | 只填缓存计费项 | 不读 |
/// | gemini | None | 不处理 ConversationStart |
///
/// 即：openai/gemini 的元数据**根本进不了 IR**；responses 的元数据会**原样
/// 泄漏到任意目标**（源协议的请求字段被写进 response.created）。

///|
/// 是否有指定字段名的非 Exact 诊断。
fn sm_diag(cr : @lux.ConversionResult[String], field : String) -> Bool {
  for d in cr.diagnostics() {
    if d.field == field {
      match d.status() {
        Degraded | Unsupported => return true
        _ => ()
      }
    }
  }
  false
}

///|
/// SSE 的第一条 `data:` 行（元数据帧排在所有内容帧之前）。
fn sm_first_frame(sse : String) -> String {
  let mut out = ""
  for line in sse.split("\n") {
    if line.has_prefix("data: ") {
      out = line.to_owned()
      break
    }
  }
  out
}

///|
/// 从事件流里取出 ConversationStart 的 extra。
fn sm_start_extra(
  res : Result[@lux.ConversionResult[Array[@lux.LucentStreamEvent]], String],
) -> Json? raise {
  match res {
    Err(e) => fail("decode failed: " + e)
    Ok(cr) => {
      for ev in cr.value() {
        match ev {
          ConversationStart(meta) => return meta.extra
          _ => ()
        }
      }
      fail("no ConversationStart")
    }
  }
}

///|
/// openai 流式首帧 chunk 顶层的非建模字段必须进 extra —— 此前一律填 None，
/// 造成「流式丢、非流式留」的不一致（非流式 openai/response.mbt 一直保留）。
test "stream meta - openai captures unmodeled first-frame fields" {
  let sse = "data: {\"id\":\"c1\",\"model\":\"gpt-4o\",\"created\":123,\"system_fingerprint\":\"fp_x\",\"service_tier\":\"default\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"content\":\"\"}}]}\n\ndata: [DONE]\n\n"
  match sm_start_extra(@openai.openai_sse_to_events(sse)) {
    Some(v) => {
      let text = v.stringify()
      assert_true(text.contains("system_fingerprint"))
      assert_true(text.contains("service_tier"))
    }
    None => fail("expected extra to capture unmodeled fields")
  }
}

///|
/// gemini 流式首帧的 `modelStatus` 等非建模顶层字段必须进 extra
/// —— 此前 gemini 用 `new()`（extra=None），元数据无处可去。
test "stream meta - gemini captures unmodeled first-frame fields" {
  let sse = "data: {\"responseId\":\"g1\",\"modelVersion\":\"gemini-2\",\"modelStatus\":{\"status\":\"OK\"},\"candidates\":[{\"index\":0,\"content\":{\"role\":\"model\",\"parts\":[{\"text\":\"hi\"}]},\"finishReason\":\"STOP\"}]}\n\n"
  match sm_start_extra(@gemini.gemini_sse_to_events(sse)) {
    Some(v) => assert_true(v.stringify().contains("modelStatus"))
    None => fail("expected extra to capture modelStatus")
  }
}

///|
/// openai 流式编码：extra 的原生键（system_fingerprint 等）写到首帧 chunk 顶层
/// —— 此前 ConversationStart 分支完全忽略 extra。
test "stream meta - openai emits native extra keys on the first chunk" {
  let events : Array[@lux.LucentStreamEvent] = [
    ConversationStart(
      @lux.LucentConversationMeta::new_full(
        Some("c1"),
        Some("gpt-4o"),
        None,
        Some(1700000000),
        Some(
          @json.parse(
            "{\"system_fingerprint\":\"fp_z\",\"service_tier\":\"default\"}",
          ),
        ),
      ),
    ),
    BlockDelta(0, @lux.LucentBlockDelta::text_delta("hi")),
    Done,
  ]
  match @openai.lux_events_to_openai_sse(events) {
    Err(e) => fail("encode failed: " + e)
    Ok(cr) => {
      let frame = sm_first_frame(cr.value())
      assert_true(frame.contains("\"system_fingerprint\":\"fp_z\""))
      assert_true(frame.contains("\"service_tier\":\"default\""))
      assert_false(sm_diag(cr, "provider_payload.system_fingerprint"))
    }
  }
}

///|
/// gemini 流式编码：此前完全不处理 ConversationStart，元数据无处可去。
/// 现原生键（modelStatus）写到首帧顶层。
test "stream meta - gemini emits native extra keys on the first frame" {
  let events : Array[@lux.LucentStreamEvent] = [
    ConversationStart(
      @lux.LucentConversationMeta::new_full(
        Some("g1"),
        Some("gemini-2"),
        None,
        None,
        Some(@json.parse("{\"modelStatus\":{\"status\":\"OK\"}}")),
      ),
    ),
    BlockDelta(0, @lux.LucentBlockDelta::text_delta("hi")),
    Done,
  ]
  match @gemini.lux_events_to_gemini_sse(events) {
    Err(e) => fail("encode failed: " + e)
    Ok(cr) => {
      let frame = sm_first_frame(cr.value())
      assert_true(frame.contains("\"modelStatus\""))
      assert_false(sm_diag(cr, "provider_payload.modelStatus"))
    }
  }
}

///|
/// messages 流式编码：Anthropic 顶层唯一的非建模字段是 container。
test "stream meta - messages emits native extra keys on message_start" {
  let events : Array[@lux.LucentStreamEvent] = [
    ConversationStart(
      @lux.LucentConversationMeta::new_full(
        Some("m1"),
        Some("claude"),
        Some(5),
        None,
        Some(@json.parse("{\"container\":\"c-1\"}")),
      ),
    ),
    BlockDelta(0, @lux.LucentBlockDelta::text_delta("hi")),
    Done,
  ]
  match @messages.lux_events_to_messages_sse(events) {
    Err(e) => fail("encode failed: " + e)
    Ok(cr) => {
      let frame = sm_first_frame(cr.value())
      assert_true(frame.contains("\"container\":\"c-1\""))
      assert_false(sm_diag(cr, "provider_payload.container"))
    }
  }
}

///|
/// 跨端泄漏（本轮核心缺陷）：responses 的 `ConversationStart.extra` 此前
/// **无门控直接展开** —— 源协议的专属字段（如 openai 的 system_fingerprint）
/// 被原样写进 response.created，目标收到不认识的字段可能 400。
/// 现按归属门控剔除并诊断。
test "stream meta - responses gates foreign extra keys instead of leaking them" {
  let events : Array[@lux.LucentStreamEvent] = [
    ConversationStart(
      @lux.LucentConversationMeta::new_full(
        Some("r1"),
        Some("gpt-5"),
        None,
        Some(1700000000),
        Some(
          @json.parse(
            "{\"moderation\":{\"flagged\":false},\"system_fingerprint\":\"fp_leak\"}",
          ),
        ),
      ),
    ),
    Done,
  ]
  match @responses.lux_events_to_responses_sse(events) {
    Err(e) => fail("encode failed: " + e)
    Ok(cr) => {
      // moderation 是 responses 响应级原生 → 写出
      assert_true(cr.value().contains("\"moderation\":"))
      // system_fingerprint 是 openai 专属 → 剔除 + 诊断，绝不泄漏
      assert_false(cr.value().contains("fp_leak"))
      assert_true(sm_diag(cr, "provider_payload.system_fingerprint"))
    }
  }
}

///|
/// 未知键放行：厂商网关可能往首帧塞自定义字段，判定方向与请求侧 extras 一致
/// —— 只剔除**可证明属于其它协议**的键，未知键不得误丢。
test "stream meta - unknown extra keys pass through on every target" {
  let events : Array[@lux.LucentStreamEvent] = [
    ConversationStart(
      @lux.LucentConversationMeta::new_full(
        Some("x1"),
        Some("m"),
        None,
        None,
        Some(@json.parse("{\"gateway_marker\":{\"v\":1}}")),
      ),
    ),
    BlockDelta(0, @lux.LucentBlockDelta::text_delta("hi")),
    Done,
  ]
  match @openai.lux_events_to_openai_sse(events) {
    Err(e) => fail("openai encode failed: " + e)
    Ok(cr) => {
      assert_true(cr.value().contains("gateway_marker"))
      assert_false(sm_diag(cr, "provider_payload.gateway_marker"))
    }
  }
  match @responses.lux_events_to_responses_sse(events) {
    Err(e) => fail("responses encode failed: " + e)
    Ok(cr) => assert_true(cr.value().contains("gateway_marker"))
  }
  match @gemini.lux_events_to_gemini_sse(events) {
    Err(e) => fail("gemini encode failed: " + e)
    Ok(cr) => assert_true(cr.value().contains("gateway_marker"))
  }
  match @messages.lux_events_to_messages_sse(events) {
    Err(e) => fail("messages encode failed: " + e)
    Ok(cr) => assert_true(cr.value().contains("gateway_marker"))
  }
}

///|
/// 编码旋钮不外泄：`reasoning_field` 是控制 openai 消息级 reasoning 字段名的
/// 开关，不是 wire 数据 —— 流式编码同样必须跳过。
test "stream meta - encoder knobs never leak into the stream" {
  let events : Array[@lux.LucentStreamEvent] = [
    ConversationStart(
      @lux.LucentConversationMeta::new_full(
        Some("x1"),
        Some("m"),
        None,
        None,
        Some(
          @json.parse(
            "{\"reasoning_field\":\"reasoning_content\",\"gateway_marker\":1}",
          ),
        ),
      ),
    ),
    Done,
  ]
  match @openai.lux_events_to_openai_sse(events) {
    Err(e) => fail("encode failed: " + e)
    Ok(cr) => {
      assert_false(cr.value().contains("reasoning_field"))
      assert_false(sm_diag(cr, "provider_payload.reasoning_field"))
      assert_true(cr.value().contains("gateway_marker"))
    }
  }
}

///|
/// 全旋钮边界：extra 里只有编码旋钮（`reasoning_field`）时，`clean` 非空但
/// 可写出片段为空 —— 覆盖 `meta_extra_fragments` 的最后一条兜底分支。
test "stream meta - knob-only extra produces no fragments" {
  let events : Array[@lux.LucentStreamEvent] = [
    ConversationStart(
      @lux.LucentConversationMeta::new_full(
        Some("x1"),
        Some("gpt-4o"),
        None,
        None,
        Some(@json.parse("{\"reasoning_field\":\"reasoning_content\"}")),
      ),
    ),
    Done,
  ]
  match @openai.lux_events_to_openai_sse(events) {
    Err(e) => fail("encode failed: " + e)
    Ok(cr) => {
      assert_false(cr.value().contains("reasoning_field"))
      assert_false(cr.value().contains("reasoning_content"))
      assert_eq(cr.diagnostics().length(), 0)
    }
  }
}

///|
/// gemini 首帧的 id/model 缺失分支（IR 允许 ConversationStart 只带部分字段）。
test "stream meta - gemini first frame tolerates missing id and model" {
  let events : Array[@lux.LucentStreamEvent] = [
    ConversationStart(
      @lux.LucentConversationMeta::new_full(
        None,
        None,
        None,
        None,
        Some(@json.parse("{\"modelStatus\":{\"status\":\"OK\"}}")),
      ),
    ),
    BlockDelta(0, @lux.LucentBlockDelta::text_delta("hi")),
    Done,
  ]
  match @gemini.lux_events_to_gemini_sse(events) {
    Err(e) => fail("encode failed: " + e)
    Ok(cr) => {
      let frame = sm_first_frame(cr.value())
      // 缺 id/model 时不输出 responseId / modelVersion 键
      assert_false(frame.contains("\"responseId\""))
      assert_false(frame.contains("\"modelVersion\""))
      assert_true(frame.contains("\"modelStatus\""))
    }
  }
}

///|
/// 元数据载体的边界分支：空 extra、非 Object extra。
/// （覆盖 `meta_extra_fragments` 的「无可写出内容」与「非对象」兜底路径。）
test "stream meta - empty and non-object extras are no-ops" {
  // extra = 空 Object → 无片段、无诊断
  let empty : Array[@lux.LucentStreamEvent] = [
    ConversationStart(
      @lux.LucentConversationMeta::new_full(
        Some("x1"),
        Some("m"),
        None,
        None,
        Some(@json.parse("{}")),
      ),
    ),
    BlockDelta(0, @lux.LucentBlockDelta::text_delta("hi")),
    Done,
  ]
  match @openai.lux_events_to_openai_sse(empty) {
    Err(e) => fail("openai encode failed: " + e)
    Ok(cr) => {
      assert_true(cr.value().contains("\"role\":\"assistant\""))
      assert_eq(cr.diagnostics().length(), 0)
    }
  }
  // extra = 非 Object（裸字符串）→ 不合并、不崩溃、不诊断
  let scalar : Array[@lux.LucentStreamEvent] = [
    ConversationStart(
      @lux.LucentConversationMeta::new_full(
        Some("x2"),
        Some("m"),
        None,
        None,
        Some(@json.parse("\"just-a-string\"")),
      ),
    ),
    BlockDelta(0, @lux.LucentBlockDelta::text_delta("hi")),
    Done,
  ]
  match @openai.lux_events_to_openai_sse(scalar) {
    Err(e) => fail("openai encode failed: " + e)
    Ok(cr) => {
      assert_true(cr.value().contains("\"role\":\"assistant\""))
      assert_false(cr.value().contains("just-a-string"))
      assert_eq(cr.diagnostics().length(), 0)
    }
  }
}

///|
/// 保留键撞名：extra 里的 `model` 与编码器自产的 `model` 同名 → 自产值胜、
/// 只出现一次、留 Degraded 诊断。
test "stream meta - extra colliding with an encoder-owned key is diagnosed" {
  let events : Array[@lux.LucentStreamEvent] = [
    ConversationStart(
      @lux.LucentConversationMeta::new_full(
        Some("x1"),
        Some("gpt-4o"),
        None,
        None,
        Some(@json.parse("{\"model\":\"zz-evil\"}")),
      ),
    ),
    Done,
  ]
  match @openai.lux_events_to_openai_sse(events) {
    Err(e) => fail("encode failed: " + e)
    Ok(cr) => {
      // 自产 model 胜出，且只出现一次
      assert_true(cr.value().contains("\"model\":\"gpt-4o\""))
      assert_false(cr.value().contains("zz-evil"))
      if count_key_occurrences(cr.value(), "model") != 1 {
        fail("duplicate model key: " + cr.value())
      }
      assert_true(sm_diag(cr, "provider_payload.model"))
    }
  }
}

///|
/// 往返闭环：openai 流式首帧的 system_fingerprint → IR extra → openai 流式
/// 首帧。元数据跨「解→编」不退化（此前 decode 侧就丢了）。
test "stream meta - openai stream metadata survives the round trip" {
  let sse = "data: {\"id\":\"c1\",\"model\":\"gpt-4o\",\"created\":123,\"system_fingerprint\":\"fp_rt\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"content\":\"\"}}]}\n\ndata: [DONE]\n\n"
  match @openai.openai_sse_to_events(sse) {
    Err(e) => fail("decode failed: " + e)
    Ok(cr) =>
      match @openai.lux_events_to_openai_sse(cr.value()) {
        Err(e) => fail("encode failed: " + e)
        Ok(out) =>
          assert_true(out.value().contains("\"system_fingerprint\":\"fp_rt\""))
      }
  }
}
