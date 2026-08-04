package prism

import (
	"context"
	"encoding/json"
	"fmt"

	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"

	dapb "github.com/morning-start/prism/transport/daemon/prismpb"
)

// GRPCTransport talks to the daemon over gRPC (ARCHITECTURE.md §5.4). Sync
// methods map to unary RPCs; Stream maps to the DecodeSSEStream server
// streaming RPC. D5 envelopes are decoded from the protobuf Envelope.
type GRPCTransport struct {
	conn   *grpc.ClientConn
	client dapb.PrismClient
}

// NewGRPCTransport returns a transport bound to the daemon gRPC endpoint
// (e.g. "127.0.0.1:8767").
func NewGRPCTransport(addr string) (*GRPCTransport, error) {
	conn, err := grpc.NewClient(addr, grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		return nil, fmt.Errorf("grpc dial: %w", err)
	}
	return &GRPCTransport{conn: conn, client: dapb.NewPrismClient(conn)}, nil
}

// Close releases the underlying connection.
func (t *GRPCTransport) Close() error {
	return t.conn.Close()
}

// Call implements Transport: dispatches the method to the matching unary RPC.
func (t *GRPCTransport) Call(ctx context.Context, method string, params map[string]any) (*Envelope, error) {
	switch method {
	case "encode_request":
		return t.callEnvelope(func(c dapb.PrismClient) (*dapb.Envelope, error) {
			return c.EncodeRequest(ctx, &dapb.EncodeRequestReq{Provider: str(params, "provider"), Text: str(params, "text")})
		})
	case "decode_response":
		return t.callEnvelope(func(c dapb.PrismClient) (*dapb.Envelope, error) {
			return c.DecodeResponse(ctx, &dapb.DecodeResponseReq{Provider: str(params, "provider"), Json: str(params, "json")})
		})
	case "decode_sse":
		return t.callEnvelope(func(c dapb.PrismClient) (*dapb.Envelope, error) {
			return c.DecodeSSE(ctx, &dapb.DecodeSSEReq{Provider: str(params, "provider"), Sse: str(params, "sse")})
		})
	case "encode_stream":
		return t.callEnvelope(func(c dapb.PrismClient) (*dapb.Envelope, error) {
			return c.EncodeStream(ctx, &dapb.EncodeStreamReq{Provider: str(params, "provider"), Text: str(params, "text")})
		})
	case "convert":
		return t.callEnvelope(func(c dapb.PrismClient) (*dapb.Envelope, error) {
			return c.Convert(ctx, &dapb.ConvertReq{
				FromProvider: str(params, "from_provider"),
				ToProvider:   str(params, "to_provider"),
				Direction:    str(params, "direction"),
				Payload:      str(params, "payload"),
			})
		})
	case "convert_stream":
		return t.callEnvelope(func(c dapb.PrismClient) (*dapb.Envelope, error) {
			return c.ConvertStream(ctx, &dapb.ConvertStreamReq{
				FromProvider: str(params, "from_provider"),
				ToProvider:   str(params, "to_provider"),
				Sse:          str(params, "sse"),
			})
		})
	case "capability":
		return t.callEnvelope(func(c dapb.PrismClient) (*dapb.Envelope, error) {
			return c.Capability(ctx, &dapb.CapabilityReq{Provider: str(params, "provider")})
		})
	case "list_providers":
		resp, err := t.client.ListProviders(ctx, &dapb.Empty{})
		if err != nil {
			return nil, err
		}
		raw, _ := json.Marshal(resp.Providers)
		return &Envelope{Value: raw, Diagnostics: []Diagnostic{}}, nil
	case "ping":
		resp, err := t.client.Ping(ctx, &dapb.Empty{})
		if err != nil {
			return nil, err
		}
		raw, _ := json.Marshal(resp.Message)
		return &Envelope{Value: raw, Diagnostics: []Diagnostic{}}, nil
	default:
		return nil, fmt.Errorf("unknown method: %s", method)
	}
}

// Stream implements Transport via the DecodeSSEStream server-streaming RPC:
// one envelope per event, ending with a done marker.
func (t *GRPCTransport) Stream(ctx context.Context, method string, params map[string]any) (<-chan *Envelope, error) {
	if method != "decode_sse" {
		return nil, fmt.Errorf("grpc stream supports decode_sse only, got %s", method)
	}
	stream, err := t.client.DecodeSSEStream(ctx, &dapb.DecodeSSEReq{
		Provider: str(params, "provider"),
		Sse:      str(params, "sse"),
	})
	if err != nil {
		return nil, err
	}
	ch := make(chan *Envelope, 8)
	go func() {
		defer close(ch)
		for {
			env, err := stream.Recv()
			if err != nil {
				return
			}
			e := fromPBEnvelope(env)
			select {
			case ch <- e:
			case <-ctx.Done():
				return
			}
		}
	}()
	return ch, nil
}

func (t *GRPCTransport) callEnvelope(fn func(dapb.PrismClient) (*dapb.Envelope, error)) (*Envelope, error) {
	env, err := fn(t.client)
	if err != nil {
		return nil, err
	}
	// Call 路径的 value 是裸字符串（如 provider JSON），需编码为 JSON 字符串
	// 字面量以匹配 SDK Envelope.ValueString() 语义（HTTP/UDS/WS 一致）。
	raw, err := json.Marshal(env.Value)
	if err != nil {
		return nil, err
	}
	out := &Envelope{Value: raw}
	for _, d := range env.Diagnostics {
		out.Diagnostics = append(out.Diagnostics, Diagnostic{
			Field:  d.Field,
			Status: d.Status,
			Detail: d.Detail,
		})
	}
	return out, nil
}

// fromPBEnvelope converts a protobuf Envelope to the SDK Envelope.
func fromPBEnvelope(env *dapb.Envelope) *Envelope {
	out := &Envelope{Value: []byte(env.Value)}
	for _, d := range env.Diagnostics {
		out.Diagnostics = append(out.Diagnostics, Diagnostic{
			Field:  d.Field,
			Status: d.Status,
			Detail: d.Detail,
		})
	}
	return out
}

// str reads a string param ("" when absent or non-string).
func str(params map[string]any, key string) string {
	if v, ok := params[key].(string); ok {
		return v
	}
	return ""
}
