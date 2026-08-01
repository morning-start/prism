// Command prism-daemon runs the Prism Gateway Daemon: a JSON-RPC 2.0
// HTTP service that fronts the Prism WASM conversion core.
//
//   prism-daemon --wasm <path> [--listen 127.0.0.1:8765]
package main

import (
	"context"
	"flag"
	"log"
	"os"
	"os/signal"
	"syscall"

	daemon "github.com/morning-start/prism/transport/daemon"
)

const version = "0.1.0"

func main() {
	wasmPath := flag.String("wasm", "_build/wasm/debug/build/cmd/main/main.wasm", "path to prism.wasm (classic wasm target)")
	listen := flag.String("listen", "127.0.0.1:8765", "HTTP listen address")
	flag.Parse()

	wasmBytes, err := os.ReadFile(*wasmPath)
	if err != nil {
		log.Fatalf("read wasm: %v", err)
	}
	backend, err := daemon.NewWASMBackend(wasmBytes)
	if err != nil {
		log.Fatalf("load wasm backend: %v", err)
	}
	defer backend.Close()

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	if err := daemon.ListenAndServe(ctx, backend, *listen, version); err != nil {
		log.Printf("daemon stopped: %v", err)
	}
}
