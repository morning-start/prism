package prism

import (
	"bufio"
	"context"
	"fmt"
	"io"
	"net"
	"net/http"
	"strings"
	"time"
)

// httpClient is a thin JSON-RPC-over-HTTP helper with SSE streaming support.
type httpClient struct {
	c *http.Client
}

func newHTTPClient() *httpClient {
	return &httpClient{c: &http.Client{Timeout: 30 * time.Second}}
}

// postJSON sends one JSON-RPC request and returns the raw response body.
func (h *httpClient) postJSON(ctx context.Context, url string, body []byte) ([]byte, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, strings.NewReader(string(body)))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := h.c.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("http %d: %s", resp.StatusCode, strings.TrimSpace(string(data)))
	}
	return data, nil
}

// postSSE sends one JSON-RPC request with Accept: text/event-stream and
// parses the SSE response into per-frame raw JSON lines.
func (h *httpClient) postSSE(ctx context.Context, url string, body []byte) ([][]byte, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, strings.NewReader(string(body)))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "text/event-stream")
	resp, err := h.c.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		data, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("http %d: %s", resp.StatusCode, strings.TrimSpace(string(data)))
	}

	var frames [][]byte
	scanner := bufio.NewScanner(resp.Body)
	var cur []byte
	for scanner.Scan() {
		line := scanner.Text()
		if line == "" {
			if len(cur) > 0 {
				frames = append(frames, cur)
				cur = nil
			}
			continue
		}
		if strings.HasPrefix(line, "data:") {
			cur = []byte(strings.TrimSpace(strings.TrimPrefix(line, "data:")))
		}
		// "event:" lines carry no payload; ignored.
	}
	if len(cur) > 0 {
		frames = append(frames, cur)
	}
	if err := scanner.Err(); err != nil {
		return nil, err
	}
	return frames, nil
}

// udsRoundTrip dials a Unix socket, writes one JSON line, and reads response
// lines. When stream is true it reads until the done marker; otherwise it
// returns just the first line.
func udsRoundTrip(ctx context.Context, sockPath, body string, stream bool) ([][]byte, error) {
	d := net.Dialer{}
	conn, err := d.DialContext(ctx, "unix", sockPath)
	if err != nil {
		return nil, fmt.Errorf("uds dial: %w", err)
	}
	defer conn.Close()
	if _, err := conn.Write([]byte(body + "\n")); err != nil {
		return nil, fmt.Errorf("uds write: %w", err)
	}
	reader := bufio.NewReader(conn)
	var lines [][]byte
	for {
		line, err := reader.ReadBytes('\n')
		if err != nil {
			return nil, fmt.Errorf("uds read: %w", err)
		}
		trimmed := strings.TrimSpace(string(line))
		lines = append(lines, []byte(trimmed))
		if !stream || strings.Contains(trimmed, `"type":"done"`) {
			break
		}
	}
	return lines, nil
}
