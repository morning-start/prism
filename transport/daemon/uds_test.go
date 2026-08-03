package daemon

import (
	"bufio"
	"context"
	"encoding/json"
	"net"
	"os"
	"path/filepath"
	"reflect"
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

// udsStreamRequest sends one JSON-lines request over a UDS connection and
// reads back all response lines until the done frame (streaming path).
func udsStreamRequest(t *testing.T, sockPath, body string) []string {
	t.Helper()
	conn, err := net.Dial("unix", sockPath)
	if err != nil {
		t.Fatalf("dial uds: %v", err)
	}
	defer conn.Close()
	if _, err := conn.Write([]byte(body + "\n")); err != nil {
		t.Fatalf("write uds request: %v", err)
	}
	reader := bufio.NewReader(conn)
	var lines []string
	for {
		line, err := reader.ReadString('\n')
		if err != nil {
			t.Fatalf("read uds response: %v (got %d lines)", err, len(lines))
		}
		lines = append(lines, stringsTrimSuffix(line))
		if stringsContains(line, `"type":"done"`) {
			break
		}
	}
	return lines
}

// udsDecodeFrameByFrame 走 UDS 流式路径，把各帧信封里的 value 重组为事件数组
// （与 HTTP 路径的 decodeFrameByFrame 语义一致）。
func udsDecodeFrameByFrame(t *testing.T, sockPath, provider, sse string) []any {
	t.Helper()
	lines := udsStreamRequest(t, sockPath, decodeSSEParams(t, provider, sse))
	var events []any
	for _, line := range lines {
		var frame struct {
			Result map[string]any `json:"result"`
		}
		if err := json.Unmarshal([]byte(line), &frame); err != nil {
			t.Fatalf("parse uds frame: %v (line=%q)", err, line)
		}
		ev, ok := frame.Result["value"]
		if !ok {
			t.Fatalf("uds frame result missing value: %v", frame.Result)
		}
		// 跳过 done 帧（value 为 {"type":"done"}）
		if m, isObj := ev.(map[string]any); isObj {
			if t2, _ := m["type"].(string); t2 == "done" {
				continue
			}
		}
		events = append(events, ev)
	}
	return events
}

func stringsTrimSuffix(s string) string {
	for len(s) > 0 && (s[len(s)-1] == '\n' || s[len(s)-1] == '\r') {
		s = s[:len(s)-1]
	}
	return s
}

// 门禁（移植自 HTTP 的 TestFrameByFrameEqualsWholeText）：UDS 流式逐事件
// 解码 == HTTP 同步整段解码，4 个基础 provider 全覆盖。
func TestUDSFrameByFrameEqualsWholeText(t *testing.T) {
	backend := loadBackend(t)
	sockPath := startUDSListener(t, backend)
	handler := NewHTTPHandler(backend, "test")
	for _, p := range []string{"openai", "openai-chat", "anthropic", "gemini"} {
		t.Run(p, func(t *testing.T) {
			sse := buildSSEFixture(p)
			whole := decodeWhole(t, handler, p, sse)
			framed := udsDecodeFrameByFrame(t, sockPath, p, sse)
			if !reflect.DeepEqual(whole, framed) {
				t.Errorf("uds frame-by-frame diverges from whole-text decode:\n whole  = %v\n framed = %v", whole, framed)
			}
		})
	}
}

// UDS 流式 convert_stream：目标 SSE 帧逐帧写出 + done 帧收尾。
func TestUDSStreamConvertStream(t *testing.T) {
	backend := loadBackend(t)
	sockPath := startUDSListener(t, backend)

	sse := buildSSEFixture("openai-chat")
	params, err := json.Marshal(map[string]string{
		"from_provider": "openai-chat",
		"to_provider":   "anthropic",
		"sse":           sse,
	})
	if err != nil {
		t.Fatal(err)
	}
	body := `{"jsonrpc":"2.0","id":8,"method":"convert_stream","params":` + string(params) + `}`
	lines := udsStreamRequest(t, sockPath, body)
	if len(lines) < 2 {
		t.Fatalf("expected multiple uds frames, got %d", len(lines))
	}
	if !stringsContains(lines[len(lines)-1], `"type":"done"`) {
		t.Errorf("last uds frame missing done marker: %q", lines[len(lines)-1])
	}
	// 至少一帧是目标协议 SSE 片段（帧内 data: 前是换行而非引号）
	var sawData bool
	for _, line := range lines {
		if stringsContains(line, `data: {`) {
			sawData = true
		}
	}
	if !sawData {
		t.Errorf("no target SSE data frame in uds stream: %v", lines)
	}
}
