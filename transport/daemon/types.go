// Package daemon implements the Prism Gateway Daemon: a JSON-RPC 2.0
// HTTP service that fronts the Prism WASM conversion core.
//
// Design source: transport/ARCHITECTURE.md §4 (wire protocol), §7 (daemon).
package daemon

import "encoding/json"

// Request is a JSON-RPC 2.0 request.
type Request struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      json.RawMessage `json:"id"`
	Method  string          `json:"method"`
	Params  json.RawMessage `json:"params"`
}

// Response is a JSON-RPC 2.0 response.
type Response struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      json.RawMessage `json:"id"`
	Result  any             `json:"result,omitempty"`
	Error   *RPCError       `json:"error,omitempty"`
}

// RPCError is a JSON-RPC 2.0 error object.
type RPCError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
	Data    any    `json:"data,omitempty"`
}

// rpcRequest builds a JSON-RPC response for the given request id.
func rpcResponse(id json.RawMessage, result any) *Response {
	return &Response{JSONRPC: "2.0", ID: id, Result: result}
}

// rpcError builds a JSON-RPC error response for the given request id.
func rpcError(id json.RawMessage, err *RPCError) *Response {
	return &Response{JSONRPC: "2.0", ID: id, Error: err}
}
