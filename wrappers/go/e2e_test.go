package prism

import (
	"strings"
	"testing"
)

// TestGoWASME2E 验证 WASM 包装的 Go API 端到端可用性：
// wazero 加载 wasm → ListProviders / Convert / ConvertStream 真实调用。
// 样本用纯文本（无 reasoning 帧）——wasm 产物中 ConvertStream 对含
// delta.reasoning 的帧存在已知丢帧问题（见 daemon e2e 记录，与产物陈旧有关）。
func TestGoWASME2E(t *testing.T) {
	c := loadClient(t)

	// 1. 注册表来自 wasm，非硬编码
	providers, err := c.ListProviders()
	if err != nil {
		t.Fatal(err)
	}
	want := map[string]bool{"openai": false, "openai-chat": false, "anthropic": false}
	for _, p := range providers {
		if _, ok := want[p]; ok {
			want[p] = true
		}
	}
	for name, found := range want {
		if !found {
			t.Errorf("expected provider %q in registry, got %v", name, providers)
		}
	}

	// 2. Convert：openai-chat → anthropic（request 方向，单次 WASM 调用）
	chatReq := `{"model":"gpt-4o","messages":[{"role":"user","content":"Hi"}]}`
	reqEnv, err := c.Convert("openai-chat", "anthropic", "request", chatReq)
	if err != nil {
		t.Fatal(err)
	}
	reqOut, err := reqEnv.ValueString()
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(reqOut, `"messages"`) || strings.Contains(reqOut, `"diagnostics"`) {
		t.Errorf("expected anthropic request JSON, got %q", reqOut)
	}

	// 3. Convert：openai-chat → anthropic（response 方向）
	chatResp := `{"id":"1","object":"chat.completion","model":"gpt-4o","choices":[{"index":0,"message":{"role":"assistant","content":"Hi back"},"finish_reason":"stop"}]}`
	respEnv, err := c.Convert("openai-chat", "anthropic", "response", chatResp)
	if err != nil {
		t.Fatal(err)
	}
	respOut, err := respEnv.ValueString()
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(respOut, `"text"`) {
		t.Errorf("expected anthropic response with text content, got %q", respOut)
	}

	// 4. ConvertStream：openai-chat → anthropic（纯文本流）
	sse := "data: {\"choices\":[{\"delta\":{\"role\":\"assistant\"},\"finish_reason\":null,\"index\":0}]}\n\ndata: {\"choices\":[{\"delta\":{\"content\":\"Hello\"},\"finish_reason\":null,\"index\":0}]}\n\ndata: {\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\",\"index\":0}]}\n\ndata: [DONE]\n\n"
	streamEnv, err := c.ConvertStream("openai-chat", "anthropic", sse)
	if err != nil {
		t.Fatal(err)
	}
	streamOut, err := streamEnv.ValueString()
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(streamOut, "text_delta") || !strings.Contains(streamOut, "Hello") {
		t.Errorf("expected anthropic SSE with text_delta, got %q", streamOut)
	}

	// 5. 未知 provider 报错（错误路径）
	if _, err := c.Convert("no-such", "anthropic", "request", chatReq); err == nil {
		t.Error("expected error for unknown source provider")
	}
}
