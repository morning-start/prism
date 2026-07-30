// Package prism provides a Go WASM wrapper around the Prism LLM protocol converter.
//
// It loads prism.wasm via wazero and exposes the 11 exported functions
// through a clean Go API.
package prism

import (
	"context"
	_ "embed"
	"encoding/json"
	"sync"

	"github.com/tetratelabs/wazero"
	"github.com/tetratelabs/wazero/api"
)

// MoonBit WASM export names match the function names exactly
// (exported via options(link: ...) in moon.pkg).
var wasmExportMap = map[string]string{
	"wasm_to_lux_req":            "wasm_to_lux_req",
	"wasm_lux_req_to_provider":   "wasm_lux_req_to_provider",
	"wasm_to_lux_resp":           "wasm_to_lux_resp",
	"wasm_lux_resp_to_provider":  "wasm_lux_resp_to_provider",
	"wasm_sse_to_events":             "wasm_sse_to_events",
	"wasm_events_to_sse":             "wasm_events_to_sse",
	"wasm_sdk_encode_req":        "wasm_sdk_encode_req",
	"wasm_sdk_decode_resp":       "wasm_sdk_decode_resp",
	"wasm_sdk_encode_stream":         "wasm_sdk_encode_stream",
	"wasm_sdk_decode_sse":            "wasm_sdk_decode_sse",
	"wasm_sdk_capability":            "wasm_sdk_capability",
}

// reversedMap maps WASM export names back to Go-friendly names.
var reversedMap map[string]string

func init() {
	reversedMap = make(map[string]string, len(wasmExportMap))
	for goName, wasmName := range wasmExportMap {
		reversedMap[wasmName] = goName
	}
}

// Runtime manages the wazero WASM runtime.
type Runtime struct {
	ctx    context.Context
	rt     wazero.Runtime
	mod    api.Module
	mu     sync.Mutex
	loaded bool
}

// NewRuntime loads prism.wasm bytes and returns a Runtime.
func NewRuntime(wasmBytes []byte) (*Runtime, error) {
	ctx := context.Background()
	rt := wazero.NewRuntime(ctx)

	// Instantiate the module with WASI support (stdout/stderr for MoonBit runtime).
	config := wazero.NewModuleConfig().WithStdout(nil).WithStderr(nil)
	mod, err := rt.InstantiateWithConfig(ctx, wasmBytes, config)
	if err != nil {
		rt.Close(ctx)
		return nil, newPrismError("instantiate WASM: " + err.Error())
	}

	return &Runtime{
		ctx:    ctx,
		rt:     rt,
		mod:    mod,
		loaded: true,
	}, nil
}

// Close releases the WASM runtime resources.
func (r *Runtime) Close() error {
	r.mu.Lock()
	defer r.mu.Unlock()
	if r.loaded {
		r.mod.Close(r.ctx)
		r.rt.Close(r.ctx)
		r.loaded = false
	}
	return nil
}

// Call invokes a WASM export function by Go-friendly name.
func (r *Runtime) Call(funcName string, args ...string) (string, error) {
	wasmName, ok := wasmExportMap[funcName]
	if !ok {
		return "", newPrismError("unknown function: " + funcName)
	}
	return r.callWasm(wasmName, args...)
}

func (r *Runtime) callWasm(name string, args ...string) (string, error) {
	r.mu.Lock()
	defer r.mu.Unlock()

	if !r.loaded {
		return "", ErrWASMNotLoaded
	}

	// Look up the exported function by name.
	// Note: MoonBit's current WASM target does not export pub fn as WASM exports.
	// This code is a scaffold for when MoonBit adds WASM export support.
	// See: docs/plans/wasm-wrappers-implementation.md §9
	exp := r.mod.ExportedFunction(name)
	if exp == nil {
		return "", newPrismError("WASM export not found: " + name + " (mapped from)")
	}

	// Convert string args to uint64 for wasm call.
	// In a full implementation, strings need to be written to WASM memory
	// and passed as pointers. Currently MoonBit's calling convention for
	// string parameters across the WASM boundary is pending.
	callArgs := make([]uint64, len(args))
	for i, s := range args {
		// Simple encoding: use first byte for now.
		// Proper string marshalling requires allocating in WASM linear memory.
		if len(s) > 0 {
			callArgs[i] = uint64(s[0])
		}
	}

	results, err := exp.Call(r.ctx, callArgs...)
	if err != nil {
		return "", newPrismError("WASM call failed: " + err.Error())
	}

	result := ""
	if len(results) > 0 {
		result = formatResult(results[0])
	}

	// Check for error response
	if len(result) > 0 && result[0] == '{' {
		var errResp struct {
			Error string `json:"error"`
		}
		if json.Unmarshal([]byte(result), &errResp) == nil && errResp.Error != "" {
			return "", newPrismError(errResp.Error)
		}
	}

	return result, nil
}

func formatResult(v uint64) string {
	return string(rune(v))
}

// ParseEvents decodes a JSON array of events from a WASM result.
func ParseEvents(jsonStr string) ([]Event, error) {
	var events []Event
	if err := json.Unmarshal([]byte(jsonStr), &events); err != nil {
		return nil, newPrismError("parse events: " + err.Error())
	}
	return events, nil
}
