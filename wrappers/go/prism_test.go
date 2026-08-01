package prism

import (
	"os"
	"strings"
	"testing"
)

func loadWasm(t *testing.T) []byte {
	t.Helper()
	data, err := os.ReadFile("prism.wasm")
	if err != nil {
		t.Skip("prism.wasm not found, skipping WASM tests")
	}
	return data
}

func TestNew(t *testing.T) {
	data := loadWasm(t)
	client, err := New(data)
	if err != nil {
		t.Fatal(err)
	}
	defer client.Close()
}

func TestListProviders(t *testing.T) {
	data := loadWasm(t)
	client, err := New(data)
	if err != nil {
		t.Fatal(err)
	}
	defer client.Close()

	providers := client.ListProviders()
	if len(providers) == 0 {
		t.Fatal("expected at least one provider")
	}
	found := false
	for _, p := range providers {
		if p == "openai" {
			found = true
			break
		}
	}
	if !found {
		t.Errorf("expected 'openai' in providers, got %v", providers)
	}
}

func TestPing(t *testing.T) {
	data := loadWasm(t)
	client, err := New(data)
	if err != nil {
		t.Fatal(err)
	}
	defer client.Close()

	if got := client.Ping(); got != "pong" {
		t.Errorf("expected pong, got %s", got)
	}
}

func TestParseEvents(t *testing.T) {
	json := `[{"type":"text_delta","text":"你好"},{"type":"finish","reason":"stop"}]`
	events, err := ParseEvents(json)
	if err != nil {
		t.Fatal(err)
	}
	if len(events) != 2 {
		t.Fatalf("expected 2 events, got %d", len(events))
	}
	if events[0].Type != "text_delta" || events[0].Text != "你好" {
		t.Errorf("unexpected first event: %+v", events[0])
	}
	if events[1].Type != "finish" || events[1].Reason != FinishReasonStop {
		t.Errorf("unexpected second event: %+v", events[1])
	}
}

func TestParseEvents_Empty(t *testing.T) {
	events, err := ParseEvents(`[]`)
	if err != nil {
		t.Fatal(err)
	}
	if len(events) != 0 {
		t.Errorf("expected 0 events, got %d", len(events))
	}
}

func TestParseEvents_InvalidJSON(t *testing.T) {
	_, err := ParseEvents(`not json`)
	if err == nil {
		t.Fatal("expected error for invalid JSON")
	}
}

// TestABIIntegration exercises the Prism string ABI end-to-end against a
// fresh classic-wasm build:
//   moon build --target wasm
// The export shim (cmd/main) emits the 11 wasm_* exports directly.
func TestABIIntegration(t *testing.T) {
	wasmPath := "../../_build/wasm/debug/build/cmd/main/main.wasm"
	data, err := os.ReadFile(wasmPath)
	if err != nil {
		t.Skipf("classic wasm build not found (%v), run: moon build --target wasm", err)
	}
	client, err := New(data)
	if err != nil {
		t.Fatal(err)
	}
	defer client.Close()

	// 1. Capability returns the full declaration.
	cap, err := client.Capability("openai")
	if err != nil {
		t.Fatal(err)
	}
	if cap["provider"] != "openai" {
		t.Errorf("expected provider openai, got %v", cap["provider"])
	}
	if _, ok := cap["model_pattern"]; !ok {
		t.Error("expected model_pattern in capability")
	}
	if _, ok := cap["capabilities"]; !ok {
		t.Error("expected capabilities in capability")
	}

	// 2. Request encoding produces OpenAI Responses JSON.
	reqJSON, err := client.EncodeRequest("openai", "Hello", nil)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(reqJSON, `"text":"Hello"`) {
		t.Errorf("expected Hello in encoded request, got %s", reqJSON)
	}

	// 3. Response decoding extracts text.
	respJSON := `{"id":"1","object":"chat.completion","model":"gpt-4o","choices":[{"index":0,"message":{"role":"assistant","content":"Hi"},"finish_reason":"stop"}]}`
	text, err := client.DecodeResponse("openai-chat", respJSON)
	if err != nil {
		t.Fatal(err)
	}
	if text != "Hi" {
		t.Errorf("expected Hi, got %s", text)
	}

	// 4. Unicode and quotes survive UTF-16 marshalling.
	uniJSON, err := client.EncodeRequest("openai", "你好\"引号", nil)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(uniJSON, `你好\"引号`) {
		t.Errorf("expected unicode round-trip, got %s", uniJSON)
	}

	// 5. Unknown provider surfaces as an error.
	if _, err := client.Capability("no-such-provider"); err == nil {
		t.Error("expected error for unknown provider")
	}
}
