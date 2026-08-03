package daemon

import (
	"context"
	"encoding/json"
	"log"
	"net/http"

	"github.com/coder/websocket"
)

// ServeWS handles the WebSocket binding (ARCHITECTURE.md §5.3): the client
// opens a WS connection at /ws, sends one JSON-RPC 2.0 message per frame
// (Text), and receives one JSON-RPC response per frame. Streaming methods
// (decode_sse / convert_stream) respond with multiple result frames — one
// per event — ending with a done frame. Session methods (decode_sse_stream /
// sse_chunk / sse_end) implement the ARCHITECTURE.md §4.5 session model.
//
// The same ServeRPC dispatcher is reused; no conversion logic lives here.
func ServeWS(ctx context.Context, backend Backend, w http.ResponseWriter, r *http.Request) {
	conn, err := websocket.Accept(w, r, nil)
	if err != nil {
		log.Printf("ws accept: %v", err)
		return
	}
	defer conn.Close(websocket.StatusNormalClosure, "done")

	sm := newSessionManager() // sessions are per-connection
	for {
		msgType, data, err := conn.Read(ctx)
		if err != nil {
			return // client closed or context cancelled
		}
		if msgType != websocket.MessageText {
			_ = conn.Write(ctx, websocket.MessageText, mustJSON(rpcError(
				json.RawMessage(`null`), domainError("expected text frame"))))
			continue
		}
		var req Request
		if err := json.Unmarshal(data, &req); err != nil {
			_ = conn.Write(ctx, websocket.MessageText, mustJSON(rpcError(
				json.RawMessage(`null`), ErrParse)))
			continue
		}
		switch req.Method {
		case "decode_sse_stream":
			serveWSSessionStart(ctx, conn, &req, backend, sm)
		case "sse_chunk", "sse_end":
			serveWSSessionFeed(ctx, conn, &req, backend, sm)
		case "decode_sse", "convert_stream":
			serveWSStream(ctx, conn, &req, backend)
		default:
			resp := ServeRPC(ctx, backend, &req)
			_ = conn.Write(ctx, websocket.MessageText, mustJSON(resp))
		}
	}
}

// serveWSSessionStart handles decode_sse_stream: create a session and return
// its id (ARCHITECTURE.md §4.5).
func serveWSSessionStart(
	ctx context.Context,
	conn *websocket.Conn,
	req *Request,
	backend Backend,
	sm *sessionManager,
) {
	params, rpcErr := parseParams(req.Params)
	if rpcErr != nil {
		_ = conn.Write(ctx, websocket.MessageText, mustJSON(rpcError(req.ID, rpcErr)))
		return
	}
	provider, e := params.strParam("provider")
	if e != nil {
		_ = conn.Write(ctx, websocket.MessageText, mustJSON(rpcError(req.ID, e)))
		return
	}
	id := sm.start(provider, req.ID)
	_ = conn.Write(ctx, websocket.MessageText, []byte(rpcEnvelope(req.ID, map[string]any{"session": id}, []any{})))
}

// serveWSSessionFeed handles sse_chunk (feed data, emit new events) and
// sse_end (final feed + done frame + close session).
func serveWSSessionFeed(
	ctx context.Context,
	conn *websocket.Conn,
	req *Request,
	backend Backend,
	sm *sessionManager,
) {
	params, rpcErr := parseParams(req.Params)
	if rpcErr != nil {
		_ = conn.Write(ctx, websocket.MessageText, mustJSON(rpcError(req.ID, rpcErr)))
		return
	}
	session, e := params.strParam("session")
	if e != nil {
		_ = conn.Write(ctx, websocket.MessageText, mustJSON(rpcError(req.ID, e)))
		return
	}
	data, e := params.strParam("data")
	if e != nil {
		_ = conn.Write(ctx, websocket.MessageText, mustJSON(rpcError(req.ID, e)))
		return
	}

	events, sessID, ok := sm.feed(ctx, backend, session, data)
	if !ok {
		_ = conn.Write(ctx, websocket.MessageText, mustJSON(rpcError(req.ID, domainError("unknown session: "+session))))
		return
	}
	// Reuse the original decode_sse_stream request id for event frames.
	for _, ev := range events {
		if ctx.Err() != nil {
			return
		}
		_ = conn.Write(ctx, websocket.MessageText, []byte(rpcEnvelope(sessID, ev, []any{})))
	}
	if req.Method == "sse_end" {
		if _, ok := sm.end(session); !ok {
			_ = conn.Write(ctx, websocket.MessageText, mustJSON(rpcError(req.ID, domainError("unknown session: "+session))))
			return
		}
		_ = conn.Write(ctx, websocket.MessageText, []byte(rpcEnvelope(sessID, map[string]any{"type": "done"}, []any{})))
	}
}

// serveWSStream handles streaming methods over WS: decode the whole payload
// first (correctness first, mirroring the HTTP/UDS paths) then write one
// frame per event, ending with a done frame.
func serveWSStream(ctx context.Context, conn *websocket.Conn, req *Request, backend Backend) {
	id := req.ID
	if len(id) == 0 {
		id = json.RawMessage(`null`)
	}
	params, rpcErr := parseParams(req.Params)
	if rpcErr != nil {
		_ = conn.Write(ctx, websocket.MessageText, mustJSON(rpcError(id, rpcErr)))
		return
	}

	switch req.Method {
	case "decode_sse":
		provider, e := params.strParam("provider")
		if e != nil {
			_ = conn.Write(ctx, websocket.MessageText, mustJSON(rpcError(id, e)))
			return
		}
		sse, e := params.strParam("sse")
		if e != nil {
			_ = conn.Write(ctx, websocket.MessageText, mustJSON(rpcError(id, e)))
			return
		}
		envStr, err := backend.DecodeSSE(ctx, provider, sse)
		if err != nil {
			_ = conn.Write(ctx, websocket.MessageText, mustJSON(rpcError(id, domainError(err.Error()))))
			return
		}
		env, e := envelopeResult(envStr)
		if e != nil {
			_ = conn.Write(ctx, websocket.MessageText, mustJSON(rpcError(id, e)))
			return
		}
		events, ok := env["value"].([]any)
		if !ok {
			_ = conn.Write(ctx, websocket.MessageText, mustJSON(rpcError(id, domainError("decode_sse value is not an event array"))))
			return
		}
		for _, ev := range events {
			if ctx.Err() != nil {
				return
			}
			_ = conn.Write(ctx, websocket.MessageText, []byte(rpcEnvelope(id, ev, []any{})))
		}
		_ = conn.Write(ctx, websocket.MessageText, []byte(rpcEnvelope(id, map[string]any{"type": "done"}, []any{})))
	case "convert_stream":
		from, e := params.strParam("from_provider")
		if e != nil {
			_ = conn.Write(ctx, websocket.MessageText, mustJSON(rpcError(id, e)))
			return
		}
		to, e := params.strParam("to_provider")
		if e != nil {
			_ = conn.Write(ctx, websocket.MessageText, mustJSON(rpcError(id, e)))
			return
		}
		sse, e := params.strParam("sse")
		if e != nil {
			_ = conn.Write(ctx, websocket.MessageText, mustJSON(rpcError(id, e)))
			return
		}
		envStr, err := backend.ConvertStream(ctx, from, to, sse)
		if err != nil {
			_ = conn.Write(ctx, websocket.MessageText, mustJSON(rpcError(id, domainError(err.Error()))))
			return
		}
		env, e := envelopeResult(envStr)
		if e != nil {
			_ = conn.Write(ctx, websocket.MessageText, mustJSON(rpcError(id, e)))
			return
		}
		target, ok := env["value"].(string)
		if !ok {
			_ = conn.Write(ctx, websocket.MessageText, mustJSON(rpcError(id, domainError("convert_stream value is not a string"))))
			return
		}
		for _, frame := range splitSSEFrames(target) {
			if ctx.Err() != nil {
				return
			}
			_ = conn.Write(ctx, websocket.MessageText, []byte(rpcEnvelope(id, frame, []any{})))
		}
		_ = conn.Write(ctx, websocket.MessageText, []byte(rpcEnvelope(id, map[string]any{"type": "done"}, []any{})))
	default:
		_ = conn.Write(ctx, websocket.MessageText, mustJSON(rpcError(id, domainError("method not streamable: "+req.Method))))
	}
}

// mustJSON serializes a Response; on the (theoretically unreachable) failure
// it falls back to a static error frame.
func mustJSON(resp *Response) []byte {
	data, err := json.Marshal(resp)
	if err != nil {
		return []byte(`{"jsonrpc":"2.0","id":null,"error":{"code":-32603,"message":"marshal frame"}}`)
	}
	return data
}
