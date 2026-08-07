package daemon

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// TestResolveFileURIs verifies that file:// strings inside a JSON payload are
// rewritten to data URIs by reading the file (so the pure wasm layer never
// sees a file_uri source).
func TestResolveFileURIs(t *testing.T) {
	dir := t.TempDir()
	png := filepath.Join(dir, "a.png")
	raw := []byte{0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x01, 0x02}
	if err := os.WriteFile(png, raw, 0o644); err != nil {
		t.Fatal(err)
	}

	payload := `{"model":"gpt-4o","messages":[{"role":"user","content":[` +
		`{"type":"image_url","image_url":{"url":"file://` + filepath.ToSlash(png) + `"}}` +
		`]}]}`
	out := resolveFileURIs(payload)
	if strings.Contains(out, "file://") {
		t.Fatalf("file:// not rewritten: %s", out)
	}
	if !strings.Contains(out, `"model":"gpt-4o"`) {
		t.Fatalf("non-file structure changed: %s", out)
	}
	// data URI with png mime + base64 payload
	want := "data:image/png;base64," + base64.StdEncoding.EncodeToString(raw)
	if !strings.Contains(out, want) {
		t.Fatalf("expected data uri %q in %s", want, out)
	}
}

// TestResolveFileURIs_NonJSON passthrough: raw SSE or non-JSON stays unchanged.
func TestResolveFileURIs_NonJSON(t *testing.T) {
	sse := "data: {\"choices\":[{\"delta\":{\"content\":\"Hi\"}}]}\n\n"
	if got := resolveFileURIs(sse); got != sse {
		t.Fatalf("non-JSON payload changed: %s", got)
	}
}

// TestResolveFileURIs_MissingFile keeps the original value (no crash), the
// conversion layer will surface its own diagnostic.
func TestResolveFileURIs_MissingFile(t *testing.T) {
	payload := `{"url":"file:///no/such/file.png"}`
	out := resolveFileURIs(payload)
	var m map[string]any
	if err := json.Unmarshal([]byte(out), &m); err != nil {
		t.Fatal(err)
	}
	if m["url"] != "file:///no/such/file.png" {
		t.Fatalf("expected original file:// kept, got %v", m["url"])
	}
}

// TestE2EConvertFileURIImage verifies the full HTTP path: a request carrying
// a file:// image URL is converted openai-chat -> anthropic without any
// file_uri Unsupported diagnostic (the daemon pre-reads the file to base64).
func TestE2EConvertFileURIImage(t *testing.T) {
	backend := loadBackend(t)
	defer backend.Close()
	handler := NewHTTPHandler(backend, "test")

	dir := t.TempDir()
	png := filepath.Join(dir, "a.png")
	raw := []byte{0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x01, 0x02}
	if err := os.WriteFile(png, raw, 0o644); err != nil {
		t.Fatal(err)
	}

	payload := `{"model":"gpt-4o","messages":[{"role":"user","content":[` +
		`{"type":"text","text":"看图"},` +
		`{"type":"image_url","image_url":{"url":"file://` + filepath.ToSlash(png) + `"}}` +
		`]}]}`
	rec := rpcStreamPost(t, handler, rpcParams(t, "convert", map[string]string{
		"from_provider": "openai-chat",
		"to_provider":   "anthropic",
		"direction":     "request",
		"payload":       payload,
	}))
	body := rec.Body.String()
	if strings.Contains(body, "file_uri") {
		t.Fatalf("file_uri diagnostic should not appear after pre-read: %s", truncate(body, 300))
	}
	// JSON-RPC 信封内 value 是转义 JSON 字符串：检查不含诊断 + 含 base64 负载
	if !strings.Contains(body, `"diagnostics":[]`) {
		t.Fatalf("expected no diagnostics in envelope: %s", truncate(body, 300))
	}
	if !strings.Contains(body, base64.StdEncoding.EncodeToString(raw)) {
		t.Fatalf("expected base64 image payload in output: %s", truncate(body, 300))
	}
}

// helper: request with bytes body via httptest
func streamPostBytes(t *testing.T, h http.Handler, body []byte) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodPost, "/", bytes.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}
