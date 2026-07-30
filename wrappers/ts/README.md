# Prism WASM — TypeScript Wrapper

> [Prism](https://github.com/morning-start/prism) LLM protocol converter - TypeScript WASM wrapper for Bun.

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
