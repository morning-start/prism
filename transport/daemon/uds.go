package daemon

import (
	"bufio"
	"context"
	"encoding/json"
	"log"
	"net"
	"os"
	"strings"
)

// ListenUDS serves JSON-RPC 2.0 over a Unix domain socket (Windows: AF_UNIX
// socket, supported since Go 1.23) using JSON lines — one JSON-RPC request
// per line, one response per line (transport/ARCHITECTURE.md §5.2).
//
// Streaming methods (decode_sse / convert_stream) hold the connection and
// write one envelope line per event, ending with a done frame; synchronous
// requests get exactly one response line and the connection stays open for
// further requests until the client closes it.
func ListenUDS(ctx context.Context, backend Backend, sockPath, version string) error {
	_ = os.Remove(sockPath) // remove stale socket from a previous run
	setSocketUmask()        // restrict new sockets to the current user (unix)
	ln, err := net.Listen("unix", sockPath)
	if err != nil {
		return err
	}
	defer ln.Close()
	go func() {
		<-ctx.Done()
		_ = ln.Close()
	}()
	log.Printf("prism daemon listening on unix://%s (version %s)", sockPath, version)
	for {
		conn, err := ln.Accept()
		if err != nil {
			select {
			case <-ctx.Done():
				return nil
			default:
				return err
			}
		}
		go serveUDSConn(ctx, backend, conn)
	}
}

// serveUDSConn reads JSON-lines requests from one UDS connection and writes
// responses back. Requests are processed sequentially per connection; each
// connection is independent (Prism is stateless).
func serveUDSConn(ctx context.Context, backend Backend, conn net.Conn) {
	defer conn.Close()
	scanner := bufio.NewScanner(conn)
	scanner.Buffer(make([]byte, 64*1024), 4*1024*1024)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			continue
		}
		var req Request
		if err := json.Unmarshal([]byte(line), &req); err != nil {
			_ = writeUDSLine(conn, rpcError(json.RawMessage(`null`), ErrParse))
			continue
		}
		if req.Method == "decode_sse" || req.Method == "convert_stream" {
			// Streaming: hold the connection, one envelope line per event.
			serveUDSStream(ctx, backend, conn, &req)
			continue
		}
		_ = writeUDSLine(conn, ServeRPC(ctx, backend, &req))
	}
}

// serveUDSStream handles decode_sse / convert_stream over UDS: it decodes the
// whole payload first (correctness first, mirroring the HTTP path) and then
// writes one envelope line per event/frame, ending with a done frame.
func serveUDSStream(ctx context.Context, backend Backend, conn net.Conn, req *Request) {
	id := req.ID
	if len(id) == 0 {
		id = json.RawMessage(`null`)
	}
	params, rpcErr := parseParams(req.Params)
	if rpcErr != nil {
		_ = writeUDSLine(conn, rpcError(id, rpcErr))
		return
	}

	switch req.Method {
	case "decode_sse":
		provider, e := params.strParam("provider")
		if e != nil {
			_ = writeUDSLine(conn, rpcError(id, e))
			return
		}
		sse, e := params.strParam("sse")
		if e != nil {
			_ = writeUDSLine(conn, rpcError(id, e))
			return
		}
		envStr, err := backend.DecodeSSE(ctx, provider, sse)
		if err != nil {
			_ = writeUDSLine(conn, rpcError(id, domainError(err.Error())))
			return
		}
		env, e := envelopeResult(envStr)
		if e != nil {
			_ = writeUDSLine(conn, rpcError(id, e))
			return
		}
		events, ok := env["value"].([]any)
		if !ok {
			_ = writeUDSLine(conn, rpcError(id, domainError("decode_sse value is not an event array")))
			return
		}
		for _, ev := range events {
			if ctx.Err() != nil {
				return // client disconnected, stop writing
			}
			_ = writeUDSRawLine(conn, rpcEnvelope(id, ev, []any{}))
		}
		_ = writeUDSRawLine(conn, rpcEnvelope(id, map[string]any{"type": "done"}, []any{}))
	case "convert_stream":
		from, e := params.strParam("from_provider")
		if e != nil {
			_ = writeUDSLine(conn, rpcError(id, e))
			return
		}
		to, e := params.strParam("to_provider")
		if e != nil {
			_ = writeUDSLine(conn, rpcError(id, e))
			return
		}
		sse, e := params.strParam("sse")
		if e != nil {
			_ = writeUDSLine(conn, rpcError(id, e))
			return
		}
		envStr, err := backend.ConvertStream(ctx, from, to, sse)
		if err != nil {
			_ = writeUDSLine(conn, rpcError(id, domainError(err.Error())))
			return
		}
		env, e := envelopeResult(envStr)
		if e != nil {
			_ = writeUDSLine(conn, rpcError(id, e))
			return
		}
		target, ok := env["value"].(string)
		if !ok {
			_ = writeUDSLine(conn, rpcError(id, domainError("convert_stream value is not a string")))
			return
		}
		for _, frame := range splitSSEFrames(target) {
			if ctx.Err() != nil {
				return
			}
			_ = writeUDSRawLine(conn, rpcEnvelope(id, frame, []any{}))
		}
		_ = writeUDSRawLine(conn, rpcEnvelope(id, map[string]any{"type": "done"}, []any{}))
	default:
		_ = writeUDSLine(conn, rpcError(id, domainError("method not streamable: "+req.Method)))
	}
}

// writeUDSLine writes one JSON-RPC response as a single JSON line (\n-terminated).
func writeUDSLine(conn net.Conn, resp *Response) error {
	data, err := json.Marshal(resp)
	if err != nil {
		return err
	}
	data = append(data, '\n')
	_, err = conn.Write(data)
	return err
}

// writeUDSRawLine writes a pre-encoded JSON line (\n-terminated). Used for
// streaming frames whose envelope string is produced by rpcEnvelope.
func writeUDSRawLine(conn net.Conn, s string) error {
	_, err := conn.Write([]byte(s + "\n"))
	return err
}
