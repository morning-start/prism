///|
/// Lux IR from_json 错误路径测试
///
/// 目标：覆盖 deserialize.mbt 中大量未覆盖的 Err(e) 分支和类型不匹配分支。
///
/// 模式：构造畸形 JSON → from_json() → 断言 Err

///|

///|
/// === LucentContent from_json 错误 ===

///|
test "LucentContent from_json - non-object rejects" {
  match LucentContent::from_json(@json.parse("123")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentContent from_json - missing type rejects" {
  match LucentContent::from_json(@json.parse("{}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentContent from_json - type field not string rejects" {
  match LucentContent::from_json(@json.parse("{\"type\":42}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentContent from_json - unknown type rejects" {
  match
    LucentContent::from_json(@json.parse("{\"type\":\"unknown_content_type\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentContent from_json - text missing text field rejects" {
  match LucentContent::from_json(@json.parse("{\"type\":\"text\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentContent from_json - text with non-string text field rejects" {
  match
    LucentContent::from_json(@json.parse("{\"type\":\"text\",\"text\":123}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentContent from_json - tool_use missing tool_use field rejects" {
  match LucentContent::from_json(@json.parse("{\"type\":\"tool_use\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentContent from_json - tool_use with invalid tool_use object rejects" {
  match
    LucentContent::from_json(
      @json.parse("{\"type\":\"tool_use\",\"tool_use\":123}"),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentContent from_json - tool_result missing tool_result field rejects" {
  match LucentContent::from_json(@json.parse("{\"type\":\"tool_result\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentContent from_json - thinking missing thinking field rejects" {
  match LucentContent::from_json(@json.parse("{\"type\":\"thinking\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentContent from_json - refusal missing refusal field rejects" {
  match LucentContent::from_json(@json.parse("{\"type\":\"refusal\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentContent from_json - image missing image field rejects" {
  match LucentContent::from_json(@json.parse("{\"type\":\"image\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentContent from_json - native missing native_tag rejects" {
  match LucentContent::from_json(@json.parse("{\"type\":\"native\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
/// === LucentToolUse from_json 错误 ===
test "LucentToolUse from_json - non-object rejects" {
  match LucentToolUse::from_json(@json.parse("null")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentToolUse from_json - missing id rejects" {
  match
    LucentToolUse::from_json(
      @json.parse("{\"name\":\"x\",\"arguments\":\"{}\"}"),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentToolUse from_json - missing name rejects" {
  match
    LucentToolUse::from_json(@json.parse("{\"id\":\"x\",\"arguments\":\"{}\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentToolUse from_json - missing arguments rejects" {
  match
    LucentToolUse::from_json(
      @json.parse("{\"id\":\"x\",\"name\":\"get_weather\"}"),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentToolUse from_json - id as non-string rejects" {
  match
    LucentToolUse::from_json(
      @json.parse("{\"id\":123,\"name\":\"get_weather\",\"arguments\":\"{}\"}"),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
/// === LucentToolResult from_json 错误 ===
test "LucentToolResult from_json - non-object rejects" {
  match LucentToolResult::from_json(@json.parse("true")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentToolResult from_json - missing tool_use_id rejects" {
  match
    LucentToolResult::from_json(
      @json.parse("{\"content\":[],\"is_error\":false}"),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentToolResult from_json - missing content rejects" {
  match
    LucentToolResult::from_json(
      @json.parse("{\"tool_use_id\":\"x\",\"is_error\":false}"),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentToolResult from_json - content not an array rejects" {
  match
    LucentToolResult::from_json(
      @json.parse(
        "{\"tool_use_id\":\"x\",\"content\":\"not-array\",\"is_error\":false}",
      ),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentToolResult from_json - missing is_error rejects" {
  match
    LucentToolResult::from_json(
      @json.parse("{\"tool_use_id\":\"x\",\"content\":[]}"),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentToolResult from_json - is_error as non-boolean rejects" {
  match
    LucentToolResult::from_json(
      @json.parse(
        "{\"tool_use_id\":\"x\",\"content\":[{\"type\":\"text\",\"text\":\"hi\"}],\"is_error\":42}",
      ),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
/// === LucentMessage from_json 错误 ===
test "LucentMessage from_json - non-object rejects" {
  match LucentMessage::from_json(@json.parse("\"hello\"")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentMessage from_json - missing role rejects" {
  match
    LucentMessage::from_json(
      @json.parse("{\"content\":[{\"type\":\"text\",\"text\":\"hi\"}]}"),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentMessage from_json - missing content rejects" {
  match LucentMessage::from_json(@json.parse("{\"role\":\"user\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
/// === LucentConversationItem from_json 错误 ===
test "LucentConversationItem from_json - non-object rejects" {
  match LucentConversationItem::from_json(@json.parse("null")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentConversationItem from_json - missing type rejects" {
  match LucentConversationItem::from_json(@json.parse("{}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentConversationItem from_json - unknown type rejects" {
  match
    LucentConversationItem::from_json(
      @json.parse("{\"type\":\"unknown_item\"}"),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentConversationItem from_json - message missing message field rejects" {
  match
    LucentConversationItem::from_json(@json.parse("{\"type\":\"message\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentConversationItem from_json - tool_call missing tool_call field rejects" {
  match
    LucentConversationItem::from_json(@json.parse("{\"type\":\"tool_call\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentConversationItem from_json - reasoning missing reasoning field rejects" {
  match
    LucentConversationItem::from_json(@json.parse("{\"type\":\"reasoning\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentConversationItem from_json - agent_action missing agent_action field rejects" {
  match
    LucentConversationItem::from_json(
      @json.parse("{\"type\":\"agent_action\"}"),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
/// === LucentTool from_json 错误 ===
test "LucentTool from_json - non-object rejects" {
  match LucentTool::from_json(@json.parse("42")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentTool from_json - missing name rejects" {
  match
    LucentTool::from_json(@json.parse("{\"parameters\":{\"type\":\"object\"}}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentTool from_json - missing parameters rejects" {
  match LucentTool::from_json(@json.parse("{\"name\":\"x\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
/// === LucentToolChoice from_json 错误 ===
test "LucentToolChoice from_json - unknown string value rejects" {
  match LucentToolChoice::from_json(@json.parse("\"bad\"")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentToolChoice from_json - non-string non-object rejects" {
  match LucentToolChoice::from_json(@json.parse("null")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentToolChoice from_json - specific_tool missing name rejects" {
  match
    LucentToolChoice::from_json(@json.parse("{\"type\":\"specific_tool\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentToolChoice from_json - specific_tool name not string rejects" {
  match
    LucentToolChoice::from_json(
      @json.parse("{\"type\":\"specific_tool\",\"name\":42}"),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentToolChoice from_json - object missing type rejects" {
  match LucentToolChoice::from_json(@json.parse("{\"name\":\"x\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
/// === LucentStructuredOutput from_json 错误 ===
test "LucentStructuredOutput from_json - unknown string rejects" {
  match LucentStructuredOutput::from_json(@json.parse("\"unknown\"")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentStructuredOutput from_json - non-string non-object rejects" {
  match LucentStructuredOutput::from_json(@json.parse("null")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentStructuredOutput from_json - json_schema missing schema rejects" {
  match
    LucentStructuredOutput::from_json(@json.parse("{\"type\":\"json_schema\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
/// === LucentReasoningEffort from_json 错误 ===
test "LucentReasoningEffort from_json - unknown string rejects" {
  match LucentReasoningEffort::from_json(@json.parse("\"ultra\"")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentReasoningEffort from_json - non-string rejects" {
  match LucentReasoningEffort::from_json(@json.parse("42")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
/// === LucentReasoningSummary from_json 错误 ===
test "LucentReasoningSummary from_json - unknown string rejects" {
  match LucentReasoningSummary::from_json(@json.parse("\"verbose\"")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentReasoningSummary from_json - non-string rejects" {
  match LucentReasoningSummary::from_json(@json.parse("null")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
/// === LucentOptions from_json 错误 ===
test "LucentOptions from_json - non-object rejects" {
  match LucentOptions::from_json(@json.parse("\"bad\"")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentOptions from_json - missing stream rejects" {
  match LucentOptions::from_json(@json.parse("{}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentOptions from_json - stream as non-boolean rejects" {
  match LucentOptions::from_json(@json.parse("{\"stream\":\"yes\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
/// === LucentReasoningConfig from_json 错误 ===
test "LucentReasoningConfig from_json - non-object rejects" {
  match LucentReasoningConfig::from_json(@json.parse("42")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentReasoningConfig from_json - missing enabled rejects" {
  match LucentReasoningConfig::from_json(@json.parse("{}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentReasoningConfig from_json - enabled as non-boolean rejects" {
  match LucentReasoningConfig::from_json(@json.parse("{\"enabled\":\"yes\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
/// === LucentCapabilities from_json 错误 ===
test "LucentCapabilities from_json - non-object rejects" {
  match LucentCapabilities::from_json(@json.parse("null")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentCapabilities from_json - missing tool_calling rejects" {
  match LucentCapabilities::from_json(@json.parse("{}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentCapabilities from_json - missing input_modalities rejects" {
  let jv = @json.parse(
    "{\"tool_calling\":true,\"parallel_tool_calls\":true,\"reasoning\":true,\"multimodal_input\":true,\"structured_output\":true}",
  )
  match LucentCapabilities::from_json(jv) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
/// === LucentModality from_json 错误 ===
test "LucentModality from_json - non-string rejects" {
  match LucentModality::from_json(@json.parse("42")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentModality from_json - empty string falls back to Native" {
  // from_json 对 String 调用 from_string；from_string 返回 None 时 Ok(Native(s))
  // 所以空串是合法的，但应产生 Native("")
  match LucentModality::from_json(@json.parse("\"\"")) {
    Ok(Native(s)) => assert_eq(s, "")
    _ => fail("expected Native")
  }
}

///|
/// === LucentMediaSource from_json 错误 ===
test "LucentMediaSource from_json - non-object rejects" {
  match LucentMediaSource::from_json(@json.parse("42")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentMediaSource from_json - missing type rejects" {
  match LucentMediaSource::from_json(@json.parse("{}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentMediaSource from_json - unknown type rejects" {
  match
    LucentMediaSource::from_json(@json.parse("{\"type\":\"unknown_type\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentMediaSource from_json - type as non-string rejects" {
  match LucentMediaSource::from_json(@json.parse("{\"type\":42}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
/// === LucentMultimedia from_json 错误 ===
test "LucentMultimedia from_json - non-object rejects" {
  match LucentMultimedia::from_json(@json.parse("null")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentMultimedia from_json - missing media_type rejects" {
  match
    LucentMultimedia::from_json(
      @json.parse("{\"source\":{\"type\":\"url\",\"data\":\"x\"}}"),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentMultimedia from_json - missing source rejects" {
  match
    LucentMultimedia::from_json(@json.parse("{\"media_type\":\"image/png\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
/// === LucentAnnotation from_json 错误 ===
test "LucentAnnotation from_json - non-object rejects" {
  match LucentAnnotation::from_json(@json.parse("42")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentAnnotation from_json - missing kind rejects" {
  match LucentAnnotation::from_json(@json.parse("{}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
/// === LucentThinking from_json 错误 ===
test "LucentThinking from_json - non-object rejects" {
  match LucentThinking::from_json(@json.parse("null")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentThinking from_json - missing text rejects" {
  match LucentThinking::from_json(@json.parse("{\"redacted\":false}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentThinking from_json - missing redacted rejects" {
  match LucentThinking::from_json(@json.parse("{\"text\":\"thinking\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
/// === LucentAgentAction from_json 错误 ===
test "LucentAgentAction from_json - non-object rejects" {
  match LucentAgentAction::from_json(@json.parse("null")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentAgentAction from_json - missing kind rejects" {
  match LucentAgentAction::from_json(@json.parse("{\"id\":\"x\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentAgentAction from_json - missing id rejects" {
  match LucentAgentAction::from_json(@json.parse("{\"kind\":\"tool\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
/// === LucentBlockType from_json 错误 ===
test "LucentBlockType from_json - non-string non-object rejects" {
  match LucentBlockType::from_json(@json.parse("42")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentBlockType from_json - object missing type rejects" {
  match LucentBlockType::from_json(@json.parse("{\"id\":\"x\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentBlockType from_json - tool_call missing id rejects" {
  match LucentBlockType::from_json(@json.parse("{\"type\":\"tool_call\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentBlockType from_json - tool_call missing name rejects" {
  match
    LucentBlockType::from_json(
      @json.parse("{\"type\":\"tool_call\",\"id\":\"x\"}"),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
/// === LucentBlockDelta from_json 错误 ===
test "LucentBlockDelta from_json - non-object rejects" {
  match LucentBlockDelta::from_json(@json.parse("null")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentBlockDelta from_json - missing type rejects" {
  match LucentBlockDelta::from_json(@json.parse("{}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentBlockDelta from_json - unknown delta type rejects" {
  match
    LucentBlockDelta::from_json(@json.parse("{\"type\":\"unknown_delta\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentBlockDelta from_json - text missing text field rejects" {
  match LucentBlockDelta::from_json(@json.parse("{\"type\":\"text\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentBlockDelta from_json - thinking missing text field rejects" {
  match LucentBlockDelta::from_json(@json.parse("{\"type\":\"thinking\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentBlockDelta from_json - signature missing signature field rejects" {
  match LucentBlockDelta::from_json(@json.parse("{\"type\":\"signature\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentBlockDelta from_json - tool_arguments missing arguments field rejects" {
  match
    LucentBlockDelta::from_json(@json.parse("{\"type\":\"tool_arguments\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentBlockDelta from_json - refusal missing text field rejects" {
  match LucentBlockDelta::from_json(@json.parse("{\"type\":\"refusal\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentBlockDelta from_json - native missing native_tag rejects" {
  match LucentBlockDelta::from_json(@json.parse("{\"type\":\"native\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
/// === LucentStreamEvent from_json 错误 ===
test "LucentStreamEvent from_json - non-object rejects" {
  match LucentStreamEvent::from_json(@json.parse("null")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentStreamEvent from_json - missing event rejects" {
  match LucentStreamEvent::from_json(@json.parse("{}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentStreamEvent from_json - unknown event rejects" {
  match LucentStreamEvent::from_json(@json.parse("{\"event\":\"bad_event\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentStreamEvent from_json - item_start missing index rejects" {
  match
    LucentStreamEvent::from_json(
      @json.parse(
        "{\"event\":\"item_start\",\"item\":{\"type\":\"message\",\"message\":{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"hi\"}]}}}",
      ),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentStreamEvent from_json - block_start missing index rejects" {
  match
    LucentStreamEvent::from_json(
      @json.parse("{\"event\":\"block_start\",\"block_type\":\"text\"}"),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentStreamEvent from_json - finish missing finish_reason rejects" {
  match LucentStreamEvent::from_json(@json.parse("{\"event\":\"finish\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentStreamEvent from_json - usage missing usage rejects" {
  match LucentStreamEvent::from_json(@json.parse("{\"event\":\"usage\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentStreamEvent from_json - error missing error field rejects" {
  match LucentStreamEvent::from_json(@json.parse("{\"event\":\"error\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
/// === LucentError from_json 错误 ===
test "LucentError from_json - non-object rejects" {
  match LucentError::from_json(@json.parse("42")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentError from_json - missing kind rejects" {
  match LucentError::from_json(@json.parse("{\"message\":\"bad\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentError from_json - missing message rejects" {
  match LucentError::from_json(@json.parse("{\"kind\":\"invalid_request\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
/// === LucentRole from_json 错误 ===
test "LucentRole from_json - non-string rejects" {
  match LucentRole::from_json(@json.parse("42")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
/// === LucentUsage from_json 错误 ===
test "LucentUsage from_json - non-object rejects" {
  match LucentUsage::from_json(@json.parse("null")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentUsage from_json - missing prompt_tokens rejects" {
  match
    LucentUsage::from_json(
      @json.parse("{\"completion_tokens\":5,\"total_tokens\":10}"),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentUsage from_json - prompt_tokens non-numeric rejects" {
  match
    LucentUsage::from_json(
      @json.parse(
        "{\"prompt_tokens\":\"five\",\"completion_tokens\":5,\"total_tokens\":10}",
      ),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentUsage from_json - missing total_tokens rejects" {
  match
    LucentUsage::from_json(
      @json.parse("{\"prompt_tokens\":10,\"completion_tokens\":5}"),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
/// === LucentChoice from_json 错误 ===
test "LucentChoice from_json - non-object rejects" {
  match LucentChoice::from_json(@json.parse("null")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentChoice from_json - missing index rejects" {
  match
    LucentChoice::from_json(
      @json.parse(
        "{\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"hi\"}]},\"finish_reason\":\"stop\"}",
      ),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentChoice from_json - missing message rejects" {
  match
    LucentChoice::from_json(
      @json.parse("{\"index\":0,\"finish_reason\":\"stop\"}"),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentChoice from_json - missing finish_reason rejects" {
  match
    LucentChoice::from_json(
      @json.parse(
        "{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"hi\"}]}}",
      ),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
/// === LucentResponse from_json 错误 ===
test "LucentResponse from_json - non-object rejects" {
  match LucentResponse::from_json(@json.parse("null")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentResponse from_json - missing schema_version rejects" {
  match
    LucentResponse::from_json(
      @json.parse("{\"id\":\"x\",\"model\":\"m\",\"choices\":[]}"),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentResponse from_json - missing id rejects" {
  match
    LucentResponse::from_json(
      @json.parse("{\"schema_version\":\"1.0\",\"model\":\"m\",\"choices\":[]}"),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentResponse from_json - missing choices rejects" {
  match
    LucentResponse::from_json(
      @json.parse("{\"schema_version\":\"1.0\",\"id\":\"x\",\"model\":\"m\"}"),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
/// === LucentRequest from_json 错误 ===
test "LucentRequest from_json - non-object rejects" {
  match LucentRequest::from_json(@json.parse("null")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentRequest from_json - missing model rejects" {
  match
    LucentRequest::from_json(
      @json.parse(
        "{\"schema_version\":\"1.0\",\"conversation\":[],\"options\":{\"stream\":false}}",
      ),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentRequest from_json - missing options rejects" {
  match
    LucentRequest::from_json(
      @json.parse(
        "{\"schema_version\":\"1.0\",\"model\":\"m\",\"conversation\":[]}",
      ),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentRequest from_json - missing conversation rejects" {
  match
    LucentRequest::from_json(
      @json.parse(
        "{\"schema_version\":\"1.0\",\"model\":\"m\",\"options\":{\"stream\":false}}",
      ),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
/// === LucentSafetyRating from_json 错误 ===
test "LucentSafetyRating from_json - non-object rejects" {
  match LucentSafetyRating::from_json(@json.parse("null")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentSafetyRating from_json - missing category rejects" {
  match
    LucentSafetyRating::from_json(@json.parse("{\"probability\":\"low\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentSafetyRating from_json - missing probability rejects" {
  match
    LucentSafetyRating::from_json(@json.parse("{\"category\":\"violence\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
/// === ProviderCapability from_json 错误 ===
test "ProviderCapability from_json - non-object rejects" {
  match ProviderCapability::from_json(@json.parse("null")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "ProviderCapability from_json - missing model_pattern rejects" {
  match
    ProviderCapability::from_json(
      @json.parse(
        "{\"provider\":\"openai\",\"capabilities\":{\"tool_calling\":true,\"parallel_tool_calls\":false,\"reasoning\":false,\"multimodal_input\":false,\"structured_output\":false,\"input_modalities\":[\"text\"],\"output_modalities\":[\"text\"]}}",
      ),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "ProviderCapability from_json - missing provider rejects" {
  match
    ProviderCapability::from_json(
      @json.parse(
        "{\"model_pattern\":\"*\",\"capabilities\":{\"tool_calling\":true,\"parallel_tool_calls\":false,\"reasoning\":false,\"multimodal_input\":false,\"structured_output\":false,\"input_modalities\":[\"text\"],\"output_modalities\":[\"text\"]}}",
      ),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "ProviderCapability from_json - missing capabilities rejects" {
  match
    ProviderCapability::from_json(
      @json.parse("{\"model_pattern\":\"*\",\"provider\":\"openai\"}"),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
/// === LucentDiscovery from_json 错误 ===
test "LucentDiscovery from_json - non-object rejects" {
  match LucentDiscovery::from_json(@json.parse("null")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "LucentDiscovery from_json - missing providers rejects" {
  match
    LucentDiscovery::from_json(
      @json.parse(
        "{\"schema_version\":\"1.0\",\"protocol_version\":\"1.0\",\"schema_url\":\"https://x\"}",
      ),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}
