package daemon

import (
	"bufio"
	"context"
	"encoding/json"
	"net"
	"os"
	"path/filepath"
	"testing"
	"time"
)

// udsRequest sends one JSON-lines request over a UDS connection and reads the
// first response line back (ARCHITECTURE.md §5.2).
func udsRequest(t *testing.T, sockPath, body string) *Response {
	t.Helper()
	conn, err := net.Dial("unix", sockPath)
	if err != nil {
		t.Fatalf("dial uds: %v", err)
	}
	defer conn.Close()
	if _, err := conn.Write([]byte(body + "\n")); err != nil {
		t.Fatalf("write uds request: %v", err)
	}
	line, err := bufio.NewReader(conn).ReadString('\n')
	if err != nil {
		t.Fatalf("read uds response: %v", err)
	}
	var resp Response
	if err := json.Unmarshal([]byte(line), &resp); err != nil {
		t.Fatalf("decode uds response: %v", err)
	}
	return &resp
}

// startUDSListener starts ListenUDS in a goroutine and waits for the socket
// to accept connections.
func startUDSListener(t *testing.T, backend Backend) string {
	t.Helper()
	sockPath := filepath.Join(t.TempDir(), "prism.sock")
	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(func() {
		cancel()
		_ = os.Remove(sockPath)
	})
	done := make(chan error, 1)
	go func() { done <- ListenUDS(ctx, backend, sockPath, "test") }()

	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		if _, err := os.Stat(sockPath); err == nil {
			// socket file exists; also verify it accepts
			if conn, err := net.Dial("unix", sockPath); err == nil {
				_ = conn.Close()
				return sockPath
			}
		}
		time.Sleep(10 * time.Millisecond)
	}
	select {
	case err := <-done:
		t.Fatalf("uds listener exited early: %v", err)
	default:
	}
	t.Fatalf("uds listener did not start on %s", sockPath)
	return ""
}

// TestUDSJSONLinesPing exercises the UDS JSON-lines path end to end: the
// request is one JSON line, the response is one envelope JSON line.
func TestUDSJSONLinesPing(t *testing.T) {
	backend := loadBackend(t)
	sockPath := startUDSListener(t, backend)

	resp := udsRequest(t, sockPath, `{"jsonrpc":"2.0","id":1,"method":"ping","params":{}}`)
	if resp.Error != nil {
		t.Fatalf("ping error: %v", resp.Error)
	}
	if v := envelopeValue(t, resp); v != "pong" {
		t.Fatalf("ping value = %v, want pong", v)
	}
}

// TestUDSJSONLinesEncodeRequest runs a real conversion request over UDS and
// checks the envelope value is a valid provider JSON string.
func TestUDSJSONLinesEncodeRequest(t *testing.T) {
	backend := loadBackend(t)
	sockPath := startUDSListener(t, backend)

	body := `{"jsonrpc":"2.0","id":2,"method":"encode_request","params":{"provider":"openai-chat","text":"Hi"}}`
	resp := udsRequest(t, sockPath, body)
	if resp.Error != nil {
		t.Fatalf("encode_request error: %v", resp.Error)
	}
	raw, ok := envelopeValue(t, resp).(string)
	if !ok {
		t.Fatalf("encode_request value is not a string: %T", envelopeValue(t, resp))
	}
	if !stringsContains(raw, `"messages"`) {
		t.Fatalf("provider JSON missing messages: %s", raw)
	}
}

// TestUDSJSONLinesUnknownMethod checks JSON-RPC error handling over UDS.
func TestUDSJSONLinesUnknownMethod(t *testing.T) {
	backend := loadBackend(t)
	sockPath := startUDSListener(t, backend)

	resp := udsRequest(t, sockPath, `{"jsonrpc":"2.0","id":3,"method":"nope","params":{}}`)
	if resp.Error == nil {
		t.Fatal("expected error for unknown method")
	}
}

func stringsContains(s, sub string) bool {
	return len(s) >= len(sub) && (func() bool {
		for i := 0; i+len(sub) <= len(s); i++ {
			if s[i:i+len(sub)] == sub {
				return true
			}
		}
		return false
	})()
}
