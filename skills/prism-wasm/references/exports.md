# WASM Exported Functions

29 ABI exports per backend (`src/cmd/main/moon.pkg` is the single source of
truth; wasm backend additionally exports `memory`). Scratch/log exports are
**degraded stubs** on wasm-gc/js (see string-abi.md); conversion exports are
identical across backends.

## IR Conversion (6)

### wasm_to_lux_req(provider, json_str) → String
Provider request JSON → LucentRequest JSON

### wasm_lux_req_to_provider(provider, json_str) → String
LucentRequest JSON → Provider request JSON

### wasm_to_lux_resp(provider, json_str) → String
Provider response JSON → LucentResponse JSON

### wasm_lux_resp_to_provider(provider, json_str) → String
LucentResponse JSON → Provider response JSON

### wasm_sse_to_events(provider, sse_str) → String
Provider SSE text → StreamEvent JSON array

### wasm_events_to_sse(provider, json_str) → String
StreamEvent JSON array → Provider SSE text

## SDK APIs (5)

### wasm_sdk_encode_req(provider, text) → String
Plain text → Provider request JSON

### wasm_sdk_decode_resp(provider, resp_json) → String
Provider response JSON → Plain text

### wasm_sdk_encode_stream(provider, text) → String
Plain text → Provider stream request JSON

### wasm_sdk_decode_sse(provider, sse_str) → String
Provider SSE → PrismEvent JSON array

### wasm_sdk_capability(provider) → String
Provider capability JSON

## Cross-Protocol (4)

### wasm_convert_req(source, json_str, target) → String
Request: source protocol → target protocol

### wasm_convert_resp(source, json_str, target) → String
Response: source protocol → target protocol

### wasm_convert_stream(source, sse_str, target) → String
Stream: source protocol → target protocol

### wasm_convert_stream_event(source, sse_event, target) → String
Single SSE event: source → target

## Memory (2)

### wasm_init_scratch(size) → Int
Allocate scratch buffer, return ptr

### wasm_read_scratch_arg(buf_ptr, offset) → String
Read string from scratch buffer

## Logging (4)

### wasm_log_init(size) → Int
Allocate log buffer, return ptr

### wasm_log_pos(buf_ptr) → Int
Get current write position

### wasm_convert_req_trace(src, json, tgt, log_ptr, log_size) → String
Request conversion with logging

### wasm_convert_resp_trace(src, json, tgt, log_ptr, log_size) → String
Response conversion with logging

### wasm_convert_stream_trace(src, sse, tgt, log_ptr, log_size) → String
Stream conversion with logging

## Query (1)

### wasm_list_providers() → String
JSON array of all provider names

## Stream Sessions (5)

### wasm_stream_new(source, target) → String
{"value": handle} — allocate incremental stream session

### wasm_stream_feed(handle, chunk) → String
{"value": ["<target SSE frame>", ...]}

### wasm_stream_finish(handle) → String
Flush trailing half-frame + held Finish frame

### wasm_stream_finished(handle) → String
{"value": true|false} — host self-check before free (added 2026-10-25)

### wasm_stream_free(handle) → String
{"value": true} — slot reusable after free

## Providers

Primary names (verified via `wasm_list_providers()`, 2026-10-25):
`responses`, `openai`, `messages`, `gemini`

Aliases (e.g. `openai-responses`, `claude-messages`, `google`, `openai-chat`)
also resolve via `match_provider_name`; see `src/sdk/registry.mbt` for the
authoritative list.
