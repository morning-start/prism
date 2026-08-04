package daemon

import (
	"context"
	"net"
	"strings"
	"testing"

	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/grpc/test/bufconn"

	pb "github.com/morning-start/prism/transport/daemon/prismpb"
)

// startGRPCServer starts an in-process gRPC server over bufconn and returns
// a client connection.
func startGRPCServer(t *testing.T, backend Backend) (*grpc.ClientConn, pb.PrismClient) {
	t.Helper()
	lis := bufconn.Listen(1 << 20)
	srv := grpc.NewServer()
	pb.RegisterPrismServer(srv, NewGRPCServer(backend))
	go func() {
		_ = srv.Serve(lis)
	}()
	t.Cleanup(func() {
		srv.Stop()
		_ = lis.Close()
	})

	conn, err := grpc.NewClient(
		"passthrough:///bufconn",
		grpc.WithContextDialer(func(ctx context.Context, _ string) (net.Conn, error) {
			return lis.DialContext(ctx)
		}),
		grpc.WithTransportCredentials(insecure.NewCredentials()),
	)
	if err != nil {
		t.Fatalf("grpc dial: %v", err)
	}
	t.Cleanup(func() { _ = conn.Close() })
	return conn, pb.NewPrismClient(conn)
}

// TestGRPCEncodeRequest exercises a synchronous RPC and checks the envelope
// value is a valid provider JSON request.
func TestGRPCEncodeRequest(t *testing.T) {
	backend := loadBackend(t)
	_, client := startGRPCServer(t, backend)

	resp, err := client.EncodeRequest(context.Background(), &pb.EncodeRequestReq{
		Provider: "openai-chat",
		Text:     "Hi",
	})
	if err != nil {
		t.Fatalf("encode_request: %v", err)
	}
	if !strings.Contains(resp.Value, `"messages"`) {
		t.Fatalf("provider JSON missing messages: %s", resp.Value)
	}
}

// TestGRPCPing exercises the simplest RPC.
func TestGRPCPing(t *testing.T) {
	backend := loadBackend(t)
	_, client := startGRPCServer(t, backend)

	resp, err := client.Ping(context.Background(), &pb.Empty{})
	if err != nil {
		t.Fatalf("ping: %v", err)
	}
	if resp.Message != "pong" {
		t.Fatalf("ping = %q, want pong", resp.Message)
	}
}

// TestGRPCConvert runs convert and checks the envelope carries diagnostics.
func TestGRPCConvert(t *testing.T) {
	backend := loadBackend(t)
	_, client := startGRPCServer(t, backend)

	// build a minimal openai-chat request via the same server
	req, err := client.EncodeRequest(context.Background(), &pb.EncodeRequestReq{
		Provider: "openai-chat",
		Text:     "Hi",
	})
	if err != nil {
		t.Fatal(err)
	}
	resp, err := client.Convert(context.Background(), &pb.ConvertReq{
		FromProvider: "openai-chat",
		ToProvider:   "anthropic",
		Direction:    "request",
		Payload:      req.Value,
	})
	if err != nil {
		t.Fatalf("convert: %v", err)
	}
	// protobuf 空 repeated 字段反序列化为 nil（与 HTTP JSON 空数组不同）；
	// 无诊断时允许 nil，有诊断时每个元素结构必须完整。
	for _, d := range resp.Diagnostics {
		if d.Field == "" && d.Status == "" {
			t.Errorf("diagnostic missing field/status: %v", d)
		}
	}
	if !strings.Contains(resp.Value, "system") && !strings.Contains(resp.Value, "messages") {
		t.Fatalf("converted anthropic request missing expected shape: %s", resp.Value)
	}
}

// TestGRPCListProviders checks the provider list RPC.
func TestGRPCListProviders(t *testing.T) {
	backend := loadBackend(t)
	_, client := startGRPCServer(t, backend)

	resp, err := client.ListProviders(context.Background(), &pb.Empty{})
	if err != nil {
		t.Fatalf("list_providers: %v", err)
	}
	if len(resp.Providers) < 7 {
		t.Fatalf("expected >= 7 providers, got %d", len(resp.Providers))
	}
}

// TestGRPCUnknownProvider returns a gRPC error for an unknown provider.
func TestGRPCUnknownProvider(t *testing.T) {
	backend := loadBackend(t)
	_, client := startGRPCServer(t, backend)

	_, err := client.EncodeRequest(context.Background(), &pb.EncodeRequestReq{
		Provider: "no-such-provider",
		Text:     "Hi",
	})
	if err == nil {
		t.Fatal("expected error for unknown provider")
	}
	if !strings.Contains(err.Error(), "provider") {
		t.Fatalf("error should mention provider, got %v", err)
	}
}

// TestGRPCEncodeStream exercises the sync EncodeStream RPC: it returns the
// streaming (stream:true) provider request JSON, not an event stream
// (per the Phase 3 term clarification).
func TestGRPCEncodeStream(t *testing.T) {
	backend := loadBackend(t)
	_, client := startGRPCServer(t, backend)

	resp, err := client.EncodeStream(context.Background(), &pb.EncodeStreamReq{
		Provider: "openai-chat",
		Text:     "Hi",
	})
	if err != nil {
		t.Fatalf("encode_stream: %v", err)
	}
	if !strings.Contains(resp.Value, `"stream":true`) {
		t.Fatalf("expected stream:true in request JSON: %s", resp.Value)
	}
}

// TestGRPCDecodeSSEStream exercises the server-streaming RPC: one envelope
// per event, ending with a done marker.
func TestGRPCDecodeSSEStream(t *testing.T) {
	backend := loadBackend(t)
	_, client := startGRPCServer(t, backend)

	stream, err := client.DecodeSSEStream(context.Background(), &pb.DecodeSSEReq{
		Provider: "openai-chat",
		Sse:      buildSSEFixture("openai-chat"),
	})
	if err != nil {
		t.Fatalf("decode_sse_stream: %v", err)
	}
	var frames int
	var sawDone bool
	for frames < 20 {
		env, err := stream.Recv()
		if err != nil {
			t.Fatalf("stream recv: %v (got %d frames)", err, frames)
		}
		frames++
		if strings.Contains(env.Value, `"type":"done"`) {
			sawDone = true
			break
		}
	}
	if frames < 2 {
		t.Fatalf("expected multiple frames, got %d", frames)
	}
	if !sawDone {
		t.Fatal("missing done marker in gRPC stream")
	}
}
