///|
/// ProviderCapability/LucentDiscovery JSON 序列化
pub fn ProviderCapability::to_json(self : ProviderCapability) -> Json {
  let fields : Map[String, Json] = {
    "model_pattern": Json::string(self.model_pattern),
    "provider": Json::string(self.provider),
    "capabilities": self.capabilities.to_json(),
  }
  match self.extra_params {
    Some(ep) => {
      let ep_fields : Map[String, Json] = Map([])
      for entry in ep {
        match entry {
          (k, v) => ep_fields[k] = v
        }
      }
      if ep_fields.length() > 0 {
        fields["extra_params"] = Json::object(ep_fields)
      }
    }
    None => ()
  }
  Json::object(fields)
}

///|
pub fn LucentDiscovery::to_json(self : LucentDiscovery) -> Json {
  Json::object({
    "schema_version": Json::string(self.schema_version),
    "protocol_version": Json::string(self.protocol_version),
    "schema_url": Json::string(self.schema_url),
    "providers": Json::array(self.providers.map(fn(p) { p.to_json() })),
  })
}

///|
pub fn lux_to_json_string(jv : Json) -> String {
  jv.stringify()
}
