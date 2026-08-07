// Command mock-vllm simulates a vLLM OpenAI-compatible endpoint that emits
// reasoning content — the vendor extension prism's openai_vllm subprotocol
// is built to handle. No GPU / real API key needed.
//
//   mock-vllm [--listen 127.0.0.1:8000]
//
// Endpoints:
//   GET  /healthz                     -> {"ok":true}
//   POST /v1/chat/completions         -> OpenAI chat completion JSON
//        - stream=false: message.reasoning + message.content
//        - stream=true:  SSE with delta.reasoning then delta.content
//   POST /v1/responses                -> OpenAI Responses item JSON
//        - output: reasoning item + message item
//
// The server echoes request reasoning config (reasoning_effort /
// enable_thinking in extra_body) into response usage metadata so V5
// (request-side config round-trip) can be asserted.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net/http"
	"strings"
)

type chatRequest struct {
	Model          string `json:"model"`
	Stream         bool   `json:"stream"`
	Reasoning      string `json:"reasoning_effort"`
	ExtraBody      map[string]any `json:"extra_body"`
}

// sampleReasoning / sampleContent: deterministic fixtures so assertions can
// compare exact text end-to-end.
const sampleReasoning = "Let me think: 9.11 is a decimal, 9.8 is a decimal. Compare digit by digit: 9.11 > 9.8? No — 9.8 == 9.80, and 9.80 > 9.11? Actually 9.8 < 9.11 is false: 9.11 - 9.8 = 0.31 > 0, so 9.11 is larger. Answer: 9.11."
const sampleContent = "9.11 is greater than 9.8."

func main() {
	listen := flag.String("listen", "127.0.0.1:8000", "listen address")
	flag.Parse()

	mux := http.NewServeMux()
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"ok":true}`))
	})
	mux.HandleFunc("/v1/chat/completions", handleChat)
	mux.HandleFunc("/v1/responses", handleResponses)

	log.Printf("mock-vllm listening on %s (reasoning simulation)", *listen)
	if err := http.ListenAndServe(*listen, mux); err != nil {
		log.Fatal(err)
	}
}

// handleChat implements /v1/chat/completions (streaming + non-streaming).
func handleChat(w http.ResponseWriter, r *http.Request) {
	var req chatRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":{"message":"bad request"}}`, http.StatusBadRequest)
		return
	}
	w.Header().Set("Content-Type", "application/json")

	if req.Stream {
		streamChat(w, req)
		return
	}
	body, _ := json.Marshal(map[string]any{
		"id":      "chatcmpl-mock-1",
		"object":  "chat.completion",
		"model":   req.Model,
		"choices": []any{
			map[string]any{
				"index": 0,
				"message": map[string]any{
					"role":      "assistant",
					"content":   sampleContent,
					"reasoning": sampleReasoning,
				},
				"finish_reason": "stop",
			},
		},
		"usage": mockUsage(req),
	})
	_, _ = w.Write(body)
}

// streamChat emits OpenAI-style SSE: reasoning deltas first, then content.
func streamChat(w http.ResponseWriter, req chatRequest) {
	w.Header().Set("Content-Type", "text/event-stream")
	flusher, ok := w.(http.Flusher)
	if !ok {
		http.Error(w, "streaming unsupported", http.StatusInternalServerError)
		return
	}
	frame := func(delta map[string]any) {
		payload, _ := json.Marshal(map[string]any{
			"choices": []any{
				map[string]any{"index": 0, "delta": delta, "finish_reason": nil},
			},
		})
		_, _ = fmt.Fprintf(w, "data: %s\n\n", payload)
		flusher.Flush()
	}
	frame(map[string]any{"role": "assistant"})
	// reasoning deltas (chunk the reasoning text so streaming is realistic)
	for _, chunk := range chunkString(sampleReasoning, 8) {
		frame(map[string]any{"reasoning": chunk})
	}
	// content deltas
	for _, chunk := range chunkString(sampleContent, 8) {
		frame(map[string]any{"content": chunk})
	}
	frame(map[string]any{"finish_reason": "stop"})
	_, _ = fmt.Fprintf(w, "data: [DONE]\n\n")
	flusher.Flush()
}

// handleResponses implements /v1/responses (reasoning item + message item).
func handleResponses(w http.ResponseWriter, r *http.Request) {
	var req chatRequest
	_ = json.NewDecoder(r.Body).Decode(&req)
	w.Header().Set("Content-Type", "application/json")
	body, _ := json.Marshal(map[string]any{
		"id":      "resp-mock-1",
		"object":  "response",
		"model":   req.Model,
		"output": []any{
			map[string]any{
				"id":      "rs_1",
				"type":    "reasoning",
				"summary": []any{map[string]any{"type": "summary_text", "text": sampleReasoning}},
				"status":  "completed",
			},
			map[string]any{
				"id":      "msg_1",
				"type":    "message",
				"role":    "assistant",
				"status":  "completed",
				"content": []any{map[string]any{"type": "output_text", "text": sampleContent}},
			},
		},
		"usage": mockUsage(req),
	})
	_, _ = w.Write(body)
}

// mockUsage echoes the reasoning request config so V5 can assert the
// request-side config survived the relay.
func mockUsage(req chatRequest) map[string]any {
	u := map[string]any{
		"prompt_tokens":     10,
		"completion_tokens": 40,
		"total_tokens":      50,
	}
	if req.Reasoning != "" {
		u["reasoning_effort_echo"] = req.Reasoning
	}
	if v, ok := req.ExtraBody["chat_template_kwargs"].(map[string]any); ok {
		if et, ok2 := v["enable_thinking"].(bool); ok2 {
			u["enable_thinking_echo"] = et
		}
	}
	return u
}

// chunkString splits s into chunks of up to n runes.
func chunkString(s string, n int) []string {
	runes := []rune(s)
	var out []string
	for i := 0; i < len(runes); i += n {
		end := i + n
		if end > len(runes) {
			end = len(runes)
		}
		out = append(out, string(runes[i:end]))
	}
	if len(out) == 0 {
		out = []string{""}
	}
	return out
}

var _ = strings.TrimSpace
