///|
/// LucentResponse JSON 序列化
pub fn LucentUsage::to_json(self : LucentUsage) -> Json {
  let fields : Map[String, Json] = {
    "prompt_tokens": self.prompt_tokens.to_json(),
    "completion_tokens": self.completion_tokens.to_json(),
    "total_tokens": self.total_tokens.to_json(),
  }
  match self.reasoning_tokens {
    Some(n) => fields["reasoning_tokens"] = n.to_json()
    None => ()
  }
  match self.cached_tokens {
    Some(n) => fields["cached_tokens"] = n.to_json()
    None => ()
  }
  match self.cache_creation_tokens {
    Some(n) => fields["cache_creation_tokens"] = n.to_json()
    None => ()
  }
  Json::object(fields)
}

///|
pub fn LucentFinishReason::to_json(self : LucentFinishReason) -> Json {
  Json::string(self.to_string())
}

///|
pub fn LucentSafetyRating::to_json(self : LucentSafetyRating) -> Json {
  Json::object({
    "category": Json::string(self.category),
    "probability": Json::string(self.probability),
  })
}

///|
pub fn LucentChoice::to_json(self : LucentChoice) -> Json {
  let fields : Map[String, Json] = {
    "index": self.index.to_json(),
    "message": self.message.to_json(),
    "finish_reason": self.finish_reason.to_json(),
  }
  match self.safety_ratings {
    Some(arr) =>
      fields["safety_ratings"] = Json::array(arr.map(fn(sr) { sr.to_json() }))
    None => ()
  }
  Json::object(fields)
}

///|
pub fn LucentResponse::to_json(self : LucentResponse) -> Json {
  let fields : Map[String, Json] = {
    "schema_version": Json::string(self.schema_version),
    "id": Json::string(self.id),
    "model": Json::string(self.model),
    "choices": Json::array(self.choices.map(fn(c) { c.to_json() })),
  }
  match self.created_at {
    Some(n) => fields["created_at"] = n.to_json()
    None => ()
  }
  match self.usage {
    Some(u) => fields["usage"] = u.to_json()
    None => ()
  }
  match self.provider_payload {
    Some(p) => fields["provider_payload"] = p
    None => ()
  }
  Json::object(fields)
}

///|
pub fn LucentError::to_json(self : LucentError) -> Json {
  let fields : Map[String, Json] = {
    "kind": self.kind.to_json(),
    "message": Json::string(self.message),
  }
  match self.provider_code {
    Some(c) => fields["provider_code"] = Json::string(c)
    None => ()
  }
  Json::object(fields)
}

///|
pub fn LucentErrorKind::to_json(self : LucentErrorKind) -> Json {
  match self {
    RateLimit => Json::string("rate_limit")
    InvalidRequest => Json::string("invalid_request")
    Authentication => Json::string("authentication")
    ServerError => Json::string("server_error")
    ContentFilter => Json::string("content_filter")
    Native(s) => Json::string(s)
  }
}

///|
pub fn LucentConversationMeta::to_json(self : LucentConversationMeta) -> Json {
  let fields : Map[String, Json] = Map([])
  match self.id {
    Some(id) => fields["id"] = Json::string(id)
    None => ()
  }
  match self.model {
    Some(m) => fields["model"] = Json::string(m)
    None => ()
  }
  match self.usage_input {
    Some(n) => fields["usage_input"] = n.to_json()
    None => ()
  }
  match self.created_at {
    Some(ts) => fields["created_at"] = ts.to_json()
    None => ()
  }
  match self.extra {
    Some(ex) => fields["extra"] = ex
    None => ()
  }
  Json::object(fields)
}
