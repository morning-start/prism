///|
/// Lux IR from_json error-path tests (consolidated per type)
///
/// Each listed input exercises one rejection branch of the type's from_json.
/// Per-type test loops over its inputs: any Ok result fails the test, and the
/// failure message carries the raw input, so a regression pinpoints the same
/// case as the previous one-test-per-input layout did. To add a case, append
/// one line to the type's input array.

///|
test "@lux.LucentContent from_json - malformed inputs reject" {
  let invalid : Array[String] = [
    "123", "{}", "{\"type\":42}", "{\"type\":\"unknown_content_type\"}", "{\"type\":\"text\"}",
    "{\"type\":\"text\",\"text\":123}", "{\"type\":\"tool_use\"}", "{\"type\":\"tool_use\",\"tool_use\":123}",
    "{\"type\":\"tool_result\"}", "{\"type\":\"thinking\"}", "{\"type\":\"refusal\"}",
    "{\"type\":\"image\"}", "{\"type\":\"native\"}",
  ]
  for s in invalid {
    match @lux.LucentContent::from_json(@json.parse(s)) {
      Ok(_) => fail("expected Err for input: \{s}")
      Err(_) => ()
    }
  }
}

///|
test "@lux.LucentToolUse from_json - malformed inputs reject" {
  let invalid : Array[String] = [
    "null", "{\"name\":\"x\",\"arguments\":\"{}\"}", "{\"id\":\"x\",\"arguments\":\"{}\"}",
    "{\"id\":\"x\",\"name\":\"get_weather\"}", "{\"id\":123,\"name\":\"get_weather\",\"arguments\":\"{}\"}",
  ]
  for s in invalid {
    match @lux.LucentToolUse::from_json(@json.parse(s)) {
      Ok(_) => fail("expected Err for input: \{s}")
      Err(_) => ()
    }
  }
}

///|
test "@lux.LucentToolResult from_json - malformed inputs reject" {
  let invalid : Array[String] = [
    "true", "{\"content\":[],\"is_error\":false}", "{\"tool_use_id\":\"x\",\"is_error\":false}",
    "{\"tool_use_id\":\"x\",\"content\":\"not-array\",\"is_error\":false}", "{\"tool_use_id\":\"x\",\"content\":[]}",
    "{\"tool_use_id\":\"x\",\"content\":[{\"type\":\"text\",\"text\":\"hi\"}],\"is_error\":42}",
  ]
  for s in invalid {
    match @lux.LucentToolResult::from_json(@json.parse(s)) {
      Ok(_) => fail("expected Err for input: \{s}")
      Err(_) => ()
    }
  }
}

///|
test "@lux.LucentMessage from_json - malformed inputs reject" {
  let invalid : Array[String] = [
    "\"hello\"", "{\"content\":[{\"type\":\"text\",\"text\":\"hi\"}]}", "{\"role\":\"user\"}",
  ]
  for s in invalid {
    match @lux.LucentMessage::from_json(@json.parse(s)) {
      Ok(_) => fail("expected Err for input: \{s}")
      Err(_) => ()
    }
  }
}

///|
test "@lux.LucentConversationItem from_json - malformed inputs reject" {
  let invalid : Array[String] = [
    "null", "{}", "{\"type\":\"unknown_item\"}", "{\"type\":\"message\"}", "{\"type\":\"tool_call\"}",
    "{\"type\":\"reasoning\"}", "{\"type\":\"agent_action\"}",
  ]
  for s in invalid {
    match @lux.LucentConversationItem::from_json(@json.parse(s)) {
      Ok(_) => fail("expected Err for input: \{s}")
      Err(_) => ()
    }
  }
}

///|
test "@lux.LucentTool from_json - malformed inputs reject" {
  let invalid : Array[String] = [
    "42", "{\"parameters\":{\"type\":\"object\"}}", "{\"name\":\"x\"}",
  ]
  for s in invalid {
    match @lux.LucentTool::from_json(@json.parse(s)) {
      Ok(_) => fail("expected Err for input: \{s}")
      Err(_) => ()
    }
  }
}

///|
test "@lux.LucentToolChoice from_json - malformed inputs reject" {
  let invalid : Array[String] = [
    "\"bad\"", "null", "{\"type\":\"specific_tool\"}", "{\"type\":\"specific_tool\",\"name\":42}",
    "{\"name\":\"x\"}",
  ]
  for s in invalid {
    match @lux.LucentToolChoice::from_json(@json.parse(s)) {
      Ok(_) => fail("expected Err for input: \{s}")
      Err(_) => ()
    }
  }
}

///|
test "@lux.LucentStructuredOutput from_json - malformed inputs reject" {
  let invalid : Array[String] = [
    "\"unknown\"", "null", "{\"type\":\"json_schema\"}",
  ]
  for s in invalid {
    match @lux.LucentStructuredOutput::from_json(@json.parse(s)) {
      Ok(_) => fail("expected Err for input: \{s}")
      Err(_) => ()
    }
  }
}

///|
test "@lux.LucentReasoningEffort from_json - malformed inputs reject" {
  let invalid : Array[String] = ["\"ultra\"", "42"]
  for s in invalid {
    match @lux.LucentReasoningEffort::from_json(@json.parse(s)) {
      Ok(_) => fail("expected Err for input: \{s}")
      Err(_) => ()
    }
  }
}

///|
test "@lux.LucentReasoningSummary from_json - malformed inputs reject" {
  let invalid : Array[String] = ["\"verbose\"", "null"]
  for s in invalid {
    match @lux.LucentReasoningSummary::from_json(@json.parse(s)) {
      Ok(_) => fail("expected Err for input: \{s}")
      Err(_) => ()
    }
  }
}

///|
test "@lux.LucentOptions from_json - malformed inputs reject" {
  let invalid : Array[String] = ["\"bad\"", "{}", "{\"stream\":\"yes\"}"]
  for s in invalid {
    match @lux.LucentOptions::from_json(@json.parse(s)) {
      Ok(_) => fail("expected Err for input: \{s}")
      Err(_) => ()
    }
  }
}

///|
test "@lux.LucentReasoningConfig from_json - malformed inputs reject" {
  let invalid : Array[String] = ["42", "{}", "{\"enabled\":\"yes\"}"]
  for s in invalid {
    match @lux.LucentReasoningConfig::from_json(@json.parse(s)) {
      Ok(_) => fail("expected Err for input: \{s}")
      Err(_) => ()
    }
  }
}

///|
test "@lux.LucentCapabilities from_json - malformed inputs reject" {
  let invalid : Array[String] = [
    "null", "{}", "{\"tool_calling\":\"full\",\"parallel_tool_calls\":\"none\",\"reasoning\":\"full\",\"multimodal_input\":\"full\",\"structured_output\":\"full\"}",
  ]
  for s in invalid {
    match @lux.LucentCapabilities::from_json(@json.parse(s)) {
      Ok(_) => fail("expected Err for input: \{s}")
      Err(_) => ()
    }
  }
}

///|
test "@lux.LucentModality from_json - malformed inputs reject" {
  let invalid : Array[String] = ["42"]
  for s in invalid {
    match @lux.LucentModality::from_json(@json.parse(s)) {
      Ok(_) => fail("expected Err for input: \{s}")
      Err(_) => ()
    }
  }
}

///|
test "@lux.LucentMediaSource from_json - malformed inputs reject" {
  let invalid : Array[String] = [
    "42", "{}", "{\"type\":\"unknown_type\"}", "{\"type\":42}",
  ]
  for s in invalid {
    match @lux.LucentMediaSource::from_json(@json.parse(s)) {
      Ok(_) => fail("expected Err for input: \{s}")
      Err(_) => ()
    }
  }
}

///|
test "@lux.LucentMultimedia from_json - malformed inputs reject" {
  let invalid : Array[String] = [
    "null", "{\"source\":{\"type\":\"url\",\"data\":\"x\"}}", "{\"media_type\":\"image/png\"}",
  ]
  for s in invalid {
    match @lux.LucentMultimedia::from_json(@json.parse(s)) {
      Ok(_) => fail("expected Err for input: \{s}")
      Err(_) => ()
    }
  }
}

///|
test "@lux.LucentAnnotation from_json - malformed inputs reject" {
  let invalid : Array[String] = ["42", "{}"]
  for s in invalid {
    match @lux.LucentAnnotation::from_json(@json.parse(s)) {
      Ok(_) => fail("expected Err for input: \{s}")
      Err(_) => ()
    }
  }
}

///|
test "@lux.LucentThinking from_json - malformed inputs reject" {
  let invalid : Array[String] = [
    "null", "{\"redacted\":false}", "{\"text\":\"thinking\"}",
  ]
  for s in invalid {
    match @lux.LucentThinking::from_json(@json.parse(s)) {
      Ok(_) => fail("expected Err for input: \{s}")
      Err(_) => ()
    }
  }
}

///|
test "@lux.LucentAgentAction from_json - malformed inputs reject" {
  let invalid : Array[String] = [
    "null", "{\"id\":\"x\"}", "{\"kind\":\"tool\"}",
  ]
  for s in invalid {
    match @lux.LucentAgentAction::from_json(@json.parse(s)) {
      Ok(_) => fail("expected Err for input: \{s}")
      Err(_) => ()
    }
  }
}

///|
test "@lux.LucentBlockType from_json - malformed inputs reject" {
  let invalid : Array[String] = [
    "42", "{\"id\":\"x\"}", "{\"type\":\"tool_call\"}", "{\"type\":\"tool_call\",\"id\":\"x\"}",
  ]
  for s in invalid {
    match @lux.LucentBlockType::from_json(@json.parse(s)) {
      Ok(_) => fail("expected Err for input: \{s}")
      Err(_) => ()
    }
  }
}

///|
test "@lux.LucentBlockDelta from_json - malformed inputs reject" {
  let invalid : Array[String] = [
    "null", "{}", "{\"type\":\"unknown_delta\"}", "{\"type\":\"text\"}", "{\"type\":\"thinking\"}",
    "{\"type\":\"signature\"}", "{\"type\":\"tool_arguments\"}", "{\"type\":\"refusal\"}",
    "{\"type\":\"native\"}",
  ]
  for s in invalid {
    match @lux.LucentBlockDelta::from_json(@json.parse(s)) {
      Ok(_) => fail("expected Err for input: \{s}")
      Err(_) => ()
    }
  }
}

///|
test "@lux.LucentStreamEvent from_json - malformed inputs reject" {
  let invalid : Array[String] = [
    "null", "{}", "{\"event\":\"bad_event\"}", "{\"event\":\"item_start\",\"item\":{\"type\":\"message\",\"message\":{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"hi\"}]}}}",
    "{\"event\":\"block_start\",\"block_type\":\"text\"}", "{\"event\":\"finish\"}",
    "{\"event\":\"usage\"}", "{\"event\":\"error\"}",
  ]
  for s in invalid {
    match @lux.LucentStreamEvent::from_json(@json.parse(s)) {
      Ok(_) => fail("expected Err for input: \{s}")
      Err(_) => ()
    }
  }
}

///|
test "@lux.LucentError from_json - malformed inputs reject" {
  let invalid : Array[String] = [
    "42", "{\"message\":\"bad\"}", "{\"kind\":\"invalid_request\"}",
  ]
  for s in invalid {
    match @lux.LucentError::from_json(@json.parse(s)) {
      Ok(_) => fail("expected Err for input: \{s}")
      Err(_) => ()
    }
  }
}

///|
test "@lux.LucentRole from_json - malformed inputs reject" {
  let invalid : Array[String] = ["42"]
  for s in invalid {
    match @lux.LucentRole::from_json(@json.parse(s)) {
      Ok(_) => fail("expected Err for input: \{s}")
      Err(_) => ()
    }
  }
}

///|
test "@lux.LucentUsage from_json - malformed inputs reject" {
  let invalid : Array[String] = [
    "null", "{\"completion_tokens\":5,\"total_tokens\":10}", "{\"prompt_tokens\":\"five\",\"completion_tokens\":5,\"total_tokens\":10}",
    "{\"prompt_tokens\":10,\"completion_tokens\":5}",
  ]
  for s in invalid {
    match @lux.LucentUsage::from_json(@json.parse(s)) {
      Ok(_) => fail("expected Err for input: \{s}")
      Err(_) => ()
    }
  }
}

///|
test "@lux.LucentChoice from_json - malformed inputs reject" {
  let invalid : Array[String] = [
    "null", "{\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"hi\"}]},\"finish_reason\":\"stop\"}",
    "{\"index\":0,\"finish_reason\":\"stop\"}", "{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"hi\"}]}}",
  ]
  for s in invalid {
    match @lux.LucentChoice::from_json(@json.parse(s)) {
      Ok(_) => fail("expected Err for input: \{s}")
      Err(_) => ()
    }
  }
}

///|
test "@lux.LucentResponse from_json - malformed inputs reject" {
  let invalid : Array[String] = [
    "null", "{\"id\":\"x\",\"model\":\"m\",\"choices\":[]}", "{\"schema_version\":\"1.0\",\"model\":\"m\",\"choices\":[]}",
    "{\"schema_version\":\"1.0\",\"id\":\"x\",\"model\":\"m\"}",
  ]
  for s in invalid {
    match @lux.LucentResponse::from_json(@json.parse(s)) {
      Ok(_) => fail("expected Err for input: \{s}")
      Err(_) => ()
    }
  }
}

///|
test "@lux.LucentRequest from_json - malformed inputs reject" {
  let invalid : Array[String] = [
    "null", "{\"schema_version\":\"1.0\",\"conversation\":[],\"options\":{\"stream\":false}}",
    "{\"schema_version\":\"1.0\",\"model\":\"m\",\"conversation\":[]}", "{\"schema_version\":\"1.0\",\"model\":\"m\",\"options\":{\"stream\":false}}",
  ]
  for s in invalid {
    match @lux.LucentRequest::from_json(@json.parse(s)) {
      Ok(_) => fail("expected Err for input: \{s}")
      Err(_) => ()
    }
  }
}

///|
test "@lux.LucentSafetyRating from_json - malformed inputs reject" {
  let invalid : Array[String] = [
    "null", "{\"probability\":\"low\"}", "{\"category\":\"violence\"}",
  ]
  for s in invalid {
    match @lux.LucentSafetyRating::from_json(@json.parse(s)) {
      Ok(_) => fail("expected Err for input: \{s}")
      Err(_) => ()
    }
  }
}

///|
test "@lux.ProviderCapability from_json - malformed inputs reject" {
  let invalid : Array[String] = [
    "null", "{\"provider\":\"openai\",\"capabilities\":{\"tool_calling\":true,\"parallel_tool_calls\":false,\"reasoning\":false,\"multimodal_input\":false,\"structured_output\":false,\"input_modalities\":[\"text\"],\"output_modalities\":[\"text\"]}}",
    "{\"model_pattern\":\"*\",\"capabilities\":{\"tool_calling\":true,\"parallel_tool_calls\":false,\"reasoning\":false,\"multimodal_input\":false,\"structured_output\":false,\"input_modalities\":[\"text\"],\"output_modalities\":[\"text\"]}}",
    "{\"model_pattern\":\"*\",\"provider\":\"openai\"}",
  ]
  for s in invalid {
    match @lux.ProviderCapability::from_json(@json.parse(s)) {
      Ok(_) => fail("expected Err for input: \{s}")
      Err(_) => ()
    }
  }
}

///|
test "@lux.LucentDiscovery from_json - malformed inputs reject" {
  let invalid : Array[String] = [
    "null", "{\"schema_version\":\"1.0\",\"protocol_version\":\"1.0\",\"schema_url\":\"https://x\"}",
  ]
  for s in invalid {
    match @lux.LucentDiscovery::from_json(@json.parse(s)) {
      Ok(_) => fail("expected Err for input: \{s}")
      Err(_) => ()
    }
  }
}

///|
/// === positive-path cases kept standalone (not rejection cases) ===

///|
test "@lux.LucentModality from_json - empty string falls back to Native" {
  // from_json 对 String 调用 from_string；from_string 返回 None 时 Ok(Native(s))
  // 所以空串是合法的，但应产生 Native("")
  match @lux.LucentModality::from_json(@json.parse("\"\"")) {
    Ok(Native(s)) => assert_eq(s, "")
    _ => fail("expected Native")
  }
}
