# Lucent IR Design

> Authoritative type definitions: `src/lux/types.mbt`, `src/lux/lux_builders.mbt`, `src/lux/lux_helpers.mbt`
> JSON Schema: `schemas/lux-ir-v1.json`
> Evolution governance: `docs/rules/lucent-ir-evolution.md`

## Schema Version

`schema_version = "v1"` — carried on every `LucentRequest` and `LucentResponse`.

## Core Model

### LucentRequest

Complete LLM request with conversation, tools, and generation options.

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `schema_version` | `String` | ✅ | Always `"v1"` |
| `model` | `String` | ✅ | Model identifier |
| `instructions` | `Array[LucentContent]?` | | System/developer instructions |
| `conversation` | `Array[LucentConversationItem]` | ✅ | Heterogeneous flat list |
| `tools` | `Array[LucentTool]?` | | Tool definitions |
| `tool_choice` | `LucentToolChoice?` | | Auto/None/Required/Specific |
| `options` | `LucentOptions` | ✅ | Generation parameters |
| `capabilities` | `LucentCapabilities?` | | Capability declaration |
| `reasoning` | `LucentReasoningConfig?` | | Extended thinking config |
| `metadata` | `Map[String, String]?` | | Opaque metadata |
| `extra` | `Map[String, Json]?` | | Provider-specific extensions |

### LucentResponse

Non-streaming LLM response with choices and usage.

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `schema_version` | `String` | ✅ | Always `"v1"` |
| `id` | `String` | ✅ | Response ID |
| `model` | `String` | ✅ | Model used |
| `created_at` | `Int?` | | Unix timestamp |
| `choices` | `Array[LucentChoice]` | ✅ | At least one |
| `usage` | `LucentUsage?` | | Token counts |
| `provider_payload` | `Json?` | | Raw provider data |

### LucentStreamEvent

Normalized streaming events. See `src/lux/stream.mbt` for the full enum.

| Event | Payload | Description |
|-------|---------|-------------|
| `ConversationStart` | metadata | Stream begins |
| `ItemStart` | ConversationItem | New message/tool/reasoning |
| `BlockStart` | content type | Content block begins |
| `BlockDelta` | delta type | Incremental content |
| `BlockEnd` | — | Content block ends |
| `ItemEnd` | — | Item complete |
| `Usage` | LucentUsage | Token counts |
| `Finish` | LucentFinishReason | Stream complete |

## Conversation Model

### LucentConversationItem

Heterogeneous flat list — messages, tool calls, tool results, reasoning, and agent actions share one array.

| Variant | Payload | Description |
|---------|---------|-------------|
| `Message` | `LucentMessage` | User/assistant/system message |
| `ToolCall` | `LucentToolUse` | Structured tool invocation |
| `ToolResult` | `LucentToolResult` | Tool execution result |
| `Reasoning` | `LucentThinking` | Standalone reasoning block |
| `AgentAction` | `LucentAgentAction` | Agent action placeholder |

### LucentMessage

| Field | Type | Notes |
|-------|------|-------|
| `role` | `LucentRole` | System/User/Assistant/Tool/Model/Developer/Native |
| `content` | `Array[LucentContent]` | Polymorphic content blocks |
| `phase` | `String?` | Pipeline phase tag |
| `reasoning` | `LucentThinking?` | Message-level reasoning (vLLM/DeepSeek) |

### LucentContent

| Variant | Payload | Description |
|---------|---------|-------------|
| `Text` | `(String, Array[LucentAnnotation]?)` | Plain text with optional annotations |
| `ToolUse` | `LucentToolUse` | Tool call in content |
| `ToolResult` | `LucentToolResult` | Tool result in content |
| `Thinking` | `LucentThinking` | Reasoning content |
| `Refusal` | `String` | Model refusal |
| `Image/Audio/Video/File` | `LucentMultimedia` | Multimodal media |
| `Native` | `(String, Json)` | Provider-specific extension |

## Enums

### LucentRole
`System` | `User` | `Assistant` | `Tool` | `Model` | `Developer` | `Native(String)`

### LucentFinishReason
`Stop` | `Length` | `ToolCalls` | `ContentFilter` | `Safety` | `Recitation` | `MalformedToolCall` | `Error` | `Native(String)`

### LucentToolKind
`Function` | `FileSearch` | `WebSearch` | `CodeInterpreter` | `ComputerUse` | `CodeExecution` | `Shell` | `ApplyPatch` | `MCP` | `Native(String)`

### SupportLevel
`Full` | `Partial` | `Absent`

### ConversionStatus
`Exact` | `Degraded` | `Unsupported` | `Invalid`

## Diagnostics

### ConversionDiagnostic

Every lossy mapping emits a diagnostic instead of silent data loss.

| Field | Type | Description |
|-------|------|-------------|
| `field` | `String` | Dot-path (e.g. `content.audio`, `tools.kind`) |
| `status` | `ConversionStatus` | Exact/Degraded/Unsupported/Invalid |
| `detail` | `String?` | Human-readable explanation |

### ConversionResult[T]

Wraps any value with an ordered diagnostic list. Success ≠ Exact: value is usable but some fields may be degraded.

## Capability Declaration

### LucentCapabilities

| Field | Type | Description |
|-------|------|-------------|
| `tool_calling` | `SupportLevel` | Function/tool calling support |
| `parallel_tool_calls` | `SupportLevel` | Concurrent tool calls |
| `reasoning` | `SupportLevel` | Extended thinking |
| `multimodal_input` | `SupportLevel` | Image/audio/video input |
| `structured_output` | `SupportLevel` | JSON schema enforcement |
| `input_modalities` | `Array[LucentModality]` | Supported input types |
| `output_modalities` | `Array[LucentModality]` | Supported output types |

## References

- Type definitions: `src/lux/types.mbt` (types), `src/lux/lux_builders.mbt` (constructors)
- JSON Schema: `schemas/lux-ir-v1.json`
- Evolution rules: `docs/rules/lucent-ir-evolution.md`
