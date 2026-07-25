# Prism Context

## Overview

Prism is a neutral intermediate protocol (Lux IR / Lucent IR) that decouples
AI agent frameworks and transit middleware from vendor-specific API formats.

## Architecture

```
prism/
  lux/           ← Lucent IR protocol definition, serialization, tests
  provider/      ← Bidirectional converters: ext ⇄ Lux
  schemas/       ← JSON Schema (source of truth)
  wasm/          ← WASM transport layer
```

## Two Consumer Types

| Role | Providers Used | Flow |
|---|---|---|
| Agent Framework SDK | 1 provider | `Lux → ProviderA` (send) + `ProviderA → Lux` (receive) |
| Transit Middleware | 2+ providers | `PA → Lux → PB` or `PA → Lux → PA` (audit/filter/throttle) |

Both consume `lux/` as the common language and `provider/*` as translators —
SDK usually bundles one provider, middleware bundles N.

## Work State

All 191 tests pass. Key milestones:

- **Serialization**: All 34+ Lux IR types have `to_json()` — 73 serialize tests pass.
- **Deserialization**: All 34+ Lux IR types have `from_json()` — now compiles and passes round-trip tests.
- **Round-trip tests**: 31 round-trip tests verify `construct → to_json → from_json → assert_eq` for all types.
- **Bug fixes applied**:
  - `LucentMediaSource::to_json` now returns `Json` object `{"type":"...","data":"..."}` preserving payload data (was returning bare string, discarding data).
  - `LucentFinishReason::from_string("safety"/"SAFETY")` correctly maps to `Safety` variant (was incorrectly returning `ContentFilter`).
- **Schema**: `schemas/lux-ir-v1.json` exists but needs `native` extension variants backfilled.

## Design Principles

- **Round-trip safety**: Provider → Lux → Provider must preserve all semantics
- **JSON Schema as source of truth**: `schemas/lux-ir-v1.json` defines the
  protocol; MoonBit is one reference implementation
- **`extra` / `provider_payload`** as safety valves for provider-specific fields
- **Provider adapters are pure functions**: `ext_to_lux_request` /
  `lux_request_to_ext` — zero side effects, testable in isolation

## Layer Model

1. Core (MoonBit) — `lux/`
2. Transport — WASM / HTTP / IPC (future)
3. SDK — auto-generated from schema (future)
4. Framework Integration — LangChain, CrewAI, etc. (future)
