///|
/// Google Gemini — 响应解码 / 编码
///
/// 官方 schema 依据（v1beta discovery）：
///   - `GenerateContentResponse` 字段为 `responseId` / `modelVersion` /
///     `candidates` / `usageMetadata` / `promptFeedback` / `modelStatus`
///     —— **没有顶层 `model` 字段**
///   - `Candidate.finishReason` 为全大写枚举（STOP / MAX_TOKENS / SAFETY / ...）
///
/// 因此：解码时响应 ID 取 `responseId`，模型版本取 `modelVersion`；
/// 编码时输出 `responseId` + `modelVersion`，不再输出不存在的 `model`。

///|
/// 3. gemini_to_lux_response — 响应解码
pub fn gemini_to_lux_response(
  json_str : String,
) -> Result[@lux.ConversionResult[@lux.LucentResponse], String] {
  let jv = match @internal.parse_protocol_json(json_str) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let diagnostics : Array[@lux.ConversionDiagnostic] = []
  // 官方 GenerateContentResponse.responseId 是响应标识；modelVersion 才是模型
  let id = @internal.field_str(jv, "responseId").unwrap_or("")
  let model = @internal.field_str(jv, "modelVersion").unwrap_or("")
  // candidates
  let choices : Array[@lux.LucentChoice] = []
  match @internal.field_arr(jv, "candidates") {
    Some(cands) => {
      let mut i = 0
      while i < cands.length() {
        let idx = @internal.field_int(cands[i], "index").unwrap_or(i)
        match @internal.obj_get(cands[i], "content") {
          Some(content) => {
            let parts = match @internal.field_arr(content, "parts") {
              Some(arr) => parse_parts(arr, Map([]), Map([]), diagnostics)
              None => []
            }
            let msg = @lux.LucentMessage::new(Assistant, parts)
            let finish = match @internal.field_str(cands[i], "finishReason") {
              Some("STOP") => @lux.Stop
              Some("MAX_TOKENS") => Length
              Some("SAFETY") => Safety
              Some("RECITATION") => Recitation
              Some("MALFORMED_FUNCTION_CALL") => MalformedToolCall
              Some(other) => @lux.LucentFinishReason::from_string(other)
              None => Stop
            }
            // safety ratings
            let ratings = match @internal.field_arr(cands[i], "safetyRatings") {
              Some(ratings) => {
                let result : Array[@lux.LucentSafetyRating] = []
                let mut k = 0
                while k < ratings.length() {
                  let cat = @internal.field_str(ratings[k], "category").unwrap_or(
                    "",
                  )
                  let prob = @internal.field_str(ratings[k], "probability").unwrap_or(
                    "",
                  )
                  result.push(@lux.LucentSafetyRating::new(cat, prob))
                  k = k + 1
                }
                Some(result)
              }
              None => None
            }
            choices.push(@lux.LucentChoice::new(idx, msg, finish, ratings))
          }
          None => ()
        }
        i = i + 1
      }
    }
    None => ()
  }
  if choices.length() == 0 {
    // 零 candidate 有两种截然不同的原因，必须区分：
    //  1. `promptFeedback.blockReason` 有值 → 提示词被安全策略**整体拦截**。
    //     这是有效业务结果（finish_reason = Safety），不是转换失败；
    //     此前一律 `Err`，调用方拿不到 blockReason，也拿不到 usage。
    //  2. 其它 → 协议残缺，确实无法转换。
    match @internal.obj_get(jv, "promptFeedback") {
      Some(pf) =>
        match @internal.field_str(pf, "blockReason") {
          Some(reason) => {
            let ratings = match @internal.field_arr(pf, "safetyRatings") {
              Some(arr) => {
                let out : Array[@lux.LucentSafetyRating] = []
                let mut k = 0
                while k < arr.length() {
                  let cat = @internal.field_str(arr[k], "category").unwrap_or(
                    "",
                  )
                  let prob = @internal.field_str(arr[k], "probability").unwrap_or(
                    "",
                  )
                  out.push(@lux.LucentSafetyRating::new(cat, prob))
                  k = k + 1
                }
                Some(out)
              }
              None => None
            }
            let empty_msg = @lux.LucentMessage::new(Assistant, [])
            let blocked = @lux.LucentChoice::new(0, empty_msg, Safety, ratings)
            let usage : @lux.LucentUsage? = match
              @internal.obj_get(jv, "usageMetadata") {
              Some(u) => {
                let (pt, ct, tt) = @internal.parse_usage_json(
                  u,
                  "promptTokenCount",
                  "candidatesTokenCount",
                  Some("totalTokenCount"),
                )
                Some(@lux.LucentUsage::full(pt, ct, tt, None, None, None))
              }
              None => None
            }
            diagnostics.push(
              @lux.ConversionDiagnostic::degraded(
                "promptFeedback.blockReason",
                Some(
                  "prompt blocked by gemini safety policy: " +
                  reason +
                  "; represented as an empty choice with finish_reason=safety",
                ),
              ),
            )
            let result = @lux.ConversionResult::new(
              @lux.LucentResponse::new(id, model, None, [blocked], usage, None),
            )
            return Ok(result.with_diagnostics(diagnostics))
          }
          None => ()
        }
      None => ()
    }
    return Err("response has no candidates")
  }
  // usage（含 thoughtsTokenCount / cachedContentTokenCount 细化用量，标准 §9）
  let usage : @lux.LucentUsage? = match @internal.obj_get(jv, "usageMetadata") {
    Some(u) => {
      let (pt, ct, tt) = @internal.parse_usage_json(
        u,
        "promptTokenCount",
        "candidatesTokenCount",
        Some("totalTokenCount"),
      )
      let reasoning = @internal.parse_reasoning_tokens(u, [])
      let cached = @internal.parse_cached_tokens_gemini(u)
      Some(@lux.LucentUsage::full(pt, ct, tt, reasoning, cached, None))
    }
    None => None
  }
  let result = @lux.ConversionResult::new(
    @lux.LucentResponse::new(id, model, None, choices, usage, None),
  )
  Ok(result.with_diagnostics(diagnostics))
}

///|
/// 4. lux_response_to_gemini — 响应编码
pub fn lux_response_to_gemini(
  resp : @lux.LucentResponse,
) -> Result[@lux.ConversionResult[String], String] {
  if resp.choices.length() == 0 {
    return Err("response has no choices")
  }
  let diagnostics : Array[@lux.ConversionDiagnostic] = []
  let cands : Array[String] = []
  let mut i = 0
  while i < resp.choices.length() {
    let c = resp.choices[i]
    let parts : Array[String] = []
    // 消息级 reasoning 优先（vLLM/DeepSeek 入站 → IR → Gemini 出站），前置为 thought:true part
    match c.message.reasoning {
      Some(th) => {
        let sig_part = match th.signature {
          Some(s) =>
            ",\"thoughtSignature\":\"" + @internal.json_escape(s) + "\""
          None => ""
        }
        parts.push(
          "{\"text\":\"" +
          @internal.json_escape(th.text) +
          "\",\"thought\":true" +
          sig_part +
          "}",
        )
      }
      None => ()
    }
    let mut j = 0
    while j < c.message.content.length() {
      // 双载体并存：消息级 reasoning 已输出，content 中 Thinking part 跳过 → Degraded
      if @lux.skip_thinking_when_dual_carrier(
          c.message.content[j],
          c.message.reasoning,
          diagnostics,
        ) {
        j = j + 1
        continue
      }
      match c.message.content[j] {
        Text(s, _) =>
          parts.push("{\"text\":\"" + @internal.json_escape(s) + "\"}")
        ToolUse(tu) => parts.push(function_call_part(tu, diagnostics))
        Thinking(th) => {
          // thought part + thoughtSignature（Gemini 跨轮思考延续凭证）
          let sig_part = match th.signature {
            Some(s) =>
              ",\"thoughtSignature\":\"" + @internal.json_escape(s) + "\""
            None => ""
          }
          parts.push(
            "{\"text\":\"" +
            @internal.json_escape(th.text) +
            "\",\"thought\":true" +
            sig_part +
            "}",
          )
        }
        File(mm) => parts.push(media_part(mm, "file", diagnostics))
        Image(mm) => parts.push(media_part(mm, "image", diagnostics))
        Audio(mm) => parts.push(media_part(mm, "audio", diagnostics))
        Video(mm) => parts.push(media_part(mm, "video", diagnostics))
        ToolResult(tr) => {
          // assistant 轮次中出现工具结果属异常编排，但不得静默丢弃
          diagnostics.push(
            @lux.ConversionDiagnostic::degraded(
              "choices.content.tool_result",
              Some(
                "tool_result inside an assistant candidate is re-encoded as functionResponse",
              ),
            ),
          )
          parts.push(
            function_response_part(
              tr.tool_use_id,
              tr.tool_use_id,
              @lux.lucent_content_to_text(tr.content),
            ),
          )
        }
        Refusal(text) =>
          diagnostics.push(
            @lux.ConversionDiagnostic::unsupported(
              "choices.content.refusal",
              Some(
                "gemini has no refusal content block; refusal text dropped: " +
                text,
              ),
            ),
          )
        Native(tag, _) =>
          diagnostics.push(
            @lux.ConversionDiagnostic::unsupported(
              "choices.content.native",
              Some("native content (" + tag + ") not supported by gemini"),
            ),
          )
      }
      j = j + 1
    }
    // 收敛到 Gemini 合法 FinishReason。实现集中到
    // `@meta.gemini_finish_reason`，与流式编码共用（此前流式路径
    // 自带一份简化映射，两处漂移）。
    let finish_str = @meta.gemini_finish_reason(
      c.finish_reason,
      "candidates",
      diagnostics,
    )
    let mut cand = "{\"index\":" +
      c.index.to_string() +
      ",\"content\":{\"role\":\"model\",\"parts\":[" +
      parts.join(",") +
      "]}"
    cand = cand + ",\"finishReason\":\"" + finish_str + "\""
    match c.safety_ratings {
      Some(ratings) => {
        let rs : Array[String] = []
        let mut k = 0
        while k < ratings.length() {
          rs.push(
            "{\"category\":\"" +
            @internal.json_escape(ratings[k].category) +
            "\",\"probability\":\"" +
            @internal.json_escape(ratings[k].probability) +
            "\"}",
          )
          k = k + 1
        }
        cand = cand + ",\"safetyRatings\":[" + rs.join(",") + "]"
      }
      None => ()
    }
    cands.push(cand + "}")
    i = i + 1
  }
  let usage_part = match resp.usage {
    Some(u) => {
      // thoughtsTokenCount / cachedContentTokenCount 是 decoded 侧读取的标准细化
      // 用量（见 usage.mbt），编码侧必须对称写出 —— 否则「解→编」往返丢数据，
      // 且与本文件解码路径自相矛盾。
      let mut s = ",\"usageMetadata\":{\"promptTokenCount\":" +
        u.prompt_tokens.to_string() +
        ",\"candidatesTokenCount\":" +
        u.completion_tokens.to_string() +
        ",\"totalTokenCount\":" +
        u.total_tokens.to_string()
      match u.reasoning_tokens {
        Some(n) => s = s + ",\"thoughtsTokenCount\":" + n.to_string()
        None => ()
      }
      match u.cached_tokens {
        Some(n) => s = s + ",\"cachedContentTokenCount\":" + n.to_string()
        None => ()
      }
      s + "}"
    }
    None => ""
  }
  // GenerateContentResponse 无 model 字段：只输出 responseId + modelVersion
  let id_part = if resp.id == "" {
    ""
  } else {
    "\"responseId\":\"" + @internal.json_escape(resp.id) + "\","
  }
  // provider_payload 出站：响应级扩展载体（对称于请求侧 options.extras）。
  // Gemini 顶层可承载的非建模字段是 modelStatus（无 vendored spec）。
  // reserved 只含**本编码器实际会写出的键** —— promptFeedback / modelStatus
  // 都不在其中：前者由解码侧专门处理，后者是 payload 的原生落点。
  let (payload_kept, payload_foreign) = @internal.split_provider_payload(
    resp.provider_payload,
    "gemini",
  )
  @lux.push_extras_foreign_at("provider_payload", payload_foreign, diagnostics)
  let reserved : Array[String] = [
    "responseId", "modelVersion", "candidates", "usageMetadata",
  ]
  let payload_collided : Array[String] = []
  match payload_kept {
    Some(m) =>
      for k, _ in m {
        if reserved.contains(k) {
          payload_collided.push(k)
        }
      }
    None => ()
  }
  let payload_clean = @internal.extras_without_keys(
    payload_kept, payload_collided,
  )
  @lux.push_extras_collisions_at(
    "provider_payload", payload_collided, diagnostics,
  )
  let payload_parts : Array[String] = []
  let _ = @internal.merge_extras_json_dedup(payload_parts, payload_clean)
  let payload_json = if payload_parts.length() > 0 {
    "," + payload_parts.join(",")
  } else {
    ""
  }
  let result = @lux.ConversionResult::new(
    "{" +
    id_part +
    "\"modelVersion\":\"" +
    @internal.json_escape(resp.model) +
    "\",\"candidates\":[" +
    cands.join(",") +
    "]" +
    usage_part +
    payload_json +
    "}",
  )
  Ok(result.with_diagnostics(diagnostics))
}
