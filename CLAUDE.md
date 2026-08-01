# Project Agents.md Guide

This is a [MoonBit](https://docs.moonbitlang.com) project.

You can browse and install extra skills here:
<https://github.com/moonbitlang/skills>

## Project Structure

- MoonBit packages are organized per directory; each directory contains a
  `moon.pkg` file listing its dependencies. Each package has its files and
  blackbox test files (ending in `_test.mbt`) and whitebox test files (ending in
  `_wbtest.mbt`).

- In the toplevel directory, there is a `moon.mod` file listing module
  metadata.

## Planning & Task Documents

When starting work on this project, read these in order to restore context:

- `docs/plans/` — roadmap-style planning only (e.g. `2026-08-01-project-roadmap.md`).
  Do NOT put task breakdowns here.
- `docs/tasks/` — task breakdown documents (per-phase implementation plans).
  Task breakdowns MUST go here, not in `docs/plans/`.
- `.moonbit-pipeline.json` — pipeline state (current phase, plan file pointer,
  task progress). Use it as the session checkpoint.
- `docs/requirements.md` — dual-scenario architecture requirements (IR hub +
  developer SDK / relay server), the source of truth for design decisions.
- `docs/rules/lucent-ir-evolution.md` — mandatory governance before changing
  any Lucent IR field, enum variant, stream event, capability, or payload.

Progress convention: one feature per commit, commit after each task, pass
`moon fmt --check` / `moon check` / `moon test` before committing.

## Coding convention

- MoonBit code is organized in block style, each block is separated by `///|`,
  the order of each block is irrelevant. In some refactorings, you can process
  block by block independently.

- Try to keep deprecated blocks in file called `deprecated.mbt` in each
  directory.

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

- Run `moon test` to check tests pass. MoonBit supports snapshot testing; when
  changes affect outputs, run `moon test --update` to refresh snapshots.

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
rtk docker ps           rtk kubectl get         rtk docker logs <c>

# Package managers (70-90% savings)
rtk pip list            rtk pnpm install        rtk npm run <script>
```

## Rules
- In command chains, prefix each segment: `rtk git add . && rtk git commit -m "msg"`
- For debugging, use raw command without rtk prefix
- `rtk proxy <cmd>` runs command without filtering but tracks usage
<!-- /headroom:rtk-instructions -->
