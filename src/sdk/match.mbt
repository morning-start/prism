///|
/// match.mbt — Provider 名称/模型模式匹配
///
/// 从 provider_capability.mbt 拆分，职责单一：字符串匹配逻辑。
/// Go 最佳实践：小文件、单一职责，匹配逻辑与注册表解耦。

///|
/// 去除输入两端空白，保证 ABI/HTTP 边界上的路由一致。
fn normalize_provider_key(value : String) -> String {
  value.trim().to_owned()
}

///|
/// 根据名称匹配 Provider
///
/// 匹配策略：
///   1. 精确匹配 name
///   2. 均未命中时，把输入当作模型名走 `match_by_model` 回退
///
/// 若只想按模型名匹配，直接调用 `match_by_model`。
pub fn match_provider_name(provider_name : String) -> ProviderRegistration? {
  let provider_key = normalize_provider_key(provider_name)
  let providers = providers_cache
  let mut i = 0
  while i < providers.length() {
    let reg = providers[i]
    // 1. 精确匹配主名称
    if reg.name == provider_key {
      return Some(reg)
    }
    // 2. 匹配别名
    let mut j = 0
    while j < reg.aliases.length() {
      if reg.aliases[j] == provider_key {
        return Some(reg)
      }
      j = j + 1
    }
    i = i + 1
  }
  // 3. 未命中名称时，把输入当作模型名匹配最具体的注册项
  match_by_model(provider_key)
}

///|
/// 根据 model_name 匹配 Provider（通过 model_pattern 子串匹配）
///
/// 返回最具体的匹配（字面约束越多、通配符越少越优先），或 None。
pub fn match_by_model(model_name : String) -> ProviderRegistration? {
  let model_key = normalize_provider_key(model_name)
  let providers = providers_cache
  let mut best : ProviderRegistration? = None
  let mut best_score = 0
  let mut i = 0
  while i < providers.length() {
    let reg = providers[i]
    let score = pattern_specificity(reg.model_pattern)
    if score > 0 &&
      score > best_score &&
      model_pattern_matches(reg.model_pattern, model_key) {
      best = Some(reg)
      best_score = score
    }
    i = i + 1
  }
  best
}

///|
/// 获取所有 Provider 的主名称列表
pub fn list_provider_names() -> Array[String] {
  let providers = providers_cache
  let result : Array[String] = []
  for reg in providers {
    result.push(reg.name)
  }
  result
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
    let stars = count_star(parts[i])
    let literals = parts[i].length() - stars
    let score = literals * 1000 - stars
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
/// Resolve a provider name or model to one registry entry.
///
/// Centralizes normalization and the stable unknown-provider error used by
/// request, response, and stream conversion paths.
fn resolve_provider(
  provider_name : String,
) -> Result[ProviderRegistration, String] {
  let provider_key = normalize_provider_key(provider_name)
  match match_provider_name(provider_key) {
    Some(reg) => Ok(reg)
    None => Err("unknown provider: " + provider_key)
  }
}
