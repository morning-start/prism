# Prism Transport Architecture

> 多语言传输层设计文档。
> 定义 Prism 协议转换引擎如何通过通用 IPC 协议服务 Go、Python、Node.js、Rust、Java 等所有语言。
> 版本：v1 (draft)
> **实现状态：部分实现。** `transport/daemon/` 已落地 HTTP binding（POST /v1 JSON-RPC + GET /health + SSE 流式响应），方法：encode_request / decode_response / decode_sse（同步 + 流式）/ encode_stream（同步）/ convert / convert_stream（同步 + 流式）/ list_providers / capability / ping，后端为 wazero WASM。UDS / WebSocket binding 与 `decode_sse_stream` 会话式逐块解码仍为规划项（phase3b）。

---

## 1. Design Goals

1. **多语言原生体验** — Go、Python、Node.js、Rust、Java、C# 每种语言都有开箱即用的客户端 SDK，接口签名保持一致
2. **传输可插拔** — 同一套业务 API 可绑定到 HTTP、UDS、WebSocket、gRPC 等传输，客户端 SDK 切换传输只需一行配置
3. **客户端极致轻薄** — 所有协议转换逻辑驻留在 Daemon 端，客户端 SDK 只做序列化 + 网络 IO（~100 行有效代码）
4. **流式透明** — 流式 SSE 解码和编码通过网络传输时，保持事件流语义不被破坏
5. **跨平台** — Linux (UDS+HTTP)、macOS (UDS+HTTP)、Windows (Named Pipe+HTTP) 全支持
6. **向前兼容** — 新增传输绑定或客户端语言时，不修改已有代码；新增 RPC 方法不破坏旧客户端

## 2. Non-Goals

- 不做服务发现 / 注册中心（Daemon 是本地进程，127.0.0.1 直连）
- 不做身份认证 / 授权（API key 管理是 Daemon 配置层的职责，不进入传输协议）
- 不做请求路由 / 负载均衡（每个 Daemon 实例独立，多实例由上层编排）
- 不替代 Host 发 HTTP 请求到 LLM 厂商（这是可选的增值能力，不是传输层职责）
- 不定义 WASM ABI 之上的「Prism IR 序列化格式」（那是 `lux/` 包的职责）

## 3. System Architecture

### 3.1 层叠架构

```
 ┌──────────────────────────────────────────────────────────────────────┐
 │                        Language Clients                              │
 │  ┌────────┐ ┌──────────┐ ┌────────┐ ┌────────┐ ┌────────┐         │
 │  │   Go   │ │  Python  │ │  Node  │ │  Rust  │ │  Java  │   ...   │
 │  │  SDK   │ │   SDK    │ │  SDK   │ │  SDK   │ │  SDK   │         │
 │  └───┬────┘ └─────┬────┘ └───┬────┘ └───┬────┘ └───┬────┘         │
 │      │            │          │          │          │              │
 │      └────────────┼──────────┼──────────┼──────────┘              │
 │                   │  同一接口契约，传输可插拔                        │
 │    ┌──────────────┴──────────┴──────────┴──────────────────┐      │
 │    │              Transport Binding Layer                   │      │
 │    │    HTTP Client  │  UDS Client  │  WS Client            │      │
 │    └────────────────────────┬──────────────────────────────┘      │
 └─────────────────────────────┼────────────────────────────────────────┘
                               │  JSON-RPC 2.0 over TCP/UDS/TLS
 ┌─────────────────────────────┼────────────────────────────────────────┐
 │  ┌──────────────────────────┴──────────────────────────────┐        │
 │  │             Prism Gateway Daemon                        │  L1   │
 │  │                                                         │        │
 │  │  ┌──────────────────────────────────────────────────┐  │        │
 │  │  │         Transport Router (JSON-RPC 2.0)          │  │        │
 │  │  │  HTTP Handler │ UDS Handler │ WS Handler          │  │        │
 │  │  └──────────────────────┬───────────────────────────┘  │        │
 │  │  ┌──────────────────────┴───────────────────────────┐  │        │
 │  │  │         Method Dispatcher                         │  │        │
 │  │  │  encode_request │ decode_response │ decode_sse    │  │        │
 │  │  │  encode_stream  │ convert         │ capability    │  │        │
 │  │  │  list_providers                                  │  │        │
 │  │  └──────────────────────┬───────────────────────────┘  │        │
 │  │  ┌──────────────────────┴───────────────────────────┐  │        │
 │  │  │         Runtime Backend (pluggable)               │  │        │
 │  │  │  ┌──────────────────┐  ┌──────────────────┐      │  │        │
 │  │  │  │  WASM Runtime    │  │  MoonBit Native   │      │  │        │
 │  │  │  │  (wazero)        │  │  (future)         │      │  │        │
 │  │  │  └──────────────────┘  └──────────────────┘      │  │        │
 │  │  └───────────────────────────────────────────────────┘  │        │
 │  └──────────────────────────────────────────────────────────┘        │
 │                                                                      │
 │  ┌──────────────────────────────────────────────────────────┐       │
 │  │         Config Layer                                       │  L0  │
 │  │  API Keys │ Endpoints │ Provider Routing │ Logging        │       │
 │  └──────────────────────────────────────────────────────────┘       │
 └──────────────────────────────────────────────────────────────────────┘
                                                                        ▲
 ┌──────────────────────────────────────────────────────────────────────┘
 │                         Prism WASM (moon build)
 │  ┌────────────────────────────────────────────────────────────────┐
 │  │  lux/  │  provider/*/  │  sdk/  │  wasm/                       │
 │  │  34+ Lucent IR types  │  7 provider adapters  │  11 exports    │
 │  └────────────────────────────────────────────────────────────────┘
 └──────────────────────────────────────────────────────────────────────
```

### 3.2 组件职责

| 层级 | 组件 | 职责 | 实现语言 |
|------|------|------|----------|
| **L0 Core** | Prism WASM | Lucent IR 协议转换核心（纯函数） | MoonBit → wasm-gc |
| **L1 Daemon** | Runtime Backend | 加载并调用 Prism WASM | Go (wazero) |
| | Method Dispatcher | JSON-RPC method 名 → 后端函数调用 | Go |
| | Transport Router | 多传输前端共享同一分发逻辑 | Go |
| **L2 Transport** | HTTP Binding | POST JSON-RPC + SSE 流式 | HTTP/1.1 |
| | UDS Binding | JSON lines over Unix Domain Socket | Unix Socket |
| | WebSocket Binding | JSON-RPC over WebSocket | WebSocket |
| | gRPC Binding（未来） | Protobuf + 双向流 | HTTP/2 |
| **L3 Client** | Go SDK | Go 原生接口，传输可插拔 | Go |
| | Python SDK | Python 原生接口，传输可插拔 | Python |
| | Node SDK（未来） | TypeScript 类型 + npm 包 | TypeScript |
| | Rust SDK（未来） | Cargo crate + 异步支持 | Rust |
| | Java SDK（未来） | Maven 包 | Java/Kotlin |

### 3.3 核心数据流

```
┌──────┐          ┌──────────┐         ┌──────────┐         ┌──────┐
│Client│          │ Daemon   │         │  Prism   │         │ Host │
│ SDK  │          │ Router   │         │  WASM    │         │(user)│
└──┬───┘          └────┬─────┘         └────┬─────┘         └──┬───┘
   │                   │                    │                  │
   │  Encode Request   │                    │                  │
   │──────────────────►│                    │                  │
   │  {provider,text}  │  call wasm export  │                  │
   │                   │───────────────────►│                  │
   │                   │  provider JSON     │                  │
   │                   │◄───────────────────│                  │
   │  {result:json}    │                    │                  │
   │◄──────────────────│                    │                  │
   │                   │                    │                  │
   │      客户端拿到 provider JSON，自己发 HTTP 到 LLM 厂商      │
   │═══════════════════│════════════════════│═══════ HTTP ═════►│
   │                   │                    │                  │
   │  Decode Response  │                    │                  │
   │──────────────────►│                    │                  │
   │  {provider,json}  │  call wasm export  │                  │
   │                   │───────────────────►│                  │
   │                   │  text / events     │                  │
   │                   │◄───────────────────│                  │
   │  {result:text}    │                    │                  │
   │◄──────────────────│                    │                  │
   │                   │                    │                  │
```

### 3.4 流式数据流

```
┌──────┐          ┌──────────┐         ┌──────────┐         ┌──────┐
│Client│          │ Daemon   │         │  Prism   │         │ Host │
│ SDK  │          │ Router   │         │  WASM    │         │(user)│
└──┬───┘          └────┬─────┘         └────┬─────┘         └──┬───┘
   │                   │                    │                  │
   │  Encode Stream    │                    │                  │
   │──────────────────►│                    │                  │
   │  {provider,text}  │  call wasm export  │                  │
   │                   │───────────────────►│                  │
   │                   │  stream request    │                  │
   │                   │  JSON (带 stream:true)               │
   │                   │◄───────────────────│                  │
   │  {stream:true,    │                    │                  │
   │   request:sse_str}│                    │                  │
   │◄──────────────────│                    │                  │
   │                   │                    │                  │
   │     Host 用 sse_str 发流式 HTTP 请求到 LLM 厂商            │
   │═══════════════════│════════════════════│══════ HTTP SSE ► │
   │                   │                    │                  │
   │  收到 SSE 块后：   │                    │                  │
   │  Decode SSE chunk │                    │                  │
   │──────────────────►│                    │                  │
   │  {provider,sse}   │  call wasm export  │                  │
   │                   │───────────────────►│                  │
   │                   │  PrismEvent[]      │                  │
   │                   │◄───────────────────│                  │
   │  SSE stream:      │                    │                  │
   │  event:data       │                    │                  │
   │  data:{text:...}  │                    │                  │
   │◄──────────────────│                    │                  │
   │  event:finish     │                    │                  │
   │◄──────────────────│                    │                  │
```

---

## 4. Wire Protocol: JSON-RPC 2.0

### 4.1 为什么选 JSON-RPC 2.0

| 考量 | JSON-RPC 2.0 | REST | gRPC | 自定义二进制 |
|------|-------------|------|------|------------|
| 语言支持度 | ★★★★★ 每种语言都有库 | ★★★★★ | ★★★★ | ★ |
| 流式支持 | 可叠加 | SSE 附加 | 原生 | 需自研 |
| 传输无关性 | 天然（HTTP/UDS/WS 通吃） | 绑定 HTTP | 绑定 HTTP/2 | 绑定传输 |
| 实现复杂度 | 极低（1 个 JSON 结构） | 中（路由设计） | 高（代码生成） | 极高 |
| 调试友好度 | ★★★★★（纯文本） | ★★★★★ | ★★★ | ★ |
| 方法增删影响 | 零（无 schema 约束） | 零 | 需重生成 pb | 需改解析 |

**结论**：JSON-RPC 2.0 是当前最轻量、最普适的选择，未来可以加 gRPC 绑定为强类型场景补充，但不取代 JSON-RPC。

### 4.2 方法目录

所有方法名使用 `snake_case`，参数名使用 `snake_case`，与 Prism MoonBit SDK 保持一致。

#### 4.2.1 同步方法

```
┌────────────────────┬────────────────────────────────────────────────────┐
│ method             │ 功能                                                │
├────────────────────┼────────────────────────────────────────────────────┤
│ encode_request     │ 文本 → 厂商请求 JSON                                 │
│ decode_response    │ 厂商响应 JSON → 文本                                 │
│ decode_sse         │ 厂商 SSE 文本 → PrismEvent[]                        │
│ convert            │ 跨厂商协议转换（Transit Middleware 核心）              │
│ list_providers     │ 列出所有已注册 provider 名称                         │
│ capability         │ 查询指定 provider 的能力声明                          │
│ ping               │ 健康检查                                            │
└────────────────────┴────────────────────────────────────────────────────┘
```

#### 4.2.2 流式方法

```
┌────────────────────┬────────────────────────────────────────────────────┐
│ method             │ 功能                                                │
├────────────────────┼────────────────────────────────────────────────────┤
│ encode_stream      │ 文本 → 流式厂商请求 JSON（带 stream:true，非事件流）   │
│ decode_sse_stream  │ 逐块传入 SSE → 逐块返回 PrismEvent（UDS/WS 阶段交付） │
└────────────────────┴────────────────────────────────────────────────────┘
```

> **语义澄清（缺口 H 修正）：** `encode_stream` 是**同步**方法——文本进，流式请求 JSON（`stream:true`）出，本身不产生事件流。真正的流式通路在**解码方向**：`decode_sse` / `convert_stream` 在 `Accept: text/event-stream` 下按 SSE 帧逐帧写出（见 §4.5）。

流式方法在 HTTP 绑定中使用 **SSE (text/event-stream)** 传输，在 UDS/WS 绑定中使用消息序列传输。

### 4.3 请求 / 响应格式

#### encode_request

```json
// ── Request ──
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "encode_request",
  "params": {
    "provider": "openai",
    "text": "你好，今天天气怎么样？",
    "opts": {
      "model": "gpt-4o",
      "temperature": 0.7,
      "max_tokens": 1024
    }
  }
}

// ── Success Response ──
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "value": "{\"model\":\"gpt-4o\",\"messages\":[{\"role\":\"user\",\"content\":\"你好，今天天气怎么样？\"}]}",
    "diagnostics": []
  }
}

// ── Error Response ──
{
  "jsonrpc": "2.0",
  "id": 1,
  "error": {
    "code": -32000,
    "message": "unknown provider: foo",
    "data": null
  }
}
```

#### decode_response

```json
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "decode_response",
  "params": {
    "provider": "openai",
    "json": "{\"choices\":[{\"message\":{\"content\":\"你好！有什么可以帮你的？\"},\"finish_reason\":\"stop\"}]}"
  }
}
→ {"jsonrpc":"2.0","id":2,"result":{"value":"你好！有什么可以帮你的？","diagnostics":[]}}
```

#### decode_sse

```json
{
  "jsonrpc": "2.0",
  "id": 3,
  "method": "decode_sse",
  "params": {
    "provider": "anthropic",
    "sse": "data: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"你好\"}}\n\ndata: {\"type\":\"message_delta\",\"usage\":{\"input_tokens\":10,\"output_tokens\":2}}\n\ndata: [DONE]"
  }
}
→ {
  "jsonrpc": "2.0",
  "id": 3,
  "result": {
    "value": [
      {"type":"text_delta","text":"你好","index":0},
      {"type":"finish","reason":"stop"}
    ],
    "diagnostics": []
  }
}
```

#### convert（跨协议转换）

这是 Transit Middleware 场景的核心方法，将一个厂商的 JSON 转换为另一个厂商的 JSON。

```json
{
  "jsonrpc": "2.0",
  "id": 4,
  "method": "convert",
  "params": {
    "from_provider": "openai",
    "to_provider": "anthropic",
    "direction": "request",
    "payload": "{\"model\":\"gpt-4o\",\"messages\":[{\"role\":\"user\",\"content\":\"你好\"}]}"
  }
}
→ {
  "jsonrpc": "2.0",
  "id": 4,
  "result": {
    "value": "{\"model\":\"claude-sonnet-4-20250514\",\"messages\":[{\"role\":\"user\",\"content\":\"你好\"}]}",
    "diagnostics": []
  }
}
```

转换流程（在 Daemon 内部）：

```
OpenAI JSON  ──[ext_to_lux_request]──►  LucentRequest  ──[lux_request_to_ext]──►  Anthropic JSON
(from_provider)                           (中立 IR)                               (to_provider)
```

#### list_providers

```json
{
  "jsonrpc": "2.0",
  "id": 5,
  "method": "list_providers",
  "params": {}
}
→ {
  "jsonrpc": "2.0",
  "id": 5,
  "result": {
    "value": ["openai", "openai-chat", "anthropic", "gemini", "google-vertex", "azure-openai", "openai-codex"],
    "diagnostics": []
  }
}
```

#### capability

```json
{
  "jsonrpc": "2.0",
  "id": 6,
  "method": "capability",
  "params": {"provider": "openai"}
}
→ {
  "jsonrpc": "2.0",
  "id": 6,
  "result": {
    "value": {
      "provider": "openai",
      "model_pattern": "o*|gpt-*",
      "supports_streaming": true,
      "supports_tools": true,
      "supports_vision": true
    },
    "diagnostics": []
  }
}
```

#### ping

```json
{
  "jsonrpc": "2.0",
  "id": 7,
  "method": "ping",
  "params": {}
}
→ {"jsonrpc":"2.0","id":7,"result":{"value":"pong","diagnostics":[]}}
```

### 4.4 错误码约定

| 范围 | 含义 | 示例 |
|------|------|------|
| -32700 | 解析错误 | JSON 格式错误 |
| -32600 | 请求无效 | 缺少 `method` 字段 |
| -32601 | 方法不存在 | `method: "foo"` |
| -32602 | 参数无效 | `provider` 为 null |
| -32603 | 内部错误 | WASM 调用异常 |
| -32000 ~ -32099 | Prism 领域错误 | provider 不存在、转换失败、JSON 解析错误 |

### 4.5 流式绑定（Streaming）

**HTTP 单请求单响应（本轮实现，D7）：** HTTP 下不做 session。客户端一次 POST 携带完整 SSE 文本，`Accept: text/event-stream` 时 daemon 解码整段后逐事件/逐帧写出，边解边发。适用方法：`decode_sse`、`convert_stream`。

> **跨帧状态说明：** 逐帧独立解码会打断跨帧状态（块索引、工具参数增量拼接），因此 daemon 一律**整段解码后流式写出**（正确性优先于首字节延迟）。逐帧解码与全量解码的等价性由测试 `TestFrameByFrameEqualsWholeText` 钉死。

#### HTTP 绑定下的流式（SSE）

```
Request:
POST /v1 HTTP/1.1
Content-Type: application/json
Accept: text/event-stream

{"jsonrpc":"2.0","id":1,"method":"decode_sse","params":{"provider":"anthropic","sse":"..."}}

Response:
HTTP/1.1 200 OK
Content-Type: text/event-stream

event: data
data: {"jsonrpc":"2.0","id":1,"result":{"value":{"type":"text_delta","text":"你"},"diagnostics":[]}}

event: data
data: {"jsonrpc":"2.0","id":1,"result":{"value":{"type":"text_delta","text":"好"},"diagnostics":[]}}

event: done
data: {"jsonrpc":"2.0","id":1,"result":{"value":{"type":"done"},"diagnostics":[]}}
```

流中途出错：HTTP 头已发出无法再改状态码，写 `event: error` 帧后收尾。

#### UDS/WS 绑定下的流式（消息序列，未来阶段交付）

```
→ {"jsonrpc":"2.0","id":1,"method":"decode_sse","params":{...}}
← {"jsonrpc":"2.0","id":1,"result":{"value":{"type":"text_delta","text":"你"},"diagnostics":[]}}
← {"jsonrpc":"2.0","id":1,"result":{"value":{"type":"text_delta","text":"好"},"diagnostics":[]}}
← {"jsonrpc":"2.0","id":1,"result":{"value":{"type":"finish","reason":"stop"},"diagnostics":[]}}
← {"jsonrpc":"2.0","id":1,"result":{"value":{"type":"done"},"diagnostics":[]}}   ← 流结束标记
```

流结束标记 `{"type":"done"}` 让客户端明确知道流已完成，不需要依赖超时判断。

#### decode_sse_stream（逐块解码，UDS/WS 阶段交付，本轮不实现）

> D7：`decode_sse_stream` 的 session + notification 模型依赖全双工，属 UDS/WS 形态；HTTP 单请求单响应下用「一次 POST + SSE 响应」表达流式即可。此方法留待 phase3b 交付。

```json
// 请求：开始一个 SSE 解码会话
{"jsonrpc":"2.0","id":1,"method":"decode_sse_stream","params":{"provider":"anthropic"}}
// 响应：session id
{"jsonrpc":"2.0","id":1,"result":{"value":{"session":"sse-001"},"diagnostics":[]}}

// 客户端逐块发送 SSE 数据（notification，无 id）
{"jsonrpc":"2.0","method":"sse_chunk","params":{"session":"sse-001","data":"data: {\"type\":\"content_block_delta\",...}\n\n"}}
// 服务端逐块返回 PrismEvent
{"jsonrpc":"2.0","id":1,"result":{"value":{"type":"text_delta","text":"你"},"diagnostics":[]}}

{"jsonrpc":"2.0","method":"sse_chunk","params":{"session":"sse-001","data":"data: {\"type\":\"content_block_delta\",...}\n\n"}}
{"jsonrpc":"2.0","id":1,"result":{"value":{"type":"text_delta","text":"好"},"diagnostics":[]}}

// 结束
{"jsonrpc":"2.0","method":"sse_chunk","params":{"session":"sse-001","data":"data: [DONE]"}}
{"jsonrpc":"2.0","id":1,"result":{"value":{"type":"finish","reason":"stop"},"diagnostics":[]}}
{"jsonrpc":"2.0","id":1,"result":{"value":{"type":"done"},"diagnostics":[]}}
```

---

## 5. Transport Bindings

### 5.1 HTTP（主要传输）

| 属性 | 值 |
|------|-----|
| 路径 | `POST /v1` |
| 请求 Content-Type | `application/json` |
| 响应 Content-Type | `application/json`（同步）或 `text/event-stream`（流式） |
| 认证 | 不在传输层处理（Daemon 配置层管理） |
| 默认端口 | `8765` |
| 跨域 | `Access-Control-Allow-Origin: *`（便于本地开发） |

**请求路由策略**：所有请求 POST 到同一端点 `/v1`，通过 `method` 字段分发。
（而非 REST 风格的 `/v1/encode_request`。原因：JSON-RPC 的 method 本已是路由标识，URL 路径应保持稳定。）

```go
// HTTP Transport — handler 示例签名
func (h *HTTPHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
    // 1. 解析 JSON-RPC 请求体
    // 2. 识别 method
    // 3. 若客户端 Accept: text/event-stream → 切换到 SSE 模式
    // 4. 分发到 MethodDispatcher
    // 5. 写回响应
}
```

**健康检查**：

```
GET /health → 200 OK {"status":"ok","version":"0.1.0","providers":7}
```

### 5.2 Unix Domain Socket / Windows Named Pipe

| 属性 | UDS | Named Pipe |
|------|-----|------------|
| 地址 | `/tmp/prism.sock` 或 `$XDG_RUNTIME_DIR/prism.sock` | `\\.\pipe\prism` |
| 协议 | JSON lines（`\n` 分隔） | JSON lines（`\n` 分隔） |
| 流式 | 全双工消息序列 | 全双工消息序列 |
| 权限 | `umask 077`（仅本用户） | 默认仅本用户 |

**JSON lines 协议**：

UDS/Named Pipe 不使用 HTTP 框架，而是直接在 socket 上读写以 `\n` 结尾的 JSON 行：

```
客户端发送:
{"jsonrpc":"2.0","id":1,"method":"encode_request","params":{...}}\n

服务端响应（sync）:
{"jsonrpc":"2.0","id":1,"result":"..."}\n

服务端响应（streaming，每行一条消息）:
{"jsonrpc":"2.0","id":1,"result":{"type":"text_delta","text":"你"}}\n
{"jsonrpc":"2.0","id":1,"result":{"type":"text_delta","text":"好"}}\n
{"jsonrpc":"2.0","id":1,"result":{"type":"done"}}\n
```

**连接管理**：
- 每个连接独立处理，不跨连接共享状态（Prism 本身无状态）
- 服务端处理完请求即写回，不 Hold 连接
- 流式请求按住连接直到流结束

### 5.3 WebSocket

| 属性 | 值 |
|------|-----|
| 路径 | `ws://127.0.0.1:8765/ws` |
| 帧格式 | 每帧一个完整 JSON 消息（Text 帧） |
| 流式 | 原生支持（多条消息在同一 WS 连接上发送） |
| 适用场景 | 浏览器、长连接密集场景 |

**握手**：标准 HTTP Upgrade，无自定义 header。

**消息格式**：与 JSON-RPC 2.0 保持一致，每帧一个完整的 JSON-RPC 消息。

```
Client → Server: {"jsonrpc":"2.0","id":1,"method":"encode_request","params":{...}}
Server → Client: {"jsonrpc":"2.0","id":1,"result":"..."}

// 流式：帧序列
Client → Server: {"jsonrpc":"2.0","id":2,"method":"encode_stream","params":{...}}
Server → Client: {"jsonrpc":"2.0","id":2,"result":{"type":"text_delta","text":"你"}}
Server → Client: {"jsonrpc":"2.0","id":2,"result":{"type":"text_delta","text":"好"}}
Server → Client: {"jsonrpc":"2.0","id":2,"result":{"type":"done"}}
```

### 5.4 gRPC（未来）

gRPC 是未来可选绑定，用于强类型场景（如微服务架构）。

```protobuf
syntax = "proto3";

package prism.transport.v1;

service Prism {
  rpc EncodeRequest(EncodeRequestReq) returns (EncodeRequestResp);
  rpc DecodeResponse(DecodeResponseReq) returns (DecodeResponseResp);
  rpc DecodeSSE(DecodeSSEReq) returns (DecodeSSEResp);
  rpc EncodeStream(EncodeStreamReq) returns (stream StreamEvent);
  rpc Convert(ConvertReq) returns (ConvertResp);
  rpc ListProviders(Empty) returns (ProviderList);
  rpc Capability(CapabilityReq) returns (CapabilityResp);
  rpc Ping(Empty) returns (Pong);
}
```

gRPC 绑定不替代 JSON-RPC，而是作为补充——微服务团队可以用 protobuf 获得类型安全和代码生成，而通用客户端仍走 JSON-RPC。

---

## 6. Client SDK Contract

### 6.1 跨语言公共接口

每种语言的 SDK 必须实现同一组接口，保持签名对齐：

```
encode_request(provider, text, opts?) → Result<Envelope, Error>
decode_response(provider, json) → Result<Envelope, Error>
decode_sse(provider, sse) → Result<Envelope, Error>

encode_stream(provider, text, opts?) → Result<Envelope, Error>  // 同步：流式请求 JSON
decode_sse_stream(provider) → SseSession                        // 逐块流式（UDS/WS 阶段）

convert(from_provider, to_provider, direction, payload) → Result<Envelope, Error>
convert_stream(from_provider, to_provider, sse) → Result<Envelope, Error>

list_providers() → Result<Array<String>, Error>
capability(provider) → Result<Envelope, Error>
ping() → Result<String, Error>
```

> **D5 信封契约：** 所有转换类方法（含 capability）返回 **Envelope** ——
> `{value, diagnostics}`，value 为厂商 JSON 字符串（provider 方向）或 IR 对象
> （IR 方向），diagnostics 为 `Exact/Degraded/Unsupported/Invalid` 结构化诊断。
> 客户端 SDK 统一解析信封：`value_string()` 取 provider 方向裸串，`value`
> 原样透出 IR 方向对象。

**Event 类型**（跨语言共享）：

```
Event =
  | TextDelta { text: String }
  | ToolCall  { id: String, name: String, arguments_json: String }
  | ToolResult { tool_use_id: String, content: String, is_error: Bool }
  | Thinking  { text: String, signature: String?, redacted: Bool }
  | Finish    { reason: FinishReason }
  | Done                                      // 流结束标记（内部用）

FinishReason = "stop" | "length" | "tool_calls" | "content_filter" | "error"
```

SDK 必须提供可插拔的 Transport 接口，让用户在一行代码间切换传输方式：

```
// 伪代码
client = Prism::new()
    .with_transport(HTTPTransport("http://127.0.0.1:8765"))
// 或
client = Prism::new()
    .with_transport(UDSTransport("/tmp/prism.sock"))
```

### 6.2 Go SDK

```go
package prism

// Transport — 可插拔传输接口
type Transport interface {
    Call(ctx context.Context, method string, params any) (json.RawMessage, error)
    CallStream(ctx context.Context, method string, params any) (<-chan json.RawMessage, error)
}

// Client — 主入口
type Client struct {
    transport Transport
}

func New(t Transport) *Client

// 方法签名（全部同步阻塞，流式返回 channel）
func (c *Client) EncodeRequest(ctx, provider, text string, opts *Options) (string, error)
func (c *Client) DecodeResponse(ctx, provider, jsonStr string) (string, error)
func (c *Client) DecodeSSE(ctx, provider, sse string) ([]Event, error)
func (c *Client) EncodeStream(ctx, provider, text string, opts *Options) (<-chan Event, error)
func (c *Client) Convert(ctx, from, to, dir, payload string) (string, error)
func (c *Client) ListProviders(ctx) ([]string, error)
func (c *Client) Capability(ctx, provider string) (*Capability, error)

// 内建传输实现
type HTTPTransport struct { ... }
type UDSTransport struct { ... }

// 事件类型
type Event struct {
    Type EventType
    TextDelta    *string
    ToolCall     *ToolCall
    ToolResult   *ToolResult
    Thinking     *Thinking
    FinishReason *string   // "stop" | "length" | "tool_calls" | "content_filter" | "error"
}

// 使用时只需切换 transport：
// prism.New(prism.HTTPTransport("http://127.0.0.1:8765"))
// prism.New(prism.UDSTransport("/tmp/prism.sock"))
```

### 6.3 Python SDK

```python
import httpx
from dataclasses import dataclass
from typing import AsyncIterator, Optional

class PrismClient:
    def __init__(self, transport: Transport):
        self._transport = transport
    
    def encode_request(self, provider: str, text: str, opts: Optional[Options] = None) -> str
    def decode_response(self, provider: str, json_str: str) -> str
    def decode_sse(self, provider: str, sse: str) -> list[Event]
    async def encode_stream(self, provider: str, text: str, opts: Optional[Options] = None) -> AsyncIterator[Event]
    def convert(self, from_provider: str, to_provider: str, direction: str, payload: str) -> str
    def list_providers(self) -> list[str]
    def capability(self, provider: str) -> Capability

# 内建传输
class HTTPTransport(Transport): ...
class UDSTransport(Transport): ...

# 同步 / 异步双模式
class AsyncPrismClient:
    async def encode_request(self, ...) -> str
    async def decode_response(self, ...) -> str
    async def decode_sse(self, ...) -> list[Event]
    async def encode_stream(self, ...) -> AsyncIterator[Event]
```

### 6.4 新增一种客户端语言的步骤

1. 实现 `Transport` 接口（HTTP 客户端即可，通常 ≥95% 场景够用）
2. 实现 `Client` 结构体，每个方法：
   - 构造 JSON-RPC 请求
   - 调用 Transport
   - 解析 JSON-RPC 响应
   - 映射 Event 到原生类型
3. 导出语义化的错误类型
4. 每个方法约 5-10 行代码，总 SDK 约 100-150 行

**不需要**：理解 Lucent IR、Provider 适配器、WASM——全在 Daemon 里。

---

## 7. Gateway Daemon

### 7.1 内部架构

```
┌─────────────────────────────────────────────────────────────────┐
│                     Prism Gateway Daemon                         │
│                                                                  │
│  ┌─────────────┐  ┌──────────────────────────────────────────┐  │
│  │   Config    │  │          Transport Layer                  │  │
│  │   (YAML)    │  │  ┌──────────┐ ┌────────┐ ┌──────────┐   │  │
│  │             │  │  │  HTTP    │ │  UDS   │ │   WS     │   │  │
│  │  API keys   │  │  │  Listener│ │  Listener│ │ Listener │   │  │
│  │  Ports      │  │  └────┬─────┘ └────┬───┘ └─────┬────┘   │  │
│  │  Log level  │  │       │            │            │        │  │
│  └─────────────┘  │       └────────────┼────────────┘        │  │
│                   │               ┌────┴─────┐                │  │
│  ┌─────────────┐  │               │  Router  │                │  │
│  │  Provider   │  │               └────┬─────┘                │  │
│  │  Registry   │  │               ┌────┴─────┐                │  │
│  │  (dynamic)  │  │               │   RPC    │                │  │
│  └─────────────┘  │               │ Dispatcher│               │  │
│                   │               └────┬─────┘                │  │
│  ┌─────────────┐  │               ┌────┴─────┐                │  │
│  │   Logger    │  │               │  Runtime  │               │  │
│  │  (slog)     │  │               │  Backend  │               │  │
│  └─────────────┘  │               └────┬─────┘                │  │
│                   │               ┌────┴─────┐                │  │
│  ┌─────────────┐  │               │  WASM VM │                │  │
│  │  Metrics    │  │               │  (wazero)│                │  │
│  │  (optional) │  │               └──────────┘                │  │
│  └─────────────┘  └──────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### 7.2 Runtime Backend 接口

```go
// RuntimeBackend — 可替换的 Prism 运行时后端
type RuntimeBackend interface {
    // 同步调用：调用 Prism 的纯函数
    ToLuxRequest(ctx, provider, jsonStr string) (string, error)
    LuxRequestToProvider(ctx, provider, luxJson string) (string, error)
    ToLuxResponse(ctx, provider, jsonStr string) (string, error)
    LuxResponseToProvider(ctx, provider, luxJson string) (string, error)
    SSEToEvents(ctx, provider, sseStr string) (string, error)
    EventsToSSE(ctx, provider, eventsJson string) (string, error)
    SDKEncodeRequest(ctx, provider, text string, optsJSON string) (string, error)
    SDKDecodeResponse(ctx, provider, respJson string) (string, error)
    SDKEncodeStream(ctx, provider, text string, optsJSON string) (string, error)
    SDKDecodeSSE(ctx, provider, sseStr string) (string, error)
    ListProviders() ([]string, error)
    Capability(provider string) (string, error)

    // 生命周期
    Init() error
    Close() error
}
```

**第一个实现：WASM Backend（wazero）**

```go
type WASMBackend struct {
    runtime  wazero.Runtime
    module   api.Module
}

func NewWASMBackend(wasmBytes []byte) (*WASMBackend, error) {
    ctx := context.Background()
    r := wazero.NewRuntime(ctx)
    // 导入 WASI 等宿主函数
    mod, err := r.Instantiate(ctx, wasmBytes)
    return &WASMBackend{runtime: r, module: mod}, err
}

func (b *WASMBackend) ToLuxRequest(ctx, provider, jsonStr string) (string, error) {
    // 调用 wasm_to_lux_request(provider, jsonStr)
    result, err := b.module.ExportedFunction("wasm_to_lux_request").Call(ctx,
        encodeString(provider), encodeString(jsonStr),
    )
    return decodeString(result[0]), err
}
```

**未来 Backend 扩展**：
- `MoonBitNativeBackend`：当 MoonBit 支持编译为 C 共享库时，通过 cgo 调用
- `ProcessBackend`：启动独立的 Prism 本地进程，通过 stdin/stdout 通信
- `RemoteBackend`：远程 Prism 实例（HTTP 调用），用于分布式部署

### 7.3 请求分派流程

```
HTTP POST /v1
       │
       ▼
  JSON 解析 ──解析失败──► 返回 JSON-RPC parse error (-32700)
       │
       ▼
  method 识别
       │
       ├── "encode_request"    ──► 构造 opts → 调用 wasm_sdk_encode_request
       ├── "decode_response"   ──► 调用 wasm_sdk_decode_response
       ├── "decode_sse"        ──► 调用 wasm_sdk_decode_sse
       ├── "encode_stream"     ──► 调用 wasm_sdk_encode_stream → 返回 SSE 流
       ├── "convert"           ──► from → lux → to 两步转换
       ├── "list_providers"    ──► 查注册表
       ├── "capability"        ──► 查注册表
       ├── "ping"              ──► 返回 "pong"
       └── 未知 method         ──► 返回 JSON-RPC method not found (-32601)
              │
              ▼
        调用 Runtime Backend
              │
              ├── 成功 → 包装为 JSON-RPC result
              └── 失败 → 包装为 JSON-RPC error
```

### 7.4 配置（YAML）

```yaml
# prism-daemon.yaml
daemon:
  log_level: info

  transports:
    http:
      enabled: true
      listen: "127.0.0.1:8765"
    uds:
      enabled: true
      path: "/tmp/prism.sock"
      permission: "0700"
    websocket:
      enabled: false
      listen: "127.0.0.1:8766"

  runtime:
    backend: "wasm"            # wasm | native(未来)
    wasm_path: "./prism.wasm"  # WASM 二进制路径
```

---

## 8. Repository Layout

```
prism/
  ├── transport/                  ← 新增：传输层
  │   ├── ARCHITECTURE.md         ← 本文件（真理来源）
  │   ├── SPEC.md                 ← JSON-RPC 2.0 协议规范（从本文件提取）
  │   ├── api.json                ← OpenAPI 3.1 规范（从 SPEC.md 生成）
  │   │
  │   ├── daemon/                 ← Prism Gateway Daemon（Go）
  │   │   ├── go.mod
  │   │   ├── main.go             ← 入口：启动所有 listener
  │   │   ├── config.go           ← YAML 配置加载
  │   │   ├── router.go           ← Transport → RPC dispatcher
  │   │   ├── dispatcher.go       ← Method → backend 分发
  │   │   ├── types.go            ← JSON-RPC 消息类型
  │   │   ├── errors.go           ← 错误码定义
  │   │   ├── runtime.go          ← RuntimeBackend 接口
  │   │   ├── wasm_backend.go     ← WASM runtime 实现（wazero）
  │   │   ├── transports/
  │   │   │   ├── http.go         ← HTTP binding
  │   │   │   ├── uds.go          ← UDS binding
  │   │   │   └── websocket.go    ← WebSocket binding
  │   │   └── config.example.yaml ← 配置示例
  │   │
  │   └── clients/                ← 各语言客户端 SDK
  │       ├── go/                 ← prism-client-go（Go SDK）
  │       │   ├── client.go       ← PrismClient 主类型
  │       │   ├── transport.go    ← Transport 接口 + HTTP/UDS 实现
  │       │   ├── types.go        ← Event / Options / Capability
  │       │   ├── errors.go       ← 错误类型
  │       │   ├── go.mod
  │       │   └── example_test.go
  │       │
  │       ├── python/             ← prism-client-python（Python SDK）
  │       │   ├── src/prism/
  │       │   │   ├── __init__.py
  │       │   │   ├── client.py
  │       │   │   ├── types.py
  │       │   │   ├── transport.py
  │       │   │   └── errors.py
  │       │   ├── pyproject.toml
  │       │   └── tests/
  │       │
  │       └── node/               ← prism-client-node（未来）
  │           └── ...
  │
  ├── lux/                        ← （已有，不变）
  ├── provider/                   ← （已有，不变）
  ├── sdk/                        ← （已有，不变）
  ├── wasm/                       ← （已有，不变）
  └── docs/
      └── transport-architecture.md ← 指向 transport/ARCHITECTURE.md
```

---

## 9. Evolution Path

```
Phase 0 (PRD) ─── 本文档定稿，团队评审
    │
Phase 1 (MVP) ─── Go Daemon + HTTP binding + Go SDK
    │              deliverable: daemon 启动，curl 可调用
    │              Go client: prism.New(HTTPTransport)
    │
Phase 2 ────────── UDS binding + Python SDK
    │              deliverable: UDS 比 HTTP 快 3x
    │              Python client: PrismClient(HTTPTransport)
    │
Phase 3 ────────── WebSocket binding + 流式完善
    │              deliverable: 浏览器可用 WS 直连
    │              decode_sse_stream 逐块解码
    │
Phase 4 ────────── gRPC binding（可选）
    │              deliverable: protobuf 强类型客户端
    │              适合微服务架构团队
    │
Phase 5 ────────── 客户端 SDK 生成 pipeline
    │              deliverable: 从 api.json 半自动生成新语言 SDK
    │              Node.js / Rust / Java SDK 同期输出
    │
Phase 6 ────────── Daemon 重写为 MoonBit 原生（当 MoonBit 网络栈成熟时）
    │              deliverable: 移除 WASM 间接层，零开销
```

**各阶段依赖关系**：
- Phase 1 不依赖 Phase 2-6，可独立发布
- Phase 3 依赖 Phase 1 的 HTTP 路由框架
- Phase 4 与 Phase 2/3 正交，可并行
- Phase 6 是纯优化，不改变 API 契约

---

## 10. Appendix: Example Sessions

### 10.1 Go SDK 使用示例

```go
package main

import (
    "context"
    "fmt"
    "log"

    "github.com/morning-start/prism/transport/clients/go/prism"
)

func main() {
    ctx := context.Background()

    // 连接到本地 Daemon（HTTP）
    client := prism.New(prism.HTTPTransport("http://127.0.0.1:8765"))

    // 列出所有可用 provider
    providers, _ := client.ListProviders(ctx)
    fmt.Println("Providers:", providers)

    // 编码请求：文本 → Anthropic JSON
    reqJSON, err := client.EncodeRequest(ctx, "anthropic", "写一首诗",
        &prism.Options{Model: "claude-sonnet-4-20250514"},
    )
    if err != nil {
        log.Fatal(err)
    }
    fmt.Println("Request JSON:", reqJSON)

    // 解码响应：Anthropic JSON → 文本
    respText, err := client.DecodeResponse(ctx, "anthropic", respJSON)
    if err != nil {
        log.Fatal(err)
    }
    fmt.Println("Response:", respText)

    // 跨协议转换：OpenAI JSON → Anthropic JSON
    anthropicJSON, err := client.Convert(ctx, "openai", "anthropic", "request", openaiReqJSON)
    if err != nil {
        log.Fatal(err)
    }
    fmt.Println("Converted:", anthropicJSON)
}
```

### 10.2 Python SDK 使用示例

```python
import asyncio
from prism import PrismClient, HTTPTransport

async def main():
    client = PrismClient(HTTPTransport("http://127.0.0.1:8765"))

    providers = await client.list_providers()
    print(f"Providers: {providers}")

    # 流式解码 SSE
    async for event in client.decode_sse_stream("openai", sse_text):
        if event.type == "text_delta":
            print(event.text, end="")
        elif event.type == "finish":
            print(f"\n[Finished: {event.finish_reason}]")

asyncio.run(main())
```

### 10.3 UDS 直接测试（无需 SDK）

```bash
# 用一个 nc 命令就能测试 UDS IPC
echo '{"jsonrpc":"2.0","id":1,"method":"list_providers","params":{}}' \
  | nc -U /tmp/prism.sock

# 结果：
# {"jsonrpc":"2.0","id":1,"result":["openai","openai-chat","anthropic","gemini","azure-openai","openai-codex"]}
```

---

> **本架构文档是 Prism Transport Layer 的真理来源（Source of Truth）。**
> 协议规范（SPEC.md）、OpenAPI 规范（api.json）以及各语言 SDK 实现均以此文档为准。
> 任何修改必须同步更新所有衍生文件。
