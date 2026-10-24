# Project Guide

This is a [MoonBit](https://docs.moonbitlang.com) project.

## Overview

Prism implements a neutral intermediate protocol — the **Lucent IR** (a.k.a.
Lux IR) — that decouples AI agent frameworks and transit middleware from
vendor-specific API formats. Any wire format is first decoded into the IR, then
encoded out to the target; there are never pairwise converters between
providers:

```
OpenAI JSON  ──[decode]──►  Lucent IR  ──[encode]──►  Anthropic JSON
Gemini JSON  ◄──[encode]──  Lucent IR  ◄──[decode]──  OpenAI JSON
                                │
                   your code here (audit / rewrite / route / filter)
```

You can browse and install extra MoonBit skills here:
<https://github.com/moonbitlang/skills>

## Repository layout

- `src/lux/` — Lucent IR core: types, serialization, diagnostics, stream events
  (no IO, no vendor binding).
- `src/provider/` — one package per wire protocol: `openai` (Chat Completions),
  `responses` (OpenAI Responses), `messages` (Anthropic Messages, incl.
  extended thinking), `gemini` (Google Gemini); `meta` holds provider metadata
  shared by the registry.
- `src/sdk/` — `Prism` facade + provider registry + routing + Context building
  (the single convergence point).
- `src/internal/` — shared primitives: JSON field access, SSE frame parsing,
  extras merging.
- `src/wasm/` + `src/cmd/main/` — WASM string-ABI exports (String in/out, zero
  provider coupling).
- `src/conformance/` — protocol conformance checkers (test toolkit).
- `schemas/` — JSON Schema, the source of truth for the protocol.

## Two consumer types

| Role | Providers used | Flow |
|---|---|---|
| Agent framework SDK | 1 provider | `Lux → ProviderA` (send) + `ProviderA → Lux` (receive) |
| Transit middleware | 2+ providers | `PA → Lux → PB`, or `PA → Lux → PA` (audit/filter/throttle) |

Both consume `src/lux/` as the common language and `src/provider/*` as
translators — an SDK usually bundles one provider, middleware bundles N.

## Architecture layers

1. Core (MoonBit) — `src/lux/`
2. Adapters — `src/provider/*`
3. SDK — `Prism` facade + registry (`src/sdk/`)
4. Transport — `src/wasm/` / HTTP / IPC (future)
5. Framework integration — LangChain, CrewAI, etc. (future)

## MoonBit project structure

- Each directory is a MoonBit package with a `moon.pkg` file listing its
  dependencies.
- Tests: blackbox tests (`*_test.mbt`, public API only) live in a dedicated
  `test/` subpackage per package (`import { "<pkg>", ... } for "test"`,
  precedent: `src/internal/test/`); whitebox tests (`*_wbtest.mbt`) must stay
  in the tested package directory — MoonBit compiles them into the package so
  they can reach non-public members (verified: moving them to a `test/`
  subpackage breaks private access).
- Toplevel `moon.mod` holds module metadata.

## Context & Planning

When starting work on this project, read these in order to restore context:

- `docs/status.md` — current project status, test inventory, module completion,
  and known limitations (**best single entry point**; updated every iteration).
- `docs/README.md` — index of all formal docs (architecture / IR spec /
  conversion contract / fidelity matrix / CRs / rules).
- `docs/architecture.md` — layered design + `Current decisions` (declined
  splits, registry model, navigation-instead-of-folders), the source of truth
  for design decisions.
- `docs/rules/lucent-ir-evolution.md` — mandatory governance before changing
  any Lucent IR field, enum variant, stream event, capability, or payload.

Optional agent workspace (gitignored, created on demand — do NOT assume these
exist):

- `.agent-workplace/` — `docs/plan/`, `docs/spec/`, `docs/task/`, `docs/report/`
  (mode outputs), `research/`, `scratch/`; `state/checkpoint.json` and
  `shared/architecture.md` are written only by flows that use them. A previous
  convention referenced `.moonbit-pipeline.json` (repo root) and
  `modes/README.md` as session checkpoints; neither is present in this
  snapshot — restore context from the docs above instead.

Progress convention: one feature per commit, commit after each task, pass
`moon fmt --check` / `moon check` / `moon test` before committing. Once a task
has passed acceptance verification (its acceptance checklist is fully green),
the agent may commit to git on its own — no need to ask the user first.

## Coding convention

- MoonBit code is organized in block style, each block is separated by `///|`,
  the order of each block is irrelevant. In some refactorings, you can process
  block by block independently.

- Try to keep deprecated blocks in file called `deprecated.mbt` in each
  directory.

### MoonBit gotchas (each of these has actually cost a build in this repo)

- **Never** write `fn f() -> T = "a string"`. A string function body is parsed as
  INLINE WASM, not a return value. Always use braces: `fn f() -> String { "x" }`.
- Any helper that calls `fail(...)` must declare `raise`:
  `fn f(x : String) -> Unit raise` / `fn f(x : String) -> T raise`.
- String interpolation `\{x}` routes through `Show`. Arrays and structs have no
  non-deprecated `Show` — interpolating one trips a deprecation warning. Only
  interpolate `String` and `Int` (e.g. into `fail` messages).
- Qualified enum annotations like `@lux.LucentToolChoice::None`,
  `@lux.LucentBlockType::Text`, `@lux.LucentFinishReason::Stop`,
  `@lux.LucentReasoningConfig::disabled()` are **rejected by
  `--warn-list +73 --deny-warn`** (unnecessary_annotation). Write the bare
  constructor and let inference resolve it. When the value is ambiguous (e.g.
  `LucentToolChoice::None` vs `Option::None`), the spelling that passes is
  `assert_eq(x.tool_choice, Some(None))`.
  In an array literal, keep the qualification on the FIRST element to pin the
  type and use bare constructors afterwards.
- In array literals, a later `@lux.LucentStreamEvent::Done` trips warning 73 once
  the type is already pinned — write bare `Done`.
- Map literal **values cannot contain method calls**: `{ "k": 30.to_json() }` is
  a parse error. Use factories: `Json::boolean(true)`, `Json::string(...)`.
- `for a, b in coll` yields `(index, element)`, NOT tuple destructuring. To walk
  an `Array[(A, B)]` use `for pair in coll { pair.0 / pair.1 }`. Also, a `for`
  loop takes at most 2 loop variables.
- In a `test/` subpackage, imported type names must be qualified in annotation
  position too (`@lux.LucentReasoningEffort`, not `LucentReasoningEffort`).
- `Char::from_int` is deprecated — use `Byte::to_char` / `Int::to_char`.
- `extend` accepts only `pub`, never `pub(all)`.
- Feeding a malformed JSON *string* to `@json.parse` makes it **raise**, which
  aborts a test with an unhandled exception instead of returning `Err`. When a
  test asserts rejection, build a **syntactically valid but semantically wrong**
  document and assert on the `Result`.

### Verifying coverage honestly

- `moon coverage analyze > cov.txt` from PowerShell writes a **UTF-16** file that
  many tools refuse as binary; convert before grepping.
- The report's hunk separator is a `…` that PowerShell redirection can mangle, so
  never key parser logic on it. A separator-agnostic extractor lives at
  `.agent-workplace/scratch/extract-uncovered.ps1`.
- `moon test -p <pkg>` scopes a run to one package and avoids compiling every
  other package — use it while iterating. Note the subpackage spelling:
  `-p morning-start/prism/lux` is the whitebox package,
  `-p morning-start/prism/lux/test` is its blackbox test package, and
  `moon test -f "<glob>"` is a FULL-NAME glob (needs the surrounding `*`).
- Bump coverage claims with a fresh `moon coverage analyze`; other packages'
  tests can already cover a line you think is open.

## Lucent IR evolution

- Before adding or changing any Lucent IR field, enum variant, tool model,
  stream event, capability, request extension, or response payload, read and
  follow [`docs/rules/lucent-ir-evolution.md`](docs/rules/lucent-ir-evolution.md).
- Every Lucent IR proposal MUST identify whether it affects protocol conversion,
  SDK/Agent consumption, or both. Conversion fidelity and explicit
  `Exact`/`Degraded`/`Unsupported` boundaries are hard gates; SDK ergonomics are
  evaluated only after those gates pass.
- Treat `docs/lux-ir-design.md` as the current formal schema specification and
  `docs/rules/lucent-ir-evolution.md` as the mandatory governance process for
  evolving that specification. Do not change one without reconciling the other.

## Field classification: standard vs extension

Every IR field (request, response, stream event, capability, or payload) belongs
to exactly one of two classes:

- **Standard fields** — defined by the official spec (`docs/lux-ir-design.md`,
  `schemas/lux-ir-v1.json`). Their required/optional status is fixed by the spec,
  and every provider target must support them.
- **Extension fields** — third-party / provider-specific (e.g. `extra`,
  `Native`, `provider_payload`). They carry data outside the official spec and
  are NOT guaranteed to be supported by any given target.

Hard rules:

- Extension fields MUST always be optional: nullable (`T?`) or an empty-by-default
  map. Never introduce a required extension field — a target provider may not
  support it.
- Deserialization must never fail because an extension field is missing or unknown;
  conversion must degrade gracefully (drop, or preserve via `extra` /
  `provider_payload` / diagnostics) instead of erroring.
- Changing a standard field's required status, or adding a new required standard
  field, is a breaking change — follow `docs/rules/lucent-ir-evolution.md` first.
- Preserve unknown extension data where practical instead of silently discarding it.

## Protocol conversion (hub)

Prism converts between the Lucent IR and the supported wire protocols — the
formal 3-endpoint contract covers OpenAI `/v1/chat/completions`, OpenAI
`/v1/responses`, and Anthropic `/v1/messages` (Google Gemini is supported as a
fourth adapter). Adapters live under `src/provider/<name>/`, each implementing
the same 6-function encode/decode contract (request / response / stream ×
decode / encode — see `docs/provider-guide.md`).

Design principles:

- **Round-trip safety**: Provider → Lux → Provider must preserve all semantics.
- **JSON Schema as source of truth**: `schemas/lux-ir-v1.json` defines the
  protocol; MoonBit is one reference implementation.
- **`extra` / `provider_payload`** are the safety valves for provider-specific
  fields.
- **Provider adapters are pure functions**: `ext_to_lux_request` /
  `lux_request_to_ext` — zero side effects, testable in isolation.

Conversion rules (details: `docs/api-protocol-converter.md` — the formal
3-endpoint conversion contract; research notes in
`.agent-workplace/research/api-protocol-converter/`):

- Normalize into the IR first, then encode IR → target endpoint. Never write
  pairwise converters between providers.
- External side is always the client's expected format; internal side is always
  the target API's native format.
- Unsupported capabilities MUST fail explicitly (`Exact`/`Degraded`/`Unsupported`),
  never silently drop data.
- Implement the common intersection first (text, tool calls, streaming), then
  extend advanced capabilities.
- Streaming conversion must maintain: content block index, tool call index,
  accumulated partial JSON arguments, and current stop reason.
- Provider-specific experimental features (thinking, server tools, audio, ...)
  are extension fields: optional, never required (see Field classification above).
- Before claiming "3-endpoint interop", pass the 12-case minimum test matrix in
  `docs/api-protocol-converter.md`.

## Tooling

- `moon fmt` is used to format your code properly.

- `moon ide` provides project navigation helpers like `peek-def`, `outline`, and
  `find-references`. See $moonbit-agent-guide for details.

- `moon info` is used to update the generated interface of the package, each
  package has a generated interface file `.mbti`, it is a brief formal
  description of the package. If nothing in `.mbti` changes, this means your
  change does not bring the visible changes to the external package users, it is
  typically a safe refactoring.

- In the last step, run `moon info && moon fmt` to update the interface and
  format the code. Check the diffs of `.mbti` file to see if the changes are
  expected.

- Run `moon test` to check tests pass (native + wasm-gc). MoonBit supports
  snapshot testing; when changes affect outputs, run `moon test --update` to
  refresh snapshots.

- Prefer `assert_eq` or `assert_true(pattern is Pattern(...))` for results that
  are stable or very unlikely to change. For snapshot tests that record
  structured debugging output, derive `Debug` and use `debug_inspect`, rather
  than deriving `Show` for debugging. For solid, well-defined results (e.g.
  scientific computations), prefer assertion tests. You can use
  `moon coverage analyze > uncovered.log` to see which parts of your code are
  not covered by tests.


<!-- headroom:rtk-instructions -->
# RTK (Rust Token Killer) - Token-Optimized Commands

When running shell commands, **always prefix with `rtk`**. This reduces context
usage by 60-90% with zero behavior change. If rtk has no filter for a command,
it passes through unchanged — so it is always safe to use.

## Key Commands
```bash
# Git (59-80% savings)
rtk git status          rtk git diff            rtk git log

# Files & Search (60-75% savings)
rtk ls <path>           rtk read <file>         rtk grep <pattern>
rtk find <pattern>      rtk diff <file>

# Test (90-99% savings) — shows failures only
rtk pytest tests/       rtk cargo test          rtk test <cmd>

# Build & Lint (80-90% savings) — shows errors only
rtk tsc                 rtk lint                rtk cargo build
rtk prettier --check    rtk mypy                rtk ruff check

# Analysis (70-90% savings)
rtk err <cmd>           rtk log <file>          rtk json <file>
rtk summary <cmd>       rtk deps                rtk env

# GitHub (26-87% savings)
rtk gh pr view <n>      rtk gh run list         rtk gh issue list

# Infrastructure (85% savings)
rtk docker ps           rtk kubectl get         rtk docker logs <n>

# Package managers (70-90% savings)
rtk pip list            rtk pnpm install        rtk npm run <script>
```

## Rules
- In command chains, prefix each segment: `rtk git add . && rtk git commit -m "msg"`
- For debugging, use raw command without rtk prefix
- `rtk proxy <cmd>` runs command without filtering but tracks usage
<!-- /headroom:rtk-instructions -->
