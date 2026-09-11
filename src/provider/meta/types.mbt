///|
/// ═══ provider 元数据唯一源（provider-owned metadata）═══
///
/// 本包是不依赖具体 provider / sdk 的公共叶子包：
///
/// - `FieldConstraint` / `ProviderSchema`：单个 provider 的请求/响应字段约束
/// - `ProviderMeta`：provider 身份（name / aliases / model_pattern）+ capability + schema
///
/// 每个 provider 的 `meta.mbt` 是自身元数据的唯一入口；
/// `src/sdk/registry.mbt` 只负责静态组合与 codec 接线，不重复元数据字段。

///|
/// FieldConstraint — 单字段约束
///
/// `required` 只描述「字段必须出现」，与取值上下界相互独立。
/// 默认构造器（`any` / `range` / `min` / `max`）都产出可选字段，
/// 需要必填时用 `required(true)` 或 `*_required` 变体显式声明。
pub struct FieldConstraint {
  min_val : Double?
  max_val : Double?
  required : Bool
  allowed_values : Array[String]?
}

///|
pub fn FieldConstraint::new(
  min_val : Double?,
  max_val : Double?,
  required : Bool,
  allowed_values : Array[String]?,
) -> FieldConstraint {
  { min_val, max_val, required, allowed_values }
}

///|
/// 无约束（可选、无上下界、无枚举限制）
pub fn FieldConstraint::any() -> FieldConstraint {
  FieldConstraint::new(None, None, false, None)
}

///|
/// 闭区间 [min, max]，可选字段
pub fn FieldConstraint::range(
  min_val : Double,
  max_val : Double,
) -> FieldConstraint {
  FieldConstraint::new(Some(min_val), Some(max_val), false, None)
}

///|
/// 闭区间 [min, max]，必填字段
pub fn FieldConstraint::range_required(
  min_val : Double,
  max_val : Double,
) -> FieldConstraint {
  FieldConstraint::new(Some(min_val), Some(max_val), true, None)
}

///|
/// 下界 min（含），可选字段
pub fn FieldConstraint::min(min_val : Double) -> FieldConstraint {
  FieldConstraint::new(Some(min_val), None, false, None)
}

///|
/// 下界 min（含），必填字段
pub fn FieldConstraint::min_required(min_val : Double) -> FieldConstraint {
  FieldConstraint::new(Some(min_val), None, true, None)
}

///|
/// 上界 max（含），可选字段
pub fn FieldConstraint::max(max_val : Double) -> FieldConstraint {
  FieldConstraint::new(None, Some(max_val), false, None)
}

///|
/// 仅声明是否必填
pub fn FieldConstraint::required(required : Bool) -> FieldConstraint {
  FieldConstraint::new(None, None, required, None)
}

///|
/// 枚举白名单约束
pub fn FieldConstraint::one_of(
  allowed_values : Array[String],
) -> FieldConstraint {
  FieldConstraint::new(None, None, false, Some(allowed_values))
}

///|
pub fn FieldConstraint::any_required() -> FieldConstraint {
  FieldConstraint::required(true)
}

///|
pub fn FieldConstraint::any_optional() -> FieldConstraint {
  FieldConstraint::required(false)
}

///|
pub fn FieldConstraint::min_bound(self : FieldConstraint) -> Double? {
  self.min_val
}

///|
pub fn FieldConstraint::max_bound(self : FieldConstraint) -> Double? {
  self.max_val
}

///|
pub fn FieldConstraint::is_required(self : FieldConstraint) -> Bool {
  self.required
}

///|
pub fn FieldConstraint::allowed(self : FieldConstraint) -> Array[String]? {
  self.allowed_values
}

///|
/// ProviderSchema — 单个 Provider 的请求/响应字段约束集合
pub struct ProviderSchema {
  provider_name : String
  /// 请求字段约束
  temperature : FieldConstraint
  top_p : FieldConstraint
  top_k : FieldConstraint
  max_output_tokens : FieldConstraint
  /// 响应字段约束
  resp_min_choices : Int
  /// 是否允许发送函数/工具调用字段（部分 provider 不支持）
  supports_tools : Bool
  /// 是否支持 system 指令作为顶层字段（而非消息列表中）
  supports_system_instruction : Bool
  /// 支持的 reasoning effort 值列表（None 表示不支持 reasoning；空数组表示全部支持）
  supported_reasoning_efforts : Array[String]?
  /// 额外约束：自定义校验函数列表 (field_name, error_msg)
  extra_checks : Array[() -> Array[String]]?
}

///|
pub fn ProviderSchema::new(
  provider_name : String,
  temperature : FieldConstraint,
  top_p : FieldConstraint,
  top_k : FieldConstraint,
  max_output_tokens : FieldConstraint,
  resp_min_choices : Int,
  supports_tools : Bool,
  supports_system_instruction : Bool,
  supported_reasoning_efforts : Array[String]?,
  extra_checks : Array[() -> Array[String]]?,
) -> ProviderSchema {
  {
    provider_name,
    temperature,
    top_p,
    top_k,
    max_output_tokens,
    resp_min_choices,
    supports_tools,
    supports_system_instruction,
    supported_reasoning_efforts,
    extra_checks,
  }
}

///|
pub fn ProviderSchema::provider_name(self : ProviderSchema) -> String {
  self.provider_name
}

///|
pub fn ProviderSchema::temperature(self : ProviderSchema) -> FieldConstraint {
  self.temperature
}

///|
pub fn ProviderSchema::top_p(self : ProviderSchema) -> FieldConstraint {
  self.top_p
}

///|
pub fn ProviderSchema::top_k(self : ProviderSchema) -> FieldConstraint {
  self.top_k
}

///|
pub fn ProviderSchema::max_output_tokens(
  self : ProviderSchema,
) -> FieldConstraint {
  self.max_output_tokens
}

///|
pub fn ProviderSchema::resp_min_choices(self : ProviderSchema) -> Int {
  self.resp_min_choices
}

///|
pub fn ProviderSchema::supports_tools(self : ProviderSchema) -> Bool {
  self.supports_tools
}

///|
pub fn ProviderSchema::supports_system_instruction(
  self : ProviderSchema,
) -> Bool {
  self.supports_system_instruction
}

///|
pub fn ProviderSchema::supported_reasoning_efforts(
  self : ProviderSchema,
) -> Array[String]? {
  self.supported_reasoning_efforts
}

///|
/// 校验请求是否符合 Provider 的字段约束
/// 返回校验错误列表，空列表表示校验通过
pub fn ProviderSchema::validate_request(
  self : ProviderSchema,
  req : @lux.LucentRequest,
) -> Array[String] {
  let errors : Array[String] = []

  // 1. 通用校验（model 非空等）
  let base = req.validate()
  for e in base.errors {
    errors.push(e)
  }

  // 2. temperature
  match req.options.temperature {
    Some(t) => {
      match self.temperature.min_val {
        Some(min) =>
          if t < min {
            errors.push(
              self.provider_name +
              " temperature must be >= " +
              min.to_string() +
              ", got " +
              t.to_string(),
            )
          }
        None => ()
      }
      match self.temperature.max_val {
        Some(max) =>
          if t > max {
            errors.push(
              self.provider_name +
              " temperature must be <= " +
              max.to_string() +
              ", got " +
              t.to_string(),
            )
          }
        None => ()
      }
    }
    None =>
      if self.temperature.required {
        errors.push(self.provider_name + " temperature is required")
      }
  }

  // 3. top_p
  match req.options.top_p {
    Some(p) => {
      match self.top_p.min_val {
        Some(min) =>
          if p < min {
            errors.push(
              self.provider_name + " top_p must be >= " + min.to_string(),
            )
          }
        None => ()
      }
      match self.top_p.max_val {
        Some(max) =>
          if p > max {
            errors.push(
              self.provider_name + " top_p must be <= " + max.to_string(),
            )
          }
        None => ()
      }
    }
    None =>
      if self.top_p.required {
        errors.push(self.provider_name + " top_p is required")
      }
  }

  // 4. top_k
  match req.options.top_k {
    Some(k) =>
      match self.top_k.min_val {
        Some(min) =>
          if k < min.to_int() {
            errors.push(
              self.provider_name + " top_k must be >= " + min.to_string(),
            )
          }
        None => ()
      }
    None =>
      if self.top_k.required {
        errors.push(self.provider_name + " top_k is required")
      }
  }

  // 5. max_output_tokens
  match req.options.max_output_tokens {
    Some(m) =>
      match self.max_output_tokens.min_val {
        Some(min) =>
          if m < min.to_int() {
            errors.push(
              self.provider_name +
              " max_output_tokens must be >= " +
              min.to_string(),
            )
          }
        None => ()
      }
    None =>
      if self.max_output_tokens.required {
        errors.push(self.provider_name + " max_output_tokens is required")
      }
  }

  // 6. tools：provider 不支持工具时，带工具的请求必须显式报错而非静默丢弃
  if !self.supports_tools {
    match req.tools {
      Some(tools) =>
        if tools.length() > 0 {
          errors.push(self.provider_name + " does not support tools")
        }
      None => ()
    }
  }

  // 7. 额外自定义校验
  match self.extra_checks {
    Some(checks) =>
      for check in checks {
        for e in check() {
          errors.push(e)
        }
      }
    None => ()
  }

  errors
}

///|
/// 校验响应是否符合 Provider 的字段约束
/// 返回校验错误列表，空列表表示校验通过
pub fn ProviderSchema::validate_response(
  self : ProviderSchema,
  resp : @lux.LucentResponse,
) -> Array[String] {
  let errors : Array[String] = []

  // 通用校验
  let base = resp.validate()
  for e in base.errors {
    errors.push(e)
  }

  // 最少 choices 数
  if resp.choices.length() < self.resp_min_choices {
    errors.push(
      self.provider_name +
      " response must have at least " +
      self.resp_min_choices.to_string() +
      " choice(s)",
    )
  }

  errors
}

///|
/// ProviderMeta — provider 身份 + 能力 + schema 的唯一来源
pub struct ProviderMeta {
  name : String
  aliases : Array[String]
  model_pattern : String
  capability : @lux.ProviderCapability
  schema : ProviderSchema
}

///|
pub fn ProviderMeta::new(
  name : String,
  aliases : Array[String],
  model_pattern : String,
  capability : @lux.ProviderCapability,
  schema : ProviderSchema,
) -> ProviderMeta {
  { name, aliases, model_pattern, capability, schema }
}

///|
pub fn ProviderMeta::name(self : ProviderMeta) -> String {
  self.name
}

///|
pub fn ProviderMeta::aliases(self : ProviderMeta) -> Array[String] {
  self.aliases
}

///|
pub fn ProviderMeta::model_pattern(self : ProviderMeta) -> String {
  self.model_pattern
}

///|
pub fn ProviderMeta::capability(self : ProviderMeta) -> @lux.ProviderCapability {
  self.capability
}

///|
pub fn ProviderMeta::schema(self : ProviderMeta) -> ProviderSchema {
  self.schema
}
