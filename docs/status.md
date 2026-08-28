# Prism Project Status

> Last updated: 2026-08-28

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

Provider aliases and model-pattern variants (codex, azure, vllm, gemini-vertex, gemini-interactions) are registered in `src/sdk/provider_capability.mbt`.

## Test Coverage

- **lux**: Whitebox (`lux_wbtest`, `serialize_wbtest`, `deserialize_wbtest`, `conversion_json_wbtest`) + blackbox (`lux_test`, `from_json_error_test`) — extensive
- **sdk**: Cross-protocol (`cross_protocol_test`), convert matrix (`convert_matrix_test`), registry (`provider_registry_wbtest`), integration (`sdk_test`, `convert_test`)
- **provider/\***: Each adapter has `_wbtest` + `_test`
- **wasm**: `wasm_test` covering all exports
- **internal**: Basic coverage in `internal/test/` subdirectory

## Known Limitations

- `src/lux/lux.mbt` is a single 1325-line file; splitting into types/builders/helpers is deferred (see architecture.md migration plan)
- Provider adapters' main `*.mbt` files still contain request encode/decode; full request/response/stream/capability split is partial
- JSON Schema (`schemas/lux-ir-v1.json`) is maintained manually; no automated drift detection against code

## Build & Verify

```bash
moon fmt --check
moon check --warn-list +73 --deny-warn
moon test                      # native + wasm-gc
```
