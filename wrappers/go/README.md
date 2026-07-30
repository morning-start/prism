# Prism WASM — Go Wrapper

> [Prism](https://github.com/morning-start/prism) LLM protocol converter - Go WASM wrapper using wazero.

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
