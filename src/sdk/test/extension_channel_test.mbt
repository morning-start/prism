///|
/// 扩展通道契约：`request.extra` 与 `options.extras` 的落点、优先级与跨端过滤。
///
/// ## 背景（audit 2026-10-22）
///
/// IR 有两个扩展载体，文档语义不同：
///
/// - `LucentRequest.extra` —— `docs/lux-ir-design.md`：「Provider-specific
///   extensions」。程序作者显式给出，知道目标是谁，故出站时**始终下发**。
///   修复前它是**死载体**：4 个 request encoder 没有一个读它，SDK 用户写入的
///   扩展被静默丢弃（无字段、无诊断）。
/// - `LucentOptions.extras` —— `schemas/lux-ir-v1.json`：「厂商私有扩展（软失败
///   保留）」。由**解码侧**填充（源协议 wire 上未被 IR 建模的顶层字段），来源
///   天然是源协议。修复前它被**原样回写到任意目标**的请求体，目标不认识的
///   字段（openai 的 `seed`/`logit_bias`、responses 的 `truncation`/`include`）
///   会导致 400。
///
/// 现在两者语义互补：`extra` 是「作者显式注入」通道，`extras` 是「源协议软
/// 保留」通道。过滤规则见 `src/internal/protocol_keys.mbt`（只剔除**可证明
/// 属于其它协议**的键；未知键一律放行，以保住厂商私有键与未来新增字段）。
///
/// 本文件把上面的语义变成可执行断言。

///|
/// 编码结果 + 非 Exact 诊断字段名，便于逐格断言。
struct EclOut {
  name : String
  body : String
  diags : Array[String]
}

///|
fn ecl_map(pairs : Array[(String, Json)]) -> Map[String, Json] {
  let m : Map[String, Json] = Map([])
  for p in pairs {
    m[p.0] = p.1
  }
  m
}

///|
fn ecl_req(
  extra : Map[String, Json]?,
  extras : Map[String, Json]?,
  stream : Bool,
) -> @lux.LucentRequest {
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
    @lux.LucentOptions::new(
      None,
      None,
      None,
      None,
      None,
      stream,
      None,
      None,
      None,
      extras,
    ),
    None,
    None,
    None,
    extra,
  )
}

///|
fn ecl_out(
  name : String,
  res : Result[@lux.ConversionResult[String], String],
) -> EclOut raise {
  match res {
    Err(e) => fail(name + " encode failed: " + e)
    Ok(cr) => {
      let ds : Array[String] = []
      for d in cr.diagnostics() {
        match d.status() {
          Exact => ()
          _ => ds.push(d.field)
        }
      }
      { name, body: cr.value(), diags: ds, }
    }
  }
}

///|
/// 同一份 IR 编码到 4 个目标（顺序：openai / responses / messages / gemini）。
fn ecl_all(req : @lux.LucentRequest) -> Array[EclOut] raise {
  [
    ecl_out("openai", @openai.lux_request_to_openai(req)),
    ecl_out("responses", @responses.lux_request_to_responses(req)),
    ecl_out("messages", @messages.lux_request_to_messages(req)),
    ecl_out("gemini", @gemini.lux_request_to_gemini(req)),
  ]
}

///|
/// 断某一格：`present=true` 要求 `options.extras` 的该键出现在 body 且恰好一次；
/// `present=false` 要求它被剔除**且**留下 `options.extras.<key>` 非 Exact 诊断
/// （即「不支持必须显式报错，绝不静默丢弃」）。
fn ecl_expect(out : EclOut, key : String, present : Bool) -> Unit raise {
  let n = count_key_occurrences(out.body, key)
  if present {
    if n != 1 {
      fail(
        out.name +
        ": expected \"" +
        key +
        "\" exactly once, got " +
        n.to_string() +
        ": " +
        out.body,
      )
    }
  } else {
    if n != 0 {
      fail(
        out.name + ": \"" + key + "\" should have been filtered: " + out.body,
      )
    }
    if !out.diags.contains("options.extras." + key) {
      fail(out.name + ": \"" + key + "\" filtered without a diagnostic")
    }
  }
}

///|
/// 修复前 `request.extra` 是死载体：4 个 encoder 没有一个读它，SDK 用户写入的
/// 扩展字段在出站 body 里完全不出现、也没有任何诊断。
test "extension channel - request.extra reaches every target" {
  let m = ecl_map([("ecl_ext", Json::string("zz"))])
  let outs = ecl_all(ecl_req(Some(m), None, false))
  for o in outs {
    if count_key_occurrences(o.body, "ecl_ext") != 1 {
      fail(o.name + ": request.extra not delivered exactly once: " + o.body)
    }
  }
  // gemini：extra 落**请求体顶层**（请求级扩展位置），不是 generationConfig
  if outs[3].body.contains("\"generationConfig\":{\"ecl_ext\"") {
    fail(
      "gemini: request.extra must land at the request top level: " +
      outs[3].body,
    )
  }
}

///|
/// `extra` 撞上目标按 IR 编码出的字段时：目标值胜、body 里该键只出现一次
/// （绝不产生重复 JSON 键）、并报 Degraded 诊断。
test "extension channel - request.extra never duplicates a target-produced key" {
  let m = ecl_map([("model", Json::string("zz-model"))])
  for o in ecl_all(ecl_req(Some(m), None, false)) {
    if count_key_occurrences(o.body, "model") != 1 {
      fail(o.name + ": duplicate \"model\" key: " + o.body)
    }
    if !o.body.contains("\"model\":\"gpt-4o\"") {
      fail(
        o.name + ": target-encoded value must win over request.extra: " + o.body,
      )
    }
    if !o.diags.contains("extra.model") {
      fail(
        o.name +
        ": dropped request.extra key must be diagnosed: " +
        o.diags.join(","),
      )
    }
  }
}

///|
/// 两个通道给出同一个键 → `request.extra`（作者显式意图）胜，`options.extras`
/// 侧剔除并报 Degraded。必须**恰好一次**：此前 gemini 会把同名键写到两处
/// （generationConfig 内 + 顶层），语义歧义。
test "extension channel - request.extra wins over options.extras" {
  let extras = ecl_map([("ecl_both", Json::number(1))])
  let extra = ecl_map([("ecl_both", Json::number(2))])
  for o in ecl_all(ecl_req(Some(extra), Some(extras), false)) {
    if count_key_occurrences(o.body, "ecl_both") != 1 {
      fail(o.name + ": expected exactly one occurrence: " + o.body)
    }
    if !o.body.contains("\"ecl_both\":2") {
      fail(o.name + ": request.extra must win over options.extras: " + o.body)
    }
    if !o.diags.contains("options.extras.ecl_both") {
      fail(
        o.name +
        ": overridden extras key must be diagnosed: " +
        o.diags.join(","),
      )
    }
  }
}

///|
/// 未知键（厂商私有、未来新增字段）一律放行 —— 这是「只剔除可证明属于其它
/// 协议的键」这一判定方向的防误丢保证，也是 extras 作为安全阀的意义所在。
test "extension channel - unknown vendor keys are never filtered" {
  let m = ecl_map([("ecl_vendor_flag", Json::boolean(true))])
  for o in ecl_all(ecl_req(None, Some(m), false)) {
    if count_key_occurrences(o.body, "ecl_vendor_flag") != 1 {
      fail(o.name + ": vendor extension key dropped: " + o.body)
    }
    if o.diags.contains("options.extras.ecl_vendor_flag") {
      fail(o.name + ": unknown key must not be reported as foreign")
    }
  }
}

///|
/// 跨端矩阵硬门：§4 item 9 列出的「纯源协议专属、IR 无载体」字段，转出到
/// 任一目标时**要么出现、要么有非 Exact 诊断** —— 不允许静默消失。
///
/// 修复前这些键被原样回写到所有目标（目标不认识 → 可能 400）；现在只有
/// 归属协议（及原生支持该键的协议）保留。
test "extension channel - foreign extras keys are never silently dropped" {
  for
    k in [
      "seed", "logit_bias", "frequency_penalty", "stream_options", "truncation",
      "background", "include", "top_logprobs", "user", "service_tier", "logprobs",
      "prompt_cache_key",
    ] {
    let m = ecl_map([(k, Json::number(1))])
    for o in ecl_all(ecl_req(None, Some(m), false)) {
      let present = count_key_occurrences(o.body, k) > 0
      if !present && !o.diags.contains("options.extras." + k) {
        fail(k + " silently dropped at " + o.name + ": " + o.body)
      }
    }
  }
}

///|
/// 逐格锁定归属（判定依据见 `src/internal/protocol_keys.mbt`）：
/// - `seed` 原生：openai / gemini（gemini 的 `generationConfig.seed`）→ 保留；
///   非原生：responses / messages → 剔除 + 诊断。
/// - `logit_bias` 原生：仅 openai。
/// - `truncation` 原生：仅 responses。
test "extension channel - native cells keep the key, non-native cells filter it" {
  let seed = ecl_all(
    ecl_req(None, Some(ecl_map([("seed", Json::number(7))])), false),
  )
  ecl_expect(seed[0], "seed", true)
  ecl_expect(seed[1], "seed", false)
  ecl_expect(seed[2], "seed", false)
  ecl_expect(seed[3], "seed", true)
  // gemini 的 seed 必须落在 generationConfig 内（generationConfig 是它的原生位置）
  if !seed[3].body.contains("\"generationConfig\":{\"seed\":7}") {
    fail("gemini: seed must land inside generationConfig: " + seed[3].body)
  }
  let bias = ecl_all(
    ecl_req(None, Some(ecl_map([("logit_bias", Json::number(1))])), false),
  )
  ecl_expect(bias[0], "logit_bias", true)
  ecl_expect(bias[1], "logit_bias", false)
  ecl_expect(bias[2], "logit_bias", false)
  ecl_expect(bias[3], "logit_bias", false)
  let trunc = ecl_all(
    ecl_req(None, Some(ecl_map([("truncation", Json::string("auto"))])), false),
  )
  ecl_expect(trunc[0], "truncation", false)
  ecl_expect(trunc[1], "truncation", true)
  ecl_expect(trunc[2], "truncation", false)
  ecl_expect(trunc[3], "truncation", false)
}

///|
/// 同源往返（openai → IR → openai）必须保住这些**未被 IR 建模**的原生参数：
/// 它们是同一协议的原生字段，过滤规则按「归属」放行，故同源往返无损。
/// 同时验证同一份 IR 发往 messages 时它们被剔除**并带诊断** —— 这正是
/// 「同一 IR 在不同目标下产出不同 diagnostics」的行为，属预期（见
/// docs/fidelity-matrix.md §3.7）。
test "extension channel - same-protocol round trip keeps unmodeled native params" {
  let src = "{\"model\":\"gpt-4o\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"seed\":42,\"logit_bias\":{\"50256\":-100},\"frequency_penalty\":0.5,\"stream_options\":{\"include_usage\":true}}"
  match @openai.openai_to_lux_request(src) {
    Err(e) => fail("decode failed: " + e)
    Ok(cr) => {
      let req = cr.value()
      match @openai.lux_request_to_openai(req) {
        Err(e) => fail("encode openai failed: " + e)
        Ok(out) => {
          let body = out.value()
          for k in ["seed", "logit_bias", "frequency_penalty", "stream_options"] {
            if count_key_occurrences(body, k) != 1 {
              fail("openai->openai lost \"" + k + "\": " + body)
            }
          }
        }
      }
      match @messages.lux_request_to_messages(req) {
        Err(e) => fail("encode messages failed: " + e)
        Ok(out) => {
          let body = out.value()
          for k in ["seed", "logit_bias", "frequency_penalty", "stream_options"] {
            if count_key_occurrences(body, k) != 0 {
              fail("openai->messages leaked \"" + k + "\": " + body)
            }
          }
          let ds : Array[String] = []
          for d in out.diagnostics() {
            ds.push(d.field)
          }
          for k in ["seed", "logit_bias", "frequency_penalty", "stream_options"] {
            if !ds.contains("options.extras." + k) {
              fail(
                "openai->messages must diagnose dropped \"" +
                k +
                "\": " +
                ds.join(","),
              )
            }
          }
        }
      }
    }
  }
}

///|
/// 两个通道在 gemini 的落点不同（文档化行为）：`options.extras` 是生成参数
/// 遗留 → `generationConfig`；`request.extra` 是请求级扩展 → 顶层。
test "extension channel - gemini destinations differ between the two channels" {
  let extra = ecl_map([("eclTopLevel", Json::boolean(true))])
  let extras = ecl_map([("eclGenConfig", Json::boolean(true))])
  let outs = ecl_all(ecl_req(Some(extra), Some(extras), false))
  let g = outs[3]
  if !g.body.contains("\"generationConfig\":{\"eclGenConfig\":true}") {
    fail("gemini: options.extras must land inside generationConfig: " + g.body)
  }
  if !g.body.contains("\"eclTopLevel\":true") {
    fail("gemini: request.extra must land at the request top level: " + g.body)
  }
  if g.body.contains("\"generationConfig\":{\"eclTopLevel\"") {
    fail(
      "gemini: request.extra must not be nested into generationConfig: " +
      g.body,
    )
  }
}

///|
/// openai 的 `stream_options.include_usage` 自动注入必须以**两个通道**为准：
/// 调用方（`request.extra`）显式给出时不得覆盖、也不得产生重复键。
test "extension channel - request.extra stream_options suppresses auto injection" {
  let m = ecl_map([
    ("stream_options", Json::object({ "include_usage": Json::boolean(false) })),
  ])
  let outs = ecl_all(ecl_req(Some(m), None, true))
  let o = outs[0]
  if count_key_occurrences(o.body, "stream_options") != 1 {
    fail("duplicate stream_options: " + o.body)
  }
  if !o.body.contains("\"include_usage\":false") {
    fail("caller stream_options via request.extra must win: " + o.body)
  }
}
