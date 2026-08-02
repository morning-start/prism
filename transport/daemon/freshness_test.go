package daemon

import (
	"io/fs"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// wasmArtifactPath is the classic-wasm build produced by `moon build --target wasm`
// from the repo root (same artifact loadBackend reads).
const wasmArtifactPath = "../../_build/wasm/debug/build/cmd/main/main.wasm"

// TestWASMArtifactFresherThanSources guards against running Go tests against a
// stale WASM artifact: the build must be newer than every MoonBit source file.
// A stale artifact silently tests old behavior and can produce false greens
// (plan gap E).
func TestWASMArtifactFresherThanSources(t *testing.T) {
	art, err := os.Stat(wasmArtifactPath)
	if err != nil {
		t.Fatalf("wasm artifact missing, run: moon build --target wasm (%v)", err)
	}
	var newest time.Time
	var newestPath string
	err = filepath.WalkDir("../..", func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() {
			switch d.Name() {
			case "_build", ".git", "node_modules":
				return filepath.SkipDir
			}
			return nil
		}
		name := d.Name()
		if !strings.HasSuffix(name, ".mbt") && name != "moon.pkg" && name != "moon.mod" {
			return nil
		}
		info, err := d.Info()
		if err != nil {
			return err
		}
		if info.ModTime().After(newest) {
			newest = info.ModTime()
			newestPath = p
		}
		return nil
	})
	if err != nil {
		t.Fatalf("walk repo sources: %v", err)
	}
	if newest.After(art.ModTime()) {
		t.Fatalf("stale wasm artifact: %s modified %v after build %v — run: moon build --target wasm",
			newestPath, newest, art.ModTime())
	}
}

// TestAllExportsPresent pins the full export surface (15 functions, including
// the 3 convert shims and list_providers) that Phase 3 depends on.
func TestAllExportsPresent(t *testing.T) {
	backend := loadBackend(t)
	for _, name := range []string{
		"wasm_to_lux_req", "wasm_lux_req_to_provider",
		"wasm_to_lux_resp", "wasm_lux_resp_to_provider",
		"wasm_sse_to_events", "wasm_events_to_sse",
		"wasm_sdk_encode_req", "wasm_sdk_decode_resp",
		"wasm_sdk_encode_stream", "wasm_sdk_decode_sse", "wasm_sdk_capability",
		"wasm_convert_req", "wasm_convert_resp", "wasm_convert_stream",
		"wasm_list_providers",
	} {
		if backend.HasExport(name) == false {
			t.Errorf("missing export: %s", name)
		}
	}
}
