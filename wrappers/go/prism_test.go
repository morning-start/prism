package prism

import (
	"os"
	"strings"
	"testing"
)

func loadWasm(t *testing.T) []byte {
	t.Helper()
	// Prefer the fresh classic-wasm build; fall back to the bundled prism.wasm.
	data, err := os.ReadFile("../../_build/wasm/debug/build/cmd/main/main.wasm")
	if err == nil {
		return data
	}
	data, err = os.ReadFile("prism.wasm")
	if err != nil {
		t.Skipf("prism.wasm not found, skipping WASM tests")
	}
	return data
}

func loadClient(t *testing.T) *Client {
	t.Helper()
	data := loadWasm(t)
	client, err := New(data)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = client.Close() })
	return client
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
	client := loadClient(t)
	providers, err := client.ListProviders()
	if err != nil {
		t.Fatal(err)
	}
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

	// 4. Unicode, quotes and astral-plane characters (emoji) survive
	// UTF-16 marshalling.
	uniJSON, err := client.EncodeRequest("openai", "你好\"引号😀🚀", nil)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(uniJSON, `你好\"引号😀🚀`) {
		t.Errorf("expected unicode round-trip, got %s", uniJSON)
	}

	// 5. Unknown provider surfaces as an error.
	if _, err := client.Capability("no-such-provider"); err == nil {
		t.Error("expected error for unknown provider")
	}
}

// buildLuxRequestWithStore 由 IR 构造器经真实解码路径产出含 options.store 的
// LucentRequest JSON（不手写 JSON，from_json 对字段严格）。
func buildLuxRequestWithStore(t *testing.T, c *Client) string {
	t.Helper()
	// openai-chat 解码带 store:true 的协议 JSON → IR（chat.mbt parse_options 读 store）。
	env, err := c.ToLuxRequest("openai-chat",
		`{"model":"gpt-4o","messages":[{"role":"user","content":"Hi"}],"store":true}`)
	if err != nil {
		t.Fatal(err)
	}
	// IR 方向：value 是 LucentRequest 对象（非 JSON 字符串），直接取原始 JSON。
	ir := string(env.Value)
	if !strings.Contains(ir, `"store"`) {
		t.Fatalf("expected store in produced IR, got %s", ir)
	}
	return ir
}

// Convert 必须单次 WASM 调用，且返回可直接发给厂商的 JSON（非信封）
func TestConvertRequestSingleCall(t *testing.T) {
	c := loadClient(t)
	payload := `{"model":"gpt-4o","input":[{"type":"message","role":"user",` +
		`"content":[{"type":"input_text","text":"Hi"}]}]}`
	env, err := c.Convert("openai", "anthropic", "request", payload)
	if err != nil {
		t.Fatal(err)
	}
	out, err := env.ValueString()
	if err != nil || !strings.Contains(out, `"messages"`) {
		t.Errorf("expected anthropic request, got %q (%v)", out, err)
	}
	if strings.Contains(out, `"diagnostics"`) {
		t.Error("value must not be an envelope — envelope was double-wrapped")
	}
}

// 诊断必须透出到 Go 侧（Phase 1 契约不得止步于 WASM 边界）
func TestDiagnosticsSurfaced(t *testing.T) {
	c := loadClient(t)
	luxReq := buildLuxRequestWithStore(t, c)
	env, err := c.LuxRequestToProvider("anthropic", luxReq)
	if err != nil {
		t.Fatal(err)
	}
	if len(env.Diagnostics) == 0 {
		t.Fatal("expected unsupported diagnostic for options.store")
	}
	if env.Diagnostics[0].Status != "unsupported" {
		t.Errorf("status = %q, want unsupported", env.Diagnostics[0].Status)
	}
	if env.Diagnostics[0].Field != "options.store" {
		t.Errorf("field = %q, want options.store", env.Diagnostics[0].Field)
	}
}

// 注册表真值，而非硬编码
func TestListProvidersFromRegistry(t *testing.T) {
	c := loadClient(t)
	got, err := c.ListProviders()
	if err != nil {
		t.Fatal(err)
	}
	if len(got) < 7 {
		t.Errorf("got %d providers, want >= 7 from registry", len(got))
	}
}
