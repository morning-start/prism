# @morning-start/prism-wasm

TypeScript wrapper for the [Prism](https://github.com/morning-start/prism) wasm
artifact: cross-protocol LLM **request / response / stream** conversion
(OpenAI ⇄ Anthropic Messages ⇄ OpenAI Responses ⇄ Gemini) over the neutral
Lucent IR, running fully in-process via WebAssembly.

- **Zero runtime dependencies** — the only input is the `.wasm` artifact bytes.
- **Typed diagnostics** — every `Exact` / `Degraded` / `Unsupported` / `Invalid`
  decision made during conversion is surfaced, never swallowed.
- **ABI-locked** — load fails fast (`MISSING_EXPORT` / `ABI_MISMATCH`) when the
  artifact drifts from the 29-export ABI the wrapper binds.
- Requires **Node ≥ 22** (wasm-gc + js-string builtins are enabled by default).

## Install

```bash
npm install @morning-start/prism-wasm
```

You need a Prism wasm-gc artifact. Build it from the repo root:

```bash
moon build --target wasm-gc
# → _build/wasm-gc/release/build/cmd/main/main.wasm
```

## Quick start

```typescript
import { loadPrism } from "@morning-start/prism-wasm";
import { readFileSync } from "node:fs";

const client = await loadPrism(readFileSync("main.wasm"));

// Request conversion: OpenAI Chat Completions → Anthropic Messages
const result = client.convertRequest(
  "openai",
  JSON.stringify({
    model: "gpt-4o-mini",
    max_tokens: 1024,
    messages: [{ role: "user", content: "hello" }],
  }),
  "messages",
);
console.log(result.value);       // Anthropic /v1/messages request JSON
console.log(result.diagnostics); // [] — Exact conversion, nothing dropped
```

## Streaming

Feed source chunks as they arrive; collect the target SSE frames each call
returns. `finish()` flushes the trailing half-frame — call it in a `finally`
block (termination contract CR-002). `free()` is idempotent.

```typescript
const session = client.createStream("openai", "messages");
try {
  for await (const chunk of upstreamSSE) {
    for (const frame of session.feed(chunk)) {
      process.stdout.write(frame); // ready-to-forward Anthropic SSE frames
    }
  }
} finally {
  for (const frame of session.finish()) process.stdout.write(frame);
  session.free();
}
```

Incremental guarantee: concatenating `feed()` + `finish()` output equals
`convertStream()` over the same input — verified by the integration suite.

## Diagnostics & error handling

The wrapper never swallows anything: diagnostics pass through verbatim, and
every failure becomes a thrown `PrismError` with a stable `code`.

```typescript
import { loadPrism, PrismError } from "@morning-start/prism-wasm";

// max_tokens omitted → the messages target backfills 4096 as Degraded
const degraded = client.convertRequest(
  "openai",
  JSON.stringify({ model: "gpt-4o-mini", messages: [{ role: "user", content: "hi" }] }),
  "messages",
);
for (const d of degraded.diagnostics) {
  console.log(`${d.status}: ${d.field} — ${d.detail}`); // e.g. degraded: max_tokens — ...
}

try {
  client.convertRequest("nonexistent", "{}", "messages");
} catch (err) {
  if (err instanceof PrismError) {
    // err.code: LOAD_FAILED | MISSING_EXPORT | ABI_MISMATCH
    //          | ENVELOPE_INVALID | CONVERSION_ERROR | SESSION_STATE
    console.error(err.code, err.message);
  }
}
```

Error codes:

| Code | Meaning |
|---|---|
| `LOAD_FAILED` | Host engine rejected the artifact (Node < 22, missing js-string builtins, corrupt bytes). |
| `MISSING_EXPORT` | Artifact lacks part of the 29-export ABI (build drift). |
| `ABI_MISMATCH` | `wasm_abi_version` ≠ expected (default `"1"`; pass `{ expectedAbi }` to pin differently). |
| `ENVELOPE_INVALID` | wasm returned a malformed envelope — integrity failure, never a conversion issue. |
| `CONVERSION_ERROR` | wasm returned an error envelope (unknown provider, malformed payload, …). |
| `SESSION_STATE` | Illegal stream session usage (feed after finish, use after free). |

## API

### `loadPrism(bytes, options?) → Promise<PrismClient>`

Instantiate + anchor-check + ABI-lock. Also available as `PrismClient.load`.
`options.expectedAbi` (default `"1"`) locks the ABI; `client.irSchema` exposes
the Lucent IR schema version the artifact was built against.

### `PrismClient`

| Method | Returns | Notes |
|---|---|---|
| `convertRequest(from, json, to)` | `{ value, diagnostics }` | Request JSON → request JSON |
| `convertResponse(from, json, to)` | `{ value, diagnostics }` | Response JSON → response JSON |
| `convertStream(from, sse, to)` | `{ value, diagnostics }` | Whole SSE text → SSE text |
| `convertStreamEvent(from, sseEvent, to)` | `{ value, diagnostics }` | Single SSE event |
| `createStream(from, to)` | `StreamSession` | Incremental handle session |
| `listProviders()` | `string[]` | e.g. `["responses","openai","messages","gemini"]` |

### `StreamSession`

| Method | Returns | Notes |
|---|---|---|
| `feed(chunk)` | `string[]` | Target SSE frames produced by this chunk |
| `finish()` | `string[]` | Flush trailing half-frame; idempotent (2nd call → `[]`) |
| `finished()` | `boolean` | Host self-check before `free()` |
| `free()` | `void` | Release the wasm slot; idempotent |

`value` is always the exact wasm output — the wrapper never re-serializes.

## Versioning contract

- The wrapper pins `wasm_abi_version` (currently `"1"`); an artifact built by a
  different ABI is refused at load time. Bump both sides together.
- Scratch/log exports (`wasm_init_scratch` …) are **degraded stubs** on the
  wasm-gc backend and intentionally not bound — see
  `.agent-team/docs/06-风险与依赖.md` (TD-004).

## Development

```bash
npm install          # dev deps: typescript, @types/node
npm run build        # tsc → dist/
npm test             # integration suite against _build/wasm-gc/.../main.wasm
```

Tests need the artifact in place (`moon build --target wasm-gc` from the repo
root) or `PRISM_WASM_PATH=<path>` pointing at one.
