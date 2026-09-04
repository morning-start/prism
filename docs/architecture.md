# Prism Architecture

## Goals

Prism converts provider-specific JSON and SSE protocols through a stable Lucent IR and exposes the same capabilities through the MoonBit SDK, WASM ABI, and TypeScript wrapper. The architecture prioritizes conversion fidelity, explicit degradation diagnostics, and a small host-facing boundary.

## Layered dependency graph

`	ext
cmd/main (WASM exports only)
    -> wasm (string ABI envelope and error boundary)
        -> sdk (user facade and conversion orchestration)
            -> provider adapters (protocol codecs)
                -> lux (Lucent IR, diagnostics, stream model)
                    -> internal (JSON and SSE primitives)
`

The dependency direction is one-way. Provider adapters may depend on lux and internal; lux must not depend on a provider. WASM must not contain provider-specific protocol mapping.

## Package responsibilities

- src/lux: stable Lucent IR types, stream events, capabilities, and conversion diagnostics.
- src/internal: non-public JSON and SSE parsing and escaping primitives.
- src/provider/*: one adapter per wire protocol implementing request, response, and stream encode/decode.
- src/sdk: public facade, static provider registry, matching, and decode-to-IR-to-encode orchestration.
- src/wasm: ABI-safe string entry points, envelopes, and error boundaries.
- src/cmd/main: exports only; no protocol or business logic.

## Provider adapter layout

Each adapter keeps its public API unchanged while separating responsibilities into files:

- `request_decode.mbt`: request JSON -> LucentRequest
- `request_encode.mbt`: LucentRequest -> request JSON
- `response.mbt`: response decode/encode
- `stream_decode.mbt`: provider SSE -> LucentStreamEvent
- `stream_encode.mbt`: LucentStreamEvent -> provider SSE
- `capability.mbt`: capability declaration

All four adapters (openai / messages / responses / gemini) share this layout.
MoonBit compiles all files in a package together, so this is a structural boundary without runtime indirection or API churn.

## Test organization

- Blackbox tests (`*_test.mbt`, public API only) live in a dedicated `test/`
  subpackage per package (`import { "<pkg>", ... } for "test"`), following the
  `internal/test` precedent.
- Whitebox tests (`*_wbtest.mbt`) must stay in the tested package directory:
  MoonBit compiles them into the package so they can reach non-public members;
  moving them to a `test/` subpackage breaks that access (verified experimentally).
- `examples/*` keep their own whitebox tests in place.

## Registry and conversion pipeline

The SDK registry is a static composition root because the WASM target does not require dynamic loading. ProviderRegistration stores codec functions, aliases, model patterns, and capabilities. Resolution is exact name, alias, then model-pattern fallback. Conversion is always source decode -> Lucent IR -> target encode; diagnostics from both phases are merged. No adapter-to-adapter conversion path is allowed.

## Stream pipeline

SSE is normalized by the shared internal parser before provider conversion. CRLF, CR, and LF line endings are supported. Adapters interpret payloads and emit Lucent stream events; only the target adapter serializes target SSE.

## Diagnostics and fidelity

Unsupported or degraded mappings must be represented by conversion diagnostics instead of silently dropping data. Convenience APIs may return only the value for compatibility, while trace APIs preserve diagnostics. Any IR field or event change must update the IR design and checklist and add cross-provider regression tests.

## WASM ABI and wrappers

The ABI is a string-in/string-out boundary. cmd/main owns export names; wasm owns scratch-memory and envelope mechanics; sdk owns conversion semantics. Generated .mbti files are part of public API review.

## Current decisions

- The Lucent package remains a single protocol-neutral core package.
  Splitting it was measured in iteration-004 (`docs/report/lux-split-feasibility.md`):
  serialize/deserialize define 70 inherent methods (`Type::method`), which MoonBit
  requires to stay in the type's package, and struct fields are intentionally
  non-public — splitting would force trait/top-level-function rewrites across
  800+ external call sites and a large public-API expansion, so **the split is
  declined**; the per-file codec split (serialize_*/deserialize_*) remains the
  structural boundary.
- Provider adapters were split from monolithic files into request, response, stream, and capability units without changing package names or function signatures.
- SDK remains the static provider composition root for now. A dedicated registry package requires a compatibility plan for the public ProviderRegistration type.
- Model fallback is deterministic by pattern specificity and registration order; overlapping patterns require registry tests.

## Migration plan

1. Keep the public API stable and validate the file-level adapter split.
2. Add registry tests for alias normalization, overlapping model patterns, and unknown providers.
3. Extract shared content and tool helpers only after exact JSON regression coverage exists.
4. Evaluate a dedicated registry package and split lux package using .mbti diffs as compatibility gates.
5. Keep WASM exports stable and require wrapper integration tests for new exports.

## Verification

Run moon fmt --check, moon check --warn-list +73 --deny-warn, native and wasm-gc tests, TypeScript client and integration tests, and git diff --check.
