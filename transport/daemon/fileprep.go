package daemon

import (
	"encoding/json"
	"strings"

	prism "github.com/morning-start/prism/wrappers/go"
)

// resolveFileURIs scans a JSON payload and replaces every string value that
// starts with file:// with a data URI (by reading the file), so the pure
// wasm conversion layer never sees a file_uri source it cannot resolve.
//
// Non-JSON payloads (e.g. raw SSE) pass through unchanged.
func resolveFileURIs(payload string) string {
	var v any
	if err := json.Unmarshal([]byte(payload), &v); err != nil {
		return payload
	}
	out, err := json.Marshal(walkJSON(v))
	if err != nil {
		return payload
	}
	return string(out)
}

// walkJSON recursively rewrites file:// string values into data URIs.
func walkJSON(v any) any {
	switch t := v.(type) {
	case map[string]any:
		for k, val := range t {
			t[k] = walkJSON(val)
		}
		return t
	case []any:
		for i, val := range t {
			t[i] = walkJSON(val)
		}
		return t
	case string:
		if strings.HasPrefix(t, "file://") {
			if uri, err := prism.FileToDataURI(t); err == nil {
				return uri
			}
		}
		return t
	default:
		return v
	}
}
