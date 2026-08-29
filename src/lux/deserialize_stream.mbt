///|
/// LucentStreamEvent JSON 反序列化
pub fn LucentStreamEvent::from_json(
  jv : Json,
) -> Result[LucentStreamEvent, String] {
  match jv {
    Object(m) =>
      match m.get("event") {
        Some(String(ev)) =>
          match ev {
            "conversation_start" => {
              let meta = match m.get("meta") {
                Some(j) =>
                  match LucentConversationMeta::from_json(j) {
                    Ok(v) => v
                    Err(e) => return Err(e)
                  }
                None => return Err("missing meta")
              }
              Ok(ConversationStart(meta))
            }
            "item_start" => {
              let idx = match get_int(m, "index") {
                Ok(n) => n
                Err(e) => return Err(e)
              }
              let item = match m.get("item") {
                Some(j) =>
                  match LucentConversationItem::from_json(j) {
                    Ok(v) => v
                    Err(e) => return Err(e)
                  }
                None => return Err("missing item")
              }
              Ok(ItemStart(idx, item))
            }
            "block_start" => {
              let idx = match get_int(m, "index") {
                Ok(n) => n
                Err(e) => return Err(e)
              }
              let bt = match m.get("block_type") {
                Some(j) =>
                  match LucentBlockType::from_json(j) {
                    Ok(v) => v
                    Err(e) => return Err(e)
                  }
                None => return Err("missing block_type")
              }
              Ok(BlockStart(idx, bt))
            }
            "block_delta" => {
              let idx = match get_int(m, "index") {
                Ok(n) => n
                Err(e) => return Err(e)
              }
              let delta = match m.get("delta") {
                Some(j) =>
                  match LucentBlockDelta::from_json(j) {
                    Ok(v) => v
                    Err(e) => return Err(e)
                  }
                None => return Err("missing delta")
              }
              Ok(BlockDelta(idx, delta))
            }
            "block_end" => {
              let idx = match get_int(m, "index") {
                Ok(n) => n
                Err(e) => return Err(e)
              }
              Ok(BlockEnd(idx))
            }
            "item_end" => {
              let idx = match get_int(m, "index") {
                Ok(n) => n
                Err(e) => return Err(e)
              }
              Ok(ItemEnd(idx))
            }
            "block_discard" => {
              let idx = match get_int(m, "index") {
                Ok(n) => n
                Err(e) => return Err(e)
              }
              Ok(BlockDiscard(idx))
            }
            "annotations" => {
              let idx = match get_int(m, "index") {
                Ok(n) => n
                Err(e) => return Err(e)
              }
              let annotations = match get_arr_annotation(m, "annotations") {
                Ok(v) => v
                Err(e) => return Err(e)
              }
              Ok(Annotations(idx, annotations))
            }
            "finish" => {
              let fr = match m.get("finish_reason") {
                Some(f) =>
                  match LucentFinishReason::from_json(f) {
                    Ok(v) => v
                    Err(e) => return Err(e)
                  }
                None => return Err("missing finish_reason")
              }
              Ok(Finish(fr))
            }
            "usage" => {
              let usage = match m.get("usage") {
                Some(j) =>
                  match LucentUsage::from_json(j) {
                    Ok(v) => v
                    Err(e) => return Err(e)
                  }
                None => return Err("missing usage")
              }
              Ok(Usage(usage))
            }
            "error" => {
              let err = match m.get("error") {
                Some(j) =>
                  match LucentError::from_json(j) {
                    Ok(v) => v
                    Err(e) => return Err(e)
                  }
                None => return Err("missing error")
              }
              Ok(Error(err))
            }
            "done" => Ok(Done)
            _ => Err("unknown stream event")
          }
        Some(_) => Err("expected string for event")
        None => Err("missing event in LucentStreamEvent")
      }
    _ => Err("expected object for LucentStreamEvent")
  }
}

///|
/// === ProviderCapability ===
pub fn ProviderCapability::from_json(
  jv : Json,
) -> Result[ProviderCapability, String] {
  match jv {
    Object(m) => {
      let model_pattern = match get_str(m, "model_pattern") {
        Ok(s) => s
        Err(e) => return Err(e)
      }
      let provider = match get_str(m, "provider") {
        Ok(s) => s
        Err(e) => return Err(e)
      }
      let capabilities = match m.get("capabilities") {
        Some(j) =>
          match LucentCapabilities::from_json(j) {
            Ok(v) => v
            Err(e) => return Err(e)
          }
        None => return Err("missing capabilities")
      }
      let extra_params : Map[String, Json]? = match m.get("extra_params") {
        Some(Object(map)) => Some(map)
        _ => None
      }
      Ok({ model_pattern, provider, capabilities, extra_params })
    }
    _ => Err("expected object for ProviderCapability")
  }
}

///|
/// === LucentDiscovery ===
pub fn LucentDiscovery::from_json(jv : Json) -> Result[LucentDiscovery, String] {
  match jv {
    Object(m) => {
      let schema_version = match get_str(m, "schema_version") {
        Ok(s) => s
        Err(e) => return Err(e)
      }
      let protocol_version = match get_str(m, "protocol_version") {
        Ok(s) => s
        Err(e) => return Err(e)
      }
      let schema_url = match get_str(m, "schema_url") {
        Ok(s) => s
        Err(e) => return Err(e)
      }
      let providers = match get_arr_provider(m, "providers") {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      Ok({ schema_version, protocol_version, schema_url, providers })
    }
    _ => Err("expected object for LucentDiscovery")
  }
}
