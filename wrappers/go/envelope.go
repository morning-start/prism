package prism

import "encoding/json"

// Diagnostic corresponds to lux.ConversionDiagnostic:
//   {"field":"options.store","status":"unsupported","detail":"..."}
// status ∈ exact | degraded | unsupported | invalid (lux/conversion_json.mbt).
type Diagnostic struct {
	Field  string `json:"field"`
	Status string `json:"status"`
	Detail string `json:"detail,omitempty"`
}

// Envelope corresponds to lux.ConversionResult::envelope_json
// (lux/conversion_json.mbt): {"value":…,"diagnostics":[…]}.
// Value is a json.RawMessage: an object in the IR direction, a JSON
// string (quoted) in the provider direction.
type Envelope struct {
	Value       json.RawMessage `json:"value"`
	Diagnostics []Diagnostic    `json:"diagnostics"`
}

// parseEnvelope decodes a WASM result into an Envelope.
func parseEnvelope(raw string) (*Envelope, error) {
	var env Envelope
	if err := json.Unmarshal([]byte(raw), &env); err != nil {
		return nil, newPrismError("parse envelope: " + err.Error())
	}
	return &env, nil
}

// ValueString unwraps Value when it is a JSON string (provider direction).
func (e *Envelope) ValueString() (string, error) {
	if len(e.Value) == 0 {
		return "", newPrismError("envelope has no value")
	}
	var s string
	if err := json.Unmarshal(e.Value, &s); err != nil {
		return "", newPrismError("envelope value is not a JSON string: " + err.Error())
	}
	return s, nil
}
