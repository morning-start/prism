package daemon

import (
	"context"
	"encoding/json"
	"errors"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	pb "github.com/morning-start/prism/transport/daemon/prismpb"
)

// GRPCServer implements prismpb.PrismServer over the daemon Backend
// (transport/ARCHITECTURE.md §5.4). Every RPC maps 1:1 to the daemon method
// set and returns the D5 envelope {value, diagnostics}; DecodeSSEStream is
// server-streaming (one envelope per event, ending with a done marker).
// No conversion logic lives here — the Backend is reused as-is.
type GRPCServer struct {
	pb.UnimplementedPrismServer
	backend Backend
}

// NewGRPCServer returns a PrismServer bound to the given backend.
func NewGRPCServer(backend Backend) *GRPCServer {
	return &GRPCServer{backend: backend}
}

// envelope builds a D5 envelope from a raw JSON string value.
func envelope(value string, diagnostics []*pb.Diagnostic) *pb.Envelope {
	return &pb.Envelope{Value: value, Diagnostics: diagnostics}
}

// parseBackendEnvelope parses the D5 envelope JSON string returned by the
// backend ({value, diagnostics}) into the gRPC Envelope message.
func parseBackendEnvelope(out string) (*pb.Envelope, error) {
	env, e := envelopeResult(out)
	if e != nil {
		return nil, errors.New(e.Message)
	}
	value, ok := env["value"].(string)
	if !ok {
		return nil, errors.New("envelope value is not a string")
	}
	var diags []*pb.Diagnostic
	if raw, ok := env["diagnostics"].([]any); ok {
		for _, x := range raw {
			m, ok := x.(map[string]any)
			if !ok {
				continue
			}
			diags = append(diags, &pb.Diagnostic{
				Field:  jsonString(m["field"]),
				Status: jsonString(m["status"]),
				Detail: jsonString(m["detail"]),
			})
		}
	}
	return envelope(value, diags), nil
}

// jsonString coerces a decoded JSON value to a string ("" for non-strings).
func jsonString(v any) string {
	if s, ok := v.(string); ok {
		return s
	}
	return ""
}

// EncodeRequest implements prismpb.PrismServer.
func (s *GRPCServer) EncodeRequest(ctx context.Context, req *pb.EncodeRequestReq) (*pb.Envelope, error) {
	out, err := s.backend.EncodeRequest(ctx, req.Provider, req.Text)
	if err != nil {
		return nil, status.Error(codes.InvalidArgument, err.Error())
	}
	return parseBackendEnvelope(out)
}

// DecodeResponse implements prismpb.PrismServer.
func (s *GRPCServer) DecodeResponse(ctx context.Context, req *pb.DecodeResponseReq) (*pb.Envelope, error) {
	out, err := s.backend.DecodeResponse(ctx, req.Provider, req.Json)
	if err != nil {
		return nil, status.Error(codes.InvalidArgument, err.Error())
	}
	return parseBackendEnvelope(out)
}

// DecodeSSE implements prismpb.PrismServer (sync: JSON array of events).
func (s *GRPCServer) DecodeSSE(ctx context.Context, req *pb.DecodeSSEReq) (*pb.Envelope, error) {
	out, err := s.backend.DecodeSSE(ctx, req.Provider, req.Sse)
	if err != nil {
		return nil, status.Error(codes.InvalidArgument, err.Error())
	}
	return parseBackendEnvelope(out)
}

// EncodeStream implements prismpb.PrismServer (sync: streaming request JSON).
func (s *GRPCServer) EncodeStream(ctx context.Context, req *pb.EncodeStreamReq) (*pb.Envelope, error) {
	out, err := s.backend.EncodeStream(ctx, req.Provider, req.Text)
	if err != nil {
		return nil, status.Error(codes.InvalidArgument, err.Error())
	}
	return parseBackendEnvelope(out)
}

// Convert implements prismpb.PrismServer.
func (s *GRPCServer) Convert(ctx context.Context, req *pb.ConvertReq) (*pb.Envelope, error) {
	out, err := s.backend.Convert(ctx, req.FromProvider, req.ToProvider, req.Direction, req.Payload)
	if err != nil {
		return nil, status.Error(codes.InvalidArgument, err.Error())
	}
	return parseBackendEnvelope(out)
}

// ConvertStream implements prismpb.PrismServer (sync: target SSE text).
func (s *GRPCServer) ConvertStream(ctx context.Context, req *pb.ConvertStreamReq) (*pb.Envelope, error) {
	out, err := s.backend.ConvertStream(ctx, req.FromProvider, req.ToProvider, req.Sse)
	if err != nil {
		return nil, status.Error(codes.InvalidArgument, err.Error())
	}
	return parseBackendEnvelope(out)
}

// ListProviders implements prismpb.PrismServer.
func (s *GRPCServer) ListProviders(_ context.Context, _ *pb.Empty) (*pb.ProviderList, error) {
	return &pb.ProviderList{Providers: s.backend.ListProviders()}, nil
}

// Capability implements prismpb.PrismServer.
func (s *GRPCServer) Capability(ctx context.Context, req *pb.CapabilityReq) (*pb.Envelope, error) {
	cap, err := s.backend.Capability(ctx, req.Provider)
	if err != nil {
		return nil, status.Error(codes.InvalidArgument, err.Error())
	}
	raw, err := json.Marshal(cap)
	if err != nil {
		return nil, status.Error(codes.Internal, "marshal capability")
	}
	return envelope(string(raw), nil), nil
}

// Ping implements prismpb.PrismServer.
func (s *GRPCServer) Ping(_ context.Context, _ *pb.Empty) (*pb.Pong, error) {
	return &pb.Pong{Message: s.backend.Ping()}, nil
}

// DecodeSSEStream implements prismpb.PrismServer (server-streaming): decode
// the whole SSE payload first (correctness first, mirroring the HTTP/UDS/WS
// paths) then stream one envelope per event, ending with a done marker.
func (s *GRPCServer) DecodeSSEStream(req *pb.DecodeSSEReq, stream pb.Prism_DecodeSSEStreamServer) error {
	ctx := stream.Context()
	envStr, err := s.backend.DecodeSSE(ctx, req.Provider, req.Sse)
	if err != nil {
		return status.Error(codes.InvalidArgument, err.Error())
	}
	env, e := envelopeResult(envStr)
	if e != nil {
		return status.Error(codes.Internal, e.Message)
	}
	events, ok := env["value"].([]any)
	if !ok {
		return status.Error(codes.Internal, "decode_sse value is not an event array")
	}
	for _, ev := range events {
		if ctx.Err() != nil {
			return ctx.Err()
		}
		raw, err := json.Marshal(ev)
		if err != nil {
			return status.Error(codes.Internal, "marshal event")
		}
		if err := stream.Send(envelope(string(raw), nil)); err != nil {
			return err
		}
	}
	done, _ := json.Marshal(map[string]any{"type": "done"})
	return stream.Send(envelope(string(done), nil))
}

// compile-time check that GRPCServer satisfies the generated interface.
var _ pb.PrismServer = (*GRPCServer)(nil)
var _ = errors.New // keep errors import if unused later
