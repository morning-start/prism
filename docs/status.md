# Prism Project Status

> Last updated: 2026-09-01

## Module Completion

| Module | Status | Notes |
|--------|--------|-------|
| `src/lux` (Lucent IR) | ✅ Stable | v1 schema, types + builders + stream events + diagnostics |
| `src/internal` | ✅ Stable | JSON helpers, SSE parser, shared primitives |
| `src/sdk` | ✅ Stable | Facade, context, registry+match, pipeline/codec_pipeline, convert, schema+event（功能组分区注释，iteration-007） |
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

Tests are organized per package: **blackbox** (`*_test.mbt`, public API only)
live in a dedicated `test/` subpackage (`import ... for "test"`); **whitebox**
(`*_wbtest.mbt`) stay in the package directory (MoonBit requires same-package
compilation to reach non-public members).

- **lux**: Whitebox (`lux_wbtest`, `serialize_wbtest`, `deserialize_wbtest`, `diagnostics_json_wbtest` in `src/lux/`) + blackbox (`lux_test`, `from_json_error_test` in `src/lux/test/`) — extensive
- **sdk**: Cross-protocol (`cross_protocol_test`), convert matrix (`convert_matrix_test`), registry (`provider_registry_wbtest`), integration (`sdk_test`, `convert_test`) — blackbox in `src/sdk/test/`
- **provider/\***: Each adapter has whitebox `_wbtest` (package dir) + blackbox `_test` (`test/` subpackage)
- **wasm**: `wasm_test` covering all exports (in `src/wasm/test/`)
- **internal**: Coverage in `internal/test/` subdirectory

## Known Limitations

- `scripts/check_schema_drift.ps1` runs in report mode by default and can be used with `-Strict` in CI; its self-test covers version, required fields, enums, and stream events

- `src/lux/types.mbt` remains the type/model hub; codec implementations are split into request/response/stream/primitive files (deserialization further split: `deserialize_helpers` / `deserialize_primitives` / `deserialize_content` / `deserialize_tools` / `deserialize_options`); diagnostics JSON codec lives in `diagnostics_json.mbt`. Package navigation: `src/lux/README.md` and `src/sdk/README.md` provide per-package file maps and dependency rules (MoonBit folders = packages, so intra-package organization uses prefixes + partition comments + index READMEs, iteration-007)
- Provider adapters use a uniform file layout: capability / request_decode / request_encode / response / stream_decode / stream_encode
- JSON Schema (`schemas/lux-ir-v1.json`) remains manually authored, but `scripts/check_schema_drift.ps1` now reports version/required-field/enum/stream-event drift

- `src/internal/sse.mbt` exports `parse_sse_frame` — shared SSE preprocessing pipeline used by messages, openai, and gemini stream decoders
- `src/internal/json.mbt` exports JSON field access (`obj_get` / `field_*`) and basic tools (`json_escape` / `parse_string_array` / `parse_content_polymorphic` / …); `extras.mbt` exports `collect_extra_fields` / `merge_extras_json` / `extras_without`; `usage.mbt` exports `parse_usage_json` / `parse_reasoning_tokens` / `parse_cached_tokens` / `parse_cache_creation_tokens` / `parse_cached_tokens_gemini` — shared helpers used by all four providers
- `src/lux/stream.mbt` exports `BlockAccumulator` (package-internal) — extracted from the 290-line stream accumulator function
- `src/lux/helpers.mbt` exports `LucentReasoningEffort::to_string` — outbound effort tier mapping shared by openai / messages / responses (gemini keeps its own downgrade mapping)

## IR Evolution Backlog (from 2026-09 protocol audit)

Items identified by the cross-protocol conversion audit (context-continuation
and tool-pairing focus). Adapter-level mitigations are in place; IR-level
carriers are pending governance per `docs/rules/lucent-ir-evolution.md`:

- **ToolResult name carrier**: `LucentToolResult` has only `tool_use_id`;
  Gemini `functionResponse.name` requires the function name, so encoders
  pre-scan `ToolCall` items to rebuild the id→name map (see
  `src/provider/gemini/request_encode.mbt` `build_tool_name_map`). An IR
  carrier would remove the scan and handle orphan tool results cleanly.
- **Reasoning continuation credential side-channel**: Responses
  `reasoning.encrypted_content` (stateless reasoning continuation) has no IR
  carrier; decode emits a Degraded diagnostic instead of preserving it.
- **ReasoningEffort `Minimal` tier**: OpenAI `reasoning_effort: "minimal"`
  (gpt-5 family) degrades to `Low` with a diagnostic; Anthropic `"max"`
  degrades to `XHigh`.
- **parallel_tool_calls as a standard option**: currently exchanged via the
  `extras` map with semantic inversion per target (`parallel_tool_calls` ↔
  `disable_parallel_tool_use`); both directions are tested.

## Build & Verify

```bash
moon fmt --check
moon check --warn-list +73 --deny-warn
moon test                      # native + wasm-gc
```
