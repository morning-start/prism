package daemon

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
)

// loadBackend reads a classic-wasm build and wraps it in the daemon backend.
// Run `moon build --target wasm` from the repo root first.
func loadBackend(t *testing.T) *WASMBackend {
	t.Helper()
	data, err := os.ReadFile("../../_build/wasm/debug/build/cmd/main/main.wasm")
	if err != nil {
		t.Skipf("classic wasm build not found (%v), run: moon build --target wasm", err)
	}
	backend, err := NewWASMBackend(data)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = backend.Close() })
	return backend
}

func rpcPost(t *testing.T, handler http.Handler, body string) *Response {
	t.Helper()
	req := httptest.NewRequest(http.MethodPost, "/v1", bytes.NewBufferString(body))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", rec.Code, rec.Body.String())
	}
	var resp Response
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	return &resp
}

func TestServeEncodeRequest(t *testing.T) {
	backend := loadBackend(t)
	handler := NewHTTPHandler(backend, "test")
	resp := rpcPost(t, handler, `{"jsonrpc":"2.0","id":1,"method":"encode_request","params":{"provider":"openai","text":"Hello"}}`)
	if resp.Error != nil {
		t.Fatalf("unexpected error: %+v", resp.Error)
	}
	out, ok := resp.Result.(string)
	if !ok || !strings.Contains(out, `"text":"Hello"`) {
		t.Errorf("expected encoded request containing Hello, got %v", resp.Result)
	}
}

func TestServeDecodeResponse(t *testing.T) {
	backend := loadBackend(t)
	handler := NewHTTPHandler(backend, "test")
	body := `{"jsonrpc":"2.0","id":2,"method":"decode_response","params":{"provider":"openai-chat","json":"{\"id\":\"1\",\"object\":\"chat.completion\",\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"Hi\"},\"finish_reason\":\"stop\"}]}"}}`
	resp := rpcPost(t, handler, body)
	if resp.Error != nil {
		t.Fatalf("unexpected error: %+v", resp.Error)
	}
	if resp.Result != "Hi" {
		t.Errorf("expected Hi, got %v", resp.Result)
	}
}

func TestServeCapability(t *testing.T) {
	backend := loadBackend(t)
	handler := NewHTTPHandler(backend, "test")
	resp := rpcPost(t, handler, `{"jsonrpc":"2.0","id":3,"method":"capability","params":{"provider":"openai"}}`)
	if resp.Error != nil {
		t.Fatalf("unexpected error: %+v", resp.Error)
	}
	cap, ok := resp.Result.(map[string]any)
	if !ok || cap["provider"] != "openai" {
		t.Errorf("expected capability map with provider openai, got %v", resp.Result)
	}
	if _, ok := cap["model_pattern"]; !ok {
		t.Error("expected model_pattern in capability")
	}
}

func TestServeConvert(t *testing.T) {
	backend := loadBackend(t)
	handler := NewHTTPHandler(backend, "test")
	// OpenAI Responses request -> Anthropic request via Lucent IR.
	payload := `{"model":"gpt-4o","input":[{"type":"message","role":"user","content":[{"type":"input_text","text":"Hi"}]}]}`
	params, err := json.Marshal(map[string]string{
		"from_provider": "openai",
		"to_provider":   "anthropic",
		"direction":     "request",
		"payload":       payload,
	})
	if err != nil {
		t.Fatal(err)
	}
	body := `{"jsonrpc":"2.0","id":4,"method":"convert","params":` + string(params) + `}`
	resp := rpcPost(t, handler, body)
	if resp.Error != nil {
		t.Fatalf("unexpected error: %+v", resp.Error)
	}
	out, ok := resp.Result.(string)
	if !ok || !strings.Contains(out, `"messages"`) {
		t.Errorf("expected anthropic request with messages, got %v", resp.Result)
	}
}

func TestServePingAndListProviders(t *testing.T) {
	backend := loadBackend(t)
	handler := NewHTTPHandler(backend, "test")
	ping := rpcPost(t, handler, `{"jsonrpc":"2.0","id":5,"method":"ping","params":{}}`)
	if ping.Result != "pong" {
		t.Errorf("expected pong, got %v", ping.Result)
	}
	list := rpcPost(t, handler, `{"jsonrpc":"2.0","id":6,"method":"list_providers","params":{}}`)
	providers, ok := list.Result.([]any)
	if !ok || len(providers) == 0 {
		t.Fatalf("expected provider list, got %v", list.Result)
	}
	found := false
	for _, p := range providers {
		if p == "openai" {
			found = true
		}
	}
	if !found {
		t.Errorf("expected openai in providers, got %v", providers)
	}
}

func TestUnknownMethod(t *testing.T) {
	backend := loadBackend(t)
	handler := NewHTTPHandler(backend, "test")
	resp := rpcPost(t, handler, `{"jsonrpc":"2.0","id":7,"method":"nope","params":{}}`)
	if resp.Error == nil || resp.Error.Code != -32601 {
		t.Fatalf("expected method-not-found error, got %+v", resp.Error)
	}
}

func TestHealth(t *testing.T) {
	backend := loadBackend(t)
	handler := NewHTTPHandler(backend, "0.1.0")
	req := httptest.NewRequest(http.MethodGet, "/health", nil)
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d", rec.Code)
	}
	var health map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &health); err != nil {
		t.Fatal(err)
	}
	if health["status"] != "ok" || health["version"] != "0.1.0" {
		t.Errorf("unexpected health: %v", health)
	}
}

var _ context.Context
