package daemon

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"sync"
)

// sseSession holds the accumulated SSE text and emission progress for one
// decode_sse_stream session (ARCHITECTURE.md §4.5).
type sseSession struct {
	provider string
	reqID    json.RawMessage // original decode_sse_stream request id
	buf      strings.Builder // accumulated SSE text across chunks
	emitted  int             // events already sent to the client
}

// sessionManager tracks live decode_sse_stream sessions. It is scoped to a
// single connection — sessions never span connections (Prism is stateless).
type sessionManager struct {
	mu       sync.Mutex
	next     int
	sessions map[string]*sseSession
}

func newSessionManager() *sessionManager {
	return &sessionManager{sessions: make(map[string]*sseSession)}
}

// start creates a session for provider and returns its id.
func (sm *sessionManager) start(provider string, reqID json.RawMessage) string {
	sm.mu.Lock()
	defer sm.mu.Unlock()
	sm.next++
	id := fmt.Sprintf("sse-%03d", sm.next)
	sm.sessions[id] = &sseSession{provider: provider, reqID: reqID}
	return id
}

// feed appends a chunk of SSE text and returns the events that became
// decodable since the previous feed. It uses whole-decode-then-diff
// (correctness first, mirroring the HTTP/UDS paths): the accumulated text is
// decoded as a whole and only newly-decoded events are returned, so an
// incomplete trailing frame simply yields no new events until it completes.
//
// Returns (events, reqID, ok); ok=false means the session id is unknown.
func (sm *sessionManager) feed(
	ctx context.Context,
	backend Backend,
	id, data string,
) ([]any, json.RawMessage, bool) {
	sm.mu.Lock()
	s, ok := sm.sessions[id]
	if !ok {
		sm.mu.Unlock()
		return nil, nil, false
	}
	s.buf.WriteString(data)
	text := s.buf.String()
	emitted := s.emitted
	reqID := s.reqID
	sm.mu.Unlock()

	envStr, err := backend.DecodeSSE(ctx, s.provider, text)
	if err != nil {
		return nil, reqID, true // partial text not yet fully decodable
	}
	env, e := envelopeResult(envStr)
	if e != nil {
		return nil, reqID, true
	}
	events, ok := env["value"].([]any)
	if !ok {
		return nil, reqID, true
	}

	sm.mu.Lock()
	if emitted < len(events) {
		sm.sessions[id].emitted = len(events)
	}
	sm.mu.Unlock()

	if emitted >= len(events) {
		return nil, reqID, true
	}
	return events[emitted:], reqID, true
}

// end closes the session and returns its original request id (for the done
// frame). Returns ok=false for an unknown session id.
func (sm *sessionManager) end(id string) (json.RawMessage, bool) {
	sm.mu.Lock()
	defer sm.mu.Unlock()
	s, ok := sm.sessions[id]
	if !ok {
		return nil, false
	}
	delete(sm.sessions, id)
	return s.reqID, true
}
