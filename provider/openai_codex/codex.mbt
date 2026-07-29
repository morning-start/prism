///|
/// OpenAI Codex Responses — 基于标准 openai_responses 的薄封装
///
/// 子协议名：openai-codex-responses
/// 特有字段：phase (commentary/final_answer)、reasoning.effort 支持 xhigh
///
/// 实现策略：
///   - 解码函数（codex→lux）：先调用主包，再后处理添加 phase
///   - 编码函数（lux→codex）：先调用主包，再后处理 JSON 插入 phase 和 xhigh

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
/// 在 JSON 字符串中的 message/item 里插入 phase 字段
/// 在 ,"content":[ 前插入 ,"phase":"<value>"
fn insert_phase_into_json(s : String, phase : String) -> String {
  let marker = ",\"content\":["
  let replacement = ",\"phase\":\"" + @lux.json_escape(phase) + "\"" + marker
  s.replace(old=marker, new=replacement)
}

///|
/// === 1. 请求解码（codex → lux） ===
///
/// 与主包差异：提取 input[].phase 字段到 LucentMessage.phase
pub fn codex_to_lux_request(
  json_str : String,
) -> Result[@lux.LucentRequest, String] {
  let jv = @json.parse(json_str) catch { _ => return Err("json parse error") }
  // 提取 phase 信息：按 input 数组顺序
  let phases : Array[String?] = []
  match @lux.field_arr(jv, "input") {
    Some(items) =>
      for item in items {
        let phase = @lux.field_str(item, "phase")
        phases.push(phase)
      }
    None => ()
  }
  // 调用主包（主包不再处理 phase）
  match @openai_responses.openai_responses_to_lux_request(json_str) {
    Ok(base) => {
      // 后处理：给 Message 项添加 phase
      let new_items : Array[@lux.LucentConversationItem] = []
      let mut msg_idx = 0
      for item in base.conversation {
        match item {
          Message(m) => {
            if msg_idx < phases.length() {
              let new_msg = @lux.LucentMessage::with_phase(
                m.role,
                m.content,
                phases[msg_idx],
              )
              new_items.push(@lux.LucentConversationItem::message(new_msg))
            } else {
              new_items.push(item)
            }
            msg_idx = msg_idx + 1
          }
          _ => new_items.push(item)
        }
      }
      Ok(base.with_conversation(new_items))
    }
    Err(e) => Err(e)
  }
}

///|
/// === 2. 请求编码（lux → codex） ===
///
/// 与主包差异：
///   - 输出 input[].phase 字段
///   - reasoning.effort 支持 xhigh
pub fn lux_request_to_codex(req : @lux.LucentRequest) -> Result[String, String] {
  // 检查是否需要 Codex 特有处理
  let needs_phase = {
    let mut found = false
    for item in req.conversation {
      match item {
        Message(m) => if m.phase != None { found = true }
        _ => ()
      }
    }
    found
  }
  let needs_xhigh = match req.reasoning {
    Some(rc) =>
      if rc.enabled {
        match rc.effort {
          Some(XHigh) => true
          _ => false
        }
      } else {
        false
      }
    None => false
  }
  if !needs_phase && !needs_xhigh {
    return @openai_responses.lux_request_to_openai_responses(req)
  }
  // 获取基础 JSON
  match @openai_responses.lux_request_to_openai_responses(req) {
    Ok(base_json) => {
      let mut jv = @json.parse(base_json) catch {
        _ => return Err("json parse error")
      }
      // 处理 phase
      if needs_phase {
        match @lux.field_arr(jv, "input") {
          Some(items) => {
            let new_items : Array[Json] = []
            let mut conv_idx = 0
            for item in items {
              let new_item = if conv_idx < req.conversation.length() {
                match req.conversation[conv_idx] {
                  Message(m) =>
                    match m.phase {
                      Some(p) => {
                        let s = item.stringify()
                        let s2 = insert_phase_into_json(s, p)
                        @json.parse(s2) catch {
                          _ => item
                        }
                      }
                      None => item
                    }
                  _ => item
                }
              } else {
                item
              }
              new_items.push(new_item)
              conv_idx = conv_idx + 1
            }
            jv = json_set(jv, "input", Json::array(new_items))
          }
          _ => ()
        }
      }
      // 处理 XHigh
      if needs_xhigh {
        match req.reasoning {
          Some(rc) => {
            let mut rf = "{\"effort\":\"xhigh\""
            match rc.summary {
              Some(Auto) => rf = rf + ",\"summary\":\"auto\""
              Some(Concise) => rf = rf + ",\"summary\":\"concise\""
              Some(Detailed) => rf = rf + ",\"summary\":\"detailed\""
              None => ()
            }
            rf = rf + "}"
            let rjv = @json.parse(rf) catch { _ => jv }
            jv = json_set(jv, "reasoning", rjv)
          }
          None => ()
        }
      }
      Ok(jv.stringify())
    }
    Err(e) => Err(e)
  }
}

///|
/// === 3. 响应解码（codex → lux） ===
///
/// 与主包相同：直接委托
pub fn codex_to_lux_response(
  json_str : String,
) -> Result[@lux.LucentResponse, String] {
  @openai_responses.openai_responses_to_lux_response(json_str)
}

///|
/// === 4. 响应编码（lux → codex） ===
///
/// 与主包差异：输出 output[].phase 字段
pub fn lux_response_to_codex(
  resp : @lux.LucentResponse,
) -> Result[String, String] {
  // 检查是否有 phase
  let needs_phase = {
    let mut found = false
    for choice in resp.choices {
      if choice.message.phase != None {
        found = true
      }
    }
    found
  }
  if !needs_phase {
    return @openai_responses.lux_response_to_openai_responses(resp)
  }
  match @openai_responses.lux_response_to_openai_responses(resp) {
    Ok(base_json) => {
      let mut jv = @json.parse(base_json) catch {
        _ => return Err("json parse error")
      }
      match @lux.field_arr(jv, "output") {
        Some(items) => {
          let new_items : Array[Json] = []
          let mut choice_idx = 0
          for item in items {
            let new_item = if choice_idx < resp.choices.length() {
              match resp.choices[choice_idx].message.phase {
                Some(p) => {
                  let s = item.stringify()
                  let s2 = insert_phase_into_json(s, p)
                  @json.parse(s2) catch {
                    _ => item
                  }
                }
                None => item
              }
            } else {
              item
            }
            new_items.push(new_item)
            choice_idx = choice_idx + 1
          }
          jv = json_set(jv, "output", Json::array(new_items))
        }
        _ => ()
      }
      Ok(jv.stringify())
    }
    Err(e) => Err(e)
  }
}

///|
/// === 5. 流解码（codex SSE → lux events） ===
///
/// 与主包相同：直接委托
pub fn codex_sse_to_events(
  sse_str : String,
) -> Result[Array[@lux.LucentStreamEvent], String] {
  @openai_responses.openai_responses_sse_to_events(sse_str)
}

///|
/// === 6. 流编码（lux events → codex SSE） ===
///
/// 与主包差异：ItemStart 事件中的 message item 需输出 phase
pub fn lux_events_to_codex_sse(
  events : Array[@lux.LucentStreamEvent],
) -> Result[String, String] {
  // 检查是否有 phase
  let needs_phase = {
    let mut found = false
    for ev in events {
      match ev {
        ItemStart(_, Message(m)) => if m.phase != None { found = true }
        _ => ()
      }
    }
    found
  }
  if !needs_phase {
    return @openai_responses.lux_events_to_openai_responses_sse(events)
  }
  match @openai_responses.lux_events_to_openai_responses_sse(events) {
    Ok(base_sse) => {
      // 后处理：在 SSE 中为每个带 phase 的 message item 插入 phase
      let parts = base_sse.split("event: response.output_item.added").to_array()
      if parts.length() <= 1 {
        return Ok(base_sse)
      }
      // 收集所有 ItemStart 事件中的 phase
      let phases : Array[String?] = []
      for ev in events {
        match ev {
          ItemStart(_, Message(m)) => phases.push(m.phase)
          ItemStart(_, _) => phases.push(None)
          _ => ()
        }
      }
      let result : Array[String] = []
      result.push(parts[0].to_owned())
      let mut i = 1
      while i < parts.length() {
        let segment = parts[i].to_owned()
        let phase_opt = if i - 1 < phases.length() {
          phases[i - 1]
        } else {
          None
        }
        match phase_opt {
          Some(p) => {
            let modified = insert_phase_into_json(segment, p)
            result.push("event: response.output_item.added" + modified)
          }
          None => result.push("event: response.output_item.added" + segment)
        }
        i = i + 1
      }
      Ok(result.join(""))
    }
    Err(e) => Err(e)
  }
}

///|
/// capability — 适配器能力声明
pub fn capability() -> @lux.ProviderCapability {
  @lux.ProviderCapability::new(
    "gpt-*-codex",
    "openai-codex",
    @lux.LucentCapabilities::create(
      true,
      true,
      true,
      true,
      true,
      [@lux.Text, @lux.Image],
      [@lux.Text],
    ),
    None,
  )
}
