# Provider Adapter Guide

How to add a new LLM provider to Prism.

## Overview

Each provider adapter is a MoonBit package under `src/provider/<name>/` that implements **6 pure functions** for encoding and decoding between a provider's wire format and the Lucent IR.

```
Provider JSON/SSE  ←→  Lucent IR  ←→  Any other provider
```

## File Layout

```
src/provider/<name>/
  moon.pkg          # package manifest
  <name>.mbt        # request decode/encode + helpers
  response.mbt      # response decode/encode
  stream.mbt        # SSE decode/encode
  capability.mbt    # capability declaration
  <name>_wbtest.mbt # whitebox tests
  <name>_test.mbt   # blackbox tests
```

## The 6-Function Contract

Each adapter exports these functions (all `String` in/out):

| Direction | Decode (provider → IR) | Encode (IR → provider) |
|-----------|----------------------|----------------------|
| **Request** | `name_to_lux_request(String) -> Result[ConversionResult[LucentRequest], String]` | `lux_request_to_name(LucentRequest) -> Result[ConversionResult[String], String]` |
| **Response** | `name_to_lux_response(String) -> Result[ConversionResult[LucentResponse], String]` | `lux_response_to_name(LucentResponse) -> Result[ConversionResult[String], String]` |
| **Stream** | `name_sse_to_events(String) -> Result[ConversionResult[Array[LucentStreamEvent]], String]` | `lux_events_to_name_sse(Array[LucentStreamEvent]) -> Result[ConversionResult[String], String]` |

## Step-by-Step

### 1. Create the package

```bash
mkdir src/provider/<name>
```

Create `moon.pkg` with dependencies:

```json
{
  "import": [
    "morning-start/prism/lux",
    "morning-start/prism/internal",
    "moonbitlang/core/json"
  ]
}
```

### 2. Implement request decode

Parse the provider's JSON request format into `LucentRequest`:

```moonbit
pub fn myprovider_to_lux_request(
  json_str : String,
) -> Result[@lux.ConversionResult[@lux.LucentRequest], String] {
  let jv = @internal.parse_protocol_json(json_str) catch {
    err => return Err(err)
  }
  let diagnostics : Array[@lux.ConversionDiagnostic] = []
  // Parse model, messages, tools, options...
  // Push diagnostics for unsupported fields
  let req = @lux.LucentRequest::new(...)
  Ok(@lux.ConversionResult::new(req).with_diagnostics(diagnostics))
}
```

### 3. Implement request encode

Convert `LucentRequest` into the provider's JSON format:

```moonbit
pub fn lux_request_to_myprovider(
  req : @lux.LucentRequest,
) -> Result[@lux.ConversionResult[String], String] {
  let diagnostics : Array[@lux.ConversionDiagnostic] = []
  // Build JSON from LucentRequest fields
  // Push diagnostics for unsupported IR features
  Ok(@lux.ConversionResult::new(json_string).with_diagnostics(diagnostics))
}
```

### 4. Implement response decode/encode

Same pattern for `LucentResponse`. Use `@internal.parse_usage_json` for token usage.

### 5. Implement stream decode/encode

Use `@internal.parse_sse_messages` to parse SSE, then convert each `SseMessage` to `LucentStreamEvent`.

### 6. Declare capabilities

```moonbit
pub fn myprovider_capability() -> @lux.ProviderCapability {
  @lux.ProviderCapability::new(
    model_pattern="my-model*",
    provider="myprovider",
    capabilities=@lux.LucentCapabilities::create(
      tool_calling=Full,
      parallel_tool_calls=Full,
      reasoning=Partial,
      multimodal_input=Full,
      structured_output=Absent,
      input_modalities=[Text, Image],
      output_modalities=[Text],
    ),
    extra_params=None,
  )
}
```

### 7. Register in SDK

Add the provider to `src/sdk/provider_capability.mbt` in `build_providers()`:

```moonbit
@sdk.ProviderRegistration::new(
  name="myprovider",
  aliases=["mp", "my-model"],
  capability=myprovider_capability(),
  model_pattern="my-model*",
  request_decode=myprovider_to_lux_request,
  request_encode=lux_request_to_myprovider,
  response_decode=myprovider_to_lux_response,
  response_encode=lux_response_to_myprovider,
  events_decode=myprovider_sse_to_events,
  events_encode=lux_events_to_myprovider_sse,
)
```

### 8. Add tests

- **Whitebox tests** (`_wbtest.mbt`): test internal helpers, edge cases, error paths
- **Blackbox tests** (`_test.mbt`): test the 6 public functions with real provider JSON fixtures
- **Cross-protocol tests**: verify round-trip through `sdk/convert.mbt`

## Diagnostics

Every unsupported or degraded field MUST emit a `ConversionDiagnostic`:

```moonbit
// Unsupported: field not present in target
diagnostics.push(@lux.ConversionDiagnostic::unsupported(
  "options.store",
  Some("store not supported by myprovider"),
))

// Degraded: field mapped with information loss
diagnostics.push(@lux.ConversionDiagnostic::degraded(
  "reasoning.budget_tokens",
  Some("budget_tokens mapped to effort level"),
))
```

## References

- `docs/lux-ir-design.md` — Lucent IR type definitions
- `docs/rules/lucent-ir-evolution.md` — Governance for IR changes
- `src/provider/openai/` — Reference implementation
