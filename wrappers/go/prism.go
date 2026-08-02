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
// Each returns an Envelope: {"value":…,"diagnostics":[…]} (Phase 1 contract).

func (c *Client) ToLuxRequest(provider, jsonStr string) (*Envelope, error) {
	result, err := c.runtime.Call("wasm_to_lux_req", provider, jsonStr)
	if err != nil {
		return nil, err
	}
	return parseEnvelope(result)
}

func (c *Client) LuxRequestToProvider(provider, luxJson string) (*Envelope, error) {
	result, err := c.runtime.Call("wasm_lux_req_to_provider", provider, luxJson)
	if err != nil {
		return nil, err
	}
	return parseEnvelope(result)
}

func (c *Client) ToLuxResponse(provider, jsonStr string) (*Envelope, error) {
	result, err := c.runtime.Call("wasm_to_lux_resp", provider, jsonStr)
	if err != nil {
		return nil, err
	}
	return parseEnvelope(result)
}

func (c *Client) LuxResponseToProvider(provider, luxJson string) (*Envelope, error) {
	result, err := c.runtime.Call("wasm_lux_resp_to_provider", provider, luxJson)
	if err != nil {
		return nil, err
	}
	return parseEnvelope(result)
}

func (c *Client) SSEToEvents(provider, sseStr string) (*Envelope, error) {
	result, err := c.runtime.Call("wasm_sse_to_events", provider, sseStr)
	if err != nil {
		return nil, err
	}
	return parseEnvelope(result)
}

func (c *Client) EventsToSSE(provider, eventsJson string) (*Envelope, error) {
	result, err := c.runtime.Call("wasm_events_to_sse", provider, eventsJson)
	if err != nil {
		return nil, err
	}
	return parseEnvelope(result)
}

// ── High-level SDK API ──
// wasm_sdk_* returns raw values here; envelope-ization lands in Task 2.

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

// ── Transit conversion (single WASM call per direction) ──

// Convert performs cross-provider protocol conversion in a single WASM
// call (wasm_convert_req / wasm_convert_resp), returning the target
// provider JSON inside an Envelope.
func (c *Client) Convert(from, to, direction, payload string) (*Envelope, error) {
	var result string
	var err error
	switch direction {
	case "request":
		result, err = c.runtime.Call("wasm_convert_req", from, payload, to)
	case "response":
		result, err = c.runtime.Call("wasm_convert_resp", from, payload, to)
	default:
		return nil, newPrismError("unknown direction: " + direction)
	}
	if err != nil {
		return nil, err
	}
	return parseEnvelope(result)
}

// ConvertStream converts streamed SSE text in a single WASM call.
func (c *Client) ConvertStream(from, to, sse string) (*Envelope, error) {
	result, err := c.runtime.Call("wasm_convert_stream", from, sse, to)
	if err != nil {
		return nil, err
	}
	return parseEnvelope(result)
}

// ListProviders returns all registered provider names from the WASM
// registry (wasm_list_providers), not a hardcoded list.
func (c *Client) ListProviders() ([]string, error) {
	result, err := c.runtime.Call("wasm_list_providers")
	if err != nil {
		return nil, err
	}
	var names []string
	if err := json.Unmarshal([]byte(result), &names); err != nil {
		return nil, newPrismError("parse providers: " + err.Error())
	}
	return names, nil
}

// Ping returns "pong" for health check.
func (c *Client) Ping() string {
	return "pong"
}

// HasExport reports whether the loaded WASM module exports the given function.
func (c *Client) HasExport(name string) bool {
	return c.runtime.HasExport(name)
}
