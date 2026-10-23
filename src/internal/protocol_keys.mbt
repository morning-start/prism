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

///|
/// 各协议的**响应级**原生字段表 —— `LucentResponse.provider_payload` 出站门控
/// 的判定依据（对称于请求侧的 `protocol_native_keys`）。
///
/// 只列「该协议响应体顶层、且 IR 未建模」的字段；IR 已建模的字段（id / model /
/// created_at / choices / usage / status 等）由标准字段路径承载，不在此列。
///
/// - `openai`：`CreateChatCompletionResponse` 顶层（vendored 官方 OpenAPI），
///   非建模字段为 `system_fingerprint` / `service_tier` / `metadata` / `moderation`。
/// - `responses`：`Response` 顶层，非建模字段为 `moderation`（`service_tier`
///   只出现在 CreateResponse **请求**侧，不在响应对象里）。
/// - `messages` / `gemini`：无 vendored spec，按公开 API 手工维护
///   （Anthropic 的 `container`、Gemini 的 `modelStatus`）。
pub fn protocol_native_response_keys(protocol : String) -> Array[String] {
  match protocol {
    "openai" => ["system_fingerprint", "service_tier", "metadata", "moderation"]
    "responses" => ["moderation"]
    "messages" => ["container"]
    "gemini" => ["modelStatus"]
    _ => []
  }
}

///|
/// `provider_payload` 中的**编码控制旋钮** —— 由调用方显式设置、用于改变编码
/// 行为的键（如 openai 的 `reasoning_field` 指定消息级 reasoning 的字段名）。
///
/// 它们不是 wire 数据：解码器从不产出，出站时必须跳过 —— 既不能写进响应体
/// （目标会收到不认识的字段），也不能当「外来键」报诊断（那是调用方的合法
/// 输入）。
fn provider_payload_knobs() -> Array[String] {
  ["reasoning_field"]
}

///|
/// `provider_payload` 出站分拣：把响应级扩展载体拆成「可写出」与「需剔除」。
///
/// 判定方向与请求侧 `extras` 完全一致（见 `protocol_native_keys` 文件头）：
/// 键 ∈ native_response(T) 或键不属于任何已知协议 → 放行；键可证明属于其它
/// 协议 → 剔除并记入返回的归属表（调用方补 Unsupported 诊断）。
///
/// 另有一个硬规则：`provider_payload_knobs()` 里的控制旋钮一律跳过 —— 它们
/// 是编码行为开关，不是数据。
///
/// 返回 `(可写出的子集, 被剔除的键 → 归属协议)`；可写出子集为空时为 None。
pub fn split_provider_payload(
  payload : Json?,
  self : String,
) -> (Map[String, Json]?, Map[String, String]) {
  let kept : Map[String, Json] = Map([])
  let dropped : Map[String, String] = Map([])
  match payload {
    Some(Object(m)) => {
      let mine = protocol_native_response_keys(self)
      let knobs = provider_payload_knobs()
      for k, v in m {
        if knobs.contains(k) {
          // 编码旋钮：跳过，不写出也不诊断
        } else if !mine.contains(k) {
          let owners : Array[String] = []
          for p in known_protocols() {
            if p != self && protocol_native_response_keys(p).contains(k) {
              owners.push(p)
            }
          }
          if owners.length() > 0 {
            dropped[k] = owners.join(", ")
          } else {
            // 未知键：放行（厂商网关可能添加响应级字段）
            kept[k] = v
          }
        } else {
          kept[k] = v
        }
      }
    }
    _ => ()
  }
  let kept_opt : Map[String, Json]? = if kept.is_empty() {
    None
  } else {
    Some(kept)
  }
  (kept_opt, dropped)
}
