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
  let id = @internal.field_str(jv, "model").unwrap_or("")
  let model = @internal.field_str(jv, "modelVersion").unwrap_or(id)
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
    return Err("response has no candidates")
  }
  // usage
  let usage = match @internal.obj_get(jv, "usageMetadata") {
    Some(u) => {
      let (pt, ct, tt) = @internal.parse_usage_json(
        u,
        "promptTokenCount",
        "candidatesTokenCount",
        Some("totalTokenCount"),
      )
      @lux.LucentUsage::new(pt, ct, tt)
    }
    None => @lux.LucentUsage::new(0, 0, 0)
  }
  let result = @lux.ConversionResult::new(
    @lux.LucentResponse::new(id, model, None, choices, Some(usage), None),
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
          Some(s) => ",\"thoughtSignature\":\"" + @internal.json_escape(s) + "\""
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
        ToolUse(tu) =>
          parts.push(
            "{\"functionCall\":{\"name\":\"" +
            @internal.json_escape(tu.name) +
            "\",\"args\":" +
            tu.arguments_json +
            "}}",
          )
        Thinking(th) => {
          // thought part + thoughtSignature（Gemini 跨轮思考延续凭证）
          let sig_part = match th.signature {
            Some(s) => ",\"thoughtSignature\":\"" + @internal.json_escape(s) + "\""
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
        File(mm) =>
          parts.push(
            "{\"fileData\":{\"mimeType\":\"" +
            @internal.json_escape(mm.media_type) +
            "\",\"fileUri\":\"" +
            @internal.json_escape(
              match mm.source {
                Url(u) => u
                FileUri(u) => u
                Inline(_) => ""
              },
            ) +
            "\"}}",
          )
        _ => ()
      }
      j = j + 1
    }
    let finish_str = match c.finish_reason {
      Stop => "STOP"
      Length => "MAX_TOKENS"
      ToolCalls => "STOP"
      Safety => "SAFETY"
      Recitation => "RECITATION"
      MalformedToolCall => "MALFORMED_FUNCTION_CALL"
      Error => "OTHER"
      _ => "STOP"
    }
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
    Some(u) =>
      ",\"usageMetadata\":{\"promptTokenCount\":" +
      u.prompt_tokens.to_string() +
      ",\"candidatesTokenCount\":" +
      u.completion_tokens.to_string() +
      ",\"totalTokenCount\":" +
      u.total_tokens.to_string() +
      "}"
    None => ""
  }
  let result = @lux.ConversionResult::new(
    "{\"candidates\":[" + cands.join(",") + "]" + usage_part + "}",
  )
  Ok(result.with_diagnostics(diagnostics))
}
