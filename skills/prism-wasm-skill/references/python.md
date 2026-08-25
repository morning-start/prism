# Python WASM Integration for Prism

## Recommended Runtime: wasmtime-py

Use [wasmtime-py](https://github.com/bytecodealliance/wasmtime-py) — the Python binding for the Bytecode Alliance's wasmtime runtime.

### Installation

```bash
pip install wasmtime
```

### Loading the WASM module

```python
from wasmtime import Engine, Store, Module, Instance, Memory, Linker, WasiConfig

class PrismRuntime:
    def __init__(self, wasm_path: str):
        engine = Engine()
        store = Store(engine)

        # Configure WASI for MoonBit runtime
        wasi = WasiConfig()
        wasi.inherit_stdout()
        wasi.stderr = open(os.devnull, 'w')
        store.set_wasi(wasi)

        linker = Linker(engine)
        linker.define_wasi()

        module = Module.from_file(engine, wasm_path)
        self.instance = linker.instantiate(store, module)
        self.store = store
        self.memory = self.instance.exports(store)["memory"]

        # Call _start to initialize MoonBit runtime
        start = self.instance.exports(store).get("_start")
        if start:
            start(store)
```

### String ABI implementation

Python 3 strings are Unicode (UCS-2 or UCS-4 depending on build). For the WASM boundary, encode to UTF-16LE.

```python
import struct

SCRATCH_START = 0x0400
SCRATCH_STRIDE = 512

def write_string(self, ptr: int, s: str) -> int:
    """Write a Python string to WASM linear memory in Prism's UTF-16LE format."""
    # Encode to UTF-16LE (without BOM)
    encoded = s.encode('utf-16-le')
    num_code_units = len(encoded) // 2

    # Write length header at ptr - 4 (u32 LE, count of UTF-16 code units)
    mem = self.memory.data_ptr(self.store)
    struct.pack_into('<I', mem, ptr - 4, num_code_units)

    # Write UTF-16LE payload at ptr
    mem[ptr:ptr + len(encoded)] = encoded

    return ptr

def read_string(self, ptr: int) -> str:
    """Read a WASM string from linear memory (Prism's UTF-16LE format)."""
    mem = self.memory.data_ptr(self.store)

    # Read u32 length at ptr - 4
    num_code_units = struct.unpack_from('<I', mem, ptr - 4)[0]

    # Read UTF-16LE payload
    byte_len = num_code_units * 2
    encoded = bytes(mem[ptr:ptr + byte_len])

    return encoded.decode('utf-16-le')
```

### Calling a WASM export

```python
def call(self, func_name: str, *args: str) -> str:
    """Call a WASM export function with string arguments."""
    exports = self.instance.exports(self.store)
    func = exports.get(func_name)
    if func is None:
        raise RuntimeError(f"WASM export not found: {func_name}")

    # Write arguments to scratch region
    ptrs = []
    ptr = SCRATCH_START
    for s in args:
        p = self.write_string(ptr, s)
        ptrs.append(p)
        ptr += SCRATCH_STRIDE

    result_ptr = func(self.store, *ptrs)
    return self.read_string(result_ptr)
```

### Envelope parsing

```python
import json
from dataclasses import dataclass
from typing import Any

@dataclass
class Diagnostic:
    field: str
    status: str
    detail: str | None = None

@dataclass
class Envelope:
    value: Any
    diagnostics: list[Diagnostic]

def parse_envelope(raw: str) -> Envelope:
    """Parse a Prism WASM result into an Envelope."""
    obj = json.loads(raw)

    # Check for error envelope
    if 'error' in obj and obj.get('error'):
        raise RuntimeError(f"prism: {obj['error']}")

    diagnostics = [
        Diagnostic(
            field=d.get('field', ''),
            status=d.get('status', ''),
            detail=d.get('detail'),
        )
        for d in obj.get('diagnostics', [])
    ]

    return Envelope(value=obj.get('value'), diagnostics=diagnostics)
```

### Client wrapper

```python
class PrismClient:
    """High-level Prism client for Python."""

    def __init__(self, wasm_path: str):
        self._runtime = PrismRuntime(wasm_path)

    def encode_request(self, provider: str, text: str) -> Envelope:
        """SDK: encode text to provider request JSON."""
        raw = self._runtime.call("wasm_sdk_encode_req", provider, text)
        return parse_envelope(raw)

    def decode_response(self, provider: str, json_str: str) -> Envelope:
        """SDK: decode provider response to text."""
        raw = self._runtime.call("wasm_sdk_decode_resp", provider, json_str)
        return parse_envelope(raw)

    def encode_stream(self, provider: str, text: str) -> Envelope:
        """SDK: encode text to streaming provider request."""
        raw = self._runtime.call("wasm_sdk_encode_stream", provider, text)
        return parse_envelope(raw)

    def decode_sse(self, provider: str, sse_text: str) -> Envelope:
        """SDK: decode provider SSE to PrismEvent list."""
        raw = self._runtime.call("wasm_sdk_decode_sse", provider, sse_text)
        return parse_envelope(raw)

    def capability(self, provider: str) -> Envelope:
        """Query provider capability declaration."""
        raw = self._runtime.call("wasm_sdk_capability", provider)
        return parse_envelope(raw)

    def convert_request(self, source: str, json_str: str, target: str) -> Envelope:
        """Transit: convert request from source to target provider."""
        raw = self._runtime.call("wasm_convert_req", source, json_str, target)
        return parse_envelope(raw)

    def convert_response(self, source: str, json_str: str, target: str) -> Envelope:
        """Transit: convert response from source to target provider."""
        raw = self._runtime.call("wasm_convert_resp", source, json_str, target)
        return parse_envelope(raw)

    def convert_stream(self, source: str, sse_text: str, target: str) -> Envelope:
        """Transit: convert SSE stream from source to target provider."""
        raw = self._runtime.call("wasm_convert_stream", source, sse_text, target)
        return parse_envelope(raw)

    def list_providers(self) -> list[str]:
        """List all registered provider names."""
        raw = self._runtime.call("wasm_list_providers")
        return json.loads(raw)
```

### Alternative: wasmer-python

If you prefer [wasmer](https://github.com/wasmerio/wasmer-python):

```bash
pip install wasmer wasmer-compiler-cranelift
```

The loading and ABI code is similar — wasmer also exposes `Memory.data_ptr()` for direct linear memory access. The main difference is the instantiation API:

```python
from wasmer import Store, Module, Instance, Memory

store = Store()
module = Module(store, wasm_bytes)
instance = Instance(module)
memory = instance.exports.memory
```

### Important notes for Python

- Python 3 strings are Unicode; `.encode('utf-16-le')` gives you the raw UTF-16LE bytes.
- `struct.pack_into` writes directly to the memory buffer — fast and zero-copy.
- `memory.data_ptr()` returns a `ctypes` pointer — you can index it like a bytearray.
- wasmtime-py requires Python 3.8+. wasmer-python requires Python 3.6+.
- For async Python (asyncio), the WASM calls are synchronous but fast (~microseconds). Use `asyncio.to_thread()` if you need non-blocking behavior for very long operations.
- Consider using `importlib.resources` or `pathlib` to locate prism.wasm relative to your package.
