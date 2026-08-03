package prism

import (
	"encoding/json"
	"fmt"
)

// Diagnostic corresponds to lux.ConversionDiagnostic:
//
//	{"field":"options.store","status":"unsupported","detail":"..."}
//
// status ∈ exact | degraded | unsupported | invalid.
type Diagnostic struct {
	Field  string `json:"field"`
	Status string `json:"status"`
	Detail string `json:"detail,omitempty"`
}

// Envelope is the D5 result shape shared by every RPC method:
// {"value":…,"diagnostics":[…]}. Value is a JSON value: an object in the IR
// direction, a JSON string (quoted) in the provider direction.
type Envelope struct {
	Value       json.RawMessage `json:"value"`
	Diagnostics []Diagnostic    `json:"diagnostics"`
}

// ValueString unwraps Value when it is a JSON string (provider direction).
func (e *Envelope) ValueString() (string, error) {
	if len(e.Value) == 0 {
		return "", fmt.Errorf("envelope has no value")
	}
	var s string
	if err := json.Unmarshal(e.Value, &s); err != nil {
		return "", fmt.Errorf("envelope value is not a JSON string: %w", err)
	}
	return s, nil
}

// Event is a Prism stream event (ARCHITECTURE.md §6.1).
type Event struct {
	Type string `json:"type"`

	// TextDelta
	Text string `json:"text,omitempty"`

	// ToolCall
	ID            string `json:"id,omitempty"`
	Name          string `json:"name,omitempty"`
	ArgumentsJSON string `json:"arguments,omitempty"`

	// ToolResult
	ToolUseID string `json:"tool_use_id,omitempty"`
	Content   string `json:"content,omitempty"`
	IsError   bool   `json:"is_error,omitempty"`

	// Finish
	Reason string `json:"reason,omitempty"`
}
