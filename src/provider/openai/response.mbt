///|
/// === 响应解码：OpenAI Chat JSON → LucentResponse ===

///|
/// 解析 choices[] → LucentChoice[]
fn parse_choices(jv : Json) -> Array[@lux.LucentChoice] {
  match @internal.field_arr(jv, "choices") {
    Some(choices) => {
      let result : Array[@lux.LucentChoice] = []
      let mut i = 0
      while i < choices.length() {
        let c = choices[i]
        let idx = @internal.field_int(c, "index").unwrap_or(0)
        match @internal.obj_get(c, "message") {
          Some(msg_jv) => {
            let role = match @internal.field_str(msg_jv, "role") {
              Some("assistant") => @lux.Assistant
              _ => Assistant
            }
            let content : Array[@lux.LucentContent] = []
            // content 字符串
            match @internal.field_str(msg_jv, "content") {
              Some(s) => content.push(@lux.LucentContent::text(s))
              None => ()
            }
            // tool_calls[]
            match @internal.field_arr(msg_jv, "tool_calls") {
              Some(calls) => {
                let mut k = 0
                while k < calls.length() {
                  let tc = calls[k]
                  let id = @internal.field_str(tc, "id").unwrap_or("")
                  match @internal.obj_get(tc, "function") {
                    Some(fn_obj) => {
                      let name = @internal.field_str(fn_obj, "name").unwrap_or(
                        "",
                      )
                      let args = @internal.field_str(fn_obj, "arguments").unwrap_or(
                        "{}",
                      )
                      content.push(
                        @lux.LucentContent::tool_use(id, name, args, None),
                      )
                    }
                    None => ()
                  }
                  k = k + 1
                }
              }
              None => ()
            }
            // 旧式 function_call（CR-007 §1.1）
            //
            // OpenAI legacy function calling 在 message 上用**单数**字段
            // `function_call: {name, arguments}`（无 `id`），与新式
            // `tool_calls: [{id, function:{name, arguments}}]` 是并存的两套载体，
            // 官方 `finish_reason` 枚举亦分别有 `function_call` / `tool_calls`。
            //
            // 此前只读 `tool_calls[]`，旧式响应解出 `content: []` —— 工具调用
            // **整体丢失**且零诊断，转 messages 后得到
            // `{"content":[],"stop_reason":"tool_use"}`（声称调了工具却没有内容）。
            //
            // 旧式字段无 id，按确定性规则合成（CR-007 §2.3 决策点一 A）：
            // 与 responses 侧 `fc_0` / `msg_0` 同类的合成前缀做法，
            // 保证同源往返可复现、tool_result 回程可对上。
            match @internal.obj_get(msg_jv, "function_call") {
              Some(fc_obj) => {
                let name = @internal.field_str(fc_obj, "name").unwrap_or("")
                let args = @internal.field_str(fc_obj, "arguments").unwrap_or(
                  "{}",
                )
                content.push(
                  @lux.LucentContent::tool_use("call_fn_0", name, args, None),
                )
              }
              None => ()
            }
            // refusal
            match @internal.field_str(msg_jv, "refusal") {
              Some(r) => content.push(@lux.LucentContent::refusal(r))
              None => ()
            }
            // reasoning（vLLM: message.reasoning；DeepSeek/Fireworks: message.reasoning_content）
            let reasoning : @lux.LucentThinking? = match
              @internal.field_str(msg_jv, "reasoning") {
              Some(text) => Some(@lux.LucentThinking::visible(text, None))
              None =>
                match @internal.field_str(msg_jv, "reasoning_content") {
                  Some(text) => Some(@lux.LucentThinking::visible(text, None))
                  None => None
                }
            }
            let finish = match @internal.field_str(c, "finish_reason") {
              Some(fr) => @lux.LucentFinishReason::from_string(fr)
              None => Stop
            }
            let msg = match reasoning {
              Some(th) =>
                @lux.LucentMessage::with_reasoning(role, content, Some(th))
              None => @lux.LucentMessage::new(role, content)
            }
            result.push(@lux.LucentChoice::new(idx, msg, finish, None))
          }
          None => ()
        }
        i = i + 1
      }
      result
    }
    None => []
  }
}

///|

///|
/// 3. openai_to_lux_response — 响应解码
pub fn openai_to_lux_response(
  json_str : String,
) -> Result[@lux.ConversionResult[@lux.LucentResponse], String] {
  let jv = match @internal.parse_protocol_json(json_str) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let id = @internal.field_str(jv, "id").unwrap_or("")
  let model = @internal.field_str(jv, "model").unwrap_or("")
  // created 归一：编码器在 IR 无时间戳时写 0 哨兵（官方 schema required，见
  // 下方 created_part），解码把 0 归回 None，保证 encode→decode 往返的 IR 恒等
  // （G5 四端点差分不变量）。真实时间戳（>0）原样保留。
  let created = match @internal.field_int(jv, "created") {
    Some(0) => None
    other => other
  }
  let choices = parse_choices(jv)
  // 响应级元数据 → provider_payload（响应级扩展载体，对称于请求侧 options.extras。
  // vendored 官方 OpenAPI `CreateChatCompletionResponse` 顶层的非建模字段为
  // system_fingerprint / service_tier / metadata / moderation，全部软失败保留；
  // 标准 §9：不进 IR 字段的响应级信息保留给调用方，不静默丢弃）
  let payload_fields : Array[String] = []
  match @internal.field_str(jv, "system_fingerprint") {
    Some(fp) =>
      payload_fields.push(
        "\"system_fingerprint\":\"" + @internal.json_escape(fp) + "\"",
      )
    None => ()
  }
  match @internal.field_str(jv, "service_tier") {
    Some(tier) =>
      payload_fields.push(
        "\"service_tier\":\"" + @internal.json_escape(tier) + "\"",
      )
    None => ()
  }
  // metadata / moderation 是对象形态，原样 stringify 保留
  for key in ["metadata", "moderation"] {
    match @internal.obj_get(jv, key) {
      Some(v) => payload_fields.push("\"" + key + "\":" + v.stringify())
      None => ()
    }
  }
  let provider_payload : Json? = if payload_fields.length() > 0 {
    match @internal.parse_json_opt("{" + payload_fields.join(",") + "}") {
      Some(v) => Some(v)
      None => None
    }
  } else {
    None
  }
  // usage（含 reasoning/cached 细化用量，标准 §9）
  let usage = match @internal.obj_get(jv, "usage") {
    Some(u) => {
      let (pt, ct, tt) = @internal.parse_usage_json(
        u,
        "prompt_tokens",
        "completion_tokens",
        Some("total_tokens"),
      )
      let reasoning = @internal.parse_reasoning_tokens(u, [
        "completion_tokens_details",
      ])
      let cached = @internal.parse_cached_tokens(u, ["prompt_tokens_details"])
      Some(@lux.LucentUsage::full(pt, ct, tt, reasoning, cached, None))
    }
    None => None
  }
  Ok(
    @lux.ConversionResult::new(
      @lux.LucentResponse::new(
        id, model, created, choices, usage, provider_payload,
      ),
    ),
  )
}

///|
/// === 响应编码：LucentResponse → OpenAI Chat JSON ===

///|
/// 4. lux_response_to_openai — 响应编码
pub fn lux_response_to_openai(
  resp : @lux.LucentResponse,
) -> Result[@lux.ConversionResult[String], String] {
  let choices_json : Array[String] = []
  let diagnostics : Array[@lux.ConversionDiagnostic] = []
  let mut i = 0
  while i < resp.choices.length() {
    let c = resp.choices[i]
    let role = role_to_string(c.message.role)
    // content 由 content_field_to_json 统一构造（含图片时数组形式）；tool_calls 入数组；refusal 入字段
    let tool_calls : Array[String] = []
    let refusal_buf : Array[String] = []
    let mut j = 0
    while j < c.message.content.length() {
      let _ = content_part_to_json(
        c.message.content[j],
        tool_calls,
        refusal_buf,
        diagnostics,
      )
      j = j + 1
    }
    let content_field = content_field_to_json(c.message.content, diagnostics)
    // reasoning：消息级 reasoning → message.reasoning 字段
    // 字段名默认 "reasoning"（vLLM）；经 provider_payload.reasoning_field 声明 "reasoning_content" 时切换
    let reasoning_field = match c.message.reasoning {
      Some(th) => {
        let field_name = match resp.provider_payload {
          Some(Object(m)) =>
            match m.get("reasoning_field") {
              Some(String(s)) if s == "reasoning_content" => s
              _ => "reasoning"
            }
          _ => "reasoning"
        }
        ",\"" + field_name + "\":\"" + @internal.json_escape(th.text) + "\""
      }
      None => ""
    }
    let mut msg_obj = "\"index\":" +
      c.index.to_string() +
      ",\"message\":{\"role\":\"" +
      @internal.json_escape(role) +
      "\"," +
      content_field +
      reasoning_field
    if tool_calls.length() > 0 {
      msg_obj = msg_obj + ",\"tool_calls\":[" + tool_calls.join(",") + "]"
    }
    if refusal_buf.length() > 0 {
      msg_obj = msg_obj +
        ",\"refusal\":\"" +
        @internal.json_escape(refusal_buf[0]) +
        "\""
    } else {
      // official-null 形状：官方 ChatCompletion schema 的 Message.required 含
      // `refusal`（string|null）、Choice.required 含 `logprobs`（Logprobs|null）
      // —— 缺失会被官方 schema 拒绝。显式 null 满足 required 且诚实表达
      // "模型未拒绝 / 无 logprobs 数据"，不虚构事实（oracle [5] 组确立）。
      msg_obj = msg_obj + ",\"refusal\":null"
    }
    // finish_reason 收敛到 OpenAI 合法枚举；与流式编码共用
    // `@meta.openai_finish_reason_json`（该函数返回已带引号的字面量）。
    msg_obj = msg_obj +
      "},\"logprobs\":null,\"finish_reason\":" +
      @meta.openai_finish_reason_json(c.finish_reason, "choices", diagnostics)
    // CR-005：`stop_sequence` 是 Anthropic 的响应侧概念（实际命中的终止序列）。
    // OpenAI Chat 的 finish_reason 是封闭枚举且无此值，无载体 → 显式诊断。
    match c.stop_sequence {
      Some(v) =>
        diagnostics.push(
          @lux.ConversionDiagnostic::unsupported(
            "choices.stop_sequence",
            Some(
              "hit stop sequence \"" +
              v +
              "\" has no openai-chat carrier (finish_reason has no stop_sequence value); dropped",
            ),
          ),
        )
      None => ()
    }
    choices_json.push("{" + msg_obj + "}")
    i = i + 1
  }
  let usage_obj = match resp.usage {
    Some(u) => {
      let mut s = ",\"usage\":{\"prompt_tokens\":" +
        u.prompt_tokens.to_string() +
        ",\"completion_tokens\":" +
        u.completion_tokens.to_string() +
        ",\"total_tokens\":" +
        u.total_tokens.to_string()
      // 细化用量：IR 有值时输出 details 子对象（o-series prompt caching / reasoning）
      match u.reasoning_tokens {
        Some(n) =>
          s = s +
            ",\"completion_tokens_details\":{\"reasoning_tokens\":" +
            n.to_string() +
            "}"
        None => ()
      }
      match u.cached_tokens {
        Some(n) =>
          s = s +
            ",\"prompt_tokens_details\":{\"cached_tokens\":" +
            n.to_string() +
            "}"
        None => ()
      }
      s + "}"
    }
    None => ""
  }
  let created_part = match resp.created_at {
    Some(n) => ",\"created\":" + n.to_string()
    // official-null 形状：官方 ChatCompletion schema 中 `created` 是必填 number
    // （不可空）。IR 无时间戳时用 0 哨兵（与流式编码 chunk_prefix 的兜底口径
    // 一致）；解码侧把 0 归回 None，往返 IR 恒等。
    None => ",\"created\":0"
  }
  // provider_payload 出站：响应级扩展载体（对称于请求侧 options.extras，见
  // @internal.split_provider_payload）。此前是**死载体**——解码写入了
  // system_fingerprint / service_tier，编码却从不吐出，openai→openai 往返丢失。
  // reasoning_field 是编码旋钮（本函数上方已消费），分拣时会自动跳过。
  let (payload_kept, payload_foreign) = @internal.split_provider_payload(
    resp.provider_payload,
    "openai",
  )
  @lux.push_extras_foreign_at("provider_payload", payload_foreign, diagnostics)
  // 与本编码器自产键撞名的键：跳过并诊断（目标自产字段优先，绝不产生重复键）
  let reserved : Array[String] = [
    "id", "object", "model", "created", "choices", "usage",
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
  let body = "{\"id\":\"" +
    @internal.json_escape(resp.id) +
    "\",\"object\":\"chat.completion\",\"model\":\"" +
    @internal.json_escape(resp.model) +
    "\"" +
    created_part +
    ",\"choices\":[" +
    choices_json.join(",") +
    "]" +
    usage_obj +
    payload_json +
    "}"
  let result = @lux.ConversionResult::new(body)
  Ok(result.with_diagnostics(diagnostics))
}
