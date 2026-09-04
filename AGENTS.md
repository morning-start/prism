# Project Guide

This is a [MoonBit](https://docs.moonbitlang.com) project.

## Project Structure

- Each directory is a MoonBit package with a `moon.pkg` file listing its
  dependencies.
- Tests: blackbox tests (`*_test.mbt`, public API only) live in a dedicated
  `test/` subpackage per package (`import { "<pkg>", ... } for "test"`,
  precedent: `src/internal/test/`); whitebox tests (`*_wbtest.mbt`) must stay
  in the tested package directory — MoonBit compiles them into the package so
  they can reach non-public members (verified: moving them to a `test/`
  subpackage breaks private access).
- Toplevel `moon.mod` holds module metadata.

## Context & Planning (flowstate)

When starting work, restore context from, in order:

- `.agent-workplace/` — private workspace (gitignored): `docs/plan/`,
  `docs/task/`, `docs/report/`, `shared/architecture.md`,
  `state/checkpoint.json`
- `.moonbit-pipeline.json` — session checkpoint (phase, plan pointer, progress)
- `docs/architecture.md` — source of truth for design decisions
- `docs/status.md` — project status and module completion tracking
- `docs/rules/lucent-ir-evolution.md` — governance for Lucent IR changes

Progress convention: one feature per commit, commit after each task, pass
`moon fmt --check` / `moon check` / `moon test` before committing. Once a
task passes acceptance verification, the agent may commit on its own.

## Coding convention

- MoonBit code is organized in block style, each block separated by `///|`;
  block order is irrelevant, and refactorings can process block by block.
- Keep deprecated blocks in `deprecated.mbt` in each directory.

## Lucent IR evolution

- Before changing any Lucent IR field, enum variant, tool model, stream event,
  capability, request extension, or response payload, read and follow
  [`docs/rules/lucent-ir-evolution.md`](docs/rules/lucent-ir-evolution.md).
- Every proposal MUST state whether it affects protocol conversion, SDK/Agent
  consumption, or both. `Exact`/`Degraded`/`Unsupported` fidelity boundaries
  are hard gates; SDK ergonomics come after.
- `docs/lux-ir-design.md` is the formal schema spec; the evolution rule above
  governs it. Never change one without reconciling the other.

## Field classification: standard vs extension

Every IR field is one of:

- **Standard** — defined by the official spec (`docs/lux-ir-design.md`,
  `schemas/lux-ir-v1.json`); required/optional status is fixed and every
  provider must support them.
- **Extension** — third-party / provider-specific (e.g. `extra`, `Native`,
  `provider_payload`); not guaranteed to be supported by any target.

Hard rules:

- Extension fields MUST always be optional (`T?` or empty-by-default map).
- Deserialization must never fail on a missing/unknown extension field; degrade
  gracefully (drop, or preserve via `extra`/`provider_payload`/diagnostics).
- Changing a standard field's required status, or adding a required standard
  field, is a breaking change — follow the IR evolution governance first.
- Preserve unknown extension data where practical.

## Protocol conversion (3-endpoint hub)

Prism converts between the Lucent IR and three wire protocols — OpenAI
`/v1/chat/completions`, `/v1/responses`, and Anthropic `/v1/messages`.
Adapters live under `src/provider/<name>/` (see `docs/provider-guide.md`).

Rules (details: `docs/api-protocol-converter.md` — the formal 3-endpoint
conversion contract; research notes in
`.agent-workplace/research/api-protocol-converter/`):

- Normalize into the IR first, then encode IR → target; never pairwise
  converters between providers.
- External side is the client's expected format; internal side is the target
  API's native format.
- Unsupported capabilities MUST fail explicitly, never silently drop data.
- Implement the common intersection first (text, tool calls, streaming).
- Streaming conversion maintains: content block index, tool call index,
  partial JSON, and stop reason.
- Provider-specific experimental features (thinking, server tools, audio, ...)
  are extension fields: optional, never required.
- Before claiming "3-endpoint interop", pass the 12-case minimum test matrix
  in `docs/api-protocol-converter.md`.

## Tooling

- `moon fmt` — formats code.
- `moon ide` — navigation helpers (`peek-def`, `outline`, `find-references`).
- `moon info` — updates the generated `.mbti` interface per package; no diff
  means a safe refactoring.
- Last step: run `moon info && moon fmt` and check `.mbti` diffs are expected.
- `moon test` — run tests; use `moon test --update` to refresh snapshots.
- Prefer `assert_eq` / `assert_true(pattern is ...)` for stable results; derive
  `Debug` + `debug_inspect` (not `Show`) for snapshot-style debugging output.
  `moon coverage analyze > uncovered.log` shows uncovered code.


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
rtk docker ps           rtk kubectl get         rtk docker logs <c>

# Package managers (70-90% savings)
rtk pip list            rtk pnpm install        rtk npm run <script>
```

## Rules
- In command chains, prefix each segment: `rtk git add . && rtk git commit -m "msg"`
- For debugging, use raw command without rtk prefix
- `rtk proxy <cmd>` runs command without filtering but tracks usage
<!-- /headroom:rtk-instructions -->
