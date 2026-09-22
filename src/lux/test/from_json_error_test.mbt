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

///|
/// === 第二轮：type / 字段存在但类型错误、缺字段、软失败回退 ===
///
/// 与首轮的区别：首轮覆盖「字段整体缺失 / 文档不是对象」，
/// 本轮覆盖「type 已声明但载荷缺失、载荷类型错误、数组元素非法、
/// 以及 Err(_) => None / Some(_) => Err(...) 的软失败分支」。

///|
test "@lux.LucentContent from_json - payload present but malformed rejects" {
  let invalid : Array[String] = [
    "{\"type\":\"tool_result\",\"tool_result\":123}", "{\"type\":\"thinking\",\"thinking\":123}",
    "{\"type\":\"image\",\"image\":123}", "{\"type\":\"audio\",\"audio\":123}", "{\"type\":\"audio\"}",
    "{\"type\":\"video\",\"video\":123}", "{\"type\":\"video\"}", "{\"type\":\"file\",\"file\":123}",
    "{\"type\":\"file\"}",
  ]
  for s in invalid {
    match @lux.LucentContent::from_json(@json.parse(s)) {
      Ok(_) => fail("expected Err for input: \{s}")
      Err(_) => ()
    }
  }
}

///|
test "@lux.LucentContent from_json - invalid annotations fall back to absent" {
  // annotations 数组中存在无法解析的条目时 Text 仍解析成功，annotations 退化为 None
  match
    @lux.LucentContent::from_json(
      @json.parse("{\"type\":\"text\",\"text\":\"hi\",\"annotations\":[42]}"),
    ) {
    Ok(Text(t, None)) => assert_eq(t, "hi")
    Ok(_) => fail("expected annotations to fall back to None")
    Err(e) => fail("expected Ok for text with invalid annotations: \{e}")
  }
}

///|
test "@lux.LucentContent from_json - native without payload defaults to null" {
  match
    @lux.LucentContent::from_json(
      @json.parse("{\"type\":\"native\",\"native_tag\":\"x\"}"),
    ) {
    Ok(Native(tag, payload)) => {
      assert_eq(tag, "x")
      assert_eq(payload.stringify(), "null")
    }
    Ok(_) => fail("expected Native content")
    Err(e) => fail("expected Ok for native without payload: \{e}")
  }
}

///|
test "@lux.LucentMessage from_json - invalid role, reasoning and content reject" {
  let invalid : Array[String] = [
    "{\"role\":123,\"content\":[]}", "{\"role\":\"user\",\"content\":[],\"reasoning\":123}",
    "{\"role\":\"user\",\"content\":[{\"type\":\"bogus\"}]}",
  ]
  for s in invalid {
    match @lux.LucentMessage::from_json(@json.parse(s)) {
      Ok(_) => fail("expected Err for input: \{s}")
      Err(_) => ()
    }
  }
}

///|
test "@lux.LucentConversationItem from_json - payload present but malformed rejects" {
  let invalid : Array[String] = [
    "{\"type\":42}", "{\"type\":\"message\",\"message\":123}", "{\"type\":\"tool_call\",\"tool_call\":123}",
    "{\"type\":\"tool_result\",\"tool_result\":123}", "{\"type\":\"tool_result\"}",
    "{\"type\":\"reasoning\",\"reasoning\":123}", "{\"type\":\"agent_action\",\"agent_action\":123}",
  ]
  for s in invalid {
    match @lux.LucentConversationItem::from_json(@json.parse(s)) {
      Ok(_) => fail("expected Err for input: \{s}")
      Err(_) => ()
    }
  }
}

///|
test "@lux.LucentStreamEvent from_json - missing per-event payload keys reject" {
  let invalid : Array[String] = [
    "{\"event\":\"conversation_start\"}", "{\"event\":\"item_start\",\"index\":0}",
    "{\"event\":\"block_start\",\"index\":0}", "{\"event\":\"block_delta\",\"index\":0}",
    "{\"event\":\"finish\"}", "{\"event\":\"usage\"}", "{\"event\":\"error\"}", "{\"event\":\"annotations\",\"index\":0}",
  ]
  for s in invalid {
    match @lux.LucentStreamEvent::from_json(@json.parse(s)) {
      Ok(_) => fail("expected Err for input: \{s}")
      Err(_) => ()
    }
  }
}

///|
test "@lux.LucentStreamEvent from_json - invalid per-event payloads reject" {
  let invalid : Array[String] = [
    "{\"event\":\"conversation_start\",\"meta\":123}", "{\"event\":\"item_start\",\"index\":0,\"item\":123}",
    "{\"event\":\"block_start\",\"index\":0,\"block_type\":{\"type\":\"tool_call\"}}",
    "{\"event\":\"block_delta\",\"delta\":{\"type\":\"text\",\"text\":\"x\"}}", "{\"event\":\"block_delta\",\"index\":0,\"delta\":123}",
    "{\"event\":\"block_end\"}", "{\"event\":\"item_end\"}", "{\"event\":\"block_discard\"}",
    "{\"event\":\"annotations\"}", "{\"event\":\"annotations\",\"index\":0,\"annotations\":[42]}",
    "{\"event\":\"annotations\",\"index\":0,\"annotations\":42}", "{\"event\":\"finish\",\"finish_reason\":123}",
    "{\"event\":\"usage\",\"usage\":123}", "{\"event\":\"error\",\"error\":123}",
    "{\"event\":42}",
  ]
  for s in invalid {
    match @lux.LucentStreamEvent::from_json(@json.parse(s)) {
      Ok(_) => fail("expected Err for input: \{s}")
      Err(_) => ()
    }
  }
}

///|
test "@lux.ProviderCapability from_json - invalid capabilities reject, extra_params parsed" {
  let caps = "\"tool_calling\":\"full\",\"parallel_tool_calls\":\"none\",\"reasoning\":\"full\"," +
    "\"multimodal_input\":\"full\",\"structured_output\":\"full\"," +
    "\"input_modalities\":[\"text\"],\"output_modalities\":[\"text\"]"
  let invalid : Array[String] = [
    "{\"model_pattern\":\"*\",\"provider\":\"openai\",\"capabilities\":123}",
  ]
  for s in invalid {
    match @lux.ProviderCapability::from_json(@json.parse(s)) {
      Ok(_) => fail("expected Err for input: \{s}")
      Err(_) => ()
    }
  }
  match
    @lux.ProviderCapability::from_json(
      @json.parse(
        "{\"model_pattern\":\"*\",\"provider\":\"openai\",\"capabilities\":{\{caps}},\"extra_params\":{\"k\":\"v\"}}",
      ),
    ) {
    Ok(pc) =>
      match pc.extra_params {
        Some(m) => assert_eq(m.length(), 1)
        None => fail("expected extra_params to be parsed")
      }
    Err(e) => fail("expected Ok for valid capability: \{e}")
  }
}

///|
test "@lux.LucentDiscovery from_json - invalid fields reject" {
  let invalid : Array[String] = [
    "{\"schema_version\":42,\"protocol_version\":\"1.0\",\"schema_url\":\"https://x\",\"providers\":[]}",
    "{\"schema_version\":\"1.0\",\"protocol_version\":42,\"schema_url\":\"https://x\",\"providers\":[]}",
    "{\"schema_version\":\"1.0\",\"protocol_version\":\"1.0\",\"schema_url\":42,\"providers\":[]}",
    "{\"schema_version\":\"1.0\",\"protocol_version\":\"1.0\",\"schema_url\":\"https://x\",\"providers\":42}",
    "{\"schema_version\":\"1.0\",\"protocol_version\":\"1.0\",\"schema_url\":\"https://x\",\"providers\":[42]}",
  ]
  for s in invalid {
    match @lux.LucentDiscovery::from_json(@json.parse(s)) {
      Ok(_) => fail("expected Err for input: \{s}")
      Err(_) => ()
    }
  }
}

///|
test "@lux.LucentUsage from_json - invalid token fields reject" {
  let invalid : Array[String] = [
    "{\"prompt_tokens\":10,\"completion_tokens\":\"five\",\"total_tokens\":15}",
    "{\"prompt_tokens\":10,\"completion_tokens\":5,\"total_tokens\":\"x\"}",
  ]
  for s in invalid {
    match @lux.LucentUsage::from_json(@json.parse(s)) {
      Ok(_) => fail("expected Err for input: \{s}")
      Err(_) => ()
    }
  }
}

///|
test "@lux.LucentChoice from_json - invalid message and finish_reason reject" {
  let invalid : Array[String] = [
    "{\"index\":0,\"message\":123,\"finish_reason\":\"stop\"}", "{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":[]},\"finish_reason\":123}",
  ]
  for s in invalid {
    match @lux.LucentChoice::from_json(@json.parse(s)) {
      Ok(_) => fail("expected Err for input: \{s}")
      Err(_) => ()
    }
  }
}

///|
test "@lux.LucentChoice from_json - invalid safety ratings fall back to absent" {
  match
    @lux.LucentChoice::from_json(
      @json.parse(
        "{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":[]},\"finish_reason\":\"stop\",\"safety_ratings\":[42]}",
      ),
    ) {
    Ok(c) =>
      match c.safety_ratings {
        Some(_) => fail("expected safety_ratings to fall back to None")
        None => ()
      }
    Err(e) => fail("expected Ok for choice with invalid safety ratings: \{e}")
  }
}

///|
test "@lux.LucentResponse from_json - invalid required fields reject" {
  let invalid : Array[String] = [
    "{\"schema_version\":\"1.0\",\"id\":\"x\",\"model\":42,\"choices\":[]}", "{\"schema_version\":\"1.0\",\"id\":\"x\",\"model\":\"m\",\"choices\":42}",
    "{\"schema_version\":\"1.0\",\"id\":\"x\",\"model\":\"m\",\"choices\":[42]}",
  ]
  for s in invalid {
    match @lux.LucentResponse::from_json(@json.parse(s)) {
      Ok(_) => fail("expected Err for input: \{s}")
      Err(_) => ()
    }
  }
}

///|
test "@lux.LucentResponse from_json - invalid usage and provider payload soft-fail" {
  match
    @lux.LucentResponse::from_json(
      @json.parse(
        "{\"schema_version\":\"1.0\",\"id\":\"x\",\"model\":\"m\",\"choices\":[],\"usage\":123}",
      ),
    ) {
    Ok(r) =>
      match r.usage {
        Some(_) => fail("expected usage to fall back to None")
        None => ()
      }
    Err(e) => fail("expected Ok for response with invalid usage: \{e}")
  }
  match
    @lux.LucentResponse::from_json(
      @json.parse(
        "{\"schema_version\":\"1.0\",\"id\":\"x\",\"model\":\"m\",\"choices\":[],\"provider_payload\":{\"k\":1}}",
      ),
    ) {
    Ok(r) =>
      match r.provider_payload {
        Some(p) => assert_eq(p.stringify(), "{\"k\":1}")
        None => fail("expected provider_payload to be kept")
      }
    Err(e) => fail("expected Ok for response with provider_payload: \{e}")
  }
}

///|
test "@lux.LucentBlockType from_json - malformed tool_call objects reject" {
  let invalid : Array[String] = [
    "{\"type\":42}", "{\"type\":\"tool_call\",\"id\":123,\"name\":\"n\"}", "{\"type\":\"tool_call\",\"id\":\"x\",\"name\":123}",
  ]
  for s in invalid {
    match @lux.LucentBlockType::from_json(@json.parse(s)) {
      Ok(_) => fail("expected Err for input: \{s}")
      Err(_) => ()
    }
  }
}

///|
test "@lux.LucentBlockType from_json - refusal and media strings accepted" {
  match @lux.LucentBlockType::from_json(@json.parse("\"refusal\"")) {
    Ok(Refusal) => ()
    Ok(_) => fail("expected Refusal")
    Err(e) => fail("expected Ok for refusal block type: \{e}")
  }
  match @lux.LucentBlockType::from_json(@json.parse("\"image\"")) {
    Ok(Image) => ()
    Ok(_) => fail("expected Image")
    Err(e) => fail("expected Ok for image block type: \{e}")
  }
  match @lux.LucentBlockType::from_json(@json.parse("\"audio\"")) {
    Ok(Audio) => ()
    Ok(_) => fail("expected Audio")
    Err(e) => fail("expected Ok for audio block type: \{e}")
  }
  match @lux.LucentBlockType::from_json(@json.parse("\"video\"")) {
    Ok(Video) => ()
    Ok(_) => fail("expected Video")
    Err(e) => fail("expected Ok for video block type: \{e}")
  }
}

///|
test "@lux.LucentBlockDelta from_json - non-string type rejects, native payload parsed" {
  match @lux.LucentBlockDelta::from_json(@json.parse("{\"type\":42}")) {
    Ok(_) => fail("expected Err for non-string type")
    Err(_) => ()
  }
  match
    @lux.LucentBlockDelta::from_json(
      @json.parse("{\"type\":\"native\",\"native_tag\":\"x\"}"),
    ) {
    Ok(NativeDelta(tag, payload)) => {
      assert_eq(tag, "x")
      assert_eq(payload.stringify(), "null")
    }
    Ok(_) => fail("expected NativeDelta")
    Err(e) => fail("expected Ok for native delta without payload: \{e}")
  }
  match
    @lux.LucentBlockDelta::from_json(
      @json.parse(
        "{\"type\":\"native\",\"native_tag\":\"x\",\"native_payload\":{\"a\":1}}",
      ),
    ) {
    Ok(NativeDelta(tag, payload)) => {
      assert_eq(tag, "x")
      assert_eq(payload.stringify(), "{\"a\":1}")
    }
    Ok(_) => fail("expected NativeDelta")
    Err(e) => fail("expected Ok for native delta with payload: \{e}")
  }
}

///|
test "@lux.LucentFinishReason from_json - non-string rejects" {
  for s in ["42", "null"] {
    match @lux.LucentFinishReason::from_json(@json.parse(s)) {
      Ok(_) => fail("expected Err for input: \{s}")
      Err(_) => ()
    }
  }
}

///|
test "@lux.LucentErrorKind from_json - non-string rejects" {
  for s in ["42", "null"] {
    match @lux.LucentErrorKind::from_json(@json.parse(s)) {
      Ok(_) => fail("expected Err for input: \{s}")
      Err(_) => ()
    }
  }
}

///|
test "@lux.LucentError from_json - non-string kind rejects" {
  match
    @lux.LucentError::from_json(@json.parse("{\"kind\":123,\"message\":\"m\"}")) {
    Ok(_) => fail("expected Err for non-string kind")
    Err(_) => ()
  }
}

///|
test "@lux.LucentConversationMeta from_json - non-object rejects" {
  match @lux.LucentConversationMeta::from_json(@json.parse("123")) {
    Ok(_) => fail("expected Err for non-object meta")
    Err(_) => ()
  }
}

///|
test "@lux.LucentMultimedia from_json - invalid source rejects" {
  match
    @lux.LucentMultimedia::from_json(
      @json.parse("{\"media_type\":\"image/png\",\"source\":42}"),
    ) {
    Ok(_) => fail("expected Err for non-object source")
    Err(_) => ()
  }
}

///|
test "@lux.LucentAnnotationKind from_json - web_search_citation accepted, unknown falls back to Native" {
  match
    @lux.LucentAnnotationKind::from_json(@json.parse("\"web_search_citation\"")) {
    Ok(WebSearchCitation) => ()
    Ok(_) => fail("expected WebSearchCitation")
    Err(e) => fail("expected Ok for web_search_citation: \{e}")
  }
  match @lux.LucentAnnotationKind::from_json(@json.parse("\"custom\"")) {
    Ok(Native(k)) => assert_eq(k, "custom")
    Ok(_) => fail("expected Native")
    Err(e) => fail("expected Ok for unknown annotation kind: \{e}")
  }
  for s in ["42", "null"] {
    match @lux.LucentAnnotationKind::from_json(@json.parse(s)) {
      Ok(_) => fail("expected Err for input: \{s}")
      Err(_) => ()
    }
  }
}

///|
test "@lux.LucentAnnotation from_json - non-string kind rejects" {
  match @lux.LucentAnnotation::from_json(@json.parse("{\"kind\":42}")) {
    Ok(_) => fail("expected Err for non-string kind")
    Err(_) => ()
  }
}

///|
test "@lux.SupportLevel from_json - unknown level and wrong type reject" {
  match @lux.SupportLevel::from_json(@json.parse("\"bogus\"")) {
    Ok(_) => fail("expected Err for unknown support level")
    Err(_) => ()
  }
  for s in ["42", "null", "true"] {
    match @lux.SupportLevel::from_json(@json.parse(s)) {
      Ok(_) => fail("expected Err for input: \{s}")
      Err(_) => ()
    }
  }
}

///|
test "@lux.LucentReasoningEffort from_json - all documented levels accepted" {
  match @lux.LucentReasoningEffort::from_json(@json.parse("\"low\"")) {
    Ok(Low) => ()
    Ok(_) => fail("expected Low")
    Err(e) => fail("expected Ok for low: \{e}")
  }
  match @lux.LucentReasoningEffort::from_json(@json.parse("\"medium\"")) {
    Ok(Medium) => ()
    Ok(_) => fail("expected Medium")
    Err(e) => fail("expected Ok for medium: \{e}")
  }
  match @lux.LucentReasoningEffort::from_json(@json.parse("\"high\"")) {
    Ok(High) => ()
    Ok(_) => fail("expected High")
    Err(e) => fail("expected Ok for high: \{e}")
  }
  match @lux.LucentReasoningEffort::from_json(@json.parse("\"xhigh\"")) {
    Ok(XHigh) => ()
    Ok(_) => fail("expected XHigh")
    Err(e) => fail("expected Ok for xhigh: \{e}")
  }
}

///|
test "@lux.LucentReasoningSummary from_json - all documented levels accepted" {
  match @lux.LucentReasoningSummary::from_json(@json.parse("\"auto\"")) {
    Ok(Auto) => ()
    Ok(_) => fail("expected Auto")
    Err(e) => fail("expected Ok for auto: \{e}")
  }
  match @lux.LucentReasoningSummary::from_json(@json.parse("\"concise\"")) {
    Ok(Concise) => ()
    Ok(_) => fail("expected Concise")
    Err(e) => fail("expected Ok for concise: \{e}")
  }
  match @lux.LucentReasoningSummary::from_json(@json.parse("\"detailed\"")) {
    Ok(Detailed) => ()
    Ok(_) => fail("expected Detailed")
    Err(e) => fail("expected Ok for detailed: \{e}")
  }
}

///|
test "@lux.LucentReasoningConfig from_json - unparseable effort and summary fall back to absent" {
  match
    @lux.LucentReasoningConfig::from_json(
      @json.parse("{\"enabled\":true,\"effort\":\"bogus\"}"),
    ) {
    Ok(c) =>
      match c.effort {
        Some(_) => fail("expected effort to fall back to None")
        None => ()
      }
    Err(e) => fail("expected Ok for reasoning config with invalid effort: \{e}")
  }
  match
    @lux.LucentReasoningConfig::from_json(
      @json.parse("{\"enabled\":true,\"summary\":\"bogus\"}"),
    ) {
    Ok(c) =>
      match c.summary {
        Some(_) => fail("expected summary to fall back to None")
        None => ()
      }
    Err(e) =>
      fail("expected Ok for reasoning config with invalid summary: \{e}")
  }
}

///|
test "@lux.LucentOptions from_json - store false and non-string stop entries" {
  match
    @lux.LucentOptions::from_json(
      @json.parse("{\"stream\":false,\"store\":false}"),
    ) {
    Ok(o) =>
      match o.store {
        Some(false) => ()
        _ => fail("expected store Some(false)")
      }
    Err(e) => fail("expected Ok for options with store false: \{e}")
  }
  match
    @lux.LucentOptions::from_json(
      @json.parse("{\"stream\":false,\"stop\":[\"a\",1]}"),
    ) {
    Ok(o) =>
      match o.stop {
        Some(_) => fail("expected stop to fall back to None")
        None => ()
      }
    Err(e) => fail("expected Ok for options with non-string stop: \{e}")
  }
}

///|
test "@lux.LucentOptions from_json - invalid structured_output and extras" {
  match
    @lux.LucentOptions::from_json(
      @json.parse("{\"stream\":false,\"structured_output\":\"bogus\"}"),
    ) {
    Ok(o) =>
      match o.structured_output {
        Some(_) => fail("expected structured_output to fall back to None")
        None => ()
      }
    Err(e) =>
      fail("expected Ok for options with invalid structured_output: \{e}")
  }
  match
    @lux.LucentOptions::from_json(
      @json.parse("{\"stream\":false,\"extras\":{\"k\":1}}"),
    ) {
    Ok(o) =>
      match o.extras {
        Some(m) => assert_eq(m.length(), 1)
        None => fail("expected extras to be parsed")
      }
    Err(e) => fail("expected Ok for options with extras: \{e}")
  }
}

///|
test "@lux.LucentReasoningConfig from_json - effort and summary accepted" {
  match
    @lux.LucentReasoningConfig::from_json(
      @json.parse(
        "{\"enabled\":true,\"effort\":\"high\",\"summary\":\"detailed\"}",
      ),
    ) {
    Ok(c) => {
      assert_eq(c.enabled, true)
      match c.effort {
        Some(High) => ()
        _ => fail("expected effort High")
      }
      match c.summary {
        Some(Detailed) => ()
        _ => fail("expected summary Detailed")
      }
    }
    Err(e) => fail("expected Ok for reasoning config: \{e}")
  }
}

///|
test "@lux.LucentCapabilities from_json - invalid support levels and modalities reject" {
  let invalid : Array[String] = [
    "{\"tool_calling\":\"full\",\"parallel_tool_calls\":\"bogus\",\"reasoning\":\"full\",\"multimodal_input\":\"full\",\"structured_output\":\"full\",\"input_modalities\":[\"text\"],\"output_modalities\":[\"text\"]}",
    "{\"tool_calling\":\"full\",\"parallel_tool_calls\":\"none\",\"reasoning\":\"bogus\",\"multimodal_input\":\"full\",\"structured_output\":\"full\",\"input_modalities\":[\"text\"],\"output_modalities\":[\"text\"]}",
    "{\"tool_calling\":\"full\",\"parallel_tool_calls\":\"none\",\"reasoning\":\"full\",\"multimodal_input\":\"bogus\",\"structured_output\":\"full\",\"input_modalities\":[\"text\"],\"output_modalities\":[\"text\"]}",
    "{\"tool_calling\":\"full\",\"parallel_tool_calls\":\"none\",\"reasoning\":\"full\",\"multimodal_input\":\"full\",\"structured_output\":\"bogus\",\"input_modalities\":[\"text\"],\"output_modalities\":[\"text\"]}",
    "{\"tool_calling\":\"bogus\",\"parallel_tool_calls\":\"none\",\"reasoning\":\"full\",\"multimodal_input\":\"full\",\"structured_output\":\"full\",\"input_modalities\":[\"text\"],\"output_modalities\":[\"text\"]}",
    "{\"tool_calling\":42,\"parallel_tool_calls\":\"none\",\"reasoning\":\"full\",\"multimodal_input\":\"full\",\"structured_output\":\"full\",\"input_modalities\":[\"text\"],\"output_modalities\":[\"text\"]}",
    "{\"tool_calling\":\"full\",\"parallel_tool_calls\":\"none\",\"reasoning\":\"full\",\"multimodal_input\":\"full\",\"structured_output\":\"full\",\"input_modalities\":42,\"output_modalities\":[\"text\"]}",
    "{\"tool_calling\":\"full\",\"parallel_tool_calls\":\"none\",\"reasoning\":\"full\",\"multimodal_input\":\"full\",\"structured_output\":\"full\",\"input_modalities\":[\"text\"],\"output_modalities\":42}",
    "{\"tool_calling\":\"full\",\"parallel_tool_calls\":\"none\",\"reasoning\":\"full\",\"multimodal_input\":\"full\",\"structured_output\":\"full\",\"input_modalities\":[\"text\"],\"output_modalities\":[42]}",
  ]
  for s in invalid {
    match @lux.LucentCapabilities::from_json(@json.parse(s)) {
      Ok(_) => fail("expected Err for input: \{s}")
      Err(_) => ()
    }
  }
}

///|
test "@lux.LucentRequest from_json - optional fields soft-fail to absent" {
  let doc = "{\"schema_version\":\"1.0\",\"model\":\"m\",\"conversation\":[]," +
    "\"options\":{\"stream\":false}," +
    "\"tools\":[42]," +
    "\"tool_choice\":\"bogus\"," +
    "\"capabilities\":123," +
    "\"reasoning\":123," +
    "\"instructions\":[{\"type\":\"bogus\"}]," +
    "\"metadata\":{\"a\":\"x\",\"b\":42}}"
  match @lux.LucentRequest::from_json(@json.parse(doc)) {
    Ok(r) => {
      match r.tools {
        Some(_) => fail("expected tools to fall back to None")
        None => ()
      }
      match r.tool_choice {
        Some(_) => fail("expected tool_choice to fall back to None")
        None => ()
      }
      match r.capabilities {
        Some(_) => fail("expected capabilities to fall back to None")
        None => ()
      }
      match r.reasoning {
        Some(_) => fail("expected reasoning to fall back to None")
        None => ()
      }
      match r.instructions {
        Some(_) => fail("expected instructions to fall back to None")
        None => ()
      }
      match r.metadata {
        Some(m) =>
          match m.get("a") {
            Some(v) => assert_eq(v, "x")
            None => fail("expected metadata entry a")
          }
        None => fail("expected metadata to keep string entries")
      }
    }
    Err(e) => fail("expected Ok for request with soft-failing options: \{e}")
  }
}

///|
test "@lux.LucentRequest from_json - invalid conversation and options reject" {
  let invalid : Array[String] = [
    "{\"schema_version\":\"1.0\",\"model\":\"m\",\"conversation\":42,\"options\":{\"stream\":false}}",
    "{\"schema_version\":\"1.0\",\"model\":\"m\",\"conversation\":[42],\"options\":{\"stream\":false}}",
    "{\"schema_version\":\"1.0\",\"model\":\"m\",\"conversation\":[],\"options\":{}}",
    "{\"schema_version\":\"1.0\",\"model\":\"m\",\"conversation\":[],\"options\":42}",
  ]
  for s in invalid {
    match @lux.LucentRequest::from_json(@json.parse(s)) {
      Ok(_) => fail("expected Err for input: \{s}")
      Err(_) => ()
    }
  }
}

///|
test "@lux.ConversationSnapshot from_json - malformed inputs reject" {
  let request = "\"schema_version\":\"1.0\",\"model\":\"m\",\"conversation\":[]," +
    "\"options\":{\"stream\":false}"
  let invalid : Array[String] = [
    "42",
    "{\"response_id\":42,\"request\":{\{request}}}",
    "{\"response_id\":\"r\",\"request\":42}",
  ]
  for s in invalid {
    match @lux.ConversationSnapshot::from_json(@json.parse(s)) {
      Ok(_) => fail("expected Err for input: \{s}")
      Err(_) => ()
    }
  }
  match
    @lux.ConversationSnapshot::from_json(
      @json.parse(
        "{\"response_id\":\"r\",\"request\":{\{request}},\"response_text\":\"hi\"}",
      ),
    ) {
    Ok(s) =>
      match s.response_text {
        Some(t) => assert_eq(t, "hi")
        None => fail("expected response_text")
      }
    Err(e) => fail("expected Ok for valid snapshot: \{e}")
  }
}

///|
test "@lux.LucentTool from_json - kind fallbacks" {
  match
    @lux.LucentTool::from_json(
      @json.parse(
        "{\"name\":\"x\",\"parameters\":{\"type\":\"object\"},\"kind\":\"apply_patch\"}",
      ),
    ) {
    Ok(t) => assert_eq(t.kind, ApplyPatch)
    Err(e) => fail("expected Ok for apply_patch tool: \{e}")
  }
  match
    @lux.LucentTool::from_json(
      @json.parse(
        "{\"name\":\"x\",\"parameters\":{\"type\":\"object\"},\"kind\":\"mcp\"}",
      ),
    ) {
    Ok(t) => assert_eq(t.kind, MCP)
    Err(e) => fail("expected Ok for mcp tool: \{e}")
  }
  match
    @lux.LucentTool::from_json(
      @json.parse("{\"name\":\"x\",\"parameters\":{\"type\":\"object\"}}"),
    ) {
    Ok(t) => assert_eq(t.kind, Function)
    Err(e) => fail("expected Ok for tool without kind: \{e}")
  }
}

///|
test "@lux.LucentToolChoice from_json - non-string type in object rejects" {
  match @lux.LucentToolChoice::from_json(@json.parse("{\"type\":42}")) {
    Ok(_) => fail("expected Err for non-string type")
    Err(_) => ()
  }
}

///|
test "@lux.LucentStructuredOutput from_json - non-string or missing type in object rejects" {
  let invalid : Array[String] = ["{\"type\":42}", "{}"]
  for s in invalid {
    match @lux.LucentStructuredOutput::from_json(@json.parse(s)) {
      Ok(_) => fail("expected Err for input: \{s}")
      Err(_) => ()
    }
  }
}
