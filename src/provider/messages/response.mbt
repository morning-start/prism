///|
/// 3. messages_to_lux_response — 响应解码
pub fn messages_to_lux_response(
  json_str : String,
) -> Result[@lux.ConversionResult[@lux.LucentResponse], String] {
  let jv = match @internal.parse_protocol_json(json_str) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let id = @internal.field_str(jv, "id").unwrap_or("")
  let model = @internal.field_str(jv, "model").unwrap_or("")
  let diagnostics : Array[@lux.ConversionDiagnostic] = []
  // content blocks → assistant message content
  let content = match @internal.field_arr(jv, "content") {
    Some(blocks) => parse_content_blocks(blocks, diagnostics)
    None => []
  }
  let msg = @lux.LucentMessage::new(Assistant, content)
  // stop_reason → finish_reason
  let finish = match @internal.field_str(jv, "stop_reason") {
    Some("end_turn") => @lux.Stop
    Some("max_tokens") => Length
    Some("tool_use") => ToolCalls
    Some("stop_sequence") => Stop
    Some(other) => @lux.LucentFinishReason::from_string(other)
    None => Stop
  }
  let choice = @lux.LucentChoice::new(0, msg, finish, None)
  // usage（cached / cache_creation 细化用量：prompt caching 计费核心，标准 §9）
  let usage = match @internal.obj_get(jv, "usage") {
    Some(u) => {
      let (pt, ct, tt) = @internal.parse_usage_json(
        u,
        "input_tokens",
        "output_tokens",
        None,
      )
      let cached = @internal.parse_cached_tokens(u, [])
      let cache_creation = @internal.parse_cache_creation_tokens(u, [])
      Some(@lux.LucentUsage::full(pt, ct, tt, None, cached, cache_creation))
    }
    None => None
  }
  let result = @lux.ConversionResult::new(
    @lux.LucentResponse::new(id, model, None, [choice], usage, None),
  )
  Ok(result.with_diagnostics(diagnostics))
}

///|
/// 4. lux_response_to_messages — 响应编码
pub fn lux_response_to_messages(
  resp : @lux.LucentResponse,
) -> Result[@lux.ConversionResult[String], String] {
  if resp.choices.length() == 0 {
    return Err("response has no choices")
  }
  let diagnostics : Array[@lux.ConversionDiagnostic] = []
  let choice = resp.choices[0]
  // content blocks
  let content_blocks : Array[String] = []
  // 消息级 reasoning 优先（vLLM/DeepSeek 入站 → IR → Anthropic 出站），前置为 thinking block
  match choice.message.reasoning {
    Some(th) => content_blocks.push(thinking_to_block(th))
    None => ()
  }
  let mut i = 0
  while i < choice.message.content.length() {
    // 双载体并存：消息级 reasoning 已输出，content 中 Thinking block 跳过 → Degraded
    if @lux.skip_thinking_when_dual_carrier(
        choice.message.content[i],
        choice.message.reasoning,
        diagnostics,
      ) {
      i = i + 1
      continue
    }
    let block = content_to_block(choice.message.content[i], diagnostics)
    if block != "" {
      content_blocks.push(block)
    }
    i = i + 1
  }
  let content_json = "[" + content_blocks.join(",") + "]"
  // stop_reason
  // Anthropic stop_reason 枚举：end_turn/max_tokens/stop_sequence/tool_use/
  // refusal/pause_turn/model_context_window_exceeded。
  // IR ContentFilter 无对等值 → 映射为 "refusal"（Anthropic 语义最近的载体）；
  // Safety/Recitation/MalformedToolCall/Error 等无对等值 → 收敛为 "end_turn"。
  let stop_reason = match choice.finish_reason {
    Stop => "\"end_turn\""
    Length => "\"max_tokens\""
    ToolCalls => "\"tool_use\""
    ContentFilter => "\"refusal\""
    Safety => "\"end_turn\""
    Recitation => "\"end_turn\""
    MalformedToolCall => "\"end_turn\""
    Error => "\"end_turn\""
    Native(s) => "\"" + @internal.json_escape(s) + "\""
  }
  // usage（cached / cache_creation 细化用量输出，标准 §9）
  let usage_json = match resp.usage {
    Some(u) => {
      let mut s = ",\"usage\":{\"input_tokens\":" +
        u.prompt_tokens.to_string() +
        ",\"output_tokens\":" +
        u.completion_tokens.to_string()
      match u.cache_creation_tokens {
        Some(n) => s = s + ",\"cache_creation_input_tokens\":" + n.to_string()
        None => ()
      }
      match u.cached_tokens {
        Some(n) => s = s + ",\"cache_read_input_tokens\":" + n.to_string()
        None => ()
      }
      s + "}"
    }
    None => ""
  }
  let body = "{\"id\":\"" +
    @internal.json_escape(resp.id) +
    "\",\"type\":\"message\",\"role\":\"assistant\",\"model\":\"" +
    @internal.json_escape(resp.model) +
    "\",\"content\":" +
    content_json +
    ",\"stop_reason\":" +
    stop_reason +
    ",\"stop_sequence\":null" +
    usage_json +
    "}"
  let result = @lux.ConversionResult::new(body)
  Ok(result.with_diagnostics(diagnostics))
}
