# 真实场景验证方案：reasoning 跨协议转换正确性

> 日期：2026-08-07
> 背景：单元测试（743/743）证明格式转换正确，但需真实场景验证证明
> 「链路真的通、reasoning 内容真的不丢」。本方案设计三条真实数据路径。

## 0. 验证目标

| # | 验证点 | 断言 |
|---|--------|------|
| V1 | vLLM/DeepSeek 入站捕获 | `message.reasoning` / `reasoning_content` 非空且内容正确进入 IR |
| V2 | 跨协议出站发射 | IR reasoning → Anthropic thinking block / Gemini thought part / Responses reasoning item |
| V3 | 流式 reasoning 不丢 | `delta.reasoning` 全程转换后目标协议仍含推理内容 |
| V4 | 保真度诊断 | 签名丢失等边界产生 `Degraded`（而非静默）|
| V5 | 请求侧配置回传 | `reasoning_effort` / `enable_thinking` 被目标请求携带 |

## 1. 前置：起 daemon

```bash
# 构建 wasm 并启动（HTTP 默认 127.0.0.1:8765）
moon build --target wasm
go build -o prism-daemon ./transport/daemon/cmd/prism-daemon
./prism-daemon --wasm _build/wasm/debug/build/cmd/main/main.wasm --listen 127.0.0.1:8765

# 健康检查
curl http://127.0.0.1:8765/v1/ping
```

## 2. 三条真实数据路径

### 路径 A：本地 vLLM 部署（最真实，需 GPU）

```bash
# 1. 起 vLLM（Qwen3 / DeepSeek-R1 系推理模型，带 reasoning）
vllm serve Qwen/Qwen3-8B --enable-reasoning --reasoning-parser qwen3

# 2. 真实请求（返回 message.reasoning + content）
curl http://localhost:8000/v1/chat/completions -d '{
  "model": "Qwen/Qwen3-8B", "stream": false,
  "messages": [{"role": "user", "content": "9.11 和 9.8 哪个大？"}]
}'
# → 抓取响应存为 vllm_resp.json（含 reasoning 字段）

# 3. 流式真实请求（返回 delta.reasoning）
curl ... -d '{"stream": true, ...}' > vllm_sse.txt

# 4. 经 prism 转换
curl http://127.0.0.1:8765/v1 -d '{
  "jsonrpc": "2.0", "id": 1,
  "method": "convert",
  "params": {"from_provider": "openai-vllm", "to_provider": "anthropic",
             "direction": "response", "payload": "<vllm_resp.json 内容>"}
}'
```

### 路径 B：云端 OpenAI 兼容端点（无需 GPU，需 API key）

候选（都返回 reasoning_content / reasoning）：
- **DeepSeek 官方**：`https://api.deepseek.com`（`deepseek-v4-pro` + `thinking.type=enabled` → `reasoning_content`）
- **OpenRouter**：`https://openrouter.ai/api/v1`（DeepSeek-R1 系 → `reasoning`）
- **Qwen/DashScope**：兼容 OpenAI 接口（`enable_thinking`）

```bash
# 真实请求 → 抓响应（含 reasoning_content）
curl https://api.deepseek.com/chat/completions -H "Authorization: Bearer $DEEPSEEK_KEY" -d '{
  "model": "deepseek-v4-pro", "stream": false,
  "thinking": {"type": "enabled"}, "reasoning_effort": "high",
  "messages": [{"role": "user", "content": "证明 1+1=2"}]
}'
# → 存 deepseek_resp.json，送入 prism convert（from: openai-vllm, to: anthropic）
```

### 路径 C：官方协议 API 直接对拍（验证出站与原生一致性）

用**官方 Anthropic/Gemini/OpenAI key** 直接调目标协议，与 prism 转换结果**对拍**：

```bash
# 官方 Anthropic（含 thinking block）
curl https://api.anthropic.com/v1/messages -H "x-api-key: $ANTHROPIC_KEY" \
  -H "anthropic-version: 2023-06-01" -d '{
    "model": "claude-sonnet-4-6", "max_tokens": 8000,
    "thinking": {"type": "enabled", "budget_tokens": 4000},
    "messages": [{"role": "user", "content": "..."}]
  }' > anthropic_native.json

# 对比：prism convert 出的 anthropic 结构 vs 原生 anthropic 结构
# 断言：thinking block 结构一致（type/thinking/signature 字段齐全）
```

## 3. 断言脚本（scripts/e2e_verify.sh 建议新增）

```bash
# 每路径的核心断言（reasoning 不丢）
python3 scripts/verify_reasoning.py \
  --from-json vllm_resp.json      # 源响应
  --to-json converted.json         # prism convert 输出
  --from-field reasoning           # 源 reasoning 字段
  --to-field thinking              # 目标 thinking 字段（anthropic）
# 断言：两者非空且文本等价（长度差 < 阈值，因转义/截断）
```

关键断言逻辑：
1. **入站捕获**：`vllm_resp.json` 含 `reasoning` 字段 → prism `decode_response` 结果 Envelope 中 `message.reasoning` 非空
2. **出站发射**：convert 到 anthropic 的输出含 `"type":"thinking"` 且 `thinking` 文本 == 源 reasoning 文本
3. **流式**：`vllm_sse.txt` → `convert_stream` → anthropic SSE 含 `thinking_delta` 事件
4. **配置**：请求方向 convert（anthropic → openai-vllm）输出含 `reasoning_effort` / `enable_thinking`

## 4. 验收标准

| 路径 | 通过条件 |
|------|---------|
| A（本地 vLLM） | V1-V5 全过：reasoning 文本往返一致（非空且内容等价）|
| B（云端端点） | V1-V3 过：reasoning_content 捕获 + anthropic thinking 发射 + 流式不丢 |
| C（官方对拍） | 结构对拍一致：thinking block 字段齐全，签名保留 |

## 5. 数据样例（离线可先用）

仓库内 `docs/analysis/thinking-inconsistency-2026-08-04.md` 已有各厂商格式样例，
可先构造离线 fixture 验证链路，再上真实数据。离线 fixture 必须由
IR 构造器 `to_json().stringify()` 产生（项目约定），不手写 JSON。

---

## 6. 模拟验证路径（无需 GPU / API key，推荐首选）

项目已实现 **mock-vllm**：`transport/daemon/cmd/mock-vllm/main.go`，
模拟 OpenAI 兼容端点（vLLM 形态），确定性返回 reasoning 内容：

- 非流式 `/v1/chat/completions` → `message.reasoning` + `message.content`
- 流式 `/v1/chat/completions?stream=true` → `delta.reasoning` + `delta.content` SSE
- `/v1/responses` → `reasoning` item + `message` item
- `usage` 回显请求侧 `reasoning_effort` / `enable_thinking`（供 V5 断言）

### 步骤 1：起 mock server + prism daemon

```bash
# 起 mock vLLM（模拟推理端点）
go build -o mock-vllm ./transport/daemon/cmd/mock-vllm
./mock-vllm --listen 127.0.0.1:8000
curl http://127.0.0.1:8000/healthz   # → {"ok":true}

# 起 prism daemon（转换核心）
moon build --target wasm
go build -o prism-daemon ./transport/daemon/cmd/prism-daemon
./prism-daemon --wasm _build/wasm/debug/build/cmd/main/main.wasm --listen 127.0.0.1:8765
curl http://127.0.0.1:8765/v1/ping   # → pong
```

### 步骤 2：V1 入站捕获（非流式 reasoning）

```bash
# 1. 从 mock 抓真实形态的响应（含 message.reasoning）
curl -s http://127.0.0.1:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen3","stream":false}' > /tmp/mock_resp.json

# 2. 经 prism decode_response（openai-vllm 子协议捕获 reasoning）
curl -s http://127.0.0.1:8765/v1 -d "{
  \"jsonrpc\":\"2.0\",\"id\":1,
  \"method\":\"decode_response\",
  \"params\":{\"provider\":\"openai-vllm\",\"json\":$(cat /tmp/mock_resp.json | jq -Rs .)}
}"
```

**断言**：`value.choices[0].message.reasoning` 与 mock 的 `sampleReasoning` 一致。

### 步骤 3：V2 跨协议出站（→ Anthropic thinking block）

```bash
curl -s http://127.0.0.1:8765/v1 -d "{
  \"jsonrpc\":\"2.0\",\"id\":2,
  \"method\":\"convert\",
  \"params\":{\"from_provider\":\"openai-vllm\",\"to_provider\":\"anthropic\",
             \"direction\":\"response\",\"payload\":$(cat /tmp/mock_resp.json | jq -Rs .)}
}"
```

**断言**：输出含 `{"type":"thinking","thinking":"<reasoning 文本>"}`。

### 步骤 4：V3 流式不丢（delta.reasoning）

```bash
# 1. 从 mock 抓流式 SSE（delta.reasoning 增量）
curl -s -N http://127.0.0.1:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen3","stream":true}' > /tmp/mock_sse.txt

# 2. 经 prism convert_stream → anthropic SSE
curl -s http://127.0.0.1:8765/v1 -d "{
  \"jsonrpc\":\"2.0\",\"id\":3,
  \"method\":\"convert_stream\",
  \"params\":{\"from_provider\":\"openai-vllm\",\"to_provider\":\"anthropic\",
             \"sse\":$(cat /tmp/mock_sse.txt | jq -Rs .)}
}"
```

**断言**：输出含 `thinking_delta` 事件，且拼接文本 == sampleReasoning。

### 步骤 5：V5 请求侧配置（reasoning_effort / enable_thinking）

```bash
curl -s http://127.0.0.1:8000/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen3","stream":false,
       "reasoning_effort":"high",
       "extra_body":{"chat_template_kwargs":{"enable_thinking":true}}}'
```

**断言**：`usage.reasoning_effort_echo == "high"`、`usage.enable_thinking_echo == true`
（mock 回显，证明请求侧配置穿透链路）。

### 步骤 6：V4 保真度诊断（可选）

用带 signature 的 Anthropic thinking block 经 IR 转 openai-vllm：
**断言**：diagnostics 含 `reasoning.signature` + `Degraded`。

### mock server 扩展点

- 改 `sampleReasoning` / `sampleContent` 常量可生成任意长度的确定性推理文本
- 加 `reasoning_content` 字段可模拟 DeepSeek 形态（改 handleChat 的 message 字段名）
- 加 `thought:true` part 可模拟 Gemini 形态
