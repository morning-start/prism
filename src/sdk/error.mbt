///|
/// ═══ 功能组：error（类型化错误，T7）═══
/// PrismError：SDK 边界的类型化错误（LucentErrorKind 上翻）。
///
/// 背景（架构审计 P1-5）：lux 已有类型化 LucentErrorKind，但 SDK
/// 边界全是 Result[_, String]——消费者的重试/熔断策略只能字符串
/// 匹配 provider_code。本组把类型化错误上翻到 SDK 边界，同时
/// **完整保留**既有 String 错误 API（兼容，不破坏公开 API）。

///|
/// PrismError — SDK 层类型化错误
///
/// kind 复用 IR 的 LucentErrorKind（RateLimit/Authentication/
/// ServerError/ContentFilter/InvalidRequest/Native），让重试与
/// 熔断策略按类型匹配而非字符串匹配。
pub struct PrismError {
  kind : @lux.LucentErrorKind
  message : String
  /// 出错的 provider（运行时解析后的规范名；未解析为 None）
  provider : String?
} derive(Eq, Debug)

///|
pub fn PrismError::new(
  kind : @lux.LucentErrorKind,
  message : String,
  provider : String?,
) -> PrismError {
  { kind, message, provider, }
}

///|
/// 从字符串错误分类（尽力而为的启发式，provider=None）
///
/// 六函数契约固定返回 String（命名规则 §3.1），类型信息在该边界
/// 丢失；分类器按消息内容**保守**推断：
/// - 未命中任何模式 → Native("unclassified")（绝不误判为可重试）
/// - 宁可漏分类，不可错分类——错分类会导致错误的重试行为
///   （如把鉴权失败当限流重试）
pub fn PrismError::from_string(message : String) -> PrismError {
  PrismError::new(classify_message(message), message, None)
}

///|
/// 设置 provider 字段（builder）
pub fn PrismError::with_provider(
  self : PrismError,
  provider : String?,
) -> PrismError {
  { ..self, provider, }
}

///|
/// 是否可重试（限流与服务端错误）
pub fn PrismError::is_retryable(self : PrismError) -> Bool {
  match self.kind {
    RateLimit | ServerError => true
    _ => false
  }
}

///|
/// 错误消息文本（兼容 String 错误时代的展示）
pub fn PrismError::message(self : PrismError) -> String {
  self.message
}

///|
/// 保守分类：按优先级匹配消息模式
fn classify_message(message : String) -> @lux.LucentErrorKind {
  let m = message.to_lower()
  // 1. 限流（先于 server：429 与 5xx 是不同重试语义）
  if m.contains("rate limit") ||
    m.contains("rate_limit") ||
    m.contains("too many requests") ||
    m.contains("429") {
    RateLimit
    // 2. 鉴权
  } else if m.contains("unauthorized") ||
    m.contains("authentication") ||
    m.contains("api key") ||
    m.contains("api-key") ||
    m.contains("permission") ||
    m.contains("401") {
    Authentication
    // 3. 内容过滤（先于 invalid：两者处置不同）
  } else if m.contains("content filter") ||
    m.contains("content_filter") ||
    m.contains("safety") ||
    m.contains("moderation") {
    ContentFilter
    // 4. 请求非法（含协议/路由/解析错误）
  } else if m.contains("invalid") ||
    m.contains("malformed") ||
    m.contains("parse") ||
    m.contains("json") ||
    m.contains("missing") ||
    m.contains("unsupported") ||
    m.contains("unknown provider") ||
    m.contains("400") {
    InvalidRequest
    // 5. 服务端/传输错误
  } else if m.contains("server") ||
    m.contains("unavailable") ||
    m.contains("timeout") ||
    m.contains("network") ||
    m.contains("connection") ||
    m.contains("500") ||
    m.contains("502") ||
    m.contains("503") {
    ServerError
  } else {
    // 6. 未分类：不猜
    Native("unclassified")
  }
}
