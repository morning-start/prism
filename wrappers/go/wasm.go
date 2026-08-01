// Package prism provides a Go WASM wrapper around the Prism LLM protocol converter.
//
// It loads prism.wasm via wazero and exposes the 11 exported functions
// through a clean Go API.
package prism

import (
	"context"
	_ "embed"
	"encoding/json"
	"strings"
	"sync"
	"unicode/utf16"

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

	exp := r.mod.ExportedFunction(name)
	if exp == nil {
		return "", newPrismError("WASM export not found: " + name)
	}

	// Prism string ABI: each String argument is an i32 linear-memory address
	// where `ptr - 4` holds a u32 length (UTF-16 code units) and `ptr` holds
	// the UTF-16LE payload. The i32 result is an address with the same layout.
	// Scratch lives below the MoonBit GC heap (heap starts above ~0x1000).
	const scratchStart = uint32(0x0400)
	const scratchStride = uint32(512)
	mem := r.mod.Memory()
	if mem == nil {
		return "", newPrismError("WASM module has no memory")
	}

	callArgs := make([]uint64, len(args))
	ptr := scratchStart
	for i, s := range args {
		// UTF-16 code units (not UTF-8 bytes).
		units := utf16.Encode([]rune(s))
		// u32 length header at ptr-4
		if !mem.WriteUint32Le(ptr-4, uint32(len(units))) {
			return "", newPrismError("write string header")
		}
		// UTF-16LE payload at ptr
		buf := make([]byte, 2*len(units))
		for j, u := range units {
			buf[2*j] = byte(u)
			buf[2*j+1] = byte(u >> 8)
		}
		if !mem.Write(ptr, buf) {
			return "", newPrismError("write string payload")
		}
		callArgs[i] = uint64(ptr)
		ptr += scratchStride
	}

	results, err := exp.Call(r.ctx, callArgs...)
	if err != nil {
		return "", newPrismError("WASM call failed: " + err.Error())
	}
	if len(results) == 0 {
		return "", newPrismError("WASM call returned no value")
	}
	resultPtr := uint32(results[0])

	// Read u32 length at resultPtr-4, then UTF-16LE payload at resultPtr.
	lenBytes, ok := mem.Read(resultPtr-4, 4)
	if !ok {
		return "", newPrismError("read result length")
	}
	strLen := uint32(lenBytes[0]) | uint32(lenBytes[1])<<8 | uint32(lenBytes[2])<<16 | uint32(lenBytes[3])<<24
	payload, ok := mem.Read(resultPtr, uint32(2*strLen))
	if !ok {
		return "", newPrismError("read result payload")
	}
	units := make([]uint16, strLen)
	for i := uint32(0); i < strLen; i++ {
		units[i] = uint16(payload[2*i]) | uint16(payload[2*i+1])<<8
	}
	result := string(utf16.Decode(units))

	if strings.HasPrefix(result, `{"error":`) {
		var errResp struct {
			Error string `json:"error"`
		}
		if json.Unmarshal([]byte(result), &errResp) == nil && errResp.Error != "" {
			return "", newPrismError(errResp.Error)
		}
	}

	return result, nil
}

// ParseEvents decodes a JSON array of events from a WASM result.
func ParseEvents(jsonStr string) ([]Event, error) {
	var events []Event
	if err := json.Unmarshal([]byte(jsonStr), &events); err != nil {
		return nil, newPrismError("parse events: " + err.Error())
	}
	return events, nil
}
