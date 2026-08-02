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
  ]
}

///|
/// 根据名称匹配 Provider
///
/// 匹配策略：
///   1. 精确匹配 name
///   2. 匹配 aliases 中的别名
///   3. 均未命中时，把输入当作模型名走 `match_by_model` 回退
///
/// 若只想按模型名匹配（不做名称/别名命中），直接调用 `match_by_model`。
pub fn match_provider_name(provider_name : String) -> ProviderRegistration? {
  let providers = providers_cache
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
  // 3. 未命中名称时，把输入当作模型名匹配最具体的注册项
  match_by_model(provider_name)
}

///|
/// 根据 model_name 匹配 Provider（通过 model_pattern 子串匹配）
///
/// 返回最具体的匹配（pattern 中 * 越多越优先），或 None。
pub fn match_by_model(model_name : String) -> ProviderRegistration? {
  let providers = providers_cache
  let mut best : ProviderRegistration? = None
  let mut best_score = 0
  let mut i = 0
  while i < providers.length() {
    let reg = providers[i]
    let score = pattern_specificity(reg.model_pattern)
    if score > 0 &&
      score > best_score &&
      model_pattern_matches(reg.model_pattern, model_name) {
      best = Some(reg)
      best_score = score
    }
    i = i + 1
  }
  best
}

///|
/// 朴素 model_pattern 匹配
///
/// 支持逗号分隔的多 pattern（如 "gpt-*,o*"）。
/// 单 pattern 格式：
///   - "claude-*"     → 前缀匹配 "claude-"
///   - "gpt-*" / "o*" → 前缀匹配
///   - "gpt-*-codex"  → 前后缀匹配
///
/// 这是最简实现，未来可替换为完整 glob/regex 引擎。
fn model_pattern_matches(pattern : String, model_name : String) -> Bool {
  let parts = pattern_parts(pattern)
  let mut i = 0
  while i < parts.length() {
    if single_pattern_matches(parts[i], model_name) {
      return true
    }
    i = i + 1
  }
  false
}

///|
/// 单个 pattern 的匹配（含通配符）
fn single_pattern_matches(pattern : String, model_name : String) -> Bool {
  if !pattern.contains("*") {
    return pattern == model_name
  }
  let star_pos = find_first_star(pattern)
  let prefix = pattern[0:star_pos].to_owned()
  let suffix = pattern[star_pos + 1:pattern.length()].to_owned()
  if suffix.contains("*") {
    let second_star = find_first_star(suffix)
    let mid_end = substring(suffix, 0, second_star)
    let final_suffix = substring(suffix, second_star + 1, suffix.length())
    let prefix_ok = prefix.length() <= model_name.length() &&
      substring(model_name, 0, prefix.length()) == prefix
    let suffix_ok = final_suffix.length() <= model_name.length() &&
      substring(
        model_name,
        model_name.length() - final_suffix.length(),
        model_name.length(),
      ) ==
      final_suffix
    prefix_ok &&
    mid_end != "" &&
    contains_after(model_name, prefix, mid_end) &&
    suffix_ok
  } else if prefix.length() <= model_name.length() &&
    suffix.length() <= model_name.length() &&
    substring(model_name, 0, prefix.length()) == prefix &&
    substring(
      model_name,
      model_name.length() - suffix.length(),
      model_name.length(),
    ) ==
    suffix {
    true
  } else {
    false
  }
}

///|
/// 逗号分隔 pattern 拆分为数组（如 "gpt-*,o*" -> ["gpt-*" "o*"]）
fn pattern_parts(pattern : String) -> Array[String] {
  let result : Array[String] = []
  let mut pos = 0
  while pos < pattern.length() {
    let comma = find_comma(pattern, pos)
    if comma == -1 {
      result.push(pattern[pos:pattern.length()].to_owned())
      pos = pattern.length()
    } else {
      result.push(pattern[pos:comma].to_owned())
      pos = comma + 1
    }
  }
  result
}

///|
fn find_comma(s : String, start : Int) -> Int {
  let mut i = start
  while i < s.length() {
    if s[i] == ',' {
      return i
    }
    i = i + 1
  }
  -1
}

///|
/// 返回 pattern 的特异性评分
///
/// 评分 = stars * 1000 + 长度（无通配符的字符数）
/// * 数量越多越具体；同 * 数量时，越长越具体
/// 例如："gpt-*-codex" (1011) > "gpt-*" (1004) > "o*" (1002)
fn pattern_specificity(pattern : String) -> Int {
  let parts = pattern_parts(pattern)
  let mut best = 0
  let mut i = 0
  while i < parts.length() {
    let count = count_star(parts[i])
    let score = count * 1000 + parts[i].length()
    if score > best {
      best = score
    }
    i = i + 1
  }
  best
}

///|
/// 统计字符串中 * 的个数
fn count_star(s : String) -> Int {
  let mut total = 0
  let mut i = 0
  while i < s.length() {
    if s[i] == '*' {
      total = total + 1
    }
    i = i + 1
  }
  total
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
  if start < 0 || end > s.length() || start > end {
    return ""
  }
  s[start:end].to_owned()
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
  let providers = providers_cache
  let result : Array[String] = []
  let mut i = 0
  while i < providers.length() {
    result.push(providers[i].name)
    i = i + 1
  }
  result
}
