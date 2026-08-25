# Rust WASM Integration for Prism

## Recommended Runtime: wasmtime

Use [wasmtime](https://wasmtime.dev/) — the Bytecode Alliance's production WASM runtime for Rust. It handles WASI, linear memory access, and has excellent Rust ergonomics.

### Cargo.toml

```toml
[dependencies]
wasmtime = "32"          # check for latest version
wasmtime-wasi = "32"     # WASI support for MoonBit runtime
serde = { version = "1", features = ["derive"] }
serde_json = "1"
```

### Loading the WASM module

```rust
use wasmtime::*;
use wasmtime_wasi::WasiCtxBuilder;

struct PrismRuntime {
    engine: Engine,
    instance: Instance,
    store: Store<WasiCtx>,
}

impl PrismRuntime {
    fn new(wasm_bytes: &[u8]) -> Result<Self, Box<dyn std::error::Error>> {
        let engine = Engine::default();
        let wasi = WasiCtxBuilder::new().build();
        let mut store = Store::new(&engine, wasi);

        let mut linker = Linker::new(&engine);
        wasmtime_wasi::add_to_linker(&mut linker, |ctx| ctx)?;

        let instance = linker.instantiate(&mut store, wasm_bytes)?;

        // Call _start to initialize MoonBit runtime
        if let Some(start) = instance.get_typed_func::<(), ()>(&mut store, "_start") {
            start.call(&mut store, ())?;
        }

        Ok(Self { engine, instance, store })
    }
}
```

### String ABI implementation

Prism uses UTF-16LE in linear memory. Rust strings are UTF-8, so conversion is needed.

```rust
const SCRATCH_START: u32 = 0x0400;
const SCRATCH_STRIDE: u32 = 512;

/// Write a Rust string to WASM linear memory in Prism's UTF-16LE format.
/// Returns the ptr to pass as the i32 argument.
fn write_string(memory: &mut Memory, store: &mut impl AsContextMut, ptr: u32, s: &str) -> u32 {
    let utf16: Vec<u16> = s.encode_utf16().collect();
    let len = utf16.len() as u32;

    // Write length header at ptr - 4 (u32 LE, count of UTF-16 code units)
    let data = memory.data_mut(store);
    let len_bytes = len.to_le_bytes();
    let hdr_offset = (ptr - 4) as usize;
    data[hdr_offset..hdr_offset + 4].copy_from_slice(&len_bytes);

    // Write UTF-16LE payload at ptr
    let payload_offset = ptr as usize;
    for (i, unit) in utf16.iter().enumerate() {
        let bytes = unit.to_le_bytes();
        let offset = payload_offset + 2 * i;
        data[offset] = bytes[0];
        data[offset + 1] = bytes[1];
    }

    ptr
}

/// Read a WASM string from linear memory (Prism's UTF-16LE format).
fn read_string(memory: &Memory, store: &impl AsContext, ptr: u32) -> String {
    let data = memory.data(store);
    let hdr_offset = (ptr - 4) as usize;

    // Read u32 length
    let len = u32::from_le_bytes([
        data[hdr_offset],
        data[hdr_offset + 1],
        data[hdr_offset + 2],
        data[hdr_offset + 3],
    ]);

    // Read UTF-16LE payload
    let payload_offset = ptr as usize;
    let mut units = Vec::with_capacity(len as usize);
    for i in 0..len {
        let lo = data[payload_offset + 2 * i as usize];
        let hi = data[payload_offset + 2 * i as usize + 1];
        units.push(u16::from_le_bytes([lo, hi]));
    }

    String::from_utf16_lossy(&units)
}
```

### Calling a WASM export

```rust
impl PrismRuntime {
    fn call(&mut self, func_name: &str, args: &[&str]) -> Result<String, Box<dyn std::error::Error>> {
        let func = self.instance
            .get_func(&mut self.store, func_name)
            .ok_or_else(|| format!("WASM export not found: {}", func_name))?;

        let memory = self.instance
            .get_memory(&mut self.store, "memory")
            .ok_or("WASM module has no exported memory")?;

        // Write each argument to scratch region
        let mut ptrs: Vec<Val> = Vec::with_capacity(args.len());
        let mut ptr = SCRATCH_START;
        for arg in args {
            let p = write_string(&mut memory, &mut self.store, ptr, arg);
            ptrs.push(Val::I32(p as i32));
            ptr += SCRATCH_STRIDE;
        }

        let mut results = vec![Val::I32(0)];
        func.call(&mut self.store, &ptrs, &mut results)?;

        let result_ptr = results[0].unwrap_i32() as u32;
        Ok(read_string(&memory, &self.store, result_ptr))
    }
}
```

### Envelope parsing

```rust
use serde::{Deserialize, Serialize};

#[derive(Debug, Serialize, Deserialize)]
pub struct Diagnostic {
    pub field: String,
    pub status: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub detail: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Envelope {
    pub value: serde_json::Value,
    pub diagnostics: Vec<Diagnostic>,
}

#[derive(Debug, Serialize, Deserialize)]
struct ErrorEnvelope {
    error: String,
    diagnostics: Vec<Diagnostic>,
}

fn parse_envelope(raw: &str) -> Result<Envelope, Box<dyn std::error::Error>> {
    // Check for error envelope first
    if raw.starts_with(r#"{"error":"#) {
        if let Ok(err) = serde_json::from_str::<ErrorEnvelope>(raw) {
            if !err.error.is_empty() {
                return Err(format!("prism: {}", err.error).into());
            }
        }
    }
    Ok(serde_json::from_str(raw)?)
}
```

### Client wrapper

```rust
pub struct PrismClient {
    runtime: PrismRuntime,
}

impl PrismClient {
    pub fn new(wasm_bytes: &[u8]) -> Result<Self, Box<dyn std::error::Error>> {
        Ok(Self {
            runtime: PrismRuntime::new(wasm_bytes)?,
        })
    }

    /// SDK: encode a text request to provider JSON
    pub fn encode_request(&mut self, provider: &str, text: &str) -> Result<Envelope, Box<dyn std::error::Error>> {
        let raw = self.runtime.call("wasm_sdk_encode_req", &[provider, text])?;
        parse_envelope(&raw)
    }

    /// SDK: decode provider response JSON to text
    pub fn decode_response(&mut self, provider: &str, json: &str) -> Result<Envelope, Box<dyn std::error::Error>> {
        let raw = self.runtime.call("wasm_sdk_decode_resp", &[provider, json])?;
        parse_envelope(&raw)
    }

    /// Transit: convert request from one provider to another
    pub fn convert_request(&mut self, from: &str, json: &str, to: &str) -> Result<Envelope, Box<dyn std::error::Error>> {
        let raw = self.runtime.call("wasm_convert_req", &[from, json, to])?;
        parse_envelope(&raw)
    }

    /// List all registered providers
    pub fn list_providers(&mut self) -> Result<Vec<String>, Box<dyn std::error::Error>> {
        let raw = self.runtime.call("wasm_list_providers", &[])?;
        Ok(serde_json::from_str(&raw)?)
    }
}
```

### Important notes for Rust

- wasmtime is the recommended runtime; wasmer also works but wasmtime has better WASI support.
- `String::from_utf16_lossy` handles malformed surrogate pairs gracefully (replaces with U+FFFD).
- If you need strict validation, use `String::from_utf16` and handle the error.
- Consider embedding prism.wasm with `include_bytes!()` for single-binary distribution.
- For `no_std` environments, you'll need to handle UTF-16 conversion manually (the `alloc` crate provides `String`/`Vec`).
- The scratch region (0x0400-0x1000) gives ~3KB for arguments. Each string gets 512 bytes of scratch space, so up to 3 arguments fit comfortably. For very long strings (>250 UTF-16 code units), consider using a larger stride or dynamic allocation.

### Handling large strings (CRITICAL)

The fixed scratch region (0x0400, stride 512) only holds ~252 UTF-16 code units per argument. Real-world JSON payloads (especially Anthropic requests with tool use, images, or extended thinking) often exceed this. Writing past the scratch boundary corrupts the MoonBit GC heap or panics with `index out of bounds`.

**Solution**: dynamically grow WASM linear memory and write large strings at the end of the grown region, safely past the GC heap.

```rust
fn write_string(&mut self, ptr: u32, s: &str) -> u32 {
    let units: Vec<u16> = s.encode_utf16().collect();
    let len = units.len() as u32;
    let needed = 4 + len * 2;

    let write_ptr = if needed <= SCRATCH_STRIDE {
        ptr  // small string: use fixed scratch slot
    } else {
        // large string: grow memory, write at the old end (+4 for header safety)
        let current_pages = self.memory.size(&self.store);
        let current_bytes = (current_pages as usize) * 65536;
        let grow_pages = ((needed as usize + 65535) / 65536) as u64;
        if grow_pages > 0 {
            self.memory.grow(&mut self.store, grow_pages).unwrap();
        }
        (current_bytes + 4) as u32  // +4: header at ptr-4 must not land in old memory
    };

    // write header + payload at write_ptr (same as before)
    // ...
    write_ptr
}
```

Key points:
- `write_string` returns the actual `ptr` where the string was written — pass this to the WASM function, not the original scratch slot
- The `+4` offset ensures the length header at `write_ptr - 4` stays within the newly allocated pages
- MoonBit's GC heap grows upward from ~0x1000 but won't reach the memory end for typical workloads
- Each `write_string` call may grow memory independently — multiple large arguments each get their own region
