/// FieldConstraint — 单字段约束
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

/// FieldConstraint 构造器
pub fn FieldConstraint::any() -> FieldConstraint {
  FieldConstraint::new(None, None, false, None)
}

pub fn FieldConstraint::min(min_val : Double) -> FieldConstraint {
  FieldConstraint::new(Some(min_val), None, true, None)
}

///|
pub fn FieldConstraint::range(min_val : Double, max_val : Double) -> FieldConstraint {
  FieldConstraint::new(Some(min_val), Some(max_val), true, None)
}

///|
pub fn FieldConstraint::range_inclusive(min_val : Double, max_val : Double) -> FieldConstraint {
  FieldConstraint::new(Some(min_val), Some(max_val), true, None)
}

///|
pub fn FieldConstraint::max(max_val : Double) -> FieldConstraint {
  FieldConstraint::new(None, Some(max_val), true, None)
}

pub fn FieldConstraint::required(required : Bool) -> FieldConstraint {
  FieldConstraint::new(None, None, required, None)
}

///|
pub fn FieldConstraint::any_required() -> FieldConstraint {
  FieldConstraint::required(true)
}

///|
pub fn FieldConstraint::any_optional() -> FieldConstraint {
  FieldConstraint::required(false)
}

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
  { provider_name, temperature, top_p, top_k, max_output_tokens, resp_min_choices, supports_tools, supports_system_instruction, supported_reasoning_efforts, extra_checks }
}

///|
pub fn ProviderSchema::validate_request(
  self : ProviderSchema,
  req : @lux.LucentRequest,
) -> Array[String] {
  let errors : Array[String] = []

  // 通用校验（model 非空等）
  let base = req.validate()
  for e in base.errors {
    errors.push(e)
  }

  // Provider 特有约束
  match self.temperature {
    FieldConstraint::new(Some(min), _, _, _) =>
      if req.options.temperature? && req.options.temperature < min {
        errors.push("temperature must be >= " + min.to_string())
      }
    FieldConstraint::new(None, Some(max), _, _) =>
      if req.options.temperature? && req.options.temperature > max {
        errors.push("temperature must be <= " + max.to_string())
      }
    _ => ()
  }

  // 类似地实现 top_p, top_k, max_output_tokens 等约束校验
  // ... (简化实现，仅示例；实际完整实现会参考现有 sdk/schema.mbt 的校验逻辑)

  errors
}

///|
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
    errors.push("response must have at least " + self.resp_min_choices.to_string() + " choice(s)")
  }

  errors
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

pub struct ProviderMeta {
  name : String
  aliases : Array[String]
  model_pattern : String
  capability : @lux.ProviderCapability
  schema : ProviderSchema
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
