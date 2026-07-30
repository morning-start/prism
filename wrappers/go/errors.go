package prism

import "errors"

var (
	// ErrWASMNotLoaded is returned when calling functions before loading WASM.
	ErrWASMNotLoaded = errors.New("WASM not loaded")

	// ErrExportNotFound is returned when a WASM export function is not found.
	ErrExportNotFound = errors.New("WASM export not found")

	// ErrInvalidProvider is returned for unknown provider names.
	ErrInvalidProvider = errors.New("unknown provider")
)

// PrismError wraps an error from the Prism WASM layer.
type PrismError struct {
	Message string
}

func (e *PrismError) Error() string {
	return "prism: " + e.Message
}

func newPrismError(msg string) *PrismError {
	return &PrismError{Message: msg}
}
