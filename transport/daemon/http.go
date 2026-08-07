package daemon

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"strings"
)

// HTTPHandler serves JSON-RPC 2.0 over HTTP at POST /v1 and a health
// check at GET /health (transport/ARCHITECTURE.md §5.1).
type HTTPHandler struct {
	backend Backend
	version string
}

// NewHTTPHandler returns a handler bound to the given backend.
func NewHTTPHandler(backend Backend, version string) *HTTPHandler {
	return &HTTPHandler{backend: backend, version: version}
}

func (h *HTTPHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	if r.Method == http.MethodGet && r.URL.Path == "/health" {
		h.serveHealth(w)
		return
	}
	if r.Method != http.MethodPost || r.URL.Path != "/v1" {
		http.Error(w, "not found", http.StatusNotFound)
		return
	}
	h.serveRPC(w, r)
}

func (h *HTTPHandler) serveHealth(w http.ResponseWriter) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(map[string]any{
		"status":    "ok",
		"version":   h.version,
		"providers": len(h.backend.ListProviders()),
	})
}

func (h *HTTPHandler) serveRPC(w http.ResponseWriter, r *http.Request) {
	var req Request
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeRPC(w, rpcError(json.RawMessage(`null`), ErrParse))
		return
	}
	// SSE 流式分支（Task 3, D7）：客户端 Accept: text/event-stream 且方法为
	// decode_sse / convert_stream 时逐帧写出；否则走同步 JSON-RPC 路径。
	if acceptsStreaming(r) && (req.Method == "decode_sse" || req.Method == "convert_stream") {
		h.serveSSE(w, r, &req)
		return
	}
	resp := ServeRPC(r.Context(), h.backend, &req)
	writeRPC(w, resp)
}

// acceptsStreaming 判断请求是否声明接受 text/event-stream。
func acceptsStreaming(r *http.Request) bool {
	for _, v := range r.Header.Values("Accept") {
		if strings.Contains(v, "text/event-stream") {
			return true
		}
	}
	return false
}

// serveSSE 处理流式请求：解码整段后逐事件/逐帧写出（正确性优先于首字节延迟；
// 跨帧状态（块索引、工具参数拼接）由 WASM 层在整段解码中维护，逐帧独立解码
// 会破坏该状态，故不等价 provider 一律回退整段解码后流式写出）。
func (h *HTTPHandler) serveSSE(w http.ResponseWriter, r *http.Request, req *Request) {
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")

	id := req.ID
	if len(id) == 0 {
		id = json.RawMessage(`null`)
	}
	params, rpcErr := parseParams(req.Params)
	if rpcErr != nil {
		streamError(w, id, rpcErr.Message)
		return
	}

	switch req.Method {
	case "decode_sse":
		provider, e := params.strParam("provider")
		if e != nil {
			streamError(w, id, e.Message)
			return
		}
		sse, e := params.strParam("sse")
		if e != nil {
			streamError(w, id, e.Message)
			return
		}
		envStr, err := h.backend.DecodeSSE(r.Context(), provider, sse)
		if err != nil {
			streamError(w, id, err.Error())
			return
		}
		env, e := envelopeResult(envStr)
		if e != nil {
			streamError(w, id, e.Message)
			return
		}
		events, ok := env["value"].([]any)
		if !ok {
			streamError(w, id, "decode_sse value is not an event array")
			return
		}
		for _, ev := range events {
			if r.Context().Err() != nil {
				return // 客户端断连，停止写出
			}
			writeSSEFrame(w, "data", rpcEnvelope(id, ev, []any{}))
		}
		writeSSEFrame(w, "done", rpcEnvelope(id, map[string]any{"type": "done"}, []any{}))
	case "convert_stream":
		from, e := params.strParam("from_provider")
		if e != nil {
			streamError(w, id, e.Message)
			return
		}
		to, e := params.strParam("to_provider")
		if e != nil {
			streamError(w, id, e.Message)
			return
		}
		sse, e := params.strParam("sse")
		if e != nil {
			streamError(w, id, e.Message)
			return
		}
		// file:// 预读：把 file:// 字符串转 data URI，转换层（纯函数）无需文件系统
		sse = resolveFileURIs(sse)
		envStr, err := h.backend.ConvertStream(r.Context(), from, to, sse)
		if err != nil {
			streamError(w, id, err.Error())
			return
		}
		env, e := envelopeResult(envStr)
		if e != nil {
			streamError(w, id, e.Message)
			return
		}
		target, ok := env["value"].(string)
		if !ok {
			streamError(w, id, "convert_stream value is not a string")
			return
		}
		for _, frame := range splitSSEFrames(target) {
			if r.Context().Err() != nil {
				return
			}
			writeSSEFrame(w, "data", rpcEnvelope(id, frame, []any{}))
		}
		writeSSEFrame(w, "done", rpcEnvelope(id, map[string]any{"type": "done"}, []any{}))
	default:
		streamError(w, id, "method not streamable: "+req.Method)
	}
}

func writeRPC(w http.ResponseWriter, resp *Response) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(resp)
}

// ListenAndServe starts the HTTP transport on addr until ctx is cancelled.
func ListenAndServe(ctx context.Context, backend Backend, addr, version string) error {
	server := &http.Server{
		Addr:    addr,
		Handler: NewHTTPHandler(backend, version),
	}
	go func() {
		<-ctx.Done()
		_ = server.Close()
	}()
	log.Printf("prism daemon listening on http://%s (version %s)", addr, version)
	return server.ListenAndServe()
}
