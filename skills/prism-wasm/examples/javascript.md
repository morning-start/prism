# JavaScript/Node.js Examples

Direct prism.wasm usage without wrappers.

## Helper Functions

```javascript
const fs = require('fs');

function writeString(memory, ptr, str) {
  const byteLen = str.length * 2;
  new DataView(memory.buffer).setUint32(ptr - 4, byteLen, true);
  const view = new Uint16Array(memory.buffer, ptr, str.length);
  for (let i = 0; i < str.length; i++) view[i] = str.charCodeAt(i);
}

function readString(memory, ptr) {
  const byteLen = new DataView(memory.buffer).getUint32(ptr - 4, true);
  const view = new Uint16Array(memory.buffer, ptr, byteLen / 2);
  return String.fromCharCode(...view);
}

function parseResult(result) {
  if (result.includes('"error"')) {
    throw new Error(JSON.parse(result).error);
  }
  return JSON.parse(result).value;
}
```

## Load WASM

```javascript
async function loadPrism() {
  const wasmBytes = fs.readFileSync('prism.wasm');
  const { instance } = await WebAssembly.instantiate(wasmBytes);
  return instance;
}
```

## Gateway Pattern

### Complete Gateway Class

```javascript
class PrismGateway {
  constructor(instance) {
    this.instance = instance;
    this.memory = instance.exports.memory;
    this.bufPtr = instance.exports.wasm_init_scratch(24576);
    this.logPtr = instance.exports.wasm_log_init(16384);
  }

  _writeArgs(...args) {
    for (let i = 0; i < args.length; i++) {
      writeString(this.memory, this.bufPtr + i * 8192, args[i]);
    }
  }

  _readArgs(count) {
    return Array.from({ length: count }, (_, i) =>
      this.instance.exports.wasm_read_scratch_arg(this.bufPtr, i * 8192)
    );
  }

  // Request: Client Protocol → Server Protocol
  convertRequest(clientProtocol, requestJSON, serverProtocol) {
    this._writeArgs(clientProtocol, requestJSON, serverProtocol);
    const [src, json, tgt] = this._readArgs(3);
    const resultPtr = this.instance.exports.wasm_convert_req(src, json, tgt);
    return parseResult(readString(this.memory, resultPtr));
  }

  // Response: Server Protocol → Client Protocol
  convertResponse(serverProtocol, responseJSON, clientProtocol) {
    this._writeArgs(serverProtocol, responseJSON, clientProtocol);
    const [src, json, tgt] = this._readArgs(3);
    const resultPtr = this.instance.exports.wasm_convert_resp(src, json, tgt);
    return parseResult(readString(this.memory, resultPtr));
  }

  // Single Stream Event: Server Protocol → Client Protocol
  convertStreamEvent(serverProtocol, sseEvent, clientProtocol) {
    this._writeArgs(serverProtocol, sseEvent, clientProtocol);
    const [src, evt, tgt] = this._readArgs(3);
    const resultPtr = this.instance.exports.wasm_convert_stream_event(src, evt, tgt);
    return parseResult(readString(this.memory, resultPtr));
  }

  // Full Stream: Server Protocol → Client Protocol
  convertStream(serverProtocol, sseText, clientProtocol) {
    this._writeArgs(serverProtocol, sseText, clientProtocol);
    const [src, sse, tgt] = this._readArgs(3);
    const resultPtr = this.instance.exports.wasm_convert_stream(src, sse, tgt);
    return parseResult(readString(this.memory, resultPtr));
  }

  // With logging
  convertRequestTrace(clientProtocol, requestJSON, serverProtocol) {
    this._writeArgs(clientProtocol, requestJSON, serverProtocol);
    const [src, json, tgt] = this._readArgs(3);
    const resultPtr = this.instance.exports.wasm_convert_req_trace(
      src, json, tgt, this.logPtr, 16384
    );
    const result = parseResult(readString(this.memory, resultPtr));
    const logs = this._readLogs();
    return { result, logs };
  }

  _readLogs() {
    const pos = this.instance.exports.wasm_log_pos(this.logPtr);
    const bytes = new Uint8Array(this.memory.buffer, this.logPtr + 4, pos - 4);
    return new TextDecoder().decode(bytes);
  }

  listProviders() {
    const resultPtr = this.instance.exports.wasm_list_providers();
    return JSON.parse(readString(this.memory, resultPtr));
  }
}
```

### Express Gateway Server

```javascript
const express = require('express');

async function main() {
  const instance = await loadPrism();
  const gateway = new PrismGateway(instance);
  const app = express();
  app.use(express.json());

  // OpenAI → Anthropic proxy
  app.post('/v1/chat/completions', async (req, res) => {
    try {
      // Convert request: OpenAI → Anthropic
      const anthropicReq = gateway.convertRequest(
        'openai',
        JSON.stringify(req.body),
        'anthropic'
      );

      // Forward to Anthropic API
      const resp = await fetch('https://api.anthropic.com/v1/messages', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'x-api-key': process.env.ANTHROPIC_API_KEY,
          'anthropic-version': '2023-06-01',
        },
        body: JSON.stringify(anthropicReq),
      });
      const anthropicResp = await resp.json();

      // Convert response: Anthropic → OpenAI
      const openaiResp = gateway.convertResponse(
        'anthropic',
        JSON.stringify(anthropicResp),
        'openai'
      );

      res.json(openaiResp);
    } catch (err) {
      res.status(500).json({ error: err.message });
    }
  });

  app.listen(3000, () => console.log('Gateway on :3000'));
}

main();
```

### Streaming Gateway

```javascript
app.post('/v1/chat/completions/stream', async (req, res) => {
  res.setHeader('Content-Type', 'text/event-stream');
  res.setHeader('Cache-Control', 'no-cache');
  res.setHeader('Connection', 'keep-alive');

  // Convert request
  const anthropicReq = gateway.convertRequest('openai', JSON.stringify(req.body), 'anthropic');

  // Stream from Anthropic
  const resp = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-api-key': process.env.ANTHROPIC_API_KEY,
      'anthropic-version': '2023-06-01',
    },
    body: JSON.stringify({ ...anthropicReq, stream: true }),
  });

  const reader = resp.body.getReader();
  const decoder = new TextDecoder();
  let buffer = '';

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;

    buffer += decoder.decode(value, { stream: true });
    const events = buffer.split('\n\n');
    buffer = events.pop();

    for (const event of events) {
      if (event.trim() && event.includes('data:')) {
        // Convert each SSE event: Anthropic → OpenAI
        const openaiEvent = gateway.convertStreamEvent('anthropic', event + '\n\n', 'openai');
        res.write(`data: ${JSON.stringify(openaiEvent)}\n\n`);
      }
    }
  }

  res.write('data: [DONE]\n\n');
  res.end();
});
```

## Simple Examples

### Convert Request

```javascript
const instance = await loadPrism();
const gateway = new PrismGateway(instance);

const openaiReq = JSON.stringify({
  model: 'gpt-4o',
  messages: [{ role: 'user', content: 'Hello' }]
});

const anthropicReq = gateway.convertRequest('openai', openaiReq, 'anthropic');
console.log(anthropicReq);
```

### List Providers

```javascript
const providers = gateway.listProviders();
console.log(providers);
// ['openai', 'anthropic', 'gemini', ...]
```

### With Logging

```javascript
const { result, logs } = gateway.convertRequestTrace('openai', openaiReq, 'anthropic');
console.log('Result:', result);
console.log('Logs:', logs);
// [INFO] convert_req: start: openai → anthropic
// [DEBUG] convert_req: input length: 123 chars
// [INFO] convert_req: success: 456 chars
```
