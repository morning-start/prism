package daemon

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"reflect"
	"strings"
	"testing"
)

// loadBackend reads a classic-wasm build and wraps it in the daemon backend.
// Run `moon build --target wasm` from the repo root first.
func loadBackend(t *testing.T) *WASMBackend {
	t.Helper()
	data, err := os.ReadFile("../../_build/wasm/debug/build/cmd/main/main.wasm")
	if err != nil {
		t.Fatalf("classic wasm build not found (%v), run: moon build --target wasm", err)
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

// envelopeValue extracts the "value" field from a D5 envelope result.
func envelopeValue(t *testing.T, resp *Response) any {
	t.Helper()
	m, ok := resp.Result.(map[string]any)
	if !ok {
		t.Fatalf("result must be an envelope object, got %T: %v", resp.Result, resp.Result)
	}
	v, ok := m["value"]
	if !ok {
		t.Fatalf("envelope missing value: %v", m)
	}
	return v
}

func TestServeEncodeRequest(t *testing.T) {
	backend := loadBackend(t)
	handler := NewHTTPHandler(backend, "test")
	resp := rpcPost(t, handler, `{"jsonrpc":"2.0","id":1,"method":"encode_request","params":{"provider":"openai","text":"Hello"}}`)
	if resp.Error != nil {
		t.Fatalf("unexpected error: %+v", resp.Error)
	}
	out, ok := envelopeValue(t, resp).(string)
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
	if out, ok := envelopeValue(t, resp).(string); !ok || out != "Hi" {
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
	cap, ok := envelopeValue(t, resp).(map[string]any)
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
	out, ok := envelopeValue(t, resp).(string)
	if !ok || !strings.Contains(out, `"messages"`) {
		t.Errorf("expected anthropic request with messages, got %v", resp.Result)
	}
}

func TestServeConvertStream(t *testing.T) {
	backend := loadBackend(t)
	handler := NewHTTPHandler(backend, "test")
	// OpenAI SSE -> Anthropic SSE via Lucent IR.
	sse := `data: {"id":"1","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":"Hi"},"finish_reason":null}]}` + "\n\ndata: [DONE]\n"
	params, err := json.Marshal(map[string]string{
		"from_provider": "openai-chat",
		"to_provider":   "anthropic",
		"sse":           sse,
	})
	if err != nil {
		t.Fatal(err)
	}
	body := `{"jsonrpc":"2.0","id":8,"method":"convert_stream","params":` + string(params) + `}`
	resp := rpcPost(t, handler, body)
	if resp.Error != nil {
		t.Fatalf("unexpected error: %+v", resp.Error)
	}
	out, ok := envelopeValue(t, resp).(string)
	if !ok || !strings.Contains(out, "data:") {
		t.Errorf("expected anthropic sse, got %v", resp.Result)
	}
}

func TestServePingAndListProviders(t *testing.T) {
	backend := loadBackend(t)
	handler := NewHTTPHandler(backend, "test")
	ping := rpcPost(t, handler, `{"jsonrpc":"2.0","id":5,"method":"ping","params":{}}`)
	if v, ok := envelopeValue(t, ping).(string); !ok || v != "pong" {
		t.Errorf("expected pong, got %v", ping.Result)
	}
	list := rpcPost(t, handler, `{"jsonrpc":"2.0","id":6,"method":"list_providers","params":{}}`)
	providers, ok := envelopeValue(t, list).([]any)
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

// TestResultIsEnvelope pins the D5 contract: every JSON-RPC result carries
// {"value":…,"diagnostics":[…]} — an empty diagnostics array must be present
// so clients can read it unconditionally.
func TestResultIsEnvelope(t *testing.T) {
	backend := loadBackend(t)
	handler := NewHTTPHandler(backend, "test")
	resp := rpcPost(t, handler, `{"jsonrpc":"2.0","id":1,"method":"encode_request",`+
		`"params":{"provider":"openai","text":"Hello"}}`)
	if resp.Error != nil {
		t.Fatalf("unexpected error: %+v", resp.Error)
	}
	m, ok := resp.Result.(map[string]any)
	if !ok {
		t.Fatalf("result must be an envelope object, got %T", resp.Result)
	}
	if _, ok := m["value"]; !ok {
		t.Error("missing value")
	}
	if _, ok := m["diagnostics"]; !ok {
		t.Error("missing diagnostics")
	}
}

var _ context.Context

// ── Task 3: HTTP SSE 流式通路 ──

// buildSSEFixture 返回各 provider 已验证的 SSE 文本
//（与 provider wbtest 使用同一批字符串，已由真实解析器验证）。
func buildSSEFixture(provider string) string {
	switch provider {
	case "openai":
		return "event: response.created\ndata: {\"type\":\"response.created\",\"response\":{\"id\":\"r_1\",\"model\":\"gpt-5\"}}\n\nevent: response.output_item.added\ndata: {\"type\":\"response.output_item.added\",\"output_index\":0,\"item\":{\"type\":\"message\",\"role\":\"assistant\",\"content\":[{\"type\":\"input_text\",\"text\":\"\"}]}}\n\nevent: response.content_part.added\ndata: {\"type\":\"response.content_part.added\",\"output_index\":0,\"content_index\":0,\"part\":{\"type\":\"output_text\",\"text\":\"\"}}\n\nevent: response.output_text.delta\ndata: {\"type\":\"response.output_text.delta\",\"output_index\":0,\"content_index\":0,\"delta\":\"Hello\"}\n\nevent: response.output_text.done\ndata: {\"type\":\"response.output_text.done\",\"output_index\":0,\"content_index\":0}\n\nevent: response.completed\ndata: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\",\"usage\":{\"input_tokens\":1,\"output_tokens\":1,\"total_tokens\":2}}}\n\n"
	case "openai-chat":
		return "data: {\"choices\":[{\"delta\":{\"role\":\"assistant\"}}]}\n\ndata: {\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}\n\ndata: {\"choices\":[{\"delta\":{\"content\":\" world\"}}]}\n\ndata: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n"
	case "anthropic":
		return "event: message_start\ndata: {\"type\":\"message_start\",\"message\":{\"id\":\"msg_1\",\"model\":\"claude-sonnet-4\"}}\n\nevent: content_block_start\ndata: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}\n\nevent: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Hello\"}}\n\nevent: content_block_stop\ndata: {\"type\":\"content_block_stop\",\"index\":0}\n\nevent: message_delta\ndata: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\"},\"usage\":{\"output_tokens\":5}}\n\nevent: message_stop\ndata: {\"type\":\"message_stop\"}\n\n"
	case "gemini":
		return "data: {\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"text\":\"Hello\"}]}}]}\ndata: {\"candidates\":[{\"content\":{\"role\":\"model\",\"parts\":[{\"text\":\" world\"}]},\"finishReason\":\"STOP\"}],\"usageMetadata\":{\"promptTokenCount\":10,\"candidatesTokenCount\":5,\"totalTokenCount\":15}}\n"
	default:
		return ""
	}
}

// sseFrame 是流式响应中的一个 SSE 帧。
type sseFrame struct {
	Event string
	Data  string
}

// parseSSEFrames 把 SSE 响应体切成帧（按 \n\n，忽略空块）。
func parseSSEFrames(body string) []sseFrame {
	var frames []sseFrame
	for _, block := range strings.Split(body, "\n\n") {
		block = strings.TrimSpace(block)
		if block == "" {
			continue
		}
		var f sseFrame
		for _, line := range strings.Split(block, "\n") {
			if strings.HasPrefix(line, "event: ") {
				f.Event = strings.TrimPrefix(line, "event: ")
			} else if strings.HasPrefix(line, "data: ") {
				f.Data += strings.TrimPrefix(line, "data: ")
			}
		}
		if f.Event != "" || f.Data != "" {
			frames = append(frames, f)
		}
	}
	return frames
}

// rpcStreamPost 发送带 Accept: text/event-stream 的 JSON-RPC 请求并返回 recorder。
func rpcStreamPost(t *testing.T, handler http.Handler, body string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodPost, "/v1", bytes.NewBufferString(body))
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "text/event-stream")
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, body = %s", rec.Code, rec.Body.String())
	}
	return rec
}

func decodeSSEParams(t *testing.T, provider, sse string) string {
	t.Helper()
	params, err := json.Marshal(map[string]string{"provider": provider, "sse": sse})
	if err != nil {
		t.Fatal(err)
	}
	return `{"jsonrpc":"2.0","id":1,"method":"decode_sse","params":` + string(params) + `}`
}

// decodeWhole 走同步路径解码整段 SSE，返回信封 value（事件数组）。
func decodeWhole(t *testing.T, handler http.Handler, provider, sse string) []any {
	t.Helper()
	resp := rpcPost(t, handler, decodeSSEParams(t, provider, sse))
	if resp.Error != nil {
		t.Fatalf("decode_sse error: %+v", resp.Error)
	}
	events, ok := envelopeValue(t, resp).([]any)
	if !ok {
		t.Fatalf("expected events array, got %T", resp.Result)
	}
	return events
}

// decodeFrameByFrame 走流式路径，把收到的各 SSE 帧里的事件重组成数组。
func decodeFrameByFrame(t *testing.T, handler http.Handler, provider, sse string) []any {
	t.Helper()
	rec := rpcStreamPost(t, handler, decodeSSEParams(t, provider, sse))
	var events []any
	for _, f := range parseSSEFrames(rec.Body.String()) {
		if f.Event == "done" {
			continue
		}
		var frame struct {
			Result map[string]any `json:"result"`
		}
		if err := json.Unmarshal([]byte(f.Data), &frame); err != nil {
			t.Fatalf("parse frame data: %v (frame=%q)", err, f.Data)
		}
		ev, ok := frame.Result["value"]
		if !ok {
			t.Fatalf("frame result missing value: %v", frame.Result)
		}
		events = append(events, ev)
	}
	return events
}

// 门禁：逐帧解码 == 全量解码（4 个基础 provider 全覆盖）
func TestFrameByFrameEqualsWholeText(t *testing.T) {
	backend := loadBackend(t)
	handler := NewHTTPHandler(backend, "test")
	for _, p := range []string{"openai", "openai-chat", "anthropic", "gemini"} {
		t.Run(p, func(t *testing.T) {
			sse := buildSSEFixture(p)
			whole := decodeWhole(t, handler, p, sse)
			framed := decodeFrameByFrame(t, handler, p, sse)
			if !reflect.DeepEqual(whole, framed) {
				t.Errorf("frame-by-frame diverges from whole-text decode:\n whole  = %v\n framed = %v", whole, framed)
			}
		})
	}
}

func TestSSEStreamingResponse(t *testing.T) {
	backend := loadBackend(t)
	handler := NewHTTPHandler(backend, "test")
	rec := rpcStreamPost(t, handler, decodeSSEParams(t, "anthropic", buildSSEFixture("anthropic")))
	if ct := rec.Header().Get("Content-Type"); !strings.HasPrefix(ct, "text/event-stream") {
		t.Fatalf("Content-Type = %q", ct)
	}
	frames := parseSSEFrames(rec.Body.String())
	if len(frames) < 2 {
		t.Fatalf("expected multiple frames, got %d", len(frames))
	}
	if frames[len(frames)-1].Event != "done" {
		t.Errorf("last frame event = %q, want done", frames[len(frames)-1].Event)
	}
}

// 同一请求不带 Accept 头 → 仍走同步 JSON，形状为信封
func TestSyncPathUnaffectedByStreaming(t *testing.T) {
	backend := loadBackend(t)
	handler := NewHTTPHandler(backend, "test")
	resp := rpcPost(t, handler, decodeSSEParams(t, "anthropic", buildSSEFixture("anthropic")))
	if resp.Error != nil {
		t.Fatalf("unexpected error: %+v", resp.Error)
	}
	m, ok := resp.Result.(map[string]any)
	if !ok {
		t.Fatalf("result must be an envelope object, got %T", resp.Result)
	}
	if _, ok := m["value"]; !ok {
		t.Error("missing value")
	}
	if _, ok := m["diagnostics"]; !ok {
		t.Error("missing diagnostics")
	}
}
