# Prism WASM — TypeScript Wrapper

> [Prism](https://github.com/morning-start/prism) LLM protocol converter - TypeScript WASM wrapper for Bun/Node.

## Prism String ABI

The classic `wasm` target exports each conversion as `(i32, ...) -> i32`. Every
String argument is passed as a linear-memory address:

- `u32 @ (ptr - 4)` = UTF-16 length in code units
- UTF-16LE payload starting at `ptr`
- the returned `i32` is an address with the same layout

The wrapper writes arguments into a scratch region below the MoonBit GC heap
and decodes the returned UTF-16 string. This is verified end-to-end by
`test/integration.test.ts` (Unicode, quotes and newlines round-trip).

## Build & Test

```bash
moon build --target wasm          # from repo root
node --experimental-strip-types test/integration.test.ts
bun test
```

## Installation

```bash
bun add @morning-start/prism-wasm
```

## Quick Start

```typescript
import { PrismClient } from "@morning-start/prism-wasm";
import { readFileSync } from "fs";

const client = new PrismClient(readFileSync("prism.wasm"));

// Encode a request: text -> OpenAI JSON
const reqJson = client.encodeRequest("openai", "你好");
console.log(reqJson);

// Decode a response: OpenAI JSON -> text
const text = client.decodeResponse("openai", respJson);
console.log(text);

// SSE decoding: Anthropic SSE -> events
const events = client.decodeSSE("anthropic", sseText);
for (const event of events) {
  if (event.type === "text_delta") {
    console.log(event.text);
  }
}

// Cross-provider conversion: OpenAI -> Anthropic
const anthropicJson = client.convert("openai", "anthropic", "request", openaiReq);
```

## API

### `PrismClient(wasmSource)`

| Method | Description |
|--------|-------------|
| `encodeRequest(provider, text, opts?)` | Text -> provider JSON |
| `decodeResponse(provider, jsonStr)` | Provider JSON -> text |
| `decodeSSE(provider, sseStr)` | Provider SSE -> Event list |
| `encodeStream(provider, text, opts?)` | Text -> streaming provider JSON |
| `convert(from, to, direction, payload)` | Cross-provider conversion |
| `capability(provider)` | Query provider capabilities |
| `listProviders()` | List all available providers |

## Development

```bash
bun install
bun test
```
