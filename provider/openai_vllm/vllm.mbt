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
/// 2. 请求编码 — 与标准 openai-chat 完全一致
pub fn lux_request_to_vllm(
  req : @lux.LucentRequest,
) -> Result[@lux.ConversionResult[String], String] {
  @openai_chat.lux_request_to_openai_chat(req)
}

///|
/// 3. 响应解码 — openai-chat 核心 + vLLM 特有 reasoning 字段后处理
///
/// 只解析一次 JSON：解析结果同时用于核心解码与 reasoning 提取。
pub fn vllm_to_lux_response(
  json_str : String,
) -> Result[@lux.ConversionResult[@lux.LucentResponse], String] {
  let jv = @json.parse(json_str) catch { _ => return Err("json parse error") }
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
/// 5. 流解码 — openai-chat 核心 + delta.reasoning 后处理
pub fn vllm_sse_to_events(
  sse_str : String,
) -> Result[@lux.ConversionResult[Array[@lux.LucentStreamEvent]], String] {
  @openai_chat.openai_chat_sse_to_events(sse_str)
}

///|
/// 6. 流编码 — openai-chat 核心（vLLM 流式 reasoning 暂走 content Thinking 块，
/// 由 openai-chat 的 ThinkingDelta → delta.reasoning 编码完成）
pub fn lux_events_to_vllm_sse(
  events : Array[@lux.LucentStreamEvent],
) -> Result[@lux.ConversionResult[String], String] {
  @openai_chat.lux_events_to_openai_chat_sse(events)
}

///|
/// capability — 适配器能力声明（vLLM 独立 provider 名）
pub fn capability() -> @lux.ProviderCapability {
  @openai_chat.capability()
}
