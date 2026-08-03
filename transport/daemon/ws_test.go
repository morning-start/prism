package daemon

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/coder/websocket"
)

// wsDial connects a websocket client to a handler at the given path.
func wsDial(t *testing.T, handler http.Handler, path string) *websocket.Conn {
	t.Helper()
	srv := httptest.NewServer(handler)
	t.Cleanup(srv.Close)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	t.Cleanup(cancel)
	conn, _, err := websocket.Dial(ctx, "ws"+strings.TrimPrefix(srv.URL, "http")+path, nil)
	if err != nil {
		t.Fatalf("ws dial: %v", err)
	}
	t.Cleanup(func() { _ = conn.Close(websocket.StatusNormalClosure, "test done") })
	return conn
}

// wsRPC sends one JSON-RPC request frame and reads the first response frame.
func wsRPC(t *testing.T, conn *websocket.Conn, body string) *Response {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := conn.Write(ctx, websocket.MessageText, []byte(body)); err != nil {
		t.Fatalf("ws write: %v", err)
	}
	_, data, err := conn.Read(ctx)
	if err != nil {
		t.Fatalf("ws read: %v", err)
	}
	var resp Response
	if err := json.Unmarshal(data, &resp); err != nil {
		t.Fatalf("decode ws response: %v", err)
	}
	return &resp
}

// wsServe wraps a backend in an HTTP handler that also serves the WS endpoint.
func wsServe(backend Backend) http.Handler {
	mux := http.NewServeMux()
	h := NewHTTPHandler(backend, "test")
	mux.Handle("/v1", h)
	mux.Handle("/health", h)
	mux.HandleFunc("/ws", func(w http.ResponseWriter, r *http.Request) {
		ServeWS(r.Context(), backend, w, r)
	})
	return mux
}

// TestWSJSONRPCEncodeRequest exercises a synchronous JSON-RPC request over a
// single WebSocket frame (ARCHITECTURE.md §5.3).
func TestWSJSONRPCEncodeRequest(t *testing.T) {
	backend := loadBackend(t)
	conn := wsDial(t, wsServe(backend), "/ws")

	resp := wsRPC(t, conn, `{"jsonrpc":"2.0","id":1,"method":"encode_request","params":{"provider":"openai-chat","text":"Hi"}}`)
	if resp.Error != nil {
		t.Fatalf("encode_request error: %+v", resp.Error)
	}
	raw, ok := envelopeValue(t, resp).(string)
	if !ok {
		t.Fatalf("encode_request value is not a string: %T", envelopeValue(t, resp))
	}
	if !strings.Contains(raw, `"messages"`) {
		t.Fatalf("provider JSON missing messages: %s", raw)
	}
}

// TestWSJSONRPCPing exercises the simplest method over WS.
func TestWSJSONRPCPing(t *testing.T) {
	backend := loadBackend(t)
	conn := wsDial(t, wsServe(backend), "/ws")

	resp := wsRPC(t, conn, `{"jsonrpc":"2.0","id":2,"method":"ping","params":{}}`)
	if resp.Error != nil {
		t.Fatalf("ping error: %+v", resp.Error)
	}
	if v := envelopeValue(t, resp); v != "pong" {
		t.Fatalf("ping value = %v, want pong", v)
	}
}

// TestWSJSONRPCUnknownMethod checks JSON-RPC error framing over WS.
func TestWSJSONRPCUnknownMethod(t *testing.T) {
	backend := loadBackend(t)
	conn := wsDial(t, wsServe(backend), "/ws")

	resp := wsRPC(t, conn, `{"jsonrpc":"2.0","id":3,"method":"nope","params":{}}`)
	if resp.Error == nil {
		t.Fatal("expected error for unknown method")
	}
}

// TestWSStreamingDecodeSSE exercises the streaming path over WS: one request
// frame, then multiple result frames (one per event) and a done frame.
func TestWSStreamingDecodeSSE(t *testing.T) {
	backend := loadBackend(t)
	conn := wsDial(t, wsServe(backend), "/ws")

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	params, err := json.Marshal(map[string]string{
		"provider": "anthropic",
		"sse":      buildSSEFixture("anthropic"),
	})
	if err != nil {
		t.Fatal(err)
	}
	body := `{"jsonrpc":"2.0","id":4,"method":"decode_sse","params":` + string(params) + `}`
	if err := conn.Write(ctx, websocket.MessageText, []byte(body)); err != nil {
		t.Fatalf("ws write: %v", err)
	}

	var frames int
	var sawDone bool
	for frames < 20 {
		_, data, err := conn.Read(ctx)
		if err != nil {
			t.Fatalf("ws read: %v", err)
		}
		var resp Response
		if err := json.Unmarshal(data, &resp); err != nil {
			t.Fatalf("decode ws frame: %v", err)
		}
		if resp.Error != nil {
			t.Fatalf("stream error: %+v", resp.Error)
		}
		if m, ok := resp.Result.(map[string]any); ok {
			if v, ok := m["value"]; ok {
				if mm, ok := v.(map[string]any); ok {
					if t2, _ := mm["type"].(string); t2 == "done" {
						sawDone = true
						break
					}
				}
			}
		}
		frames++
	}
	if frames < 2 {
		t.Fatalf("expected multiple ws frames, got %d", frames)
	}
	if !sawDone {
		t.Error("missing done frame in ws stream")
	}
}
