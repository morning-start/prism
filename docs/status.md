# Prism Project Status

> Last updated: 2026-08-30

## Module Completion

| Module | Status | Notes |
|--------|--------|-------|
| `src/lux` (Lucent IR) | ✅ Stable | v1 schema, types + builders + stream events + diagnostics |
| `src/internal` | ✅ Stable | JSON helpers, SSE parser, shared primitives |
| `src/sdk` | ✅ Stable | Facade, registry, matching, convert pipeline |
| `src/wasm` | ✅ Stable | 11 exported functions, scratch memory, log buffer |
| `src/provider/openai` | ✅ Complete | Chat Completions + stream + capability |
| `src/provider/messages` | ✅ Complete | Anthropic Messages API + extended thinking |
| `src/provider/responses` | ✅ Complete | OpenAI Responses API |
| `src/provider/gemini` | ✅ Complete | Google Gemini API + Vertex variant |
| `src/cmd/main` | ✅ Complete | WASM exports only |
| `wrappers/ts` | ✅ Complete | TypeScript client |
| `wrappers/go` | ✅ Complete | Go client |

## Implemented Providers (9 adapters)

| Adapter | Protocol | Request | Response | Stream | Capability |
|---------|----------|---------|----------|--------|------------|
| `openai` | OpenAI Chat Completions | ✅ | ✅ | ✅ | ✅ |
| `responses` | OpenAI Responses API | ✅ | ✅ | ✅ | ✅ |
| `messages` | Anthropic Messages API | ✅ | ✅ | ✅ | ✅ |
| `gemini` | Google Gemini API | ✅ | ✅ | ✅ | ✅ |

Provider aliases and model-pattern variants (codex, azure, vllm, gemini-vertex, gemini-interactions) are registered in `src/sdk/registry.mbt`.

## Test Coverage

- **lux**: Whitebox (`lux_wbtest`, `serialize_wbtest`, `deserialize_wbtest`, `conversion_json_wbtest`) + blackbox (`lux_test`, `from_json_error_test`) — extensive
- **sdk**: Cross-protocol (`cross_protocol_test`), convert matrix (`convert_matrix_test`), registry (`provider_registry_wbtest`), integration (`sdk_test`, `convert_test`)
- **provider/\***: Each adapter has `_wbtest` + `_test`
- **wasm**: `wasm_test` covering all exports
- **internal**: Basic coverage in `internal/test/` subdirectory

## Known Limitations

- `scripts/check_schema_drift.ps1` runs in report mode by default and can be used with `-Strict` in CI; its self-test covers version, required fields, enums, and stream events

- `src/lux/lux.mbt` remains the type/model hub; codec implementations are split into request/response/stream/primitive files
- Provider request codecs are split into dedicated request_decode/request_encode files; response/stream code remains co-located where further separation is not yet justified
- JSON Schema (`schemas/lux-ir-v1.json`) remains manually authored, but `scripts/check_schema_drift.ps1` now reports version/required-field/enum/stream-event drift

- `src/internal/sse.mbt` exports `parse_sse_frame` — shared SSE preprocessing pipeline used by messages, openai, and gemini stream decoders
- `src/internal/json.mbt` exports `parse_string_array` and `merge_extras_json` — shared JSON helpers used by all four providers
- `src/lux/stream.mbt` exports `BlockAccumulator` (package-internal) — extracted from the 290-line stream accumulator function

## Build & Verify

```bash
moon fmt --check
moon check --warn-list +73 --deny-warn
moon test                      # native + wasm-gc
```
