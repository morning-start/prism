///|
/// ═══ 功能组：registry+match（注册与路由）═══
/// 本文件：注册表定义（ProviderRegistration + providers_cache + build_providers）。
/// 匹配逻辑见 match.mbt。
///
/// 依赖声明见 `moon.pkg`（MoonBit 不允许在 .mbt 内联 import）。

///|
/// 单个 Provider 注册条目
///
/// 身份字段（name / aliases / model_pattern / capability）与 `schema` 全部
/// 来自 `src/provider/<name>/meta.mbt`，本类型只负责把元数据与六个 codec
/// 函数绑在一起。新增 provider 时不要在 build_providers 里重复元数据字面量。
pub struct ProviderRegistration {
  /// 主名称（如 "openai" "messages"）
  name : String
  /// 别名（如 "chat"、"google"、"claude-messages"）
  aliases : Array[String]
  /// 能力声明
  capability : @lux.ProviderCapability
  /// model pattern（从 capability 提取，用于文本通配符匹配）
  model_pattern : String
  /// 该 provider 的字段约束 schema（来自 meta，供校验/schema facade 使用）
  schema : @meta.ProviderSchema
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
  schema : @meta.ProviderSchema,
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
    schema,
    request_decode,
    request_encode,
    response_decode,
    response_encode,
    events_decode,
    events_encode,
  }
}

///|
/// 从 provider 自有元数据构造注册项 —— registry 不再重复元数据字段。
pub fn ProviderRegistration::from_metadata(
  metadata : @meta.ProviderMeta,
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
  ProviderRegistration::new(
    metadata.name(),
    metadata.aliases(),
    metadata.capability(),
    metadata.model_pattern(),
    metadata.schema(),
    request_decode,
    request_encode,
    response_decode,
    response_encode,
    events_decode,
    events_encode,
  )
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
  providers_cache.copy()
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
/// 注册表构造 — provider 静态启用集合的唯一清单
///
/// 顺序是匹配优先级的一部分：`responses` 与 `openai` 的 model_pattern 同为
/// `gpt-*,o*`，`match_by_model` 采用「严格大于」更新最优项，因此 gpt-* 模型
/// 会稳定命中排在前面的 `responses`。调整顺序前请先看 match.mbt 与相关测试。
fn build_providers() -> Array[ProviderRegistration] {
  [
    // OpenAI Responses
    ProviderRegistration::from_metadata(
      @responses.metadata(),
      @responses.responses_to_lux_request,
      @responses.lux_request_to_responses,
      @responses.responses_to_lux_response,
      @responses.lux_response_to_responses,
      @responses.responses_sse_to_events,
      @responses.lux_events_to_responses_sse,
    ),
    // OpenAI Chat Completions
    ProviderRegistration::from_metadata(
      @openai.metadata(),
      @openai.openai_to_lux_request,
      @openai.lux_request_to_openai,
      @openai.openai_to_lux_response,
      @openai.lux_response_to_openai,
      @openai.openai_sse_to_events,
      @openai.lux_events_to_openai_sse,
    ),
    // Anthropic Messages
    ProviderRegistration::from_metadata(
      @messages.metadata(),
      @messages.messages_to_lux_request,
      @messages.lux_request_to_messages,
      @messages.messages_to_lux_response,
      @messages.lux_response_to_messages,
      @messages.messages_sse_to_events,
      @messages.lux_events_to_messages_sse,
    ),
    // Google Gemini（REST API）
    ProviderRegistration::from_metadata(
      @gemini.metadata(),
      @gemini.gemini_to_lux_request,
      @gemini.lux_request_to_gemini,
      @gemini.gemini_to_lux_response,
      @gemini.lux_response_to_gemini,
      @gemini.gemini_sse_to_events,
      @gemini.lux_events_to_gemini_sse,
    ),
  ]
}
