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
  Splitting it was measured in iteration-004 (`.agent-workplace/research/iteration-008/lux-split-feasibility.md`):
  serialize/deserialize define 70 inherent methods (`Type::method`), which MoonBit
  requires to stay in the type's package, and struct fields are intentionally
  non-public — splitting would force trait/top-level-function rewrites across
  800+ external call sites and a large public-API expansion, so **the split is
  declined**; the per-file codec split (serialize_*/deserialize_*) remains the
  structural boundary.
- Navigation instead of folders: re-audited in iteration-007 — every lux/sdk
  source file carries inherent methods bound to package-local types, so any
  sub-folder would create a sub-package and break same-package method rules
  (or introduce package cycles). Package-internal organization therefore uses
  **file-name prefixes + partition comments + per-package `README.md` indexes**
  (`src/lux/README.md`, `src/sdk/README.md`) as the navigation layer instead of
  nested directories.
- Nested feature sub-packages are not viable (re-audited in iteration-007):
  "big package calls small feature packages" is the wrong dependency direction —
  MoonBit package dependencies are acyclic, and every feature that could be
  extracted (serialize/deserialize/diagnostics) depends on the parent package's
  types, so `lux → lux/serialize → lux` would be a cycle. The only legal
  sub-package direction is leaf → parent (e.g. `test/` sub-packages). Shared
  base utilities live in the sibling `src/internal` package (leaf, core-only
  deps), already consumed by all four providers; lux's internal `get_*` helpers
  have zero external consumers, so sinking them to `internal` would be churn
  without benefit.
- The "common protocol package" already exists (iteration-008): `src/lux`
  provides the shared IR types plus their `to_json`/`from_json`
  (serialize_*/deserialize_*), stream events and diagnostics; `src/internal`
  provides the shared JSON/extras/usage/SSE utilities. The four provider
  adapters are thin "protocol JSON ↔ IR" layers over these. Trait-ifying the
  6-function contract was evaluated and declined: the contract is already an
  implicit interface (identical signatures across packages, verified in
  `.mbti`), the SDK is a static composition root with no runtime polymorphism
  need, and trait conversion would break the public API for no benefit.
  Remaining provider-side near-duplicates (usage field names, tool-definition
  wrappers, error codes, stream event names) are protocol-semantic differences
  and must stay in each adapter; genuinely identical helpers keep landing in
  `src/internal`.
- Trait-ification of the 6-function contract re-confirmed declined (iteration-008,
  user decision): the SDK already dispatches through the `ProviderRegistration`
  struct's **function fields** (`(src.response_decode)(json_str)` in
  `src/sdk/convert.mbt`) — a function-table that already achieves the same
  "unified interface" a `trait Codec` would provide, and it is bound at compile
  time (static composition root), so a trait's polymorphism/bounds benefit has
  no consumer. Adding `trait Codec` + 4 adapter structs + 24 forwarding impls
  would be pure ceremony with double-maintenance (top-level functions must stay
  for the public API). Clarity is already provided by `.mbti`, registration
  field comments, and `docs/api-protocol-converter.md`.
- Provider adapters were split from monolithic files into request, response, stream, and capability units without changing package names or function signatures.
- SDK remains the static provider composition root; a dedicated registry
  package was measured in iteration-005 (`.agent-workplace/research/iteration-008/sdk-split-feasibility.md`):
  its 36 inherent methods (`Prism::*` etc.) must stay in the type's package and
  struct fields are intentionally non-public, so **the split is declined** —
  same conclusion as the lux measurement. Type definitions plus their methods
  (including registration/serialization logic) form a non-splittable unit in
  MoonBit; per-file organization is the structural boundary.
- Model fallback is deterministic by pattern specificity and registration order; overlapping patterns require registry tests.

## Migration plan

1. Keep the public API stable and validate the file-level adapter split.
2. Add registry tests for alias normalization, overlapping model patterns, and unknown providers.
3. Extract shared content and tool helpers only after exact JSON regression coverage exists.
4. Evaluate a dedicated registry package and split lux package using .mbti diffs as compatibility gates.
5. Keep WASM exports stable and require wrapper integration tests for new exports.

## Verification

Run moon fmt --check, moon check --warn-list +73 --deny-warn, native and wasm-gc tests, TypeScript client and integration tests, and git diff --check.
