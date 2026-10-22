///|
/// 各协议的**原生请求字段**表 —— `options.extras` 跨端过滤的判定依据。
///
/// ## 为什么需要这张表
///
/// IR 有两个扩展通道，语义不同：
///
/// - `LucentRequest.extra` —— **程序作者显式给出**的目标端扩展
///   （`docs/lux-ir-design.md`：「Provider-specific extensions」）。作者知道
///   自己要发往哪个目标，故出站时**始终下发**，不做过滤。
/// - `LucentOptions.extras` —— **解码侧填充**的源协议 wire 顶层字段
///   （`schemas/lux-ir-v1.json`：「厂商私有扩展（软失败保留）」）。它的来源
///   天然是**源协议**，因此出站到目标 T 时，若某键可证明属于另一个协议，
///   下发给 T 只会让 T 收到不认识的字段（常见后果是 400 拒绝）。
///
/// ## 判定方向：证明为外来才剔除
///
/// 规则：键 k 在目标 T 上被剔除 ⟺ k ∉ native(T) 且 ∃S≠T, k ∈ native(S)。
///
/// 刻意不采用「白名单内才放行」：
///
/// - **未知键一律放行**（厂商私有键、未来新增字段）→ 不破坏同源往返
///   （openai→openai 保 `seed`、未来新参数）与厂商注入场景；
/// - 表**漏项**只降低过滤强度，不会误丢数据；表**多列**才可能误丢，
///   而每次剔除都带诊断，可被发现。
///
/// 因此每张表的目标是「该协议自己的顶层字段，力求完备」，而不是精确最小集。
/// 注意「目标自身表完备」才是防误丢的关键：只有同一键在另一个协议表里有、
/// 在目标表里漏了，才会误丢。
///
/// ## 表来源
///
/// - `openai` / `responses`：仓库内 vendored 官方 OpenAPI
///   `schemas/endpoints/openai-openapi.yaml`（MIT），按 `allOf`/`$ref` 展开
///   `CreateChatCompletionRequest`（含 `CreateModelResponseProperties`）与
///   `CreateResponse`（含 `ModelResponseProperties` + `ResponseProperties`）
///   的顶层属性集，去掉嵌套对象泄漏进来的键。
/// - `messages` / `gemini`：仓库内**无** vendored spec，按公开 API 手工维护，
///   改动时须对照官方文档。
pub fn protocol_native_keys(protocol : String) -> Array[String] {
  match protocol {
    // OpenAI Chat Completions 顶层参数（vendored OpenAPI 展开后去除嵌套噪声）
    "openai" =>
      [
        "model", "messages", "tools", "tool_choice", "function_call", "functions",
        "temperature", "top_p", "n", "stop", "stream", "stream_options", "max_tokens",
        "max_completion_tokens", "presence_penalty", "frequency_penalty", "logit_bias",
        "logprobs", "top_logprobs", "user", "seed", "response_format", "reasoning_effort",
        "store", "metadata", "service_tier", "parallel_tool_calls", "modalities",
        "audio", "prediction", "web_search_options", "prompt_cache_key", "prompt_cache_retention",
        "safety_identifier", "verbosity", "moderation",
      ]
    // OpenAI Responses 顶层参数（同前；`stop`/`logit_bias`/`seed`/`n` 官方无此参数）
    "responses" =>
      [
        "model", "input", "instructions", "tools", "tool_choice", "temperature",
        "top_p", "max_output_tokens", "stream", "stream_options", "store", "metadata",
        "previous_response_id", "reasoning", "include", "truncation", "background",
        "text", "parallel_tool_calls", "service_tier", "top_logprobs", "prompt_cache_key",
        "prompt_cache_retention", "prompt_cache_options", "user", "safety_identifier",
        "max_tool_calls", "conversation", "context_management", "prompt", "container",
      ]
    // Anthropic /v1/messages 顶层参数（手工维护）
    "messages" =>
      [
        "model", "messages", "system", "max_tokens", "stop_sequences", "stream",
        "temperature", "top_p", "top_k", "metadata", "tools", "tool_choice", "thinking",
        "service_tier", "container", "mcp_servers", "context_management", "betas",
        "disable_parallel_tool_use",
      ]
    // Google Gemini generateContent：顶层字段 + generationConfig 字段
    // （extras 在 gemini 出站时落在 generationConfig 内，故两处键都算「原生」）
    "gemini" =>
      [
        "contents", "tools", "toolConfig", "systemInstruction", "generationConfig",
        "safetySettings", "cachedContent", "temperature", "topP", "topK", "candidateCount",
        "maxOutputTokens", "stopSequences", "responseMimeType", "responseSchema",
        "responseLogprobs", "logprobs", "seed", "presencePenalty", "frequencyPenalty",
        "thinkingConfig", "mediaResolution", "speechConfig",
      ]
    _ => []
  }
}

///|
/// 已知协议名（用于遍历归属）
fn known_protocols() -> Array[String] {
  ["openai", "responses", "messages", "gemini"]
}

///|
/// 找出 extras 中**可证明属于其它协议**的键，返回 键 → 归属协议（逗号分隔）。
///
/// `self` 是即将编码的目标协议名。返回空 Map 表示无需剔除。
/// 判定规则见 `protocol_native_keys` 的文件头说明。
pub fn foreign_extra_keys(
  extras : Map[String, Json]?,
  self : String,
) -> Map[String, String] {
  let out : Map[String, String] = Map([])
  match extras {
    Some(m) => {
      let mine = protocol_native_keys(self)
      for k, _ in m {
        if !mine.contains(k) {
          let owners : Array[String] = []
          for p in known_protocols() {
            if p != self && protocol_native_keys(p).contains(k) {
              owners.push(p)
            }
          }
          if owners.length() > 0 {
            out[k] = owners.join(", ")
          }
        }
      }
    }
    None => ()
  }
  out
}

///|
/// 从 extras 中排除给定键（`keys` 仅作为键集合使用，其值被忽略）。
/// 移除后为空返回 None（与 `extras_without` 口径一致）。
pub fn extras_excluding(
  extras : Map[String, Json]?,
  keys : Map[String, String],
) -> Map[String, Json]? {
  let arr : Array[String] = []
  for k, _ in keys {
    arr.push(k)
  }
  extras_without_keys(extras, arr)
}
