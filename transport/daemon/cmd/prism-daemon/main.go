// Command prism-daemon runs the Prism Gateway Daemon: a JSON-RPC 2.0
// HTTP service that fronts the Prism WASM conversion core.
//
//   prism-daemon --wasm <path> [--listen 127.0.0.1:8765] [--uds /tmp/prism.sock] [--ws :8766]
package main

import (
	"context"
	"flag"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"

	daemon "github.com/morning-start/prism/transport/daemon"
)

const version = "0.1.0"

func main() {
	wasmPath := flag.String("wasm", "_build/wasm/debug/build/cmd/main/main.wasm", "path to prism.wasm (classic wasm target)")
	listen := flag.String("listen", "127.0.0.1:8765", "HTTP listen address")
	udsPath := flag.String("uds", "", "Unix domain socket path (empty disables UDS)")
	wsAddr := flag.String("ws", "", "WebSocket listen address, e.g. :8766 (empty disables WS)")
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

	if *udsPath != "" {
		go func() {
			if err := daemon.ListenUDS(ctx, backend, *udsPath, version); err != nil && ctx.Err() == nil {
				log.Printf("uds listener stopped: %v", err)
			}
		}()
	}

	if *wsAddr != "" {
		mux := http.NewServeMux()
		mux.Handle("/v1", daemon.NewHTTPHandler(backend, version))
		mux.Handle("/health", daemon.NewHTTPHandler(backend, version))
		mux.HandleFunc("/ws", func(w http.ResponseWriter, r *http.Request) {
			daemon.ServeWS(r.Context(), backend, w, r)
		})
		go func() {
			if err := http.ListenAndServe(*wsAddr, mux); err != nil && ctx.Err() == nil {
				log.Printf("ws listener stopped: %v", err)
			}
		}()
	}

	if err := daemon.ListenAndServe(ctx, backend, *listen, version); err != nil {
		log.Printf("daemon stopped: %v", err)
	}
}
