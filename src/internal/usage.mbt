///|
/// token 用量解析 — Provider 适配器共用
///
/// 统一四个适配器的 usage 解析模式。每个协议的字段名不同：
/// - OpenAI: `prompt_tokens` / `completion_tokens` / `total_tokens`
/// - Anthropic: `input_tokens` / `output_tokens`（无 total，需计算）
/// - Responses: `input_tokens` / `output_tokens` / `total_tokens`
/// - Gemini: `promptTokenCount` / `candidatesTokenCount` / `totalTokenCount`

///|
/// 从 JSON 对象中解析 token 用量
///
/// `tt_key` 为 None 时，total = pt + ct。
pub fn parse_usage_json(
  u : Json,
  pt_key : String,
  ct_key : String,
  tt_key : String?,
) -> (Int, Int, Int) {
  let pt = field_int(u, pt_key).unwrap_or(0)
  let ct = field_int(u, ct_key).unwrap_or(0)
  let tt = match tt_key {
    Some(key) => field_int(u, key).unwrap_or(pt + ct)
    None => pt + ct
  }
  (pt, ct, tt)
}

///|
/// 提取 reasoning token 数（reasoning 时代细化用量，标准 §9）
///
/// 形态一（OpenAI 系）：`completion_tokens_details.reasoning_tokens`
/// 形态二（Gemini 系）：`thoughtsTokenCount` 直接挂 usage 顶层
/// 形态三（Anthropic / vLLM）：无该字段 → None
///
/// `path` 传空串时按顶层 `thoughtsTokenCount` 读取（Gemini 形态）。
pub fn parse_reasoning_tokens(u : Json, path : Array[String]) -> Int? {
  let mut cursor : Json? = Some(u)
  for key in path {
    match cursor {
      Some(jv) => cursor = obj_get(jv, key)
      None => return None
    }
  }
  match cursor {
    Some(jv) =>
      field_int(
        jv,
        if path.is_empty() {
          "thoughtsTokenCount"
        } else {
          "reasoning_tokens"
        },
      )
    None => None
  }
}

///|
/// 提取 cached token 数（prompt caching 计费核心，标准 §9）
///
/// 形态一（OpenAI 系）：`prompt_tokens_details.cached_tokens`
/// 形态二（Anthropic 系）：`cache_read_input_tokens` 直接挂 usage 顶层
/// 形态三（Gemini 系）：`cachedContentTokenCount` 直接挂 usage 顶层
///
/// `path` 传空串时按顶层 `cache_read_input_tokens` 读取（Anthropic 形态）。
pub fn parse_cached_tokens(u : Json, path : Array[String]) -> Int? {
  let mut cursor : Json? = Some(u)
  for key in path {
    match cursor {
      Some(jv) => cursor = obj_get(jv, key)
      None => return None
    }
  }
  match cursor {
    Some(jv) =>
      field_int(
        jv,
        if path.is_empty() {
          "cache_read_input_tokens"
        } else {
          "cached_tokens"
        },
      )
    None => None
  }
}

///|
/// 提取 cache creation token 数（Anthropic cache write 计费项，标准 §9）
///
/// 仅 Anthropic 形态：`cache_creation_input_tokens` 直接挂 usage 顶层。
/// `path` 传空串时按该键读取；非空 path 表示 OpenAI/Gemini 形态，无此概念 → None。
pub fn parse_cache_creation_tokens(u : Json, path : Array[String]) -> Int? {
  if path.length() > 0 {
    return None
  }
  field_int(u, "cache_creation_input_tokens")
}

///|
/// 提取 Gemini cachedContentTokenCount（Gemini prompt caching 用量项）
pub fn parse_cached_tokens_gemini(u : Json) -> Int? {
  field_int(u, "cachedContentTokenCount")
}
