package prism

import (
	"encoding/base64"
	"fmt"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"runtime"
	"strings"
)

// FileToDataURI reads a file:// URI and returns a data URI
// (data:<mime>;base64,<payload>) suitable for Inline media/file sources.
//
// Usage: the conversion layer is a pure function with no filesystem access,
// so callers that hold IR FileUri/Image sources must resolve them to base64
// before passing them into the WASM converter (e.g. as an Inline source).
//
// Example:
//
//	uri, _ := prism.FileToDataURI("file:///tmp/report.pdf")
//	// uri == "data:application/pdf;base64,JVBERi0xLjQK..."
func FileToDataURI(fileURI string) (string, error) {
	u, err := url.Parse(fileURI)
	if err != nil {
		return "", newPrismError("parse file uri: " + err.Error())
	}
	if u.Scheme != "file" {
		return "", newPrismError("expected file:// URI, got: " + fileURI)
	}
	path := u.Path
	if u.Host != "" {
		if len(u.Host) == 2 && u.Host[1] == ':' {
			// file://C:/Users/... → C:/Users/...（Windows 盘符被解析为 host）
			path = u.Host + u.Path
		} else {
			// file://host/share → //host/share（UNC 路径）
			path = "//" + u.Host + u.Path
		}
	}
	if runtime.GOOS == "windows" {
		// file:///C:/Users/... → C:/Users/...（去掉前导斜杠，保留盘符）
		path = strings.TrimPrefix(path, "/")
		path = filepath.FromSlash(path)
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return "", newPrismError("read file: " + err.Error())
	}
	mime := http.DetectContentType(data)
	if mime == "application/octet-stream" || mime == "text/plain; charset=utf-8" {
		// Fall back to extension-based type for common documents.
		if ext := extToMIME(path); ext != "" {
			mime = ext
		}
	}
	enc := base64.StdEncoding.EncodeToString(data)
	return fmt.Sprintf("data:%s;base64,%s", mime, enc), nil
}

// extToMIME maps a few common extensions to MIME types; returns "" when unknown.
func extToMIME(path string) string {
	lower := strings.ToLower(path)
	switch {
	case strings.HasSuffix(lower, ".pdf"):
		return "application/pdf"
	case strings.HasSuffix(lower, ".png"):
		return "image/png"
	case strings.HasSuffix(lower, ".jpg"), strings.HasSuffix(lower, ".jpeg"):
		return "image/jpeg"
	case strings.HasSuffix(lower, ".webp"):
		return "image/webp"
	case strings.HasSuffix(lower, ".txt"):
		return "text/plain"
	case strings.HasSuffix(lower, ".json"):
		return "application/json"
	}
	return ""
}
