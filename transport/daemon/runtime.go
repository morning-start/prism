package daemon

import "context"

// Backend abstracts the Prism conversion core behind the daemon.
// The first (and current) implementation wraps the WASM runtime via
// wrappers/go; future backends (native, remote) implement the same surface.
type Backend interface {
	// EncodeRequest converts text to a provider JSON request body.
	EncodeRequest(ctx context.Context, provider, text string) (string, error)
	// DecodeResponse extracts plain text from a provider JSON response.
	DecodeResponse(ctx context.Context, provider, respJSON string) (string, error)
	// DecodeSSE decodes provider SSE text into a JSON array of events.
	DecodeSSE(ctx context.Context, provider, sseText string) (string, error)
	// EncodeStream converts text to a streaming (stream:true) provider request.
	EncodeStream(ctx context.Context, provider, text string) (string, error)
	// Convert translates a provider payload to another provider via Lucent IR.
	Convert(ctx context.Context, from, to, direction, payload string) (string, error)
	// ListProviders returns registered provider names.
	ListProviders() []string
	// Capability returns the capability declaration for a provider.
	Capability(ctx context.Context, provider string) (map[string]any, error)
	// Ping is a health probe.
	Ping() string
}
