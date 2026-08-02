package daemon

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
)

// splitSSEFrames 按空行（\n\n）把 SSE 文本切成帧；尾部不完整帧也保留。
// 用于 convert_stream 的目标 SSE 逐帧写出。
func splitSSEFrames(text string) []string {
	var frames []string
	var cur strings.Builder
	for _, line := range strings.Split(text, "\n") {
		if line == "" {
			if cur.Len() > 0 {
				frames = append(frames, cur.String())
				cur.Reset()
			}
			continue
		}
		cur.WriteString(line)
		cur.WriteString("\n")
	}
	if cur.Len() > 0 {
		frames = append(frames, cur.String())
	}
	return frames
}

// writeSSEFrame 写一个 SSE 帧并 Flush。若 writer 不支持 Flusher（如
// httptest.ResponseRecorder），跳过 flush —— 仅影响首字节延迟，不影响正确性。
func writeSSEFrame(w http.ResponseWriter, event, payload string) {
	if event != "" {
		_, _ = fmt.Fprintf(w, "event: %s\n", event)
	}
	_, _ = fmt.Fprintf(w, "data: %s\n\n", payload)
	if f, ok := w.(http.Flusher); ok {
		f.Flush()
	}
}

// rpcEnvelope 构造一个 JSON-RPC 帧信封：{"jsonrpc","id","result":{value,diagnostics}}。
func rpcEnvelope(id json.RawMessage, value any, diagnostics []any) string {
	resp := &Response{
		JSONRPC: "2.0",
		ID:      id,
		Result: map[string]any{
			"value":       value,
			"diagnostics": diagnostics,
		},
	}
	raw, err := json.Marshal(resp)
	if err != nil {
		// 理论不可达：value 来自 json.Unmarshal 的结果，必可再序列化。
		return fmt.Sprintf(`{"jsonrpc":"2.0","id":%s,"error":{"code":-32603,"message":"marshal frame"}}`, id)
	}
	return string(raw)
}

// streamError 写一个 event: error 帧后收尾（HTTP 头已发出，无法再改状态码）。
func streamError(w http.ResponseWriter, id json.RawMessage, msg string) {
	writeSSEFrame(w, "error", rpcEnvelope(id, map[string]any{"error": msg}, []any{}))
}
