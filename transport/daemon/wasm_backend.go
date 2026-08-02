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

// envelopeString serializes a client Envelope back to its JSON string so the
// dispatcher can parse it into the JSON-RPC result payload (D5 envelope).
func envelopeString(env *prism.Envelope) (string, error) {
	raw, err := json.Marshal(env)
	if err != nil {
		return "", err
	}
	return string(raw), nil
}

func (b *WASMBackend) EncodeRequest(ctx context.Context, provider, text string) (string, error) {
	env, err := b.client.EncodeRequest(provider, text, nil)
	if err != nil {
		return "", err
	}
	return envelopeString(env)
}

func (b *WASMBackend) DecodeResponse(ctx context.Context, provider, respJSON string) (string, error) {
	env, err := b.client.DecodeResponse(provider, respJSON)
	if err != nil {
		return "", err
	}
	return envelopeString(env)
}

func (b *WASMBackend) DecodeSSE(ctx context.Context, provider, sseText string) (string, error) {
	env, err := b.client.DecodeSSE(provider, sseText)
	if err != nil {
		return "", err
	}
	return envelopeString(env)
}

func (b *WASMBackend) EncodeStream(ctx context.Context, provider, text string) (string, error) {
	env, err := b.client.EncodeStream(provider, text, nil)
	if err != nil {
		return "", err
	}
	return envelopeString(env)
}

func (b *WASMBackend) Convert(ctx context.Context, from, to, direction, payload string) (string, error) {
	env, err := b.client.Convert(from, to, direction, payload)
	if err != nil {
		return "", err
	}
	return envelopeString(env)
}

func (b *WASMBackend) ConvertStream(ctx context.Context, from, to, sse string) (string, error) {
	env, err := b.client.ConvertStream(from, to, sse)
	if err != nil {
		return "", err
	}
	return envelopeString(env)
}

func (b *WASMBackend) ListProviders() []string {
	names, err := b.client.ListProviders()
	if err != nil {
		return nil
	}
	return names
}

func (b *WASMBackend) Capability(ctx context.Context, provider string) (map[string]any, error) {
	env, err := b.client.Capability(provider)
	if err != nil {
		return nil, err
	}
	var m map[string]any
	if err := json.Unmarshal(env.Value, &m); err != nil {
		return nil, err
	}
	return m, nil
}

func (b *WASMBackend) Ping() string {
	return b.client.Ping()
}

// HasExport reports whether the loaded WASM module exports the given function.
// Used by freshness gates to pin the export surface.
func (b *WASMBackend) HasExport(name string) bool {
	return b.client.HasExport(name)
}
