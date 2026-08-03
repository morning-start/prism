package daemon

import (
	"context"
	"encoding/json"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/coder/websocket"
)

// wsSessionRPC sends one request frame and reads one response frame,
// returning the raw result value (envelope "value").
func wsSessionRPC(t *testing.T, conn *websocket.Conn, body string) any {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := conn.Write(ctx, websocket.MessageText, []byte(body)); err != nil {
		t.Fatalf("ws write: %v", err)
	}
	_, data, err := conn.Read(ctx)
	if err != nil {
		t.Fatalf("ws read: %v", err)
	}
	var resp Response
	if err := json.Unmarshal(data, &resp); err != nil {
		t.Fatalf("decode ws response: %v", err)
	}
	if resp.Error != nil {
		t.Fatalf("rpc error: %+v", resp.Error)
	}
	return envelopeValue(t, &resp)
}

// wsReadFrame reads one frame and returns the envelope value (or nil for done).
func wsReadFrame(t *testing.T, conn *websocket.Conn) any {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_, data, err := conn.Read(ctx)
	if err != nil {
		t.Fatalf("ws read: %v", err)
	}
	var resp Response
	if err := json.Unmarshal(data, &resp); err != nil {
		t.Fatalf("decode ws frame: %v", err)
	}
	if resp.Error != nil {
		t.Fatalf("frame error: %+v", resp.Error)
	}
	return envelopeValue(t, &resp)
}

// TestWSSessionDecodeStream exercises the decode_sse_stream session model
// (ARCHITECTURE.md §4.5): start session → feed SSE chunks via sse_chunk
// notifications → end with [DONE] → collect event frames until done marker.
//
// 门禁：会话逐块喂入的事件序列 == 整段解码的事件序列。
func TestWSSessionDecodeStream(t *testing.T) {
	backend := loadBackend(t)
	conn := wsDial(t, wsServe(backend), "/ws")

	// 1. 开始会话
	v := wsSessionRPC(t, conn, `{"jsonrpc":"2.0","id":1,"method":"decode_sse_stream","params":{"provider":"openai-chat"}}`)
	sess, ok := v.(map[string]any)
	if !ok {
		t.Fatalf("decode_sse_stream value not an object: %T", v)
	}
	sessionID, ok := sess["session"].(string)
	if !ok || sessionID == "" {
		t.Fatalf("missing session id: %v", v)
	}

	// 2. 逐块喂 SSE（按字节切成 2 块，模拟真实网络分块；第 1 块可能含不完整帧）
	fixture := buildSSEFixture("openai-chat")
	chunks := splitSSETestChunks(fixture, 2)
	for i, chunk := range chunks {
		params, err := json.Marshal(map[string]string{
			"session": sessionID,
			"data":    chunk,
		})
		if err != nil {
			t.Fatal(err)
		}
		body := `{"jsonrpc":"2.0","method":"sse_chunk","params":` + string(params) + `}`
		if err := conn.Write(context.Background(), websocket.MessageText, []byte(body)); err != nil {
			t.Fatalf("ws write chunk %d: %v", i, err)
		}
	}

	// 3. 结束会话（喂 [DONE]）
	params, err := json.Marshal(map[string]string{
		"session": sessionID,
		"data":    "data: [DONE]",
	})
	if err != nil {
		t.Fatal(err)
	}
	if err := conn.Write(context.Background(), websocket.MessageText, []byte(`{"jsonrpc":"2.0","method":"sse_end","params":`+string(params)+`}`)); err != nil {
		t.Fatalf("ws write end: %v", err)
	}

	// 4. 排空读取：收集所有事件帧直到 done 标记
	var framed []any
	var sawDone bool
	for i := 0; i < 20; i++ {
		ev := wsReadFrame(t, conn)
		if mm, ok := ev.(map[string]any); ok {
			if t2, _ := mm["type"].(string); t2 == "done" {
				sawDone = true
				break
			}
		}
		framed = append(framed, ev)
	}
	if !sawDone {
		t.Fatal("missing done frame at session end")
	}

	// 5. 门禁：会话逐块事件 == 整段解码
	handler := NewHTTPHandler(backend, "test")
	whole := decodeWhole(t, handler, "openai-chat", fixture)
	if !reflect.DeepEqual(whole, framed) {
		t.Errorf("session feed diverges from whole-text decode:\n whole  = %v\n framed = %v", whole, framed)
	}
}

// splitSSETestChunks splits an SSE string into n roughly-equal chunks.
func splitSSETestChunks(s string, n int) []string {
	if n <= 1 {
		return []string{s}
	}
	step := (len(s) + n - 1) / n
	var chunks []string
	for i := 0; i < len(s); i += step {
		end := i + step
		if end > len(s) {
			end = len(s)
		}
		chunks = append(chunks, s[i:end])
	}
	return chunks
}

// TestWSSessionUnknownSession verifies an unknown session id is rejected.
func TestWSSessionUnknownSession(t *testing.T) {
	backend := loadBackend(t)
	conn := wsDial(t, wsServe(backend), "/ws")

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	params, _ := json.Marshal(map[string]string{"session": "nope", "data": "data: x"})
	if err := conn.Write(ctx, websocket.MessageText, []byte(`{"jsonrpc":"2.0","method":"sse_chunk","params":`+string(params)+`}`)); err != nil {
		t.Fatalf("ws write: %v", err)
	}
	_, data, err := conn.Read(ctx)
	if err != nil {
		t.Fatalf("ws read: %v", err)
	}
	var resp Response
	if err := json.Unmarshal(data, &resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if resp.Error == nil {
		t.Fatal("expected error for unknown session")
	}
	if !strings.Contains(resp.Error.Message, "session") {
		t.Fatalf("error message should mention session, got %q", resp.Error.Message)
	}
}
