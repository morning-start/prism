---
name: prism-wasm-integration
description: |
  Guide for loading and calling prism.wasm from any language with WASM support (Rust, TypeScript, Python, Go, C/C++, Zig, etc.). Use this skill whenever someone wants to embed Prism's LLM protocol conversion in their own application via WASM — whether they say "use prism.wasm", "call prism from [language]", "integrate prism WASM", "load the wasm module", or ask about Prism's WASM ABI, string passing, or export functions. Also trigger when someone wants to convert between LLM provider formats (OpenAI, Anthropic, Gemini, etc.) in a non-MoonBit language using WASM.
---

# Prism WASM Integration Guide

Prism is an LLM protocol conversion engine. It converts between provider formats (OpenAI, Anthropic, Gemini, Azure, Vertex, vLLM) via a neutral intermediate representation called Lucent IR. The WASM build exposes 15 pure functions — all `String → String`, no state, no side effects — making it safe and easy to embed in any language.

## Architecture Overview

```
Your App  ──String JSON──▸  prism.wasm  ──String JSON──▸  Your App
              (provider       (convert via         (provider
               format A)       Lucent IR)           format B)
```

Two usage patterns:

1. **SDK mode** — your app speaks one provider format, Prism encodes/decodes for you
2. **Transit mode** — convert provider A's format directly to provider B's format in one call

## Critical: The String ABI

Prism uses MoonBit's classic `wasm` target. Strings are passed via linear memory with this layout:

```
┌──────────────────────────────────────────────────────┐
│  ptr - 4:  u32 length  (UTF-16 code units, LE)       │
│  ptr:      UTF-16LE payload  (length × 2 bytes)      │
└──────────────────────────────────────────────────────┘
```

- **Arguments**: write strings to linear memory, pass the `ptr` (i32) to the function
- **Return value**: the function returns an i32 `ptr` with the same layout
- **Scratch region**: use addresses below `0x1000` for argument strings (the MoonBit GC heap starts above ~0x1000). Use a stride of 512+ bytes between arguments to avoid overlap.

### Encoding a string argument

```
1. Encode your string as UTF-16LE code units
2. Write u32 length (number of code units, NOT bytes) at ptr - 4 in little-endian
3. Write UTF-16LE payload at ptr
4. Pass ptr (as i32) to the WASM function
```

### Decoding a result string

```
1. Read u32 length from resultPtr - 4 (little-endian)
2. Read length × 2 bytes from resultPtr
3. Decode as UTF-16LE code units → your native string
```

**Gotcha**: Many languages use UTF-8 internally. You must convert to/from UTF-16LE for the WASM boundary. JavaScript/TypeScript natively uses UTF-16 so this is simpler there.

## Exported Functions (15 total)

All functions take and return strings. Call them by name from the WASM module's exports.

### Low-level IR conversion (6)

| Export | Args | Description |
|---|---|---|
| `wasm_to_lux_req` | `(provider, json)` | Provider request JSON → LucentRequest JSON |
| `wasm_lux_req_to_provider` | `(provider, luxJson)` | LucentRequest JSON → Provider request JSON |
| `wasm_to_lux_resp` | `(provider, json)` | Provider response JSON → LucentResponse JSON |
| `wasm_lux_resp_to_provider` | `(provider, luxJson)` | LucentResponse JSON → Provider response JSON |
| `wasm_sse_to_events` | `(provider, sseText)` | Provider SSE text → StreamEvent JSON array |
| `wasm_events_to_sse` | `(provider, eventsJson)` | StreamEvent JSON array → Provider SSE text |

### High-level SDK (5)

| Export | Args | Description |
|---|---|---|
| `wasm_sdk_encode_req` | `(provider, text)` | Plain text → Provider request JSON |
| `wasm_sdk_decode_resp` | `(provider, json)` | Provider response JSON → Plain text |
| `wasm_sdk_encode_stream` | `(provider, text)` | Plain text → Streaming provider request JSON |
| `wasm_sdk_decode_sse` | `(provider, sseText)` | Provider SSE → PrismEvent JSON array |
| `wasm_sdk_capability` | `(provider)` | Query provider capability declaration |

### Transit conversion (3)

| Export | Args | Description |
|---|---|---|
| `wasm_convert_req` | `(source, json, target)` | Convert request: source provider → target provider |
| `wasm_convert_resp` | `(source, json, target)` | Convert response: source provider → target provider |
| `wasm_convert_stream` | `(source, sseText, target)` | Convert SSE stream: source → target |

### Query (1)

| Export | Args | Description |
|---|---|---|
| `wasm_list_providers` | `()` | JSON array of all registered provider names |

## Envelope Contract

Every function (except `wasm_list_providers`) returns an **envelope**:

```json
{"value": "...", "diagnostics": [{"field": "...", "status": "exact|degraded|unsupported|invalid", "detail": "..."}]}
```

- `value` — the result payload (object or JSON string depending on direction)
- `diagnostics` — conversion fidelity notes per field

Errors return:

```json
{"error": "message", "diagnostics": []}
```

Always check for the `error` key first before accessing `value`.

## Building prism.wasm

```bash
moon build --target wasm
# Output: _build/wasm/release/build/cmd/main/main.wasm
```

The `cmd/main` package is the executable entry point that defines the WASM exports via `options(link: { "wasm": { "exports": [...], "export-memory-name": "memory" } })` in its `moon.pkg`.

## Language-Specific Guides

Read the reference file for your target language:

- **TypeScript/JavaScript** → `references/typescript.md` (also: existing wrapper at `wrappers/ts/`)
- **Go** → `references/go.md` (also: existing wrapper at `wrappers/go/`)
- **Rust** → `references/rust.md`
- **Python** → `references/python.md`

Each reference covers: loading the WASM module, implementing the string ABI, a working client class, and error handling.

## Reference Implementations

The project includes production-quality wrappers you can study or use directly:

- **Go wrapper** (`wrappers/go/`): Uses wazero runtime. Install: `go get github.com/morning-start/prism/wrappers/go`
- **TypeScript wrapper** (`wrappers/ts/`): Uses WebAssembly API. Install: `npm install @morning-start/prism-wasm`

These are the canonical implementations. When writing a new language wrapper, mirror their structure:

1. **Runtime layer** — load WASM, implement `writeString`/`readString` for the UTF-16 ABI
2. **Client layer** — wrap each export with typed methods, parse envelopes
3. **Types layer** — define Envelope, Diagnostic, PrismEvent types natively

## Common Pitfalls

1. **UTF-8 vs UTF-16**: The #1 mistake. Prism uses UTF-16LE in linear memory, not UTF-8. Most languages (Rust, Go, Python) use UTF-8 internally — you must transcode.

2. **Length is code units, not bytes**: The length header at `ptr - 4` counts UTF-16 code units (each 2 bytes), not bytes. For BMP characters it equals the character count; for supplementary characters (>U+FFFF) one character becomes two code units.

3. **Scratch collision with GC heap**: Don't write argument strings above `0x1000` — the MoonBit garbage collector uses that region. Reset your scratch pointer on each call.

4. **Memory buffer detachment**: In JS/TS, `WebAssembly.Memory.buffer` detaches when memory grows. Always get a fresh `DataView`/`Uint8Array` per call, not once at load time.

5. **_start must run**: The WASM module has a `_start` export that initializes the MoonBit runtime. Call it once after instantiation before any conversion function.

6. **Error envelope parsing**: Don't assume the result is valid JSON on error. Check for `{"error":` prefix first, then parse.

7. **wasm_list_providers takes no args**: It's the only function with zero string arguments. Just call it directly — no need to write anything to linear memory.
