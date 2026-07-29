///|
/// ProviderCapability Registry — SDK 层 Provider 注册表
///
/// 将所有 Provider 的 capability() + 6 个转换函数集中管理。
/// 新增 Provider 只需在 `ALL_PROVIDERS` 追加一条，无需改动 dispatch 逻辑。
///
/// 匹配规则（`match_provider_name`）：
///   1. 精确匹配 provider_name（如 "anthropic" → "anthropic" 条目）
///   2. 匹配 alias 列表（如 "google" → "gemini" 条目，"google-vertex" → "gemini-vertex" 条目）
///   3. 若未匹配，通过 model_name 正则匹配 model_pattern（如 "gpt-4o-codex" → "openai-codex"）

///|
/// 单个 Provider 注册条目
pub struct ProviderRegistration {
  /// 主名称（如 "openai" "anthropic"）
  name : String
  /// 别名列表（如 "google" "openai-responses"）
  aliases : Array[String]
  /// 能力声明
  capability : @lux.ProviderCapability
  /// 请求解码：provider JSON → LucentRequest
  request_decode : (String) -> Result[@lux.LucentRequest, String]
  /// 请求编码：LucentRequest → provider JSON
  request_encode : (@lux.LucentRequest) -> Result[String, String]
  /// 响应解码：provider JSON → LucentResponse
  response_decode : (String) -> Result[@lux.LucentResponse, String]
  /// 响应编码：LucentResponse → provider JSON
  response_encode : (@lux.LucentResponse) -> Result[String, String]
  /// 流式解码：SSE 文本 → StreamEvent 数组
  events_decode : (String) -> Result[Array[@lux.LucentStreamEvent], String]
  /// 流式编码：StreamEvent 数组 → SSE 文本
  events_encode : (Array[@lux.LucentStreamEvent]) -> Result[String, String]
}

///|
pub fn ProviderRegistration::new(
  name : String,
  aliases : Array[String],
  capability : @lux.ProviderCapability,
  request_decode : (String) -> Result[@lux.LucentRequest, String],
  request_encode : (@lux.LucentRequest) -> Result[String, String],
  response_decode : (String) -> Result[@lux.LucentResponse, String],
  response_encode : (@lux.LucentResponse) -> Result[String, String],
  events_decode : (String) -> Result[Array[@lux.LucentStreamEvent], String],
  events_encode : (Array[@lux.LucentStreamEvent]) -> Result[String, String],
) -> ProviderRegistration {
  {
    name,
    aliases,
    capability,
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
/// 新增 Provider 只需在此处追加。
/// 注意：条目顺序影响匹配优先级（精确匹配优先于正则匹配）。
pub fn all_providers() -> Array[ProviderRegistration] {
  [
    ///| OpenAI Responses（主）
    ProviderRegistration::new(
      "openai",
      ["openai-responses", "oai-responses"],
      @openai_responses.capability(),
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
      @openai_codex.codex_to_lux_request,
      @openai_codex.lux_request_to_codex,
      @openai_codex.codex_to_lux_response,
      @openai_codex.lux_response_to_codex,
      @openai_codex.codex_sse_to_events,
      @openai_codex.lux_events_to_codex_sse,
    ),
  ]
}

///|
/// 根据名称匹配 Provider
///
/// 匹配策略：
///   1. 精确匹配 name
///   2. 匹配 aliases 中的别名
///   3. 返回 None（由调用方兜底或报错）
///
/// 若需通过 model_name 正则匹配，调用 `match_by_model`。
pub fn match_provider_name(provider_name : String) -> ProviderRegistration? {
  let providers = all_providers()
  let mut i = 0
  while i < providers.length() {
    let reg = providers[i]
    // 1. 精确匹配
    if reg.name == provider_name {
      return Some(reg)
    }
    // 2. 别名匹配
    let mut j = 0
    while j < reg.aliases.length() {
      if reg.aliases[j] == provider_name {
        return Some(reg)
      }
      j = j + 1
    }
    i = i + 1
  }
  None
}

///|
/// 根据 model_name 匹配 Provider（通过 model_pattern 子串匹配）
///
/// 使用朴素子串匹配作为正则的前缀兜底。
/// 例如 "gpt-4o-codex" 匹配 "gpt-*-codex"（含 `-codex` 子串且 name 含 "gpt"）。
///
/// 返回最先匹配（按 ALL_PROVIDERS 顺序）的 ProviderRegistration，或 None。
pub fn match_by_model(model_name : String) -> ProviderRegistration? {
  let providers = all_providers()
  let mut i = 0
  while i < providers.length() {
    let reg = providers[i]
    if model_pattern_matches(reg.capability.model_pattern, model_name) {
      return Some(reg)
    }
    i = i + 1
  }
  None
}

///|
/// 朴素 model_pattern 匹配
///
/// 支持的 pattern 格式：
///   - "claude-*"  → 前缀匹配 "claude-"
///   - "gpt-*"    → 前缀匹配 "gpt-"
///   - "o*"       → 前缀匹配 "o"
///   - "azure-*"  → 前缀匹配 "azure-"
///   - "gpt-*-codex" → 前后缀匹配（含 "-codex" 后缀且前缀匹配 "gpt-"）
///
/// 这是最简实现，未来可替换为完整 glob/regex 引擎。
fn model_pattern_matches(pattern : String, model_name : String) -> Bool {
  if pattern.contains("*") {
    // 含通配符：拆分为前后缀
    let star_pos = find_first_star(pattern)
    if star_pos == -1 {
      return pattern == model_name
    }
    let prefix = substring(pattern, 0, star_pos)
    let suffix = substring(pattern, star_pos + 1, pattern.length())
    if suffix.contains("*") {
      // 形如 "gpt-*-codex"：拆出第二段
      let second_star = find_first_star(suffix)
      let mid_end = substring(suffix, 0, second_star)
      let final_suffix = substring(suffix, second_star + 1, suffix.length())
      if model_name[:prefix.length()] == prefix &&
        mid_end != "" &&
        contains_after(model_name, prefix, mid_end) &&
        model_name[model_name.length() - final_suffix.length():] == final_suffix {
        true
      } else {
        false
      }
    } else if model_name[:prefix.length()] == prefix &&
      model_name[model_name.length() - suffix.length():] == suffix {
      true
    } else {
      false
    }
  } else {
    pattern == model_name
  }
}

///|
/// 查找第一个 '*' 的位置，未找到返回 -1
fn find_first_star(s : String) -> Int {
  let mut i = 0
  while i < s.length() {
    if s[i] == '*' {
      return i
    }
    i = i + 1
  }
  -1
}

///|
/// 提取子串
fn substring(s : String, start : Int, end : Int) -> String {
  let mut result = ""
  let mut i = start
  while i < end {
    result = result + s[i].to_string()
    i = i + 1
  }
  result
}

///|
/// 检查 s 中 position 之后的子串中是否包含 needle
fn contains_after(s : String, skip_prefix : String, needle : String) -> Bool {
  let rest = substring(s, skip_prefix.length(), s.length())
  rest.contains(needle)
}

///|
/// 获取所有 Provider 的主名称列表
pub fn list_provider_names() -> Array[String] {
  let providers = all_providers()
  let result : Array[String] = []
  let mut i = 0
  while i < providers.length() {
    result.push(providers[i].name)
    i = i + 1
  }
  result
}
