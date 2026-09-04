///|
/// OpenAI Chat — 流编码（LucentStreamEvent[] → SSE）
///
/// 把 Lux 事件流编码为 OpenAI Chat SSE 格式：
/// - ConversationStart → data: {"choices":[{"delta":{"role":"assistant"}}]}
/// - BlockDelta(TextDelta) → data: {"choices":[{"delta":{"content":"..."}]}]}
/// - BlockDelta(ToolArgumentsDelta) → data: {"choices":[{"delta":{"tool_calls":[{"index":N,"function":{"arguments":"..."}}]}]}
/// - BlockStart(ToolCall(id,name)) → data: {"choices":[{"delta":{"tool_calls":[{"index":N,"id":"...","type":"function","function":{"name":"..."}}]}]}
/// - Finish(reason) → data: {"choices":[{"delta":{},"finish_reason":"..."}]}
/// - Usage(u) → data: {"usage":{...}}
/// - Done → data: [DONE]

///|
/// 每个 chunk 的公共前缀：id / object / created / model
fn chunk_prefix(id : String, model : String, created : Int) -> String {
  "data: {\"id\":\"" +
  @internal.json_escape(id) +
  "\",\"object\":\"chat.completion.chunk\",\"created\":" +
  created.to_string() +
  ",\"model\":\"" +
  @internal.json_escape(model) +
  "\","
}

///|
pub fn lux_events_to_openai_sse(
  events : Array[@lux.LucentStreamEvent],
) -> Result[@lux.ConversionResult[String], String] {
  let out : Array[String] = []
  let mut i = 0
  // 从 ConversationStart 提取，注入每个 chunk
  let mut chat_id = ""
  let mut chat_model = ""
  let mut chat_created : Int = 0
  while i < events.length() {
    match events[i] {
      ConversationStart(meta) => {
        chat_id = meta.id.unwrap_or("chatcmpl-0")
        chat_model = meta.model.unwrap_or("")
        chat_created = meta.created_at.unwrap_or(0)
        out.push(
          chunk_prefix(chat_id, chat_model, chat_created) +
          "\"choices\":[{\"delta\":{\"role\":\"assistant\"}}]}",
        )
      }
      ItemStart(_, _) | ItemEnd(_) | BlockDiscard(_) | Annotations(_, _) => ()
      // 块边界在 OpenAI Chat 流中不显式（无 BlockStart/BlockEnd 对应）
      // 但 ToolCall 的 BlockStart 携带 id/name，需编码为 tool_calls 首帧
      BlockStart(idx, bt) =>
        match bt {
          ToolCall(id, name) =>
            out.push(
              chunk_prefix(chat_id, chat_model, chat_created) +
              "\"choices\":[{\"delta\":{\"tool_calls\":[" +
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
              chunk_prefix(chat_id, chat_model, chat_created) +
              "\"choices\":[{\"delta\":{\"content\":\"" +
              @internal.json_escape(s) +
              "\"}}]}",
            )
          ToolArgumentsDelta(s) =>
            out.push(
              chunk_prefix(chat_id, chat_model, chat_created) +
              "\"choices\":[{\"delta\":{\"tool_calls\":[" +
              "{\"index\":" +
              idx.to_string() +
              ",\"function\":{\"arguments\":\"" +
              @internal.json_escape(s) +
              "\"}}]}}]}",
            )
          ThinkingDelta(s) =>
            // DeepSeek/vLLM 使用 reasoning_content 字段传递 thinking 内容
            out.push(
              chunk_prefix(chat_id, chat_model, chat_created) +
              "\"choices\":[{\"delta\":{\"reasoning_content\":\"" +
              @internal.json_escape(s) +
              "\"}}]}",
            )
          SignatureDelta(_) =>
            // OpenAI Chat 无原生 signature 载体，忽略（IR 侧 signature 已在
            // 非流式路径由消息级 reasoning 承载，chat 端无延续语义）
            ()
          RefusalDelta(s) =>
            // refusal 以 content 增量输出（Chat 无独立 refusal delta 字段）
            out.push(
              chunk_prefix(chat_id, chat_model, chat_created) +
              "\"choices\":[{\"delta\":{\"content\":\"" +
              @internal.json_escape(s) +
              "\"}}]}",
            )
          NativeDelta(_, _) => ()
        }
      Finish(fr) =>
        out.push(
          chunk_prefix(chat_id, chat_model, chat_created) +
          "\"choices\":[{\"delta\":{},\"finish_reason\":\"" +
          @internal.json_escape(fr.to_string()) +
          "\"}]}",
        )
      Usage(u) => {
        // 附带空 choices 保证 Chat Completions 格式合法
        let mut usage_json = "\"choices\":[],\"usage\":{\"prompt_tokens\":" +
          u.prompt_tokens.to_string() +
          ",\"completion_tokens\":" +
          u.completion_tokens.to_string() +
          ",\"total_tokens\":" +
          u.total_tokens.to_string()
        match u.reasoning_tokens {
          Some(n) =>
            usage_json = usage_json +
              ",\"completion_tokens_details\":{\"reasoning_tokens\":" +
              n.to_string() +
              "}"
          None => ()
        }
        match u.cached_tokens {
          Some(n) =>
            usage_json = usage_json +
              ",\"prompt_tokens_details\":{\"cached_tokens\":" +
              n.to_string() +
              "}"
          None => ()
        }
        out.push(
          chunk_prefix(chat_id, chat_model, chat_created) + usage_json + "}}",
        )
      }
      Error(e) => {
        // 官方错误帧为独立 data: {"error":{...}}，不包 chunk 外壳（id/choices 前缀）
        // kind 类型化为 OpenAI error.type 语义（rate_limit_error 等），未知走 native
        let error_type = match e.kind {
          RateLimit => "rate_limit_error"
          InvalidRequest => "invalid_request_error"
          Authentication => "authentication_error"
          ServerError => "server_error"
          ContentFilter => "invalid_request_error"
          Native(tag) => tag
        }
        out.push(
          "data: {\"error\":{\"type\":\"" +
          @internal.json_escape(error_type) +
          "\",\"message\":\"" +
          @internal.json_escape(e.message) +
          "\"}}",
        )
      }
      Done => out.push("data: [DONE]")
    }
    i = i + 1
  }
  Ok(@lux.ConversionResult::new(out.join("\n\n") + "\n\n"))
}
