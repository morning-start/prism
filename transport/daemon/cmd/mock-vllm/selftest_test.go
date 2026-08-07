package main

import (
	"bytes"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// postJSON 向 handler 发 JSON 请求，返回响应体。
func postJSON(t *testing.T, h http.Handler, path string, body any) string {
	t.Helper()
	raw, _ := json.Marshal(body)
	req := httptest.NewRequest(http.MethodPost, path, bytes.NewReader(raw))
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	if rec.Code != http.StatusOK {
		t.Fatalf("status %d: %s", rec.Code, rec.Body.String())
	}
	out, _ := io.ReadAll(rec.Body)
	return string(out)
}

// 自测 1：非流式 /v1/chat/completions 返回 message.reasoning。
func TestSelftestNonStreamReasoning(t *testing.T) {
	h := http.NewServeMux()
	h.HandleFunc("/v1/chat/completions", handleChat)
	body := postJSON(t, h, "/v1/chat/completions",
		map[string]any{"model": "qwen3", "stream": false})
	var d struct {
		Choices []struct {
			Message map[string]any `json:"message"`
		} `json:"choices"`
	}
	if err := json.Unmarshal([]byte(body), &d); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	msg := d.Choices[0].Message
	if _, ok := msg["reasoning"]; !ok {
		t.Fatalf("message missing reasoning field: %v", msg)
	}
	r, _ := msg["reasoning"].(string)
	if !strings.Contains(r, "9.11") {
		t.Fatalf("reasoning content unexpected: %s", r)
	}
	t.Logf("OK: non-stream message.reasoning present (%d chars)", len(r))
}

// 自测 2：流式 /v1/chat/completions 返回 delta.reasoning。
func TestSelftestStreamReasoning(t *testing.T) {
	h := http.NewServeMux()
	h.HandleFunc("/v1/chat/completions", handleChat)
	body := postJSON(t, h, "/v1/chat/completions",
		map[string]any{"model": "qwen3", "stream": true})
	if !strings.Contains(body, `"reasoning"`) {
		t.Fatalf("stream body missing delta.reasoning: %.200s", body)
	}
	if !strings.Contains(body, "data: [DONE]") {
		t.Fatalf("stream missing [DONE]: %.200s", body)
	}
	t.Logf("OK: stream delta.reasoning + [DONE] present (%d bytes)", len(body))
}

// 自测 3：/v1/responses 返回 reasoning item。
func TestSelftestResponsesReasoningItem(t *testing.T) {
	h := http.NewServeMux()
	h.HandleFunc("/v1/responses", handleResponses)
	body := postJSON(t, h, "/v1/responses",
		map[string]any{"model": "qwen3"})
	if !strings.Contains(body, `"type":"reasoning"`) {
		t.Fatalf("responses body missing reasoning item: %.200s", body)
	}
	t.Logf("OK: responses reasoning item present")
}

// 自测 4：请求侧配置回显（reasoning_effort / enable_thinking）。
func TestSelftestConfigEcho(t *testing.T) {
	h := http.NewServeMux()
	h.HandleFunc("/v1/chat/completions", handleChat)
	body := postJSON(t, h, "/v1/chat/completions", map[string]any{
		"model":           "qwen3",
		"stream":          false,
		"reasoning_effort": "high",
		"extra_body": map[string]any{
			"chat_template_kwargs": map[string]any{"enable_thinking": true},
		},
	})
	var d struct {
		Usage map[string]any `json:"usage"`
	}
	_ = json.Unmarshal([]byte(body), &d)
	if d.Usage["reasoning_effort_echo"] != "high" {
		t.Fatalf("reasoning_effort_echo missing: %v", d.Usage)
	}
	if d.Usage["enable_thinking_echo"] != true {
		t.Fatalf("enable_thinking_echo missing: %v", d.Usage)
	}
	t.Logf("OK: config echo present (effort=%v thinking=%v)",
		d.Usage["reasoning_effort_echo"], d.Usage["enable_thinking_echo"])
}
