package prism

import (
	"context"
	"net"
	"net/http"
	"os"
	"strings"
	"testing"

	daemon "github.com/morning-start/prism/transport/daemon"
)

// startTestDaemon loads the WASM backend and starts HTTP + UDS + WS
// listeners in-process, returning their addresses.
func startTestDaemon(t *testing.T) (httpAddr, udsPath, wsAddr string) {
	t.Helper()
	data, err := os.ReadFile("../../_build/wasm/debug/build/cmd/main/main.wasm")
	if err != nil {
		t.Fatalf("classic wasm build not found (%v), run: moon build --target wasm", err)
	}
	backend, err := daemon.NewWASMBackend(data)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = backend.Close() })

	// HTTP listener
	httpLn, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = httpLn.Close() })
	httpAddr = httpLn.Addr().String()
	httpSrv := &http.Server{Handler: daemon.NewHTTPHandler(backend, "test")}
	go func() { _ = httpSrv.Serve(httpLn) }()

	// UDS listener
	udsPath = t.TempDir() + "/prism.sock"
	udsCtx, udsCancel := context.WithCancel(context.Background())
	t.Cleanup(udsCancel)
	go func() { _ = daemon.ListenUDS(udsCtx, backend, udsPath, "test") }()

	// WS listener (HTTP upgrade on /ws)
	wsLn, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = wsLn.Close() })
	wsAddr = wsLn.Addr().String()
	mux := http.NewServeMux()
	mux.Handle("/v1", daemon.NewHTTPHandler(backend, "test"))
	mux.Handle("/health", daemon.NewHTTPHandler(backend, "test"))
	mux.HandleFunc("/ws", func(w http.ResponseWriter, r *http.Request) {
		daemon.ServeWS(r.Context(), backend, w, r)
	})
	wsSrv := &http.Server{Handler: mux}
	go func() { _ = wsSrv.Serve(wsLn) }()
	return httpAddr, udsPath, wsAddr
}

// testWithTransports runs fn against all three transports (可插拔契约).
func testWithTransports(t *testing.T, httpAddr, udsPath, wsAddr string, fn func(t *testing.T, c *Client)) {
	t.Helper()
	transports := map[string]Transport{
		"http": NewHTTPTransport("http://" + httpAddr + "/v1"),
		"uds":  NewUDSTransport(udsPath),
		"ws":   NewWSTransport("ws://" + wsAddr + "/ws"),
	}
	for name, tr := range transports {
		t.Run(name, func(t *testing.T) {
			fn(t, NewClient(tr))
		})
	}
}

// TestTransportPing runs ping across all three transports.
func TestTransportPing(t *testing.T) {
	httpAddr, udsPath, wsAddr := startTestDaemon(t)
	testWithTransports(t, httpAddr, udsPath, wsAddr, func(t *testing.T, c *Client) {
		v, err := c.Ping(context.Background())
		if err != nil {
			t.Fatalf("ping: %v", err)
		}
		if v != "pong" {
			t.Fatalf("ping = %q, want pong", v)
		}
	})
}

// TestTransportEncodeRequest runs encode_request across all transports and
// checks the envelope value is a valid provider JSON request.
func TestTransportEncodeRequest(t *testing.T) {
	httpAddr, udsPath, wsAddr := startTestDaemon(t)
	testWithTransports(t, httpAddr, udsPath, wsAddr, func(t *testing.T, c *Client) {
		env, err := c.EncodeRequest(context.Background(), "openai-chat", "Hi")
		if err != nil {
			t.Fatalf("encode_request: %v", err)
		}
		raw, err := env.ValueString()
		if err != nil {
			t.Fatalf("value string: %v", err)
		}
		if !strings.Contains(raw, `"messages"`) {
			t.Fatalf("provider JSON missing messages: %s", raw)
		}
	})
}

// TestTransportConvert runs convert across all transports and checks the
// envelope carries a diagnostics array.
func TestTransportConvert(t *testing.T) {
	httpAddr, udsPath, wsAddr := startTestDaemon(t)
	testWithTransports(t, httpAddr, udsPath, wsAddr, func(t *testing.T, c *Client) {
		// build a minimal openai-chat request through the same client
		req, err := c.EncodeRequest(context.Background(), "openai-chat", "Hi")
		if err != nil {
			t.Fatal(err)
		}
		reqJSON, _ := req.ValueString()
		env, err := c.Convert(context.Background(), "openai-chat", "anthropic", "request", reqJSON)
		if err != nil {
			t.Fatalf("convert: %v", err)
		}
		if env.Diagnostics == nil {
			t.Error("convert envelope missing diagnostics")
		}
		raw, err := env.ValueString()
		if err != nil {
			t.Fatalf("convert value: %v", err)
		}
		if !strings.Contains(raw, "system") && !strings.Contains(raw, "messages") {
			t.Fatalf("converted anthropic request missing expected shape: %s", raw)
		}
	})
}

// TestTransportStreamDecodeSSE streams decode_sse over each transport and
// asserts multiple events plus a done marker.
func TestTransportStreamDecodeSSE(t *testing.T) {
	httpAddr, udsPath, wsAddr := startTestDaemon(t)
	testWithTransports(t, httpAddr, udsPath, wsAddr, func(t *testing.T, c *Client) {
		sse := "data: {\"choices\":[{\"delta\":{\"role\":\"assistant\"}}]}\n\ndata: {\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}\n\ndata: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}}]}\n\ndata: [DONE]\n"
		events, err := c.StreamDecodeSSE(context.Background(), "openai-chat", sse)
		if err != nil {
			t.Fatalf("stream decode_sse: %v", err)
		}
		if len(events) < 2 {
			t.Fatalf("expected multiple events, got %d", len(events))
		}
		var sawDone bool
		for _, ev := range events {
			if ev.Type == "done" {
				sawDone = true
			}
		}
		if !sawDone {
			t.Error("missing done event in stream")
		}
	})
}

// TestTransportUnknownMethod returns a JSON-RPC error on all transports.
func TestTransportUnknownMethod(t *testing.T) {
	httpAddr, udsPath, wsAddr := startTestDaemon(t)
	testWithTransports(t, httpAddr, udsPath, wsAddr, func(t *testing.T, c *Client) {
		_, err := c.CallRaw(context.Background(), "nope", map[string]any{})
		if err == nil {
			t.Fatal("expected error for unknown method")
		}
		if !strings.Contains(err.Error(), "method") {
			t.Fatalf("error should mention method, got %v", err)
		}
	})
}
