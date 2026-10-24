# Lucent IR Design

> Authoritative type definitions: `src/lux/types.mbt`, `src/lux/builders.mbt`, `src/lux/helpers.mbt`
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

### Extension channels

The IR has **two** extension carriers with deliberately different semantics. They
are not interchangeable — pick by intent:

| | `LucentRequest.extra` | `LucentOptions.extras` |
|---|---|---|
| Written by | the program author, explicitly | the decoders, automatically |
| Meaning | provider-specific extension **for the target** | source-protocol wire field the IR does not model (soft-fail preservation) |
| Wire destination | request body top level | generation-parameter position (`generationConfig` for Gemini) |
| Cross-protocol filtering | **none** — emitted verbatim, the author is responsible for target validity | keys provably native to *another* protocol are dropped with an `Unsupported` diagnostic |
| Unknown keys | emitted verbatim | emitted verbatim (never a hard failure) |

Precedence when several sources write the same key:

> fields the target derives from IR standard fields **>** `request.extra` **>**
> `options.extras`

Every override or drop is reported through `ConversionDiagnostic`
(`Degraded` / `Unsupported`) — never silently — and a key appears **at most once**
in the emitted JSON object.

Both stay optional (`T?`, empty-by-default maps) and neither can make
deserialization fail; this is the "extension fields must always be optional" rule
in `AGENTS.md`.

The **response** side has the mirrored carrier: `LucentResponse.provider_payload`
holds source-protocol response-level fields the IR does not model (e.g. OpenAI's
`system_fingerprint` / `service_tier` / `metadata` / `moderation`). It follows
the same ownership gating as `options.extras`: native to the target → emitted;
provably foreign → dropped with an `Unsupported` diagnostic; unknown keys →
passed through. Keys used as **encoder knobs** (currently `reasoning_field`,
which selects the field name for message-level reasoning) are never emitted —
they are control inputs, not wire data. See
`src/internal/protocol_keys.mbt` (`split_provider_payload`) and
`docs/fidelity-matrix.md` §3.11.

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

### LucentChoice

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `index` | `Int32` | ✅ | Candidate index |
| `message` | `LucentMessage` | ✅ | The reply |
| `finish_reason` | `LucentFinishReason` | ✅ | Why generation stopped |
| `safety_ratings` | `Array[LucentSafetyRating]?` | | Provider safety ratings |
| `stop_sequence` | `String?` | | **CR-005**: the custom stop sequence that was actually hit |

`stop_sequence` carries the **response-side fact** "which configured stop string
terminated generation" — distinct from `LucentOptions.stop`, which is the
**request-side candidate list**. The two must not be conflated: one is what you
allowed, the other is what happened.

Semantics: `stop_sequence.is_some()` ⟺ the source protocol reported
`stop_reason == "stop_sequence"` (Anthropic Messages). Only Messages has this
concept; the other three targets drop it with an explicit `Unsupported`
diagnostic. On the **streaming** path the value rides `Finish`'s second
payload slot (`Finish(reason, stop_sequence?)`, CR-006 batch 2, governance
§5): the constructor `LucentStreamEvent::finish(reason)` covers the
reason-only case, and the stream accumulator writes it into
`LucentChoice.stop_sequence` — so streaming accumulation and non-streaming
decoding share the same field instead of maintaining a second vocabulary.

Serialization: `None` emits no key at all (preserves the pre-existing byte
shape); deserialization treats missing / empty / non-string as `None` (soft
failure for an optional field, governance §4).

### LucentStreamEvent

Normalized streaming events. See `src/lux/stream.mbt` for the full enum.

| Event | Payload | Description |
|-------|---------|-------------|
| `ConversationStart` | `LucentConversationMeta` | Stream begins |
| `ItemStart` | `(index, ConversationItem)` | New message/tool/reasoning |
| `BlockStart` | `(index, LucentBlockType)` | Content block begins |
| `BlockDelta` | `(index, LucentBlockDelta)` | Incremental content |
| `BlockEnd` | `index` | Content block ends |
| `ItemEnd` | `index` | Item complete |
| `BlockDiscard` | `index` | 已废弃（CR-003 选项 B）：无生产者；读取兼容保留 |
| `Annotations` | `(index, Array[LucentAnnotation])` | Citation/annotation side-channel |
| `Usage` | `LucentUsage` | Token counts |
| `Finish` | `(LucentFinishReason, String?)` | Stream complete; second slot = hit stop sequence (CR-006 batch 2, optional) |
| `Error` | `LucentError` | Typed error event |
| `Done` | — | Stream terminated (emitted by session layer in conversion paths) |

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

### ConversationSnapshot (T8)

Middleware-local session storage unit for stateless continuation. OpenAI
Responses' `previous_response_id` is a server-side stateful continuation;
converting it to stateless endpoints (chat/messages/gemini) requires the
middleware to locally store and restore history. This type is the storage
unit — not part of any wire protocol; `to_json`/`from_json` exist for host
persistence. IR proposal: accepted via the governance process in
`docs/rules/lucent-ir-evolution.md` (proposal workspace retired 2026-10-24).

| Field | Type | Notes |
|-------|------|-------|
| `response_id` | `String` | The Responses API response id this snapshot belongs to |
| `request` | `LucentRequest` | Request context that produced the response (restore source) |
| `response_text` | `String?` | Optional response text (audit/debug) |

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

- Type definitions: `src/lux/types.mbt` (types), `src/lux/builders.mbt` (constructors)
- JSON Schema: `schemas/lux-ir-v1.json`
- Evolution rules: `docs/rules/lucent-ir-evolution.md`
