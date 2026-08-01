# Prism WASM — Python Wrapper

> [Prism](https://github.com/morning-start/prism) LLM protocol converter - Python WASM wrapper (wasmtime).

## Prism String ABI

The classic `wasm` target exports each conversion as `(i32, ...) -> i32`. Every
String argument is passed as a linear-memory address:

- `u32 @ (ptr - 4)` = UTF-16 length in code units
- UTF-16LE payload starting at `ptr`
- the returned `i32` is an address with the same layout

The wrapper writes arguments into a scratch region below the MoonBit GC heap
and decodes the returned UTF-16 string.

## Build & Test

```bash
pip install wasmtime
moon build --target wasm          # from repo root
python -c "from prism_wasm import PrismClient; ..."  # PYTHONPATH=src
```

## Installation

```bash
pip install prism-wasm
```

## Quick Start

```python
from prism_wasm import PrismClient, PrismOptions

# Load the WASM binary
client = PrismClient("prism.wasm")

# Encode a request: text -> OpenAI JSON
req_json = client.encode_request("openai", "你好")
print(req_json)

# Decode a response: OpenAI JSON -> text
text = client.decode_response("openai", resp_json)
print(text)

# SSE decoding: Anthropic SSE -> events
events = client.decode_sse("anthropic", sse_text)
for event in events:
    if event.type == "text_delta":
        print(event.text)

# Cross-provider conversion: OpenAI -> Anthropic
anthropic_json = client.convert("openai", "anthropic", "request", openai_req)
```

## API

### `PrismClient(wasm_source)`

| Method | Description |
|--------|-------------|
| `encode_request(provider, text, opts?)` | Text -> provider JSON |
| `decode_response(provider, json_str)` | Provider JSON -> text |
| `decode_sse(provider, sse_str)` | Provider SSE -> Event list |
| `encode_stream(provider, text, opts?)` | Text -> streaming provider JSON |
| `convert(from_provider, to_provider, direction, payload)` | Cross-provider conversion |
| `capability(provider)` | Query provider capabilities |
| `list_providers()` | List all available providers |

### `AsyncPrismClient(wasm_source)`

Async version with the same API, methods return coroutines.
