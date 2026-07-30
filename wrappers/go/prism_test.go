package prism

import (
	"os"
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
