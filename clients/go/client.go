package prism

import (
	"context"
	"encoding/json"
)

// Client is the language-neutral Prism SDK client (ARCHITECTURE.md §6.1):
// every method maps 1:1 to a daemon RPC, and the transport is pluggable
// (HTTP / UDS / WebSocket) — switching transports is a one-line change.
type Client struct {
	tr Transport
}

// NewClient returns a Client bound to the given transport.
func NewClient(tr Transport) *Client {
	return &Client{tr: tr}
}

// CallRaw issues an arbitrary RPC and returns the raw envelope.
func (c *Client) CallRaw(ctx context.Context, method string, params map[string]any) (*Envelope, error) {
	return c.tr.Call(ctx, method, params)
}

// EncodeRequest converts text to a provider JSON request body.
func (c *Client) EncodeRequest(ctx context.Context, provider, text string) (*Envelope, error) {
	return c.tr.Call(ctx, "encode_request", map[string]any{
		"provider": provider,
		"text":     text,
	})
}

// DecodeResponse extracts plain text from a provider JSON response.
func (c *Client) DecodeResponse(ctx context.Context, provider, respJSON string) (*Envelope, error) {
	return c.tr.Call(ctx, "decode_response", map[string]any{
		"provider": provider,
		"json":     respJSON,
	})
}

// DecodeSSE decodes provider SSE text into a JSON array of events.
func (c *Client) DecodeSSE(ctx context.Context, provider, sse string) (*Envelope, error) {
	return c.tr.Call(ctx, "decode_sse", map[string]any{
		"provider": provider,
		"sse":      sse,
	})
}

// EncodeStream converts text to a streaming (stream:true) provider request.
func (c *Client) EncodeStream(ctx context.Context, provider, text string) (*Envelope, error) {
	return c.tr.Call(ctx, "encode_stream", map[string]any{
		"provider": provider,
		"text":     text,
	})
}

// Convert translates a provider payload to another provider via Lucent IR.
func (c *Client) Convert(ctx context.Context, from, to, direction, payload string) (*Envelope, error) {
	return c.tr.Call(ctx, "convert", map[string]any{
		"from_provider": from,
		"to_provider":   to,
		"direction":     direction,
		"payload":       payload,
	})
}

// ConvertStream translates streamed SSE text between providers.
func (c *Client) ConvertStream(ctx context.Context, from, to, sse string) (*Envelope, error) {
	return c.tr.Call(ctx, "convert_stream", map[string]any{
		"from_provider": from,
		"to_provider":   to,
		"sse":           sse,
	})
}

// ListProviders returns registered provider names.
func (c *Client) ListProviders(ctx context.Context) ([]string, error) {
	env, err := c.tr.Call(ctx, "list_providers", map[string]any{})
	if err != nil {
		return nil, err
	}
	var names []string
	if err := json.Unmarshal(env.Value, &names); err != nil {
		return nil, err
	}
	return names, nil
}

// Capability returns the capability declaration for a provider.
func (c *Client) Capability(ctx context.Context, provider string) (*Envelope, error) {
	return c.tr.Call(ctx, "capability", map[string]any{
		"provider": provider,
	})
}

// Ping is a health probe.
func (c *Client) Ping(ctx context.Context) (string, error) {
	env, err := c.tr.Call(ctx, "ping", map[string]any{})
	if err != nil {
		return "", err
	}
	return env.ValueString()
}

// StreamDecodeSSE streams provider SSE text and returns the event frames as
// typed Events (one per envelope frame), ending after the done marker.
func (c *Client) StreamDecodeSSE(ctx context.Context, provider, sse string) ([]*Event, error) {
	ch, err := c.tr.Stream(ctx, "decode_sse", map[string]any{
		"provider": provider,
		"sse":      sse,
	})
	if err != nil {
		return nil, err
	}
	var events []*Event
	for env := range ch {
		var ev Event
		if err := json.Unmarshal(env.Value, &ev); err != nil {
			return nil, err
		}
		events = append(events, &ev)
		if ev.Type == "done" {
			break
		}
	}
	return events, nil
}
