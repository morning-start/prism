package prism

// FinishReason is why the LLM finished generating.
type FinishReason string

const (
	FinishReasonStop         FinishReason = "stop"
	FinishReasonLength       FinishReason = "length"
	FinishReasonToolCalls    FinishReason = "tool_calls"
	FinishReasonContentFilter FinishReason = "content_filter"
	FinishReasonError        FinishReason = "error"
)

// Options for encoding a request.
type Options struct {
	Model       string   `json:"model,omitempty"`
	Temperature *float64 `json:"temperature,omitempty"`
	MaxTokens   *int     `json:"max_tokens,omitempty"`
}

// Event represents a Prism stream event.
type Event struct {
	Type string `json:"type"`

	// TextDelta
	Text string `json:"text,omitempty"`

	// ToolCall
	ID             string `json:"id,omitempty"`
	Name           string `json:"name,omitempty"`
	ArgumentsJSON  string `json:"arguments,omitempty"`

	// ToolResult
	ToolUseID string `json:"tool_use_id,omitempty"`
	Content   string `json:"content,omitempty"`
	IsError   bool   `json:"is_error,omitempty"`

	// Finish
	Reason FinishReason `json:"reason,omitempty"`
}
