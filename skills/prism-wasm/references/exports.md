# WASM Exported Functions

All 23 exported functions from prism.wasm.

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

## Providers

`openai`, `openai-responses`, `openai-codex`, `openai-azure`, `openai-vllm`, `anthropic`, `gemini`, `gemini-vertex`, `gemini-interactions`
