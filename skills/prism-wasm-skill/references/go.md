# Go WASM Integration for Prism

## Quick Start

If you just want to use Prism from Go, install the existing wrapper:

```bash
go get github.com/morning-start/prism/wrappers/go
```

```go
import prism "github.com/morning-start/prism/wrappers/go"

//go:embed path/to/prism.wasm
var prismWasm []byte

client, err := prism.New(prismWasm)
if err != nil {
    log.Fatal(err)
}
defer client.Close()

// SDK mode: encode a text request for OpenAI
envelope, err := client.EncodeRequest("openai", "Hello, world!", nil)
if err != nil {
    log.Fatal(err)
}
fmt.Println(envelope.Value)

// Transit mode: convert OpenAI request to Anthropic format
envelope, err = client.Convert("openai", "anthropic", "request", openaiJSON)
```

## Building Your Own Wrapper

If you need a custom implementation, use [wazero](https://github.com/tetratelabs/wazero) — a pure-Go WASM runtime with zero CGo dependencies.

### Loading the WASM module

```go
import (
    "context"
    "github.com/tetratelabs/wazero"
    "github.com/tetratelabs/wazero/api"
)

func loadPrism(wasmBytes []byte) (api.Module, wazero.Runtime, error) {
    ctx := context.Background()
    rt := wazero.NewRuntime(ctx)

    // WASI support needed for MoonBit runtime (stdout/stderr)
    config := wazero.NewModuleConfig().WithStdout(nil).WithStderr(nil)
    mod, err := rt.InstantiateWithConfig(ctx, wasmBytes, config)
    if err != nil {
        rt.Close(ctx)
        return nil, nil, err
    }
    return mod, rt, nil
}
```

### String ABI implementation

```go
import "unicode/utf16"

const scratchStart = uint32(0x0400)
const scratchStride = uint32(512)

// writeString writes a Go string to WASM linear memory at ptr.
// Returns the ptr to pass to the WASM function.
func writeString(mem api.Memory, ptr uint32, s string) (uint32, error) {
    units := utf16.Encode([]rune(s))
    // Length header at ptr-4: u32 LE, count of UTF-16 code units
    if !mem.WriteUint32Le(ptr-4, uint32(len(units))) {
        return 0, fmt.Errorf("write string header at %x", ptr)
    }
    // UTF-16LE payload at ptr
    buf := make([]byte, 2*len(units))
    for j, u := range units {
        buf[2*j] = byte(u)
        buf[2*j+1] = byte(u >> 8)
    }
    if !mem.Write(ptr, buf) {
        return 0, fmt.Errorf("write string payload at %x", ptr)
    }
    return ptr, nil
}

// readString reads a WASM string from linear memory at ptr.
func readString(mem api.Memory, ptr uint32) (string, error) {
    // Read u32 length at ptr-4
    lenBytes, ok := mem.Read(ptr-4, 4)
    if !ok {
        return "", fmt.Errorf("read result length at %x", ptr)
    }
    strLen := uint32(lenBytes[0]) | uint32(lenBytes[1])<<8 |
              uint32(lenBytes[2])<<16 | uint32(lenBytes[3])<<24

    // Read UTF-16LE payload
    payload, ok := mem.Read(ptr, uint32(2*strLen))
    if !ok {
        return "", fmt.Errorf("read result payload at %x", ptr)
    }
    units := make([]uint16, strLen)
    for i := uint32(0); i < strLen; i++ {
        units[i] = uint16(payload[2*i]) | uint16(payload[2*i+1])<<8
    }
    return string(utf16.Decode(units)), nil
}
```

### Calling a WASM export

```go
func callExport(mod api.Module, funcName string, args ...string) (string, error) {
    ctx := context.Background()
    exp := mod.ExportedFunction(funcName)
    if exp == nil {
        return "", fmt.Errorf("export not found: %s", funcName)
    }

    mem := mod.Memory()
    ptr := scratchStart
    callArgs := make([]uint64, len(args))
    for i, s := range args {
        p, err := writeString(mem, ptr, s)
        if err != nil {
            return "", err
        }
        callArgs[i] = uint64(p)
        ptr += scratchStride
    }

    results, err := exp.Call(ctx, callArgs...)
    if err != nil {
        return "", fmt.Errorf("WASM call %s: %w", funcName, err)
    }
    return readString(mem, uint32(results[0]))
}
```

### Envelope parsing

```go
type Envelope struct {
    Value       json.RawMessage `json:"value"`
    Diagnostics []Diagnostic    `json:"diagnostics"`
}

type Diagnostic struct {
    Field  string `json:"field"`
    Status string `json:"status"`
    Detail string `json:"detail,omitempty"`
}

func parseEnvelope(raw string) (*Envelope, error) {
    // Check for error envelope first
    if strings.HasPrefix(raw, `{"error":`) {
        var errResp struct{ Error string `json:"error"` }
        if json.Unmarshal([]byte(raw), &errResp) == nil && errResp.Error != "" {
            return nil, fmt.Errorf("prism: %s", errResp.Error)
        }
    }
    var env Envelope
    if err := json.Unmarshal([]byte(raw), &env); err != nil {
        return nil, fmt.Errorf("parse envelope: %w", err)
    }
    return &env, nil
}
```

### Important notes for Go

- wazero is the recommended runtime (pure Go, no CGo). wasmer-go also works.
- Go strings are UTF-8; you must convert to/from UTF-16LE for the WASM boundary.
- The `unicode/utf16` stdlib handles BMP and supplementary characters correctly.
- Use `//go:embed` to bundle prism.wasm into your binary, or load from filesystem.
- Always call `_start` after instantiation (wazero's `InstantiateWithConfig` does this automatically for WASI modules).

### Single Event Stream Conversion Example

```go
// Convert a single SSE event from OpenAI to Anthropic
openaiEvent := "data: {\"id\":\"1\",\"object\":\"chat.completion.chunk\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hello\"},\"finish_reason\":null}]}\n\n"
result, err := client.ConvertStreamEvent("openai-chat", openaiEvent, "anthropic")
if err != nil {
    log.Fatal(err)
}
fmt.Println(result.Value) // Anthropic-format SSE event

// Convert stream end event
doneEvent := "data: [DONE]\n\n"
endResult, err := client.ConvertStreamEvent("openai-chat", doneEvent, "anthropic")
if err != nil {
    log.Fatal(err)
}
fmt.Println(endResult.Value) // Anthropic's message_stop event
```
