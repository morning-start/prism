///|
/// LucentRequest JSON 序列化
pub fn LucentRequest::to_json(self : LucentRequest) -> Json {
  let fields : Map[String, Json] = {
    "schema_version": Json::string(self.schema_version),
    "model": Json::string(self.model),
    "conversation": Json::array(self.conversation.map(fn(ci) { ci.to_json() })),
    "options": self.options.to_json(),
  }
  match self.instructions {
    Some(instrs) =>
      fields["instructions"] = Json::array(instrs.map(fn(c) { c.to_json() }))
    None => ()
  }
  match self.tools {
    Some(tools) =>
      fields["tools"] = Json::array(tools.map(fn(t) { t.to_json() }))
    None => ()
  }
  match self.tool_choice {
    Some(tc) => fields["tool_choice"] = tc.to_json()
    None => ()
  }
  match self.capabilities {
    Some(cap) => fields["capabilities"] = cap.to_json()
    None => ()
  }
  match self.reasoning {
    Some(rc) => fields["reasoning"] = rc.to_json()
    None => ()
  }
  match self.metadata {
    Some(m) => {
      let meta_fields : Map[String, Json] = Map([])
      for entry in m {
        match entry {
          (k, v) => meta_fields[k] = Json::string(v)
        }
      }
      if meta_fields.length() > 0 {
        fields["metadata"] = Json::object(meta_fields)
      }
    }
    None => ()
  }
  match self.extra {
    Some(e) => {
      let extra_fields : Map[String, Json] = Map([])
      for entry in e {
        match entry {
          (k, v) => extra_fields[k] = v
        }
      }
      if extra_fields.length() > 0 {
        fields["extra"] = Json::object(extra_fields)
      }
    }
    None => ()
  }
  Json::object(fields)
}
