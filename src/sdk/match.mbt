///|
/// ═══ 功能组：registry+match（注册与路由）═══
/// 本文件：路由匹配（match_provider_name / match_by_model）。
/// 注册表定义见 registry.mbt。

///|
/// match.mbt — Provider 名称/模型模式匹配
///
/// 从 provider_capability.mbt 拆分，职责单一：字符串匹配逻辑。
/// Go 最佳实践：小文件、单一职责，匹配逻辑与注册表解耦。
///
/// T6：匹配叠加动态注册表（register_provider 注册的部署态条目）——
/// 静态表优先、动态表兜底；无动态注册时行为与此前完全一致。

///|
/// 在给定注册数组中按名称匹配（精确主名 → 别名）
fn match_name_in(
  providers : Array[ProviderRegistration],
  provider_key : String,
) -> ProviderRegistration? {
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
  None
}

///|
/// 根据名称匹配 Provider
///
/// 匹配策略：
///   1. 静态表精确匹配 name / 别名
///   2. 动态表（register_provider）精确匹配 name / 别名
///   3. 均未命中时，把输入当作模型名走 `match_by_model` 回退
///
/// 若只想按模型名匹配，直接调用 `match_by_model`。
pub fn match_provider_name(provider_name : String) -> ProviderRegistration? {
  let provider_key = provider_name.trim().to_owned()
  // 1+2. 静态表优先，动态表兜底
  match match_name_in(providers_cache, provider_key) {
    Some(reg) => Some(reg)
    None =>
      match match_name_in(dynamic_providers, provider_key) {
        Some(reg) => Some(reg)
        // 3. 未命中名称时，把输入当作模型名匹配最具体的注册项
        None => match_by_model(provider_key)
      }
  }
}

///|
/// 根据 model_name 匹配 Provider（通过 model_pattern 子串匹配）
///
/// 返回最具体的匹配（pattern 中 * 越多越优先），或 None。
/// 静态表与动态表联合评分：特异性严格大于才替换（同分静态优先）。
pub fn match_by_model(model_name : String) -> ProviderRegistration? {
  let (best_static, score_static) = scan_by_model(
    providers_cache,
    model_name,
    None,
    0,
  )
  let (best_final, _) = scan_by_model(
    dynamic_providers, model_name, best_static, score_static,
  )
  best_final
}

///|
/// 扫描一张表按 model_pattern 评分，返回（最优项, 最优分）
fn scan_by_model(
  providers : Array[ProviderRegistration],
  model_name : String,
  initial_best : ProviderRegistration?,
  initial_score : Int32,
) -> (ProviderRegistration?, Int32) {
  let mut best = initial_best
  let mut best_score = initial_score
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
  (best, best_score)
}

///|
/// 获取所有 Provider 的主名称列表（静态表 + 动态表，动态在后）
pub fn list_provider_names() -> Array[String] {
  let result : Array[String] = []
  for reg in providers_cache {
    result.push(reg.name)
  }
  for reg in dynamic_providers {
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
fn find_comma(s : String, start : Int32) -> Int32 {
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
fn pattern_specificity(pattern : String) -> Int32 {
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
fn count_star(s : String) -> Int32 {
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
fn find_first_star(s : String) -> Int32 {
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
fn substring(s : String, start : Int32, end : Int32) -> String {
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
