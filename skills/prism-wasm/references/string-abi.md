# String ABI Specification

How strings pass between host and WASM in prism.wasm.

## Memory Layout

```
┌──────────────┬─────────────────────┐
│ Length (4B)   │ UTF-16LE Data       │
│ u32 LE       │ (byte_len bytes)    │
└──────────────┴─────────────────────┘
  ptr - 4        ptr
```

- **Length**: u32 little-endian byte count at `ptr - 4`
- **Data**: UTF-16LE encoded characters at `ptr`
- **Byte length** = character count × 2

## Write String (Host → WASM)

```javascript
function writeString(memory, ptr, str) {
  const byteLen = str.length * 2;
  new DataView(memory.buffer).setUint32(ptr - 4, byteLen, true);
  const view = new Uint16Array(memory.buffer, ptr, str.length);
  for (let i = 0; i < str.length; i++) view[i] = str.charCodeAt(i);
}
```

```python
def write_string(memory, ptr, s):
    encoded = s.encode('utf-16-le')
    memory.write(struct.pack('<I', len(encoded)), ptr - 4)
    memory.write(encoded, ptr)
```

## Read String (WASM → Host)

```javascript
function readString(memory, ptr) {
  const byteLen = new DataView(memory.buffer).getUint32(ptr - 4, true);
  const view = new Uint16Array(memory.buffer, ptr, byteLen / 2);
  return String.fromCharCode(...view);
}
```

```python
def read_string(memory, ptr):
    byte_len = struct.unpack('<I', memory.read(ptr - 4, 4))[0]
    return memory.read(ptr, byte_len).decode('utf-16-le')
```

## Scratch Buffer

For passing multiple string arguments:

1. `wasm_init_scratch(size)` → bufPtr
2. Write strings at offsets (stride 8192 recommended)
3. `wasm_read_scratch_arg(bufPtr, offset)` reads them back

```
bufPtr + 0      → arg 0
bufPtr + 8192   → arg 1
bufPtr + 16384  → arg 2
```

## Fixed Scratch Region

WASM has a fixed scratch region at 0x0400 with stride 512. For strings < 252 characters, write directly there. For larger strings, use `wasm_init_scratch`.

## MoonBit Object Header

All MoonBit objects in WASM have an 8-byte header (rc + meta). `wasm_init_scratch` returns a pointer to the data payload (after the header).
