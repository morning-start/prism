package daemon

import (
	"context"
	"encoding/json"

	prism "github.com/morning-start/prism/wrappers/go"
)

// WASMBackend fronts the Prism WASM module through the wrappers/go ABI
// layer (UTF-16 linear-memory marshalling).
type WASMBackend struct {
	client *prism.Client
}

// NewWASMBackend loads prism.wasm and returns a ready backend.
func NewWASMBackend(wasmBytes []byte) (*WASMBackend, error) {
	client, err := prism.New(wasmBytes)
	if err != nil {
		return nil, err
	}
	return &WASMBackend{client: client}, nil
}

// Close releases the underlying WASM runtime.
func (b *WASMBackend) Close() error {
	return b.client.Close()
}

func (b *WASMBackend) EncodeRequest(ctx context.Context, provider, text string) (string, error) {
	return b.client.EncodeRequest(provider, text, nil)
}

func (b *WASMBackend) DecodeResponse(ctx context.Context, provider, respJSON string) (string, error) {
	return b.client.DecodeResponse(provider, respJSON)
}

func (b *WASMBackend) DecodeSSE(ctx context.Context, provider, sseText string) (string, error) {
	events, err := b.client.DecodeSSE(provider, sseText)
	if err != nil {
		return "", err
	}
	data, err := json.Marshal(events)
	if err != nil {
		return "", err
	}
	return string(data), nil
}

func (b *WASMBackend) EncodeStream(ctx context.Context, provider, text string) (string, error) {
	return b.client.EncodeStream(provider, text, nil)
}

func (b *WASMBackend) Convert(ctx context.Context, from, to, direction, payload string) (string, error) {
	return b.client.Convert(from, to, direction, payload)
}

func (b *WASMBackend) ListProviders() []string {
	// ListProviders is currently a static registry mirror in wrappers/go;
	// it matches the seven registered adapters.
	return b.client.ListProviders()
}

func (b *WASMBackend) Capability(ctx context.Context, provider string) (map[string]any, error) {
	return b.client.Capability(provider)
}

func (b *WASMBackend) Ping() string {
	return b.client.Ping()
}
