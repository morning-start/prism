package daemon

import (
	"context"
	"encoding/json"
)

// methodParams is the loose JSON object carrying RPC params; handlers
// decode the fields they need so unknown keys are ignored.
type methodParams map[string]json.RawMessage

// parseParams decodes the request params into a map, returning ErrParams
// when the payload is not a JSON object.
func parseParams(raw json.RawMessage) (methodParams, *RPCError) {
	if len(raw) == 0 {
		return methodParams{}, nil
	}
	var params methodParams
	if err := json.Unmarshal(raw, &params); err != nil {
		return nil, ErrParams
	}
	return params, nil
}

// strParam extracts a string field from params.
func (p methodParams) strParam(key string) (string, *RPCError) {
	raw, ok := p[key]
	if !ok {
		return "", ErrParams
	}
	var s string
	if err := json.Unmarshal(raw, &s); err != nil {
		return "", ErrParams
	}
	return s, nil
}

// ServeRPC dispatches a single JSON-RPC request to the backend.
func ServeRPC(ctx context.Context, backend Backend, req *Request) *Response {
	id := req.ID
	if len(id) == 0 {
		id = json.RawMessage(`null`)
	}

	switch req.Method {
	case "encode_request":
		return serveEncodeRequest(ctx, backend, id, req.Params)
	case "decode_response":
		return serveDecodeResponse(ctx, backend, id, req.Params)
	case "decode_sse":
		return serveDecodeSSE(ctx, backend, id, req.Params)
	case "encode_stream":
		return serveEncodeStream(ctx, backend, id, req.Params)
	case "convert":
		return serveConvert(ctx, backend, id, req.Params)
	case "list_providers":
		return rpcResponse(id, backend.ListProviders())
	case "capability":
		return serveCapability(ctx, backend, id, req.Params)
	case "ping":
		return rpcResponse(id, backend.Ping())
	default:
		return rpcError(id, ErrMethod)
	}
}

func serveEncodeRequest(ctx context.Context, backend Backend, id json.RawMessage, raw json.RawMessage) *Response {
	params, rpcErr := parseParams(raw)
	if rpcErr != nil {
		return rpcError(id, rpcErr)
	}
	provider, rpcErr := params.strParam("provider")
	if rpcErr != nil {
		return rpcError(id, rpcErr)
	}
	text, rpcErr := params.strParam("text")
	if rpcErr != nil {
		return rpcError(id, rpcErr)
	}
	result, err := backend.EncodeRequest(ctx, provider, text)
	if err != nil {
		return rpcError(id, domainError(err.Error()))
	}
	return rpcResponse(id, result)
}

func serveDecodeResponse(ctx context.Context, backend Backend, id json.RawMessage, raw json.RawMessage) *Response {
	params, rpcErr := parseParams(raw)
	if rpcErr != nil {
		return rpcError(id, rpcErr)
	}
	provider, rpcErr := params.strParam("provider")
	if rpcErr != nil {
		return rpcError(id, rpcErr)
	}
	jsonStr, rpcErr := params.strParam("json")
	if rpcErr != nil {
		return rpcError(id, rpcErr)
	}
	result, err := backend.DecodeResponse(ctx, provider, jsonStr)
	if err != nil {
		return rpcError(id, domainError(err.Error()))
	}
	return rpcResponse(id, result)
}

func serveDecodeSSE(ctx context.Context, backend Backend, id json.RawMessage, raw json.RawMessage) *Response {
	params, rpcErr := parseParams(raw)
	if rpcErr != nil {
		return rpcError(id, rpcErr)
	}
	provider, rpcErr := params.strParam("provider")
	if rpcErr != nil {
		return rpcError(id, rpcErr)
	}
	sse, rpcErr := params.strParam("sse")
	if rpcErr != nil {
		return rpcError(id, rpcErr)
	}
	result, err := backend.DecodeSSE(ctx, provider, sse)
	if err != nil {
		return rpcError(id, domainError(err.Error()))
	}
	return rpcResponse(id, json.RawMessage(result))
}

func serveEncodeStream(ctx context.Context, backend Backend, id json.RawMessage, raw json.RawMessage) *Response {
	params, rpcErr := parseParams(raw)
	if rpcErr != nil {
		return rpcError(id, rpcErr)
	}
	provider, rpcErr := params.strParam("provider")
	if rpcErr != nil {
		return rpcError(id, rpcErr)
	}
	text, rpcErr := params.strParam("text")
	if rpcErr != nil {
		return rpcError(id, rpcErr)
	}
	result, err := backend.EncodeStream(ctx, provider, text)
	if err != nil {
		return rpcError(id, domainError(err.Error()))
	}
	return rpcResponse(id, result)
}

func serveConvert(ctx context.Context, backend Backend, id json.RawMessage, raw json.RawMessage) *Response {
	params, rpcErr := parseParams(raw)
	if rpcErr != nil {
		return rpcError(id, rpcErr)
	}
	from, rpcErr := params.strParam("from_provider")
	if rpcErr != nil {
		return rpcError(id, rpcErr)
	}
	to, rpcErr := params.strParam("to_provider")
	if rpcErr != nil {
		return rpcError(id, rpcErr)
	}
	direction, rpcErr := params.strParam("direction")
	if rpcErr != nil {
		return rpcError(id, rpcErr)
	}
	payload, rpcErr := params.strParam("payload")
	if rpcErr != nil {
		return rpcError(id, rpcErr)
	}
	result, err := backend.Convert(ctx, from, to, direction, payload)
	if err != nil {
		return rpcError(id, domainError(err.Error()))
	}
	return rpcResponse(id, result)
}

func serveCapability(ctx context.Context, backend Backend, id json.RawMessage, raw json.RawMessage) *Response {
	params, rpcErr := parseParams(raw)
	if rpcErr != nil {
		return rpcError(id, rpcErr)
	}
	provider, rpcErr := params.strParam("provider")
	if rpcErr != nil {
		return rpcError(id, rpcErr)
	}
	result, err := backend.Capability(ctx, provider)
	if err != nil {
		return rpcError(id, domainError(err.Error()))
	}
	return rpcResponse(id, result)
}
