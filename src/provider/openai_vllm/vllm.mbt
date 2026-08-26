///|
/// OpenAI vLLM — 基于标准 openai-chat 的薄封装子协议
///
/// 子协议名：openai-vllm
/// 定位：vLLM 是 OpenAI Chat 兼容的**上游推理引擎**，其 `message.reasoning` /
/// `delta.reasoning` 是 OpenAI Chat 形态上的**厂商扩展字段**（标准 OpenAI Chat
/// 不暴露 reasoning 内容，仅 `usage.reasoning_tokens` 计数）。
/// 采用子协议隔离（而非直接内嵌到 openai-chat）的原因：
///   1. 标准 openai-chat 保持纯净，不含任何厂商特有字段；
///   2. vLLM 未来若把字段改为标准格式，只需调整本子协议，标准协议零改动；
///   3. 同类厂商（DeepSeek/Fireworks 的 `reasoning_content`）可复用同一模式。
///
/// 实现策略（与 openai_azure / openai_codex 先例一致）：
///   - 解码函数（vllm→lux）：先调用 openai-chat 核心，再后处理提取
///     `message.reasoning` / `reasoning_content` → `LucentMessage.reasoning`
///   - 编码函数（lux→vllm）：先调用 openai-chat 核心，再后处理插入 reasoning 字段
///     （默认 `reasoning`，经 `provider_payload.reasoning_field` 切换为 `reasoning_content`）
///   - 流式：先调用 openai-chat 核心事件，再后处理 `delta.reasoning` → Thinking 块

///|
/// 1. 请求解码 — 与标准 openai-chat 完全一致
pub fn vllm_to_lux_request(
  json_str : String,
) -> Result[@lux.ConversionResult[@lux.LucentRequest], String] {
  @openai_chat.openai_chat_to_lux_request(json_str)
}

///|
/// 2. 请求编码 — openai-chat 核心 + vLLM 特有 thinking 配置
///
/// 差异：vLLM 用 `extra_body.chat_template_kwargs.enable_thinking` 控制思考
/// （Qwen3 等模型）；标准 OpenAI Chat 用 `reasoning_effort`（openai-chat
/// 已发射）。本子协议在 openai-chat 结果上后处理插入 enable_thinking。
pub fn lux_request_to_vllm(
  req : @lux.LucentRequest,
) -> Result[@lux.ConversionResult[String], String] {
  let base = @openai_chat.lux_request_to_openai_chat(req)
  match base {
    Ok(cr) =>
      match req.reasoning {
        Some(rc) => {
          // 在顶层插入 extra_body.chat_template_kwargs.enable_thinking
          let jv = @json.parse(cr.value()) catch { _ => return Ok(cr) }
          let kwargs = match @internal.obj_get(jv, "extra_body") {
            Some(Object(m)) =>
              match m.get("chat_template_kwargs") {
                Some(existing) => existing
                _ => Json::object(Map([]))
              }
            _ => Json::object(Map([]))
          }
          let kwargs2 = json_set(
            kwargs,
            "enable_thinking",
            Json::boolean(rc.enabled),
          )
          let extra = match @internal.obj_get(jv, "extra_body") {
            Some(e) => json_set(e, "chat_template_kwargs", kwargs2)
            None => Json::object({ "chat_template_kwargs": kwargs2 })
          }
          let root = json_set(jv, "extra_body", extra)
          Ok(@lux.ConversionResult::new(root.stringify()))
        }
        None => Ok(cr)
      }
    Err(e) => Err(e)
  }
}

///|
/// 3. 响应解码 — openai-chat 核心 + vLLM 特有 reasoning 字段后处理
///
/// 只解析一次 JSON：解析结果同时用于核心解码与 reasoning 提取。
pub fn vllm_to_lux_response(
  json_str : String,
) -> Result[@lux.ConversionResult[@lux.LucentResponse], String] {
  let jv = match @internal.parse_protocol_json(json_str) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  match @openai_chat.openai_chat_to_lux_response(json_str) {
    Ok(base) => Ok(attach_reasoning(base.value(), jv))
    Err(e) => Err(e)
  }
}

///|
/// 从原始 JSON 提取每 choice 的 message.reasoning / reasoning_content，
/// 重建 message 为带消息级 reasoning 的形态。
fn attach_reasoning(
  resp : @lux.LucentResponse,
  jv : Json,
) -> @lux.ConversionResult[@lux.LucentResponse] {
  let choices = resp.choices
  let rebuilt : Array[@lux.LucentChoice] = []
  let mut i = 0
  while i < choices.length() {
    let c = choices[i]
    let reasoning = match @internal.obj_get(jv, "choices") {
      Some(Array(cs)) if i < cs.length() =>
        match @internal.obj_get(cs[i], "message") {
          Some(m) =>
            match @internal.field_str(m, "reasoning") {
              Some(text) => Some(@lux.LucentThinking::visible(text, None))
              None =>
                match @internal.field_str(m, "reasoning_content") {
                  Some(text) => Some(@lux.LucentThinking::visible(text, None))
                  None => None
                }
            }
          None => None
        }
      _ => None
    }
    let msg = match reasoning {
      Some(th) =>
        @lux.LucentMessage::with_reasoning(
          c.message.role,
          c.message.content,
          Some(th),
        )
      None => c.message
    }
    rebuilt.push(@lux.LucentChoice::new(c.index, msg, c.finish_reason, None))
    i = i + 1
  }
  let new_resp = @lux.LucentResponse::new(
    resp.id,
    resp.model,
    resp.created_at,
    rebuilt,
    resp.usage,
    resp.provider_payload,
  )
  @lux.ConversionResult::new(new_resp)
}

///|
/// 在 JSON 对象中设置/替换一个键值对（重建 Object）
fn json_set(obj : Json, key : String, val : Json) -> Json {
  match obj {
    Object(entries) => {
      let new_map : Map[String, Json] = Map([])
      let mut found = false
      for entry in entries {
        match entry {
          (k, v) =>
            if k == key {
              new_map[k] = val
              found = true
            } else {
              new_map[k] = v
            }
        }
      }
      if !found {
        new_map[key] = val
      }
      Json::object(new_map)
    }
    _ => obj
  }
}

///|
/// 4. 响应编码 — openai-chat 核心 + reasoning 字段后处理
///
/// 出站字段名：默认 `reasoning`（vLLM 形态）；经 provider_payload.reasoning_field
/// 显式声明 `reasoning_content`（DeepSeek/Fireworks 形态）时切换。
pub fn lux_response_to_vllm(
  resp : @lux.LucentResponse,
) -> Result[@lux.ConversionResult[String], String] {
  let base = @openai_chat.lux_response_to_openai_chat(resp)
  match base {
    Ok(cr) => {
      // 取首个 choice 的消息级 reasoning，后处理插入 message 对象
      let reasoning_opt = if resp.choices.length() > 0 {
        resp.choices[0].message.reasoning
      } else {
        None
      }
      match reasoning_opt {
        Some(th) => {
          let field_name = reasoning_field_name(resp)
          let jv = @json.parse(cr.value()) catch { _ => return Ok(cr) }
          match @internal.obj_get(jv, "choices") {
            Some(Array(cs)) if cs.length() > 0 => {
              let msg = match @internal.obj_get(cs[0], "message") {
                Some(m) => json_set(m, field_name, Json::string(th.text))
                None => { "message": Json::string(th.text) }
              }
              let c0 = json_set(cs[0], "message", msg)
              let new_cs : Array[Json] = [c0]
              let mut k = 1
              while k < cs.length() {
                new_cs.push(cs[k])
                k = k + 1
              }
              let root = json_set(jv, "choices", Json::array(new_cs))
              Ok(@lux.ConversionResult::new(root.stringify()))
            }
            _ => Ok(cr)
          }
        }
        None => Ok(cr)
      }
    }
    Err(e) => Err(e)
  }
}

///|
/// 出站字段名：默认 reasoning（vLLM 形态）；经 provider_payload.reasoning_field
/// 显式声明 "reasoning_content"（DeepSeek/Fireworks 形态）时切换。
fn reasoning_field_name(resp : @lux.LucentResponse) -> String {
  match resp.provider_payload {
    Some(Object(m)) =>
      match m.get("reasoning_field") {
        Some(String(s)) if s == "reasoning_content" => s
        _ => "reasoning"
      }
    _ => "reasoning"
  }
}

///|
/// 5. 流解码 — vLLM SSE → Lux 事件（含 delta.reasoning 捕获）
///
/// 与标准 openai-chat 的差异：vLLM 在 delta 中携带 `reasoning` /
/// `reasoning_content` 字段（标准 Chat API 无）。本子协议自行解析，
/// 捕获 reasoning 增量 → 独立 Thinking 块（块索引 1，content 用 0）。
pub fn vllm_sse_to_events(
  sse_str : String,
) -> Result[@lux.ConversionResult[Array[@lux.LucentStreamEvent]], String] {
  let events : Array[@lux.LucentStreamEvent] = []
  let lines = sse_str.split("\n").to_array()
  let mut text_block_open = false // 是否有未闭合的文本块
  let mut thinking_block_open = false // 是否有未闭合的 reasoning 块
  let mut current_tool_block = -1 // 当前工具调用块索引（-1 表示无）
  let mut i = 0
  while i < lines.length() {
    let line = lines[i]
    let line_str = line.to_owned()
    // 检查是否为 data: 行（逐字符比较，因为 MoonBit String 无 startsWith 方法）
    let is_data = if line_str.length() >= 5 {
      line_str[0] == 'd' &&
      line_str[1] == 'a' &&
      line_str[2] == 't' &&
      line_str[3] == 'a' &&
      line_str[4] == ':'
    } else {
      false
    }
    if is_data {
      // 提取 data: 后的内容
      let mut payload = ""
      let mut p = 5
      while p < line_str.length() {
        let ch = Int::unsafe_to_char(line_str[p].to_int())
        payload = payload + "\{ch}"
        p = p + 1
      }
      payload = payload.trim().to_owned()
      if payload == "[DONE]" {
        // 闭合未关闭的块
        if text_block_open {
          events.push(BlockEnd(0))
          text_block_open = false
        }
        if thinking_block_open {
          events.push(BlockEnd(1))
          thinking_block_open = false
        }
        if current_tool_block >= 0 {
          events.push(BlockEnd(current_tool_block))
          current_tool_block = -1
        }
        events.push(Done)
        i = i + 1
        continue
      }
      // 清理 SSE 心跳标记（如 : keep-alive）
      payload = @internal.clean_sse_heartbeat(payload)
      // 检测截断的 JSON（字符串未闭合、括号不匹配）
      if @internal.is_json_truncated(payload) {
        // 截断的事件，跳过
        i = i + 1
        continue
      }
      // 清理无效转义序列（某些 API 可能包含 \: 等非标准转义）
      payload = @internal.sanitize_json_escapes(payload)
      let jv = @json.parse(payload) catch {
        _ => {
          i = i + 1
          continue
        }
      }
      // usage 帧（choices 空的最后一帧）
      match @internal.obj_get(jv, "usage") {
        Some(u) => {
          let pt = @internal.field_int(u, "prompt_tokens").unwrap_or(0)
          let ct = @internal.field_int(u, "completion_tokens").unwrap_or(0)
          let tt = @internal.field_int(u, "total_tokens").unwrap_or(0)
          events.push(Usage(@lux.LucentUsage::new(pt, ct, tt)))
        }
        None => ()
      }
      // choices[0].delta
      match @internal.field_arr(jv, "choices") {
        Some(choices) =>
          if choices.length() > 0 {
            match @internal.obj_get(choices[0], "delta") {
              Some(delta) => {
                // role
                match @internal.field_str(delta, "role") {
                  Some("assistant") =>
                    events.push(
                      ConversationStart(
                        @lux.LucentConversationMeta::new(None, None, None),
                      ),
                    )
                  _ => ()
                }
                // content
                match @internal.field_str(delta, "content") {
                  Some(s) => {
                    if !text_block_open {
                      events.push(BlockStart(0, Text))
                      text_block_open = true
                    }
                    events.push(
                      BlockDelta(0, @lux.LucentBlockDelta::text_delta(s)),
                    )
                  }
                  None => ()
                }
                // reasoning（vLLM: delta.reasoning；DeepSeek/Fireworks: delta.reasoning_content）
                // 独立块索引 1（content 固定用 0），经 Thinking 块生命周期表达
                let reasoning_text = match
                  @internal.field_str(delta, "reasoning") {
                  Some(s) => Some(s)
                  None => @internal.field_str(delta, "reasoning_content")
                }
                match reasoning_text {
                  Some(s) => {
                    if !thinking_block_open {
                      events.push(
                        BlockStart(1, @lux.LucentBlockType::thinking()),
                      )
                      thinking_block_open = true
                    }
                    events.push(
                      BlockDelta(1, @lux.LucentBlockDelta::thinking_delta(s)),
                    )
                  }
                  None => ()
                }
                // tool_calls
                match @internal.field_arr(delta, "tool_calls") {
                  Some(tcs) => {
                    let mut k = 0
                    while k < tcs.length() {
                      let tc = tcs[k]
                      let idx = @internal.field_int(tc, "index").unwrap_or(0)
                      // 切换块：若旧块未关闭，先关旧块
                      if current_tool_block >= 0 && current_tool_block != idx {
                        events.push(BlockEnd(current_tool_block))
                      }
                      if current_tool_block != idx {
                        // 新工具调用块开始：id + function.name（首帧）
                        let id = @internal.field_str(tc, "id").unwrap_or("")
                        let name = match @internal.obj_get(tc, "function") {
                          Some(fn_obj) =>
                            @internal.field_str(fn_obj, "name").unwrap_or("")
                          None => ""
                        }
                        events.push(
                          BlockStart(
                            idx,
                            @lux.LucentBlockType::tool_call(id, name),
                          ),
                        )
                        current_tool_block = idx
                      }
                      // arguments 增量
                      match @internal.obj_get(tc, "function") {
                        Some(fn_obj) =>
                          match @internal.field_str(fn_obj, "arguments") {
                            Some(args) =>
                              events.push(
                                BlockDelta(
                                  idx,
                                  @lux.LucentBlockDelta::tool_arguments_delta(
                                    args,
                                  ),
                                ),
                              )
                            None => ()
                          }
                        None => ()
                      }
                      k = k + 1
                    }
                  }
                  None => ()
                }
              }
              None => ()
            }
            // finish_reason
            match @internal.field_str(choices[0], "finish_reason") {
              Some(fr) => {
                // 闭合未关闭的块
                if text_block_open {
                  events.push(BlockEnd(0))
                  text_block_open = false
                }
                if thinking_block_open {
                  events.push(BlockEnd(1))
                  thinking_block_open = false
                }
                if current_tool_block >= 0 {
                  events.push(BlockEnd(current_tool_block))
                  current_tool_block = -1
                }
                events.push(Finish(@lux.LucentFinishReason::from_string(fr)))
              }
              None => ()
            }
          }
        None => ()
      }
    }
    i = i + 1
  }
  Ok(@lux.ConversionResult::new(events))
}

///|
/// 6. 流编码 — Lux 事件 → vLLM SSE（含 delta.reasoning 发射）
///
/// 与标准 openai-chat 的差异：ThinkingDelta → `delta.reasoning` 增量
/// （标准 Chat API 无 reasoning 字段）。
pub fn lux_events_to_vllm_sse(
  events : Array[@lux.LucentStreamEvent],
) -> Result[@lux.ConversionResult[String], String] {
  let out : Array[String] = []
  let mut i = 0
  while i < events.length() {
    match events[i] {
      ConversationStart(_) =>
        out.push("data: {\"choices\":[{\"delta\":{\"role\":\"assistant\"}}]}")
      ItemStart(_, _) | ItemEnd(_) | BlockDiscard(_) | Annotations(_, _) => ()
      BlockStart(idx, bt) =>
        match bt {
          ToolCall(id, name) =>
            out.push(
              "data: {\"choices\":[{\"delta\":{\"tool_calls\":[" +
              "{\"index\":" +
              idx.to_string() +
              ",\"id\":\"" +
              @internal.json_escape(id) +
              "\",\"type\":\"function\",\"function\":{\"name\":\"" +
              @internal.json_escape(name) +
              "\"}}]}}]}",
            )
          _ => ()
        }
      BlockEnd(_) => ()
      BlockDelta(idx, delta) =>
        match delta {
          TextDelta(s) =>
            out.push(
              "data: {\"choices\":[{\"delta\":{\"content\":\"" +
              @internal.json_escape(s) +
              "\"}}]}",
            )
          ToolArgumentsDelta(s) =>
            out.push(
              "data: {\"choices\":[{\"delta\":{\"tool_calls\":[" +
              "{\"index\":" +
              idx.to_string() +
              ",\"function\":{\"arguments\":\"" +
              @internal.json_escape(s) +
              "\"}}]}}]}",
            )
          ThinkingDelta(s) =>
            out.push(
              "data: {\"choices\":[{\"delta\":{\"reasoning\":\"" +
              @internal.json_escape(s) +
              "\"}}]}",
            )
          SignatureDelta(_) | RefusalDelta(_) | NativeDelta(_, _) => ()
        }
      Finish(fr) =>
        out.push(
          "data: {\"choices\":[{\"delta\":{},\"finish_reason\":\"" +
          @internal.json_escape(fr.to_string()) +
          "\"}]}",
        )
      Usage(u) =>
        out.push(
          "data: {\"usage\":{\"prompt_tokens\":" +
          u.prompt_tokens.to_string() +
          ",\"completion_tokens\":" +
          u.completion_tokens.to_string() +
          ",\"total_tokens\":" +
          u.total_tokens.to_string() +
          "}}",
        )
      Error(e) =>
        out.push(
          "data: {\"error\":{\"message\":\"" +
          @internal.json_escape(e.message) +
          "\"}}",
        )
      Done => out.push("data: [DONE]")
    }
    i = i + 1
  }
  Ok(@lux.ConversionResult::new(out.join("\n\n") + "\n\n"))
}

///|
/// capability — 适配器能力声明（vLLM 独立 provider 名）
pub fn capability() -> @lux.ProviderCapability {
  @openai_chat.capability()
}
