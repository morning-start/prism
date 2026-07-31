///|
/// ProviderSchema — 各 Provider 请求/响应字段约束定义
///
/// 每个 Provider 适配器可声明自己的字段取值范围、是否必需、格式要求等。
/// SDK 在 encode/decode 时用这些约束做输入校验（请求）和输出校验（响应）。
///
/// 使用方式：
/// ```
/// let schema = ProviderSchema::openai()
/// let errors = schema.validate_request(lux_req)
/// ```

///|
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
/// === 各 Provider 默认约束 ===

///|
/// OpenAI Chat Completions / Responses
pub fn ProviderSchema::openai() -> ProviderSchema {
  {
    provider_name: "openai",
    temperature: { min_val: Some(0.0), max_val: Some(2.0), required: false, allowed_values: None },
    top_p: { min_val: Some(0.0), max_val: Some(1.0), required: false, allowed_values: None },
    top_k: { min_val: None, max_val: None, required: false, allowed_values: None },
    max_output_tokens: { min_val: Some(1.0), max_val: None, required: false, allowed_values: None },
    resp_min_choices: 1,
    supports_tools: true,
    supports_system_instruction: true,
    supported_reasoning_efforts: None,
    extra_checks: None,
  }
}

///|
/// Anthropic Messages
pub fn ProviderSchema::anthropic() -> ProviderSchema {
  {
    provider_name: "anthropic",
    temperature: { min_val: Some(0.0), max_val: Some(1.0), required: false, allowed_values: None },
    top_p: { min_val: Some(0.0), max_val: Some(1.0), required: false, allowed_values: None },
    top_k: { min_val: Some(1.0), max_val: None, required: false, allowed_values: None },
    max_output_tokens: { min_val: Some(1.0), max_val: None, required: false, allowed_values: None },
    resp_min_choices: 1,
    supports_tools: true,
    supports_system_instruction: true,
    supported_reasoning_efforts: None,
    extra_checks: None,
  }
}

///|
/// Google Gemini
pub fn ProviderSchema::gemini() -> ProviderSchema {
  {
    provider_name: "gemini",
    temperature: { min_val: Some(0.0), max_val: Some(1.0), required: false, allowed_values: None },
    top_p: { min_val: Some(0.0), max_val: Some(1.0), required: false, allowed_values: None },
    top_k: { min_val: Some(1.0), max_val: None, required: false, allowed_values: None },
    max_output_tokens: { min_val: Some(1.0), max_val: None, required: false, allowed_values: None },
    resp_min_choices: 1,
    supports_tools: true,
    supports_system_instruction: true,
    supported_reasoning_efforts: None,
    extra_checks: None,
  }
}

///|
/// Azure OpenAI
pub fn ProviderSchema::azure() -> ProviderSchema {
  // Azure OpenAI 与 OpenAI 约束大体相同
  ProviderSchema::openai()
}

///|
/// 根据 provider 名获取对应 schema（自动匹配）
pub fn get_schema(provider : String) -> ProviderSchema? {
  match provider {
    "openai" | "openai-chat" | "openai-codex" => Some(ProviderSchema::openai())
    "anthropic" | "claude" => Some(ProviderSchema::anthropic())
    "gemini" | "google" | "google-vertex" => Some(ProviderSchema::gemini())
    "azure-openai" | "azure" => Some(ProviderSchema::azure())
    _ => None
  }
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

  // 2. Provider 特有约束
  match req.options.temperature {
    Some(t) => {
      match self.temperature.min_val {
        Some(min) => if t < min {
          errors.push(self.provider_name + " temperature must be >= " + min.to_string() + ", got " + t.to_string())
        }
        None => ()
      }
      match self.temperature.max_val {
        Some(max) => if t > max {
          errors.push(self.provider_name + " temperature must be <= " + max.to_string() + ", got " + t.to_string())
        }
        None => ()
      }
    }
    None => if self.temperature.required {
      errors.push(self.provider_name + " temperature is required")
    }
  }

  match req.options.top_p {
    Some(p) => {
      match self.top_p.min_val {
        Some(min) => if p < min { errors.push(self.provider_name + " top_p must be >= " + min.to_string()) }
        None => ()
      }
      match self.top_p.max_val {
        Some(max) => if p > max { errors.push(self.provider_name + " top_p must be <= " + max.to_string()) }
        None => ()
      }
    }
    None => ()
  }

  match req.options.top_k {
    Some(k) => {
      match self.top_k.min_val {
        Some(min) => if k < min.to_int() { errors.push(self.provider_name + " top_k must be >= " + min.to_string()) }
        None => ()
      }
    }
    None => ()
  }

  match req.options.max_output_tokens {
    Some(m) => {
      match self.max_output_tokens.min_val {
        Some(min) => if m < min.to_int() { errors.push(self.provider_name + " max_output_tokens must be >= " + min.to_string()) }
        None => ()
      }
    }
    None => ()
  }

  // 3. 额外自定义校验
  match self.extra_checks {
    Some(checks) => {
      for check in checks {
        for e in check() {
          errors.push(e)
        }
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
    errors.push(self.provider_name + " response must have at least " + self.resp_min_choices.to_string() + " choice(s)")
  }

  errors
}
