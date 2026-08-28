# Python Examples

Direct prism.wasm usage with wasmer or wasmtime.

## Helper Functions

```python
import json
import struct

def write_string(memory, ptr: int, s: str):
    encoded = s.encode('utf-16-le')
    memory.write(struct.pack('<I', len(encoded)), ptr - 4)
    memory.write(encoded, ptr)

def read_string(memory, ptr: int) -> str:
    byte_len = struct.unpack('<I', memory.read(ptr - 4, 4))[0]
    return memory.read(ptr, byte_len).decode('utf-16-le')

def parse_result(result: str):
    parsed = json.loads(result)
    if 'error' in parsed:
        raise RuntimeError(parsed['error'])
    return parsed.get('value', parsed)
```

## Load WASM (wasmer)

```python
from wasmer import Module, Instance

def load_prism(wasm_path='prism.wasm'):
    with open(wasm_path, 'rb') as f:
        module = Module(f.read())
    return Instance(module)
```

## Gateway Class

```python
class PrismGateway:
    def __init__(self, instance):
        self.instance = instance
        self.memory = instance.exports['memory']
        self.buf_ptr = instance.exports['wasm_init_scratch'](24576)
        self.log_ptr = instance.exports['wasm_log_init'](16384)

    def _write_args(self, *args):
        for i, arg in enumerate(args):
            write_string(self.memory, self.buf_ptr + i * 8192, arg)

    def _read_args(self, count):
        return [
            self.instance.exports['wasm_read_scratch_arg'](self.buf_ptr, i * 8192)
            for i in range(count)
        ]

    def convert_request(self, client_protocol, request_json, server_protocol):
        """Request: Client Protocol → Server Protocol"""
        self._write_args(client_protocol, request_json, server_protocol)
        src, json_str, tgt = self._read_args(3)
        result_ptr = self.instance.exports['wasm_convert_req'](src, json_str, tgt)
        return parse_result(read_string(self.memory, result_ptr))

    def convert_response(self, server_protocol, response_json, client_protocol):
        """Response: Server Protocol → Client Protocol"""
        self._write_args(server_protocol, response_json, client_protocol)
        src, json_str, tgt = self._read_args(3)
        result_ptr = self.instance.exports['wasm_convert_resp'](src, json_str, tgt)
        return parse_result(read_string(self.memory, result_ptr))

    def convert_stream_event(self, server_protocol, sse_event, client_protocol):
        """Single SSE Event: Server Protocol → Client Protocol"""
        self._write_args(server_protocol, sse_event, client_protocol)
        src, evt, tgt = self._read_args(3)
        result_ptr = self.instance.exports['wasm_convert_stream_event'](src, evt, tgt)
        return parse_result(read_string(self.memory, result_ptr))

    def convert_request_trace(self, client_protocol, request_json, server_protocol):
        """Request conversion with logging"""
        self._write_args(client_protocol, request_json, server_protocol)
        src, json_str, tgt = self._read_args(3)
        result_ptr = self.instance.exports['wasm_convert_req_trace'](
            src, json_str, tgt, self.log_ptr, 16384
        )
        result = parse_result(read_string(self.memory, result_ptr))
        return result, self._read_logs()

    def list_providers(self):
        result_ptr = self.instance.exports['wasm_list_providers']()
        return json.loads(read_string(self.memory, result_ptr))

    def _read_logs(self):
        pos = self.instance.exports['wasm_log_pos'](self.log_ptr)
        return bytes(self.memory.read(self.log_ptr + 4, pos - 4)).decode('utf-8')
```

## Flask Gateway Server

```python
from flask import Flask, request, jsonify
import requests

app = Flask(__name__)
instance = load_prism()
gateway = PrismGateway(instance)

BACKENDS = {
    'claude': {'protocol': 'anthropic', 'url': 'https://api.anthropic.com/v1/messages'},
    'gpt4': {'protocol': 'openai', 'url': 'https://api.openai.com/v1/chat/completions'},
    'gemini': {'protocol': 'gemini', 'url': 'https://generativelanguage.googleapis.com/v1/...'},
}

@app.route('/v1/chat/completions', methods=['POST'])
def proxy():
    data = request.json
    target = data.pop('target', 'gpt4')
    backend = BACKENDS[target]

    # Convert: OpenAI → Target Protocol
    target_req = gateway.convert_request('openai', json.dumps(data), backend['protocol'])

    # Forward to backend
    resp = requests.post(
        backend['url'],
        headers={'Authorization': f'Bearer {get_api_key(target)}'},
        json=target_req,
    )

    # Convert: Target Protocol → OpenAI
    openai_resp = gateway.convert_response(backend['protocol'], resp.text, 'openai')
    return jsonify(openai_resp)

def get_api_key(target):
    import os
    return os.environ.get(f'{target.upper()}_API_KEY', '')

if __name__ == '__main__':
    app.run(port=8080)
```

## Simple Examples

### Convert Request

```python
instance = load_prism()
gateway = PrismGateway(instance)

openai_req = json.dumps({
    'model': 'gpt-4o',
    'messages': [{'role': 'user', 'content': 'Hello'}]
})

anthropic_req = gateway.convert_request('openai', openai_req, 'anthropic')
print(anthropic_req)
```

### List Providers

```python
providers = gateway.list_providers()
print(providers)  # ['openai', 'anthropic', 'gemini', ...]
```

### With Logging

```python
result, logs = gateway.convert_request_trace('openai', openai_req, 'anthropic')
print('Result:', result)
print('Logs:', logs)
# [INFO] convert_req: start: openai → anthropic
# [DEBUG] convert_req: input length: 123 chars
# [INFO] convert_req: success: 456 chars
```
