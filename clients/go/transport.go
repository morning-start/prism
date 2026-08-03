package prism

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"sync/atomic"

	"github.com/coder/websocket"
)

// Transport abstracts the wire protocol between the client and the Prism
// daemon (ARCHITECTURE.md §6.1): Call performs one JSON-RPC request,
// Stream performs a request whose response is a sequence of envelope frames
// (streaming methods: decode_sse / convert_stream).
type Transport interface {
	Call(ctx context.Context, method string, params map[string]any) (*Envelope, error)
	Stream(ctx context.Context, method string, params map[string]any) (<-chan *Envelope, error)
}

// rpcRequest is the JSON-RPC 2.0 request frame shared by all transports.
type rpcRequest struct {
	JSONRPC string         `json:"jsonrpc"`
	ID      int64          `json:"id"`
	Method  string         `json:"method"`
	Params  map[string]any `json:"params"`
}

// rpcResponse is the JSON-RPC 2.0 response frame shared by all transports.
type rpcResponse struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      json.RawMessage `json:"id"`
	Result  json.RawMessage `json:"result,omitempty"`
	Error   *rpcError       `json:"error,omitempty"`
}

type rpcError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

// call builds a JSON-RPC request with an incrementing id.
func call(method string, params map[string]any) *rpcRequest {
	id := atomic.AddInt64(&rpcSeq, 1)
	return &rpcRequest{JSONRPC: "2.0", ID: id, Method: method, Params: params}
}

var rpcSeq int64

// decodeRPC parses a raw response frame into an envelope or error.
func decodeRPC(data []byte) (*Envelope, error) {
	var resp rpcResponse
	if err := json.Unmarshal(data, &resp); err != nil {
		return nil, fmt.Errorf("parse rpc response: %w", err)
	}
	if resp.Error != nil {
		return nil, fmt.Errorf("rpc error %d: %s", resp.Error.Code, resp.Error.Message)
	}
	var env Envelope
	if err := json.Unmarshal(resp.Result, &env); err != nil {
		return nil, fmt.Errorf("parse envelope: %w", err)
	}
	return &env, nil
}

// --- HTTP transport ---

// HTTPTransport talks to the daemon over JSON-RPC 2.0 POST + SSE streaming
// (ARCHITECTURE.md §5.1).
type HTTPTransport struct {
	baseURL string
	client  *httpClient
}

// NewHTTPTransport returns a transport bound to the daemon HTTP endpoint
// (e.g. "http://127.0.0.1:8765/v1").
func NewHTTPTransport(baseURL string) *HTTPTransport {
	return &HTTPTransport{baseURL: strings.TrimSuffix(baseURL, "/"), client: newHTTPClient()}
}

// Call implements Transport.
func (t *HTTPTransport) Call(ctx context.Context, method string, params map[string]any) (*Envelope, error) {
	body, err := json.Marshal(call(method, params))
	if err != nil {
		return nil, err
	}
	data, err := t.client.postJSON(ctx, t.baseURL, body)
	if err != nil {
		return nil, err
	}
	return decodeRPC(data)
}

// Stream implements Transport (SSE streaming over HTTP).
func (t *HTTPTransport) Stream(ctx context.Context, method string, params map[string]any) (<-chan *Envelope, error) {
	body, err := json.Marshal(call(method, params))
	if err != nil {
		return nil, err
	}
	lines, err := t.client.postSSE(ctx, t.baseURL, body)
	if err != nil {
		return nil, err
	}
	ch := make(chan *Envelope, 8)
	go func() {
		defer close(ch)
		for _, line := range lines {
			env, err := decodeRPC(line)
			if err != nil {
				return
			}
			select {
			case ch <- env:
			case <-ctx.Done():
				return
			}
		}
	}()
	return ch, nil
}

// --- UDS transport ---

// UDSTransport talks to the daemon over a Unix domain socket using JSON
// lines (ARCHITECTURE.md §5.2).
type UDSTransport struct {
	sockPath string
}

// NewUDSTransport returns a transport bound to a Unix domain socket path.
func NewUDSTransport(sockPath string) *UDSTransport {
	return &UDSTransport{sockPath: sockPath}
}

// Call implements Transport.
func (t *UDSTransport) Call(ctx context.Context, method string, params map[string]any) (*Envelope, error) {
	body, err := json.Marshal(call(method, params))
	if err != nil {
		return nil, err
	}
	lines, err := udsRoundTrip(ctx, t.sockPath, string(body), false)
	if err != nil {
		return nil, err
	}
	if len(lines) == 0 {
		return nil, fmt.Errorf("uds: empty response")
	}
	return decodeRPC(lines[0])
}

// Stream implements Transport (JSON-lines streaming over UDS).
func (t *UDSTransport) Stream(ctx context.Context, method string, params map[string]any) (<-chan *Envelope, error) {
	body, err := json.Marshal(call(method, params))
	if err != nil {
		return nil, err
	}
	lines, err := udsRoundTrip(ctx, t.sockPath, string(body), true)
	if err != nil {
		return nil, err
	}
	ch := make(chan *Envelope, 8)
	go func() {
		defer close(ch)
		for _, line := range lines {
			env, err := decodeRPC(line)
			if err != nil {
				return
			}
			select {
			case ch <- env:
			case <-ctx.Done():
				return
			}
		}
	}()
	return ch, nil
}

// --- WebSocket transport ---

// WSTransport talks to the daemon over WebSocket, one JSON-RPC message per
// frame (ARCHITECTURE.md §5.3).
type WSTransport struct {
	url string
}

// NewWSTransport returns a transport bound to a WebSocket endpoint
// (e.g. "ws://127.0.0.1:8765/ws").
func NewWSTransport(url string) *WSTransport {
	return &WSTransport{url: url}
}

// Call implements Transport.
func (t *WSTransport) Call(ctx context.Context, method string, params map[string]any) (*Envelope, error) {
	body, err := json.Marshal(call(method, params))
	if err != nil {
		return nil, err
	}
	data, err := wsRoundTrip(ctx, t.url, string(body), false)
	if err != nil {
		return nil, err
	}
	if len(data) == 0 {
		return nil, fmt.Errorf("ws: empty response")
	}
	return decodeRPC(data[0])
}

// Stream implements Transport (multi-frame streaming over WS).
func (t *WSTransport) Stream(ctx context.Context, method string, params map[string]any) (<-chan *Envelope, error) {
	body, err := json.Marshal(call(method, params))
	if err != nil {
		return nil, err
	}
	frames, err := wsRoundTrip(ctx, t.url, string(body), true)
	if err != nil {
		return nil, err
	}
	ch := make(chan *Envelope, 8)
	go func() {
		defer close(ch)
		for _, data := range frames {
			env, err := decodeRPC(data)
			if err != nil {
				return
			}
			select {
			case ch <- env:
			case <-ctx.Done():
				return
			}
		}
	}()
	return ch, nil
}

// wsRoundTrip dials a WS connection, sends one frame, and returns all
// response frames (all of them when streaming, just the first otherwise).
func wsRoundTrip(ctx context.Context, url, body string, stream bool) ([][]byte, error) {
	conn, _, err := websocket.Dial(ctx, url, nil)
	if err != nil {
		return nil, fmt.Errorf("ws dial: %w", err)
	}
	defer conn.Close(websocket.StatusNormalClosure, "done")
	if err := conn.Write(ctx, websocket.MessageText, []byte(body)); err != nil {
		return nil, fmt.Errorf("ws write: %w", err)
	}
	var frames [][]byte
	for {
		_, data, err := conn.Read(ctx)
		if err != nil {
			return nil, fmt.Errorf("ws read: %w", err)
		}
		frames = append(frames, data)
		if !stream {
			break
		}
		var resp rpcResponse
		_ = json.Unmarshal(data, &resp)
		if strings.Contains(string(data), `"type":"done"`) {
			break
		}
	}
	return frames, nil
}
