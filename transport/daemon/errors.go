package daemon

// JSON-RPC 2.0 error codes, per transport/ARCHITECTURE.md §4.4.
var (
	ErrParse    = &RPCError{Code: -32700, Message: "parse error"}
	ErrInvalid  = &RPCError{Code: -32600, Message: "invalid request"}
	ErrMethod   = &RPCError{Code: -32601, Message: "method not found"}
	ErrParams   = &RPCError{Code: -32602, Message: "invalid params"}
	ErrInternal = &RPCError{Code: -32603, Message: "internal error"}
)

// domainError wraps a Prism conversion failure as a domain error
// (-32000 ~ -32099 range: unknown provider, conversion failure, bad JSON).
func domainError(message string) *RPCError {
	return &RPCError{Code: -32000, Message: message}
}
