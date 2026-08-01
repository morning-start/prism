package daemon

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
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
	resp := ServeRPC(r.Context(), h.backend, &req)
	writeRPC(w, resp)
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
