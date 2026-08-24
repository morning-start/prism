# Prism 使用指南

> 从不同角度、不同场景出发，教会你如何上手使用 Prism。

---

## 目录

1. [快速概览](#1-快速概览)
2. [MoonBit 原生使用](#2-moonbit-原生使用)
3. [Go wrapper 使用](#3-go-wrapper-使用)
4. [TypeScript wrapper 使用](#4-typescript-wrapper-使用)
5. [场景一：嵌入 SDK —— 应用内协议转换](#5-场景一嵌入-sdk--应用内协议转换)
6. [场景二：跨协议中间件 —— 网关模式](#6-场景二跨协议中间件--网关模式)
7. [场景三：流式转码 —— SSE 处理](#7-场景三流式转码--sse-处理)
8. [场景四：企业审计网关 —— 全量日志](#8-场景四企业审计网关--全量日志)
9. [完整 API 参考](#9-完整-api-参考)

---

## 1. 快速概览

Prism 是一个 **LLM 协议转换引擎**，核心能力是：**在任意两个 LLM 厂商协议格式之间自由转换**。

```
OpenAI JSON  ──[decode]──►  Lucent IR  ──[encode]──►  Anthropic JSON
Gemini JSON  ◄──[encode]──  Lucent IR  ◄──[decode]──  OpenAI JSON
                                │
                    代码可以在这里插一手
                    （审计、改写、路由、过滤）
```

Prism 提供 **三种使用形态**：

| 形态 | 适合谁 | 一句话 |
|------|--------|--------|
| MoonBit SDK | MoonBit 用户 | `Prism::new().with_provider("openai")` |
| Go wrapper | Go 服务端开发者 | `prism.New(wasmBytes)` |
| TypeScript wrapper | Node/Bun 全栈开发者 | `new PrismClient(wasmBytes)` |

---

## 2. MoonBit 原生使用

### 2.1 安装

```bash
moon add morning-start/prism
```

### 2.2 快速开始 —— 应用开发者视角（L1）

```moonbit
fn main {
  // 一行创建，指定厂商
  let prism = Prism::new().with_provider("openai")

  // 编码请求：文本 → OpenAI JSON
  let req_json = prism.encode_request("你好", PrismOptions::default())
  // → {"model":"gpt-4o","messages":[{"role":"user","content":"你好"}]}

  // 解码响应：OpenAI JSON → 文本
  let text = prism.decode_response(resp_json)
  // → "你好！有什么可以帮你的？"
}
```

切换厂商只需改 provider 名：

```moonbit
let prism = Prism::new().with_provider("anthropic")  // 自动适配 Claude 格式
let req = prism.encode_request("你好", PrismOptions::default())
// → {"model":"claude-sonnet-4","messages":[{"role":"user","content":"你好"}]}
```

### 2.3 事件循环 —— 框架作者视角（L2）

```moonbit
let ctx = Context::new()
  .add_system("你是一个有用的助手")
  .add_user("帮我查北京的天气")
  .add_tools([SdkTool { name: "get_weather", description: "查询天气", ... }])

match prism.decode_sse(sse_text) {
  Ok(events) => {
    for event in events {
      match event {
        TextDelta(s) => ui.append(s)        // 流式文本
        ToolCall(tc) => execute_tool(tc)    // 工具调用
        Thinking(t) => ui.show_thinking(t)  // 推理过程
        Finish(r) => break                  // 结束
      }
    }
  }
}
```

### 2.4 低层 IR 转换 —— 协议开发者视角（L0）

```moonbit
// 厂商 JSON → Lucent IR（解码）
let lux_req = wasm_to_lux_req("openai", openai_json)
let lux_resp = wasm_to_lux_resp("openai", openai_json)

// Lucent IR → 厂商 JSON（编码）
let anthropic_json = wasm_lux_req_to_provider("anthropic", lux_req_json)
```

---

## 3. Go wrapper 使用

### 3.1 安装

```bash
go get github.com/morning-start/prism/wrappers/go
```

### 3.2 快速开始

```go
package main

import (
    "fmt"
    "log"
    "os"
    prism "github.com/morning-start/prism/wrappers/go"
)

func main() {
    wasmBytes, _ := os.ReadFile("prism.wasm")
    client, err := prism.New(wasmBytes)
    if err != nil {
        log.Fatal(err)
    }
    defer client.Close()

    // 编码请求
    req, _ := client.EncodeRequest("openai", "你好", nil)
    fmt.Println("Request:", req)

    // 解码响应
    text, _ := client.DecodeResponse("openai", respJSON)
    fmt.Println("Response:", text)

    // 跨协议转换
    anthropicJSON, _ := client.Convert("openai", "anthropic", "request", openaiReq)
    fmt.Println("Anthropic:", anthropicJSON)
}
```

---

## 4. TypeScript wrapper 使用

### 4.1 安装

```bash
bun add @morning-start/prism-wasm
```

### 4.2 快速开始

```typescript
import { PrismClient } from "@morning-start/prism-wasm";
import { readFileSync } from "fs";

const client = new PrismClient(readFileSync("prism.wasm"));

// 编码请求
const req = client.encodeRequest("openai", "你好");
console.log(req);

// 解码 SSE
const events = client.decodeSSE("anthropic", sseText);
for (const event of events) {
  if (event.type === "text_delta") {
    process.stdout.write(event.text);
  }
}

// 查询能力
const cap = client.capability("openai");
console.log(cap);  // → { provider: "openai" }
```

---

## 5. 场景一：嵌入 SDK —— 应用内协议转换

**你只需要在代码里集成一个 LLM 协议，但想让用户自由切换厂商。**

### 工作流

```
你的应用
  │
  ├── 用户选 "OpenAI"  →  Prism 编解码 OpenAI JSON  →  发 HTTP
  ├── 用户选 "Claude"  →  Prism 编解码 Anthropic JSON  →  发 HTTP
  └── 用户选 "Gemini"  →  Prism 编解码 Gemini JSON  →  发 HTTP
```

### 代码

```python
class LLMApp:
    def __init__(self, provider: str, api_key: str):
        self.client = PrismClient("prism.wasm")
        self.provider = provider
        self.api_key = api_key

    def chat(self, text: str) -> str:
        # Step 1: Prism 编码文本 → provider JSON
        req_json = self.client.encode_request(self.provider, text)

        # Step 2: 发 HTTP 到 LLM 厂商
        resp = requests.post(
            self._endpoint(),
            headers={"Authorization": f"Bearer {self.api_key}"},
            json=json.loads(req_json),
        )

        # Step 3: Prism 解码响应 → 文本
        return self.client.decode_response(self.provider, resp.text)

app = LLMApp("anthropic", "sk-ant-xxx")
print(app.chat("写一首诗"))
# 切换厂商只需改 provider 名：
app2 = LLMApp("gemini", "AIza-xxx")
```

---

## 6. 场景二：跨协议中间件 —— 网关模式

**你的客户端只支持 OpenAI 格式，但你想用 Anthropic 的 Claude 模型。**

### 工作流

```
客户端 (OpenAI 格式)
    │
    ▼
[Prism 网关] ── 1. to_lux_req ──► Lucent IR
                 2. 代码处理（可选）
                 3. lux_to_provider ──► Anthropic JSON
    │
    ▼
Anthropic API (Claude)
    │
    ▼
[Prism 网关] ◄── 4. to_lux_resp ◄── Lucent IR
                 5. 代码处理（可选）
                 6. lux_to_provider ◄── OpenAI JSON
    │
    ▼
客户端 (OpenAI 格式)
```

### 代码（Python 版）

```python
from flask import Flask, request, jsonify
import requests

app = Flask(__name__)
prism = PrismClient("prism.wasm")

# 后端映射：客户端指定 target 即可切换
BACKENDS = {
    "claude":   {"provider": "anthropic", "url": "https://api.anthropic.com/v1/messages"},
    "gemini":   {"provider": "gemini",    "url": "https://generativelanguage.googleapis.com/v1/..."},
    "deepseek": {"provider": "openai",    "url": "https://api.deepseek.com/chat/completions"},
}

@app.route("/v1/chat/completions", methods=["POST"])
def proxy():
    data = request.json
    target = data.pop("target", "default")

    backend = BACKENDS.get(target, BACKENDS["default"])
    
    # 转换请求格式
    lux_req = prism.to_lux_request("openai", json.dumps(data))
    target_req = prism.lux_request_to_provider(backend["provider"], lux_req)

    # 发送到目标 LLM
    resp = requests.post(
        backend["url"],
        headers={"Authorization": f"Bearer {get_api_key(target)}"},
        json=json.loads(target_req),
    )

    # 转换响应格式回 OpenAI
    lux_resp = prism.to_lux_response(backend["provider"], resp.text)
    return jsonify(json.loads(
        prism.lux_response_to_provider("openai", lux_resp)
    ))
```

客户端只需一行切换后端：

```python
# 客户端代码 - 同样是 OpenAI 格式，但实际走的是 Claude
requests.post("http://localhost:5000/v1/chat/completions", json={
    "model": "gpt-4o",        # 客户端随便填
    "target": "claude",       # Prism 网关理解这个字段
    "messages": [{"role": "user", "content": "你好"}],
})
```

---

## 7. 场景三：流式转码 —— SSE 处理

**你在客户端收到 Anthropic 的 SSE 流，但你的 UI 只认 OpenAI 的 SSE 格式。**

### 代码

```python
# 收到 Anthropic 的 SSE
anthropic_sse = (
    'data: {"type":"content_block_start","index":0,'
    '"content_block":{"type":"text","text":""}}\n\n'
    'data: {"type":"content_block_delta","index":0,'
    '"delta":{"type":"text_delta","text":"你好"}}\n\n'
    'data: [DONE]'
)

# 转成统一 PrismEvent 列表
events = client.decode_sse("anthropic", anthropic_sse)
for ev in events:
    if ev.type == "text_delta":
        print(ev.text, end="")  # 逐 token 输出

# 也可以转成 OpenAI SSE 格式发回给客户端
openai_sse = client.events_to_sse("openai", json.dumps([
    {"type": "text_delta", "text": "你好"},
    {"type": "finish", "reason": "stop"},
]))
```

### TypeScript 版

```typescript
const events = client.decodeSSE("anthropic", sseText);
for (const event of events) {
  switch (event.type) {
    case "text_delta":
      response.write(event.text);
      break;
    case "tool_call":
      await executeTool(event);
      break;
    case "thinking":
      ui.showThinking(event.text);
      break;
    case "finish":
      response.end();
      break;
  }
}
```

---

## 8. 场景四：企业审计网关 —— 全量日志

**你想在每一条 LLM 请求/响应中间插入审计、脱敏、限流逻辑。**

### 架构

```
客户端 ──► Prism 审计网关 ──► LLM 厂商
                 │
                 ▼
             日志数据库
            （全量记录请求/响应）
```

### 代码

```python
from prism_wasm import PrismClient
import json, time

class AuditGateway:
    def __init__(self):
        self.prism = PrismClient("prism.wasm")
        self.db = AuditDB()

    def process_request(self, provider: str, raw_req: str) -> str:
        # 1. 解码到 Lucent IR（可以理解请求内容）
        lux_req = json.loads(
            self.prism.to_lux_request(provider, raw_req)
        )
        
        # 2. 审计：记录用户输入
        user_text = self._extract_user_text(lux_req)
        self.db.log_request(provider, user_text, time.time())
        
        # 3. 脱敏：替换敏感信息
        lux_req = self._redact_sensitive(lux_req)
        
        # 4. 限流检查
        if not self._rate_limit(provider):
            raise HTTPException(429, "rate limited")
        
        # 5. 编码回 provider 格式，发往 LLM
        return self.prism.lux_request_to_provider(provider, json.dumps(lux_req))

    def process_response(self, provider: str, raw_resp: str) -> str:
        # 同理处理响应
        lux_resp = json.loads(
            self.prism.to_lux_response(provider, raw_resp)
        )
        
        # 审计：记录模型输出
        output = self._extract_output(lux_resp)
        self.db.log_response(provider, output, time.time())
        
        # 安全过滤
        lux_resp = self._filter_harmful(lux_resp)
        
        return self.prism.lux_response_to_provider(provider, json.dumps(lux_resp))
```

---

## 9. 完整 API 参考

### 所有语言的统一 API 签名

| 分类 | 函数 | 输入 | 输出 | 作用 |
|------|------|------|------|------|
| **低层 IR** | `to_lux_req` | provider, json_str | LucentReq JSON | Provider 请求 → 中立 IR |
| | `lux_req_to_provider` | provider, lux_json | Provider JSON | 中立 IR → Provider 请求 |
| | `to_lux_resp` | provider, json_str | LucentResp JSON | Provider 响应 → 中立 IR |
| | `lux_resp_to_provider` | provider, lux_json | Provider JSON | 中立 IR → Provider 响应 |
| | `sse_to_events` | provider, sse_str | StreamEvent JSON | SSE 文本 → 事件数组 |
| | `events_to_sse` | provider, events_json | SSE 文本 | 事件数组 → SSE 文本 |
| **高层 SDK** | `encode_req` | provider, text, opts? | Provider JSON | 文本 → Provider 请求 |
| | `decode_resp` | provider, json_str | 文本 | Provider 响应 → 纯文本 |
| | `encode_stream` | provider, text, opts? | Provider JSON | 文本 → 流式请求 |
| | `decode_sse` | provider, sse_str | PrismEvent[] | SSE 文本 → 事件列表 |
| | `capability` | provider | dict | 查询能力声明 |
| **工具** | `convert` | from, to, dir, payload | Provider JSON | 跨协议转换 |
| | `list_providers` | — | string[] | 列出所有 Provider |
| | `ping` | — | "pong" | 健康检查 |

### 当前支持的 Provider

| provider 名 | 对应厂商 | 协议 |
|-------------|---------|------|
| `openai` 或 `openai-chat` | OpenAI | Chat Completions |
| `anthropic` | Anthropic | Messages API |
| `gemini` | Google | Gemini API |
| `google-vertex` | Google | Vertex AI |
| `azure-openai` | Azure | Azure OpenAI |
| `openai-codex` | OpenAI | Codex |

