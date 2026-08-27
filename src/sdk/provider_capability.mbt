///|
/// provider_capability.mbt — Provider 注册表定义与构造
///
/// 职责：ProviderRegistration 结构体、注册表缓存、build_providers 构造。
/// 匹配逻辑（match_provider_name / match_by_model）见 match.mbt。

///|
/// 单个 Provider 注册条目
pub struct ProviderRegistration {
  /// 主名称（如 "openai" "anthropic"）
  name : String
  /// 别名列表（如 "google" "openai-responses"）
  aliases : Array[String]
  /// 能力声明
  capability : @lux.ProviderCapability
  /// model pattern（从 capability 提取，用于文本通配符匹配）
  model_pattern : String
  /// 请求解码：provider JSON → LucentRequest（带诊断）
  request_decode : (String) -> Result[
    @lux.ConversionResult[@lux.LucentRequest],
    String,
  ]
  /// 请求编码：LucentRequest → provider JSON（带诊断）
  request_encode : (@lux.LucentRequest) -> Result[
    @lux.ConversionResult[String],
    String,
  ]
  /// 响应解码：provider JSON → LucentResponse（带诊断）
  response_decode : (String) -> Result[
    @lux.ConversionResult[@lux.LucentResponse],
    String,
  ]
  /// 响应编码：LucentResponse → provider JSON（带诊断）
  response_encode : (@lux.LucentResponse) -> Result[
    @lux.ConversionResult[String],
    String,
  ]
  /// 流式解码：SSE 文本 → StreamEvent 数组（带诊断）
  events_decode : (String) -> Result[
    @lux.ConversionResult[Array[@lux.LucentStreamEvent]],
    String,
  ]
  /// 流式编码：StreamEvent 数组 → SSE 文本（带诊断）
  events_encode : (Array[@lux.LucentStreamEvent]) -> Result[
    @lux.ConversionResult[String],
    String,
  ]
}

///|
pub fn ProviderRegistration::new(
  name : String,
  aliases : Array[String],
  capability : @lux.ProviderCapability,
  model_pattern : String,
  request_decode : (String) -> Result[
    @lux.ConversionResult[@lux.LucentRequest],
    String,
  ],
  request_encode : (@lux.LucentRequest) -> Result[
    @lux.ConversionResult[String],
    String,
  ],
  response_decode : (String) -> Result[
    @lux.ConversionResult[@lux.LucentResponse],
    String,
  ],
  response_encode : (@lux.LucentResponse) -> Result[
    @lux.ConversionResult[String],
    String,
  ],
  events_decode : (String) -> Result[
    @lux.ConversionResult[Array[@lux.LucentStreamEvent]],
    String,
  ],
  events_encode : (Array[@lux.LucentStreamEvent]) -> Result[
    @lux.ConversionResult[String],
    String,
  ],
) -> ProviderRegistration {
  {
    name,
    aliases,
    capability,
    model_pattern,
    request_decode,
    request_encode,
    response_decode,
    response_encode,
    events_decode,
    events_encode,
  }
}

///|
/// 所有已注册的 Provider
///
/// 新增 Provider 只需在 `build_providers` 中追加。
/// 注意：条目顺序影响匹配优先级（精确匹配优先于正则匹配）。
///
/// 每次调用返回独立数组，调用方可安全修改；内部匹配路径改用
/// `providers_cache` 避免重复构造。
pub fn all_providers() -> Array[ProviderRegistration] {
  build_providers()
}

///|
/// 注册表缓存 — 构造一次复用
///
/// `build_providers` 会为每个条目调用 `capability()`，其中包含数组分配；
/// 匹配函数（`match_provider_name` / `match_by_model` / `list_provider_names`）
/// 属于每次 SDK 调用都会经过的热路径，故在模块初始化时构造一次。
/// 仅供只读使用。
let providers_cache : Array[ProviderRegistration] = build_providers()

///|
/// 注册表构造 — 唯一的 Provider 清单来源
fn build_providers() -> Array[ProviderRegistration] {
  [
    ///| OpenAI Responses（主）
    ProviderRegistration::new(
      "openai",
      ["openai-responses", "oai-responses"],
      @openai_responses.capability(),
      "gpt-*,o*",
      @openai_responses.openai_responses_to_lux_request,
      @openai_responses.lux_request_to_openai_responses,
      @openai_responses.openai_responses_to_lux_response,
      @openai_responses.lux_response_to_openai_responses,
      @openai_responses.openai_responses_sse_to_events,
      @openai_responses.lux_events_to_openai_responses_sse,
    ),
    ///| OpenAI Chat Completions
    ProviderRegistration::new(
      "openai-chat",
      ["openai_chat", "oai-chat", "chat"],
      @openai_chat.capability(),
      "gpt-*,o*",
      @openai_chat.openai_chat_to_lux_request,
      @openai_chat.lux_request_to_openai_chat,
      @openai_chat.openai_chat_to_lux_response,
      @openai_chat.lux_response_to_openai_chat,
      @openai_chat.openai_chat_sse_to_events,
      @openai_chat.lux_events_to_openai_chat_sse,
    ),
    ///| Anthropic Messages
    ProviderRegistration::new(
      "anthropic",
      ["claude", "claude-messages"],
      @anthropic.capability(),
      "claude-*",
      @anthropic.anthropic_to_lux_request,
      @anthropic.lux_request_to_anthropic,
      @anthropic.anthropic_to_lux_response,
      @anthropic.lux_response_to_anthropic,
      @anthropic.anthropic_sse_to_events,
      @anthropic.lux_events_to_anthropic_sse,
    ),
    ///| Google Gemini（REST API）
    ProviderRegistration::new(
      "gemini",
      ["google", "google-gemini"],
      @gemini.capability(),
      "gemini-*",
      @gemini.gemini_to_lux_request,
      @gemini.lux_request_to_gemini,
      @gemini.gemini_to_lux_response,
      @gemini.lux_response_to_gemini,
      @gemini.gemini_sse_to_events,
      @gemini.lux_events_to_gemini_sse,
    ),
    ///| Google Vertex AI Gemini
    ProviderRegistration::new(
      "google-vertex",
      ["vertex", "gemini-vertex"],
      @gemini_vertex.capability(),
      "gemini-*",
      @gemini_vertex.vertex_to_lux_request,
      @gemini_vertex.lux_request_to_vertex,
      @gemini_vertex.vertex_to_lux_response,
      @gemini_vertex.lux_response_to_vertex,
      @gemini_vertex.vertex_sse_to_events,
      @gemini_vertex.lux_events_to_vertex_sse,
    ),
    ///| Azure OpenAI Responses
    ProviderRegistration::new(
      "azure-openai",
      ["azure", "azure-openai-responses"],
      @openai_azure.capability(),
      "azure-*",
      @openai_azure.azure_to_lux_request,
      @openai_azure.lux_request_to_azure,
      @openai_azure.azure_to_lux_response,
      @openai_azure.lux_response_to_azure,
      @openai_azure.azure_sse_to_events,
      @openai_azure.lux_events_to_azure_sse,
    ),
    ///| OpenAI Codex（Responses 子协议）
    ProviderRegistration::new(
      "openai-codex",
      ["codex", "gpt-codex"],
      @openai_codex.capability(),
      "gpt-*-codex",
      @openai_codex.codex_to_lux_request,
      @openai_codex.lux_request_to_codex,
      @openai_codex.codex_to_lux_response,
      @openai_codex.lux_response_to_codex,
      @openai_codex.codex_sse_to_events,
      @openai_codex.lux_events_to_codex_sse,
    ),
    ///| OpenAI vLLM（Chat 兼容子协议，承载 message.reasoning / delta.reasoning）
    ProviderRegistration::new(
      "openai-vllm",
      ["vllm", "vllm-chat"],
      @openai_vllm.capability(),
      "qwen-*,deepseek-*,glm-*,yi-*",
      @openai_vllm.vllm_to_lux_request,
      @openai_vllm.lux_request_to_vllm,
      @openai_vllm.vllm_to_lux_response,
      @openai_vllm.lux_response_to_vllm,
      @openai_vllm.vllm_sse_to_events,
      @openai_vllm.lux_events_to_vllm_sse,
    ),
  ]
}
