package prism

import "encoding/json"

// Client is the high-level Prism API.
type Client struct {
	runtime *Runtime
}

// New creates a new Prism client from prism.wasm bytes.
func New(wasmBytes []byte) (*Client, error) {
	rt, err := NewRuntime(wasmBytes)
	if err != nil {
		return nil, err
	}
	return &Client{runtime: rt}, nil
}

// Close releases resources.
func (c *Client) Close() error {
	return c.runtime.Close()
}

// ── Low-level IR conversion ──

func (c *Client) ToLuxRequest(provider, jsonStr string) (string, error) {
	return c.runtime.Call("wasm_to_lux_req", provider, jsonStr)
}

func (c *Client) LuxRequestToProvider(provider, luxJson string) (string, error) {
	return c.runtime.Call("wasm_lux_req_to_provider", provider, luxJson)
}

func (c *Client) ToLuxResponse(provider, jsonStr string) (string, error) {
	return c.runtime.Call("wasm_to_lux_resp", provider, jsonStr)
}

func (c *Client) LuxResponseToProvider(provider, luxJson string) (string, error) {
	return c.runtime.Call("wasm_lux_resp_to_provider", provider, luxJson)
}

func (c *Client) SSEToEvents(provider, sseStr string) (string, error) {
	return c.runtime.Call("wasm_sse_to_events", provider, sseStr)
}

func (c *Client) EventsToSSE(provider, eventsJson string) (string, error) {
	return c.runtime.Call("wasm_events_to_sse", provider, eventsJson)
}

// ── High-level SDK API ──

// EncodeRequest encodes a text request to provider JSON format.
func (c *Client) EncodeRequest(provider, text string, opts *Options) (string, error) {
	return c.runtime.Call("wasm_sdk_encode_req", provider, text)
}

// DecodeResponse decodes a provider JSON response to plain text.
func (c *Client) DecodeResponse(provider, jsonStr string) (string, error) {
	return c.runtime.Call("wasm_sdk_decode_resp", provider, jsonStr)
}

// EncodeStream encodes a text request for streaming.
func (c *Client) EncodeStream(provider, text string, opts *Options) (string, error) {
	return c.runtime.Call("wasm_sdk_encode_stream", provider, text)
}

// DecodeSSE decodes provider SSE text to Event list.
func (c *Client) DecodeSSE(provider, sseStr string) ([]Event, error) {
	result, err := c.runtime.Call("wasm_sdk_decode_sse", provider, sseStr)
	if err != nil {
		return nil, err
	}
	return ParseEvents(result)
}

// Capability queries a provider's capability declaration.
func (c *Client) Capability(provider string) (map[string]any, error) {
	result, err := c.runtime.Call("wasm_sdk_capability", provider)
	if err != nil {
		return nil, err
	}
	var cap map[string]any
	if err := json.Unmarshal([]byte(result), &cap); err != nil {
		return nil, newPrismError("parse capability: " + err.Error())
	}
	return cap, nil
}

// Convert performs cross-provider protocol conversion.
func (c *Client) Convert(from, to, direction, payload string) (string, error) {
	if direction == "request" {
		lux, err := c.ToLuxRequest(from, payload)
		if err != nil {
			return "", err
		}
		return c.LuxRequestToProvider(to, lux)
	}
	lux, err := c.ToLuxResponse(from, payload)
	if err != nil {
		return "", err
	}
	return c.LuxResponseToProvider(to, lux)
}

// ListProviders returns all registered provider names.
func (c *Client) ListProviders() []string {
	return []string{
		"openai",
		"openai-chat",
		"anthropic",
		"gemini",
		"google-vertex",
		"azure-openai",
		"openai-codex",
	}
}

// Ping returns "pong" for health check.
func (c *Client) Ping() string {
	return "pong"
}

// HasExport reports whether the loaded WASM module exports the given function.
func (c *Client) HasExport(name string) bool {
	return c.runtime.HasExport(name)
}
