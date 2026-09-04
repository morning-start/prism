///|
/// Lux IR from_json 错误路径测试
///
/// 目标：覆盖 deserialize.mbt 中大量未覆盖的 Err(e) 分支和类型不匹配分支。
///
/// 模式：构造畸形 JSON → from_json() → 断言 Err

///|

///|
/// === @lux.LucentContent from_json 错误 ===

///|
test "@lux.LucentContent from_json - non-object rejects" {
  match @lux.LucentContent::from_json(@json.parse("123")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentContent from_json - missing type rejects" {
  match @lux.LucentContent::from_json(@json.parse("{}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentContent from_json - type field not string rejects" {
  match @lux.LucentContent::from_json(@json.parse("{\"type\":42}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentContent from_json - unknown type rejects" {
  match
    @lux.LucentContent::from_json(
      @json.parse("{\"type\":\"unknown_content_type\"}"),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentContent from_json - text missing text field rejects" {
  match @lux.LucentContent::from_json(@json.parse("{\"type\":\"text\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentContent from_json - text with non-string text field rejects" {
  match
    @lux.LucentContent::from_json(
      @json.parse("{\"type\":\"text\",\"text\":123}"),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentContent from_json - tool_use missing tool_use field rejects" {
  match @lux.LucentContent::from_json(@json.parse("{\"type\":\"tool_use\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentContent from_json - tool_use with invalid tool_use object rejects" {
  match
    @lux.LucentContent::from_json(
      @json.parse("{\"type\":\"tool_use\",\"tool_use\":123}"),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentContent from_json - tool_result missing tool_result field rejects" {
  match
    @lux.LucentContent::from_json(@json.parse("{\"type\":\"tool_result\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentContent from_json - thinking missing thinking field rejects" {
  match @lux.LucentContent::from_json(@json.parse("{\"type\":\"thinking\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentContent from_json - refusal missing refusal field rejects" {
  match @lux.LucentContent::from_json(@json.parse("{\"type\":\"refusal\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentContent from_json - image missing image field rejects" {
  match @lux.LucentContent::from_json(@json.parse("{\"type\":\"image\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentContent from_json - native missing native_tag rejects" {
  match @lux.LucentContent::from_json(@json.parse("{\"type\":\"native\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
/// === @lux.LucentToolUse from_json 错误 ===
test "@lux.LucentToolUse from_json - non-object rejects" {
  match @lux.LucentToolUse::from_json(@json.parse("null")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentToolUse from_json - missing id rejects" {
  match
    @lux.LucentToolUse::from_json(
      @json.parse("{\"name\":\"x\",\"arguments\":\"{}\"}"),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentToolUse from_json - missing name rejects" {
  match
    @lux.LucentToolUse::from_json(
      @json.parse("{\"id\":\"x\",\"arguments\":\"{}\"}"),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentToolUse from_json - missing arguments rejects" {
  match
    @lux.LucentToolUse::from_json(
      @json.parse("{\"id\":\"x\",\"name\":\"get_weather\"}"),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentToolUse from_json - id as non-string rejects" {
  match
    @lux.LucentToolUse::from_json(
      @json.parse("{\"id\":123,\"name\":\"get_weather\",\"arguments\":\"{}\"}"),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
/// === @lux.LucentToolResult from_json 错误 ===
test "@lux.LucentToolResult from_json - non-object rejects" {
  match @lux.LucentToolResult::from_json(@json.parse("true")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentToolResult from_json - missing tool_use_id rejects" {
  match
    @lux.LucentToolResult::from_json(
      @json.parse("{\"content\":[],\"is_error\":false}"),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentToolResult from_json - missing content rejects" {
  match
    @lux.LucentToolResult::from_json(
      @json.parse("{\"tool_use_id\":\"x\",\"is_error\":false}"),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentToolResult from_json - content not an array rejects" {
  match
    @lux.LucentToolResult::from_json(
      @json.parse(
        "{\"tool_use_id\":\"x\",\"content\":\"not-array\",\"is_error\":false}",
      ),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentToolResult from_json - missing is_error rejects" {
  match
    @lux.LucentToolResult::from_json(
      @json.parse("{\"tool_use_id\":\"x\",\"content\":[]}"),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentToolResult from_json - is_error as non-boolean rejects" {
  match
    @lux.LucentToolResult::from_json(
      @json.parse(
        "{\"tool_use_id\":\"x\",\"content\":[{\"type\":\"text\",\"text\":\"hi\"}],\"is_error\":42}",
      ),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
/// === @lux.LucentMessage from_json 错误 ===
test "@lux.LucentMessage from_json - non-object rejects" {
  match @lux.LucentMessage::from_json(@json.parse("\"hello\"")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentMessage from_json - missing role rejects" {
  match
    @lux.LucentMessage::from_json(
      @json.parse("{\"content\":[{\"type\":\"text\",\"text\":\"hi\"}]}"),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentMessage from_json - missing content rejects" {
  match @lux.LucentMessage::from_json(@json.parse("{\"role\":\"user\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
/// === @lux.LucentConversationItem from_json 错误 ===
test "@lux.LucentConversationItem from_json - non-object rejects" {
  match @lux.LucentConversationItem::from_json(@json.parse("null")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentConversationItem from_json - missing type rejects" {
  match @lux.LucentConversationItem::from_json(@json.parse("{}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentConversationItem from_json - unknown type rejects" {
  match
    @lux.LucentConversationItem::from_json(
      @json.parse("{\"type\":\"unknown_item\"}"),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentConversationItem from_json - message missing message field rejects" {
  match
    @lux.LucentConversationItem::from_json(
      @json.parse("{\"type\":\"message\"}"),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentConversationItem from_json - tool_call missing tool_call field rejects" {
  match
    @lux.LucentConversationItem::from_json(
      @json.parse("{\"type\":\"tool_call\"}"),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentConversationItem from_json - reasoning missing reasoning field rejects" {
  match
    @lux.LucentConversationItem::from_json(
      @json.parse("{\"type\":\"reasoning\"}"),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentConversationItem from_json - agent_action missing agent_action field rejects" {
  match
    @lux.LucentConversationItem::from_json(
      @json.parse("{\"type\":\"agent_action\"}"),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
/// === @lux.LucentTool from_json 错误 ===
test "@lux.LucentTool from_json - non-object rejects" {
  match @lux.LucentTool::from_json(@json.parse("42")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentTool from_json - missing name rejects" {
  match
    @lux.LucentTool::from_json(
      @json.parse("{\"parameters\":{\"type\":\"object\"}}"),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentTool from_json - missing parameters rejects" {
  match @lux.LucentTool::from_json(@json.parse("{\"name\":\"x\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
/// === @lux.LucentToolChoice from_json 错误 ===
test "@lux.LucentToolChoice from_json - unknown string value rejects" {
  match @lux.LucentToolChoice::from_json(@json.parse("\"bad\"")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentToolChoice from_json - non-string non-object rejects" {
  match @lux.LucentToolChoice::from_json(@json.parse("null")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentToolChoice from_json - specific_tool missing name rejects" {
  match
    @lux.LucentToolChoice::from_json(
      @json.parse("{\"type\":\"specific_tool\"}"),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentToolChoice from_json - specific_tool name not string rejects" {
  match
    @lux.LucentToolChoice::from_json(
      @json.parse("{\"type\":\"specific_tool\",\"name\":42}"),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentToolChoice from_json - object missing type rejects" {
  match @lux.LucentToolChoice::from_json(@json.parse("{\"name\":\"x\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
/// === @lux.LucentStructuredOutput from_json 错误 ===
test "@lux.LucentStructuredOutput from_json - unknown string rejects" {
  match @lux.LucentStructuredOutput::from_json(@json.parse("\"unknown\"")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentStructuredOutput from_json - non-string non-object rejects" {
  match @lux.LucentStructuredOutput::from_json(@json.parse("null")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentStructuredOutput from_json - json_schema missing schema rejects" {
  match
    @lux.LucentStructuredOutput::from_json(
      @json.parse("{\"type\":\"json_schema\"}"),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
/// === @lux.LucentReasoningEffort from_json 错误 ===
test "@lux.LucentReasoningEffort from_json - unknown string rejects" {
  match @lux.LucentReasoningEffort::from_json(@json.parse("\"ultra\"")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentReasoningEffort from_json - non-string rejects" {
  match @lux.LucentReasoningEffort::from_json(@json.parse("42")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
/// === @lux.LucentReasoningSummary from_json 错误 ===
test "@lux.LucentReasoningSummary from_json - unknown string rejects" {
  match @lux.LucentReasoningSummary::from_json(@json.parse("\"verbose\"")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentReasoningSummary from_json - non-string rejects" {
  match @lux.LucentReasoningSummary::from_json(@json.parse("null")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
/// === @lux.LucentOptions from_json 错误 ===
test "@lux.LucentOptions from_json - non-object rejects" {
  match @lux.LucentOptions::from_json(@json.parse("\"bad\"")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentOptions from_json - missing stream rejects" {
  match @lux.LucentOptions::from_json(@json.parse("{}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentOptions from_json - stream as non-boolean rejects" {
  match @lux.LucentOptions::from_json(@json.parse("{\"stream\":\"yes\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
/// === @lux.LucentReasoningConfig from_json 错误 ===
test "@lux.LucentReasoningConfig from_json - non-object rejects" {
  match @lux.LucentReasoningConfig::from_json(@json.parse("42")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentReasoningConfig from_json - missing enabled rejects" {
  match @lux.LucentReasoningConfig::from_json(@json.parse("{}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentReasoningConfig from_json - enabled as non-boolean rejects" {
  match
    @lux.LucentReasoningConfig::from_json(@json.parse("{\"enabled\":\"yes\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
/// === @lux.LucentCapabilities from_json 错误 ===
test "@lux.LucentCapabilities from_json - non-object rejects" {
  match @lux.LucentCapabilities::from_json(@json.parse("null")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentCapabilities from_json - missing tool_calling rejects" {
  match @lux.LucentCapabilities::from_json(@json.parse("{}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentCapabilities from_json - missing input_modalities rejects" {
  let jv = @json.parse(
    "{\"tool_calling\":\"full\",\"parallel_tool_calls\":\"none\",\"reasoning\":\"full\",\"multimodal_input\":\"full\",\"structured_output\":\"full\"}",
  )
  match @lux.LucentCapabilities::from_json(jv) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
/// === @lux.LucentModality from_json 错误 ===
test "@lux.LucentModality from_json - non-string rejects" {
  match @lux.LucentModality::from_json(@json.parse("42")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

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
/// === @lux.LucentMediaSource from_json 错误 ===
test "@lux.LucentMediaSource from_json - non-object rejects" {
  match @lux.LucentMediaSource::from_json(@json.parse("42")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentMediaSource from_json - missing type rejects" {
  match @lux.LucentMediaSource::from_json(@json.parse("{}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentMediaSource from_json - unknown type rejects" {
  match
    @lux.LucentMediaSource::from_json(
      @json.parse("{\"type\":\"unknown_type\"}"),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentMediaSource from_json - type as non-string rejects" {
  match @lux.LucentMediaSource::from_json(@json.parse("{\"type\":42}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
/// === @lux.LucentMultimedia from_json 错误 ===
test "@lux.LucentMultimedia from_json - non-object rejects" {
  match @lux.LucentMultimedia::from_json(@json.parse("null")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentMultimedia from_json - missing media_type rejects" {
  match
    @lux.LucentMultimedia::from_json(
      @json.parse("{\"source\":{\"type\":\"url\",\"data\":\"x\"}}"),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentMultimedia from_json - missing source rejects" {
  match
    @lux.LucentMultimedia::from_json(
      @json.parse("{\"media_type\":\"image/png\"}"),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
/// === @lux.LucentAnnotation from_json 错误 ===
test "@lux.LucentAnnotation from_json - non-object rejects" {
  match @lux.LucentAnnotation::from_json(@json.parse("42")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentAnnotation from_json - missing kind rejects" {
  match @lux.LucentAnnotation::from_json(@json.parse("{}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
/// === @lux.LucentThinking from_json 错误 ===
test "@lux.LucentThinking from_json - non-object rejects" {
  match @lux.LucentThinking::from_json(@json.parse("null")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentThinking from_json - missing text rejects" {
  match @lux.LucentThinking::from_json(@json.parse("{\"redacted\":false}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentThinking from_json - missing redacted rejects" {
  match @lux.LucentThinking::from_json(@json.parse("{\"text\":\"thinking\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
/// === @lux.LucentAgentAction from_json 错误 ===
test "@lux.LucentAgentAction from_json - non-object rejects" {
  match @lux.LucentAgentAction::from_json(@json.parse("null")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentAgentAction from_json - missing kind rejects" {
  match @lux.LucentAgentAction::from_json(@json.parse("{\"id\":\"x\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentAgentAction from_json - missing id rejects" {
  match @lux.LucentAgentAction::from_json(@json.parse("{\"kind\":\"tool\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
/// === @lux.LucentBlockType from_json 错误 ===
test "@lux.LucentBlockType from_json - non-string non-object rejects" {
  match @lux.LucentBlockType::from_json(@json.parse("42")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentBlockType from_json - object missing type rejects" {
  match @lux.LucentBlockType::from_json(@json.parse("{\"id\":\"x\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentBlockType from_json - tool_call missing id rejects" {
  match
    @lux.LucentBlockType::from_json(@json.parse("{\"type\":\"tool_call\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentBlockType from_json - tool_call missing name rejects" {
  match
    @lux.LucentBlockType::from_json(
      @json.parse("{\"type\":\"tool_call\",\"id\":\"x\"}"),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
/// === @lux.LucentBlockDelta from_json 错误 ===
test "@lux.LucentBlockDelta from_json - non-object rejects" {
  match @lux.LucentBlockDelta::from_json(@json.parse("null")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentBlockDelta from_json - missing type rejects" {
  match @lux.LucentBlockDelta::from_json(@json.parse("{}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentBlockDelta from_json - unknown delta type rejects" {
  match
    @lux.LucentBlockDelta::from_json(
      @json.parse("{\"type\":\"unknown_delta\"}"),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentBlockDelta from_json - text missing text field rejects" {
  match @lux.LucentBlockDelta::from_json(@json.parse("{\"type\":\"text\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentBlockDelta from_json - thinking missing text field rejects" {
  match
    @lux.LucentBlockDelta::from_json(@json.parse("{\"type\":\"thinking\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentBlockDelta from_json - signature missing signature field rejects" {
  match
    @lux.LucentBlockDelta::from_json(@json.parse("{\"type\":\"signature\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentBlockDelta from_json - tool_arguments missing arguments field rejects" {
  match
    @lux.LucentBlockDelta::from_json(
      @json.parse("{\"type\":\"tool_arguments\"}"),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentBlockDelta from_json - refusal missing text field rejects" {
  match
    @lux.LucentBlockDelta::from_json(@json.parse("{\"type\":\"refusal\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentBlockDelta from_json - native missing native_tag rejects" {
  match @lux.LucentBlockDelta::from_json(@json.parse("{\"type\":\"native\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
/// === @lux.LucentStreamEvent from_json 错误 ===
test "@lux.LucentStreamEvent from_json - non-object rejects" {
  match @lux.LucentStreamEvent::from_json(@json.parse("null")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentStreamEvent from_json - missing event rejects" {
  match @lux.LucentStreamEvent::from_json(@json.parse("{}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentStreamEvent from_json - unknown event rejects" {
  match
    @lux.LucentStreamEvent::from_json(@json.parse("{\"event\":\"bad_event\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentStreamEvent from_json - item_start missing index rejects" {
  match
    @lux.LucentStreamEvent::from_json(
      @json.parse(
        "{\"event\":\"item_start\",\"item\":{\"type\":\"message\",\"message\":{\"role\":\"user\",\"content\":[{\"type\":\"text\",\"text\":\"hi\"}]}}}",
      ),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentStreamEvent from_json - block_start missing index rejects" {
  match
    @lux.LucentStreamEvent::from_json(
      @json.parse("{\"event\":\"block_start\",\"block_type\":\"text\"}"),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentStreamEvent from_json - finish missing finish_reason rejects" {
  match
    @lux.LucentStreamEvent::from_json(@json.parse("{\"event\":\"finish\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentStreamEvent from_json - usage missing usage rejects" {
  match
    @lux.LucentStreamEvent::from_json(@json.parse("{\"event\":\"usage\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentStreamEvent from_json - error missing error field rejects" {
  match
    @lux.LucentStreamEvent::from_json(@json.parse("{\"event\":\"error\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
/// === @lux.LucentError from_json 错误 ===
test "@lux.LucentError from_json - non-object rejects" {
  match @lux.LucentError::from_json(@json.parse("42")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentError from_json - missing kind rejects" {
  match @lux.LucentError::from_json(@json.parse("{\"message\":\"bad\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentError from_json - missing message rejects" {
  match
    @lux.LucentError::from_json(@json.parse("{\"kind\":\"invalid_request\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
/// === @lux.LucentRole from_json 错误 ===
test "@lux.LucentRole from_json - non-string rejects" {
  match @lux.LucentRole::from_json(@json.parse("42")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
/// === @lux.LucentUsage from_json 错误 ===
test "@lux.LucentUsage from_json - non-object rejects" {
  match @lux.LucentUsage::from_json(@json.parse("null")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentUsage from_json - missing prompt_tokens rejects" {
  match
    @lux.LucentUsage::from_json(
      @json.parse("{\"completion_tokens\":5,\"total_tokens\":10}"),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentUsage from_json - prompt_tokens non-numeric rejects" {
  match
    @lux.LucentUsage::from_json(
      @json.parse(
        "{\"prompt_tokens\":\"five\",\"completion_tokens\":5,\"total_tokens\":10}",
      ),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentUsage from_json - missing total_tokens rejects" {
  match
    @lux.LucentUsage::from_json(
      @json.parse("{\"prompt_tokens\":10,\"completion_tokens\":5}"),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
/// === @lux.LucentChoice from_json 错误 ===
test "@lux.LucentChoice from_json - non-object rejects" {
  match @lux.LucentChoice::from_json(@json.parse("null")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentChoice from_json - missing index rejects" {
  match
    @lux.LucentChoice::from_json(
      @json.parse(
        "{\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"hi\"}]},\"finish_reason\":\"stop\"}",
      ),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentChoice from_json - missing message rejects" {
  match
    @lux.LucentChoice::from_json(
      @json.parse("{\"index\":0,\"finish_reason\":\"stop\"}"),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentChoice from_json - missing finish_reason rejects" {
  match
    @lux.LucentChoice::from_json(
      @json.parse(
        "{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":[{\"type\":\"text\",\"text\":\"hi\"}]}}",
      ),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
/// === @lux.LucentResponse from_json 错误 ===
test "@lux.LucentResponse from_json - non-object rejects" {
  match @lux.LucentResponse::from_json(@json.parse("null")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentResponse from_json - missing schema_version rejects" {
  match
    @lux.LucentResponse::from_json(
      @json.parse("{\"id\":\"x\",\"model\":\"m\",\"choices\":[]}"),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentResponse from_json - missing id rejects" {
  match
    @lux.LucentResponse::from_json(
      @json.parse("{\"schema_version\":\"1.0\",\"model\":\"m\",\"choices\":[]}"),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentResponse from_json - missing choices rejects" {
  match
    @lux.LucentResponse::from_json(
      @json.parse("{\"schema_version\":\"1.0\",\"id\":\"x\",\"model\":\"m\"}"),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
/// === @lux.LucentRequest from_json 错误 ===
test "@lux.LucentRequest from_json - non-object rejects" {
  match @lux.LucentRequest::from_json(@json.parse("null")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentRequest from_json - missing model rejects" {
  match
    @lux.LucentRequest::from_json(
      @json.parse(
        "{\"schema_version\":\"1.0\",\"conversation\":[],\"options\":{\"stream\":false}}",
      ),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentRequest from_json - missing options rejects" {
  match
    @lux.LucentRequest::from_json(
      @json.parse(
        "{\"schema_version\":\"1.0\",\"model\":\"m\",\"conversation\":[]}",
      ),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentRequest from_json - missing conversation rejects" {
  match
    @lux.LucentRequest::from_json(
      @json.parse(
        "{\"schema_version\":\"1.0\",\"model\":\"m\",\"options\":{\"stream\":false}}",
      ),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
/// === @lux.LucentSafetyRating from_json 错误 ===
test "@lux.LucentSafetyRating from_json - non-object rejects" {
  match @lux.LucentSafetyRating::from_json(@json.parse("null")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentSafetyRating from_json - missing category rejects" {
  match
    @lux.LucentSafetyRating::from_json(@json.parse("{\"probability\":\"low\"}")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentSafetyRating from_json - missing probability rejects" {
  match
    @lux.LucentSafetyRating::from_json(
      @json.parse("{\"category\":\"violence\"}"),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
/// === @lux.ProviderCapability from_json 错误 ===
test "@lux.ProviderCapability from_json - non-object rejects" {
  match @lux.ProviderCapability::from_json(@json.parse("null")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.ProviderCapability from_json - missing model_pattern rejects" {
  match
    @lux.ProviderCapability::from_json(
      @json.parse(
        "{\"provider\":\"openai\",\"capabilities\":{\"tool_calling\":true,\"parallel_tool_calls\":false,\"reasoning\":false,\"multimodal_input\":false,\"structured_output\":false,\"input_modalities\":[\"text\"],\"output_modalities\":[\"text\"]}}",
      ),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.ProviderCapability from_json - missing provider rejects" {
  match
    @lux.ProviderCapability::from_json(
      @json.parse(
        "{\"model_pattern\":\"*\",\"capabilities\":{\"tool_calling\":true,\"parallel_tool_calls\":false,\"reasoning\":false,\"multimodal_input\":false,\"structured_output\":false,\"input_modalities\":[\"text\"],\"output_modalities\":[\"text\"]}}",
      ),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.ProviderCapability from_json - missing capabilities rejects" {
  match
    @lux.ProviderCapability::from_json(
      @json.parse("{\"model_pattern\":\"*\",\"provider\":\"openai\"}"),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
/// === @lux.LucentDiscovery from_json 错误 ===
test "@lux.LucentDiscovery from_json - non-object rejects" {
  match @lux.LucentDiscovery::from_json(@json.parse("null")) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}

///|
test "@lux.LucentDiscovery from_json - missing providers rejects" {
  match
    @lux.LucentDiscovery::from_json(
      @json.parse(
        "{\"schema_version\":\"1.0\",\"protocol_version\":\"1.0\",\"schema_url\":\"https://x\"}",
      ),
    ) {
    Ok(_) => fail("expected Err, got Ok")
    Err(_) => ()
  }
}
