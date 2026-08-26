# TypeScript/JavaScript WASM Integration for Prism

## Quick Start

Install the existing wrapper:

```bash
npm install @morning-start/prism-wasm
# or: bun add @morning-start/prism-wasm
```

```typescript
import { PrismClient } from "@morning-start/prism-wasm";
import { readFileSync } from "fs";

const wasmBytes = readFileSync("path/to/prism.wasm");
const client = new PrismClient(wasmBytes);

// SDK mode: encode a text request for OpenAI
const envelope = client.encodeRequest("openai", "Hello, world!");
console.log(envelope.value);

// Transit mode: convert OpenAI → Anthropic
const result = client.convert("openai", "anthropic", "request", openaiJSON);
```

## Building Your Own Wrapper

TypeScript/JavaScript has the easiest time with Prism's ABI because JS strings are natively UTF-16. No transcoding needed — just direct `charCodeAt()` / `fromCharCode()` mapping.

### Loading the WASM module

```typescript
// Node.js
import { readFileSync } from "fs";

function loadPrism(wasmSource: string | Buffer): WebAssembly.Instance {
  const bytes = typeof wasmSource === "string" ? readFileSync(wasmSource) : wasmSource;
  const module = new WebAssembly.Module(bytes as unknown as ArrayBuffer);
  const instance = new WebAssembly.Instance(module, {});
  const memory = instance.exports.memory as WebAssembly.Memory;

  // Run MoonBit runtime initializer
  const start = instance.exports._start as (() => void) | undefined;
  if (typeof start === "function") start();

  return instance;
}

// Browser / Deno
async function loadPrismFromURL(url: string): Promise<WebAssembly.Instance> {
  const response = await fetch(url);
  const bytes = await response.arrayBuffer();
  const { instance } = await WebAssembly.instantiate(bytes, {});
  const start = instance.exports._start as (() => void) | undefined;
  if (typeof start === "function") start();
  return instance;
}
```

### String ABI implementation

```typescript
const SCRATCH_START = 0x0400;
const SCRATCH_STRIDE = 512;
let _scratch = SCRATCH_START;

function memory(): WebAssembly.Memory {
  // Access from the loaded instance
  return _instance!.exports.memory as WebAssembly.Memory;
}

function bytes(): Uint8Array {
  return new Uint8Array(memory().buffer);
}

function dataView(): DataView {
  return new DataView(memory().buffer);
}

/** Write a JS string to WASM linear memory at ptr. */
function writeString(ptr: number, s: string): void {
  const view = bytes();
  const dv = dataView();

  // Length header at ptr - 4: u32 LE, count of UTF-16 code units
  dv.setUint32(ptr - 4, s.length, true);

  // UTF-16LE payload at ptr (JS strings are already UTF-16)
  for (let i = 0; i < s.length; i++) {
    const code = s.charCodeAt(i);
    view[ptr + 2 * i] = code & 0xff;
    view[ptr + 2 * i + 1] = (code >> 8) & 0xff;
  }
}

/** Read a WASM string from linear memory at ptr. */
function readString(ptr: number): string {
  const view = bytes();
  const dv = dataView();

  // u32 length at ptr - 4
  const len = dv.getUint32(ptr - 4, true);

  // UTF-16LE payload → JS string
  let out = "";
  for (let i = 0; i < len; i++) {
    out += String.fromCharCode(
      view[ptr + 2 * i] | (view[ptr + 2 * i + 1] << 8)
    );
  }
  return out;
}
```

### Calling a WASM export

```typescript
function callWasm(funcName: string, ...args: string[]): string {
  const inst = _instance!;
  const fn = inst.exports[funcName as keyof WebAssembly.Exports] as
    | ((...a: number[]) => number)
    | undefined;

  if (typeof fn !== "function") {
    throw new Error(`WASM export not found: ${funcName}`);
  }

  // Write each arg to scratch region
  _scratch = SCRATCH_START;
  const ptrs: number[] = [];
  for (const s of args) {
    writeString(_scratch, s);
    ptrs.push(_scratch);
    _scratch += SCRATCH_STRIDE;
  }

  const resultPtr = fn(...ptrs);
  return readString(resultPtr);
}
```

### Envelope parsing

```typescript
interface Diagnostic {
  field: string;
  status: string;
  detail?: string;
}

interface Envelope {
  value: unknown;
  diagnostics: Diagnostic[];
}

function parseEnvelope(raw: string): Envelope {
  const obj = JSON.parse(raw);

  // Check for error envelope
  if (obj.error) {
    throw new Error(`prism: ${obj.error}`);
  }

  return {
    value: obj.value,
    diagnostics: Array.isArray(obj.diagnostics)
      ? obj.diagnostics.map((d: Record<string, unknown>) => ({
          field: String(d.field ?? ""),
          status: String(d.status ?? ""),
          ...(d.detail !== undefined ? { detail: String(d.detail) } : {}),
        }))
      : [],
  };
}
```

### Important notes for TypeScript/JavaScript

- JS strings are natively UTF-16, so `charCodeAt()` gives you UTF-16 code units directly. No transcoding needed.
- **Buffer detachment**: `WebAssembly.Memory.buffer` detaches when memory grows. Always call `new Uint8Array(memory.buffer)` fresh per call, not once at load time.
- For supplementary characters (emoji, CJK extension B+, etc.), `charCodeAt()` returns surrogate pairs. The loop above handles them correctly because it iterates by `length` (which counts UTF-16 code units).
- In the browser, use `WebAssembly.instantiateStreaming()` for faster loading.
- Bun supports the same WebAssembly API as Node.js — the existing wrapper works with both.
- For Deno, use `Deno.readFile()` to load the WASM bytes.

### Single Event Stream Conversion Example

```typescript
// Convert a single SSE event from OpenAI to Anthropic
const openaiEvent = 'data: {"id":"1","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":"Hello"},"finish_reason":null}]}\n\n';
const result = client.convertStreamEvent("openai-chat", openaiEvent, "anthropic");
console.log(result.value); // Anthropic-format SSE event

// Convert stream end event
const doneEvent = "data: [DONE]\n\n";
const endResult = client.convertStreamEvent("openai-chat", doneEvent, "anthropic");
console.log(endResult.value); // Anthropic's message_stop event
```
