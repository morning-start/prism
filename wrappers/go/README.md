# Prism WASM — Go Wrapper

> [Prism](https://github.com/morning-start/prism) LLM protocol converter - Go WASM wrapper using wazero.

## Prism String ABI

The classic `wasm` target exports each conversion as `(i32, ...) -> i32`. Every
String argument is passed as a linear-memory address:

- `u32 @ (ptr - 4)` = UTF-16 length in code units
- UTF-16LE payload starting at `ptr`
- the returned `i32` is an address with the same layout

The wrapper writes arguments into a scratch region below the MoonBit GC heap
and decodes the returned UTF-16 string. Verified end-to-end by
`TestABIIntegration` in `prism_test.go`.

## Build & Test

```bash
moon build --target wasm          # from repo root, then:
go test -v ./...
```

## Installation

```bash
go get github.com/morning-start/prism/wrappers/go
```

## Quick Start

```go
package main

import (
    "fmt"
    "log"
    "os"
    prism "github.com/morning-start/prism/wrappers/go"
)

func main() {
    wasmBytes, _ := os.ReadFile("prism.wasm")
    client, err := prism.New(wasmBytes)
    if err != nil {
        log.Fatal(err)
    }
    defer client.Close()

    // List providers
    providers := client.ListProviders()
    fmt.Println("Providers:", providers)

    // Encode a request
    reqJSON, err := client.EncodeRequest("openai", "你好", nil)
    if err != nil {
        log.Fatal(err)
    }
    fmt.Println("Request:", reqJSON)
}
```

## API

### Functions

| Method | Description |
|--------|-------------|
| `EncodeRequest(provider, text, opts?)` | Text → provider JSON |
| `DecodeResponse(provider, jsonStr)` | Provider JSON → text |
| `DecodeSSE(provider, sseStr)` | Provider SSE → Event list |
| `EncodeStream(provider, text, opts?)` | Text → streaming provider JSON |
| `Convert(from, to, direction, payload)` | Cross-provider conversion |
| `Capability(provider)` | Query provider capabilities |
| `ListProviders()` | List all available providers |
| `Ping()` | Health check |

## Development

```bash
go test -v ./...
```
