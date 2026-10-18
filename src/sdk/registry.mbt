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
  /// 流式编码（ctx 感知，T5 增量转换用）：逐帧转换时跨帧复用首帧
  /// 会话元信息（openai/responses 需要；messages/gemini 无状态，忽略 ctx）
  events_encode_with_ctx : (
    Array[@lux.LucentStreamEvent],
    @lux.LucentConversationMeta?,
  ) -> Result[@lux.ConversionResult[String], String]
  /// 流式编码会话工厂（P0 修复）：逐帧转换时同一会话复用跨帧状态
  /// （块→输出索引/累积参数/计数器）。None 时回退到 events_encode_with_ctx
  /// 逐帧无状态调用（动态注册的 provider 保持既有行为）。
  stream_encoder : (() -> @lux.LucentStreamEncoder)?
  /// 流式解码会话工厂（P1 修复）：逐帧解码时同一会话复用跨帧状态
  /// （当前打开的块/工具索引/累积用量）。None 时回退到 events_decode。
  stream_decoder : (() -> @lux.LucentStreamDecoder)?
  /// 部署态端点基址（Extension：可选，SDK 不发起 HTTP，仅供宿主路由读取）
  base_url : String?
  /// 认证头名（Extension：可选，如 "Authorization" / "x-api-key"）
  auth_header : String?
  /// API 版本（Extension：可选，如 Azure "2024-10-21"）
  api_version : String?
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
  events_encode_with_ctx : (
    Array[@lux.LucentStreamEvent],
    @lux.LucentConversationMeta?,
  ) -> Result[@lux.ConversionResult[String], String],
  base_url : String?,
  auth_header : String?,
  api_version : String?,
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
    events_encode_with_ctx,
    stream_encoder: None,
    stream_decoder: None,
    base_url,
    auth_header,
    api_version,
  }
}

///|
/// 附加流式会话工厂（P0/P1 修复）：逐帧转换时同一会话复用跨帧状态。
///
/// 与 `new` 的逐帧无状态回退相比，会话化保证「逐帧 == 整批」由构造成立——
/// provider 的两条路径共享同一状态机，而非各自实现后互相对齐。
/// 动态注册的 provider 可不设置（回退既有行为）。
pub fn ProviderRegistration::with_stream_sessions(
  self : ProviderRegistration,
  stream_encoder : (() -> @lux.LucentStreamEncoder)?,
  stream_decoder : (() -> @lux.LucentStreamDecoder)?,
) -> ProviderRegistration {
  {
    name: self.name,
    aliases: self.aliases,
    capability: self.capability,
    model_pattern: self.model_pattern,
    schema: self.schema,
    request_decode: self.request_decode,
    request_encode: self.request_encode,
    response_decode: self.response_decode,
    response_encode: self.response_encode,
    events_decode: self.events_decode,
    events_encode: self.events_encode,
    events_encode_with_ctx: self.events_encode_with_ctx,
    stream_encoder,
    stream_decoder,
    base_url: self.base_url,
    auth_header: self.auth_header,
    api_version: self.api_version,
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
  events_encode_with_ctx : (
    Array[@lux.LucentStreamEvent],
    @lux.LucentConversationMeta?,
  ) -> Result[@lux.ConversionResult[String], String],
  base_url : String?,
  auth_header : String?,
  api_version : String?,
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
    events_encode_with_ctx,
    base_url,
    auth_header,
    api_version,
  )
}

///|
/// RegistrationOverrides — 薄注册覆盖项（T6，derive 工厂用）
///
/// 全部可选：None 表示继承基座值。codecs/capability/schema 不可覆盖
/// （协议能力属于基座 adapter；部署态只改身份与端点）。
pub struct RegistrationOverrides {
  name : String?
  aliases : Array[String]?
  model_pattern : String?
  base_url : String?
  auth_header : String?
  api_version : String?
}

///|
pub fn RegistrationOverrides::default() -> RegistrationOverrides {
  {
    name: None,
    aliases: None,
    model_pattern: None,
    base_url: None,
    auth_header: None,
    api_version: None,
  }
}

///|
/// 可选覆盖：Some 优先，否则继承基座值（with_overrides 共用）
fn[T] override_or(override_val : T?, base_val : T?) -> T? {
  match override_val {
    Some(v) => Some(v)
    None => base_val
  }
}

///|
/// 薄注册工厂：复用基座 adapter + 覆盖部署态元数据（azure/vllm 场景）
///
/// 六个 codec 函数与 capability/schema 原样继承（协议行为不变），
/// 只替换身份与端点字段——中间件为同一协议配多个部署端点时不重写
/// 转换逻辑。覆盖 name 时建议同步覆盖 model_pattern/aliases 避免与
/// 基座匹配冲突（静态表精确匹配优先，动态项不会遮蔽静态项）。
pub fn ProviderRegistration::with_overrides(
  self : ProviderRegistration,
  overrides : RegistrationOverrides,
) -> ProviderRegistration {
  {
    name: overrides.name.unwrap_or(self.name),
    aliases: match overrides.aliases {
      Some(a) => a
      None => self.aliases
    },
    capability: self.capability,
    model_pattern: overrides.model_pattern.unwrap_or(self.model_pattern),
    schema: self.schema,
    request_decode: self.request_decode,
    request_encode: self.request_encode,
    response_decode: self.response_decode,
    response_encode: self.response_encode,
    events_decode: self.events_decode,
    events_encode: self.events_encode,
    events_encode_with_ctx: self.events_encode_with_ctx,
    stream_encoder: self.stream_encoder,
    stream_decoder: self.stream_decoder,
    base_url: override_or(overrides.base_url, self.base_url),
    auth_header: override_or(overrides.auth_header, self.auth_header),
    api_version: override_or(overrides.api_version, self.api_version),
  }
}

///|
/// 所有已注册的 Provider（静态表 + 动态表，动态在后）
///
/// 新增 Provider 只需在 `build_providers` 中追加，或运行时
/// `register_provider`。注意：条目顺序影响匹配优先级（精确匹配
/// 优先于正则匹配；静态表整体优先于动态表）。
///
/// 每次调用返回独立数组，调用方可安全修改；内部匹配路径直接读
/// `providers_cache` / `dynamic_providers` 避免重复构造。
pub fn all_providers() -> Array[ProviderRegistration] {
  let result = providers_cache.copy()
  for reg in dynamic_providers {
    result.push(reg)
  }
  result
}

///|
/// 动态注册表 — 运行时 register_provider 追加（T6）
///
/// 与静态表分离：静态表是编译期启用集合（默认路径，行为不变），
/// 动态表承载中间件部署态配置（自定义端点/别名）。匹配时静态表
/// 优先，动态表兜底——默认路径零影响。
let dynamic_providers : Array[ProviderRegistration] = []

///|
/// 注册单个 Provider（运行时显式动态注册）
///
/// 用于中间件部署态：复用已有 adapter + 覆盖 model_pattern/endpoint
/// （配合 ProviderRegistration::derive 薄注册工厂）。
/// 幂等：同名主名称重复注册会替换旧动态项。
/// 注意：动态项不会遮蔽静态表的精确/别名匹配（静态优先）。
pub fn register_provider(reg : ProviderRegistration) -> Unit {
  let mut i = 0
  while i < dynamic_providers.length() {
    if dynamic_providers[i].name == reg.name {
      dynamic_providers[i] = reg
      return
    }
    i = i + 1
  }
  dynamic_providers.push(reg)
}

///|
/// 注销动态注册的 Provider（按主名称）
///
/// 静态表项不受影响（尝试注销静态名返回 false）。
/// 返回是否实际移除了动态项。
pub fn unregister_provider(name : String) -> Bool {
  let kept : Array[ProviderRegistration] = []
  let mut found = false
  for reg in dynamic_providers {
    if reg.name == name {
      found = true
    } else {
      kept.push(reg)
    }
  }
  if found {
    // 顶层 let 不可整体赋值：原地清空后重填（数组是引用类型）
    while dynamic_providers.length() > 0 {
      let _ = dynamic_providers.pop()
    }
    for reg in kept {
      dynamic_providers.push(reg)
    }
  }
  found
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
      @responses.lux_events_to_responses_sse_with_ctx,
      None,
      None,
      None,
    ).with_stream_sessions(
      Some(@responses.responses_stream_encoder),
      Some(@responses.responses_stream_decoder),
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
      @openai.lux_events_to_openai_sse_with_ctx,
      None,
      None,
      None,
    ).with_stream_sessions(None, Some(@openai.openai_stream_decoder)),
    // Anthropic Messages
    ProviderRegistration::from_metadata(
      @messages.metadata(),
      @messages.messages_to_lux_request,
      @messages.lux_request_to_messages,
      @messages.messages_to_lux_response,
      @messages.lux_response_to_messages,
      @messages.messages_sse_to_events,
      @messages.lux_events_to_messages_sse,
      // messages 编码无跨帧状态，忽略 ctx
      fn(
        events : Array[@lux.LucentStreamEvent],
        _ctx : @lux.LucentConversationMeta?,
      ) -> Result[@lux.ConversionResult[String], String] {
        @messages.lux_events_to_messages_sse(events)
      },
      None,
      None,
      None,
    ).with_stream_sessions(None, Some(@messages.messages_stream_decoder)),
    // Google Gemini（REST API）
    ProviderRegistration::from_metadata(
      @gemini.metadata(),
      @gemini.gemini_to_lux_request,
      @gemini.lux_request_to_gemini,
      @gemini.gemini_to_lux_response,
      @gemini.lux_response_to_gemini,
      @gemini.gemini_sse_to_events,
      @gemini.lux_events_to_gemini_sse,
      // gemini 编码无跨帧上下文需求，忽略 ctx
      fn(
        events : Array[@lux.LucentStreamEvent],
        _ctx : @lux.LucentConversationMeta?,
      ) -> Result[@lux.ConversionResult[String], String] {
        @gemini.lux_events_to_gemini_sse(events)
      },
      None,
      None,
      None,
    ).with_stream_sessions(Some(@gemini.gemini_stream_encoder), None),
  ]
}
