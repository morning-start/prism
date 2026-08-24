# Prism SDK 使用指南

> 本文档演示 Prism SDK 的三种使用层级。
> 底层 IR 和适配器细节对开发者不可见。

---

## 安装

```toml
# moon.pkg
import {
  "morning-start/prism/sdk",
}
```

---

## L1：应用开发者 —— 一行调用

```moonbit
/// === 最简单的对话 ===
let prism = Prism::new().with_provider("openai")

// 1. 编码请求为提供商 JSON
let req_json = prism.encode_request(
  "Hello!",
  PrismOptions::default(),
)

// 2. Host 发送 HTTP 请求（伪代码）
// POST /v1/responses
// Authorization: Bearer sk-xxx
// Body: req_json
// → 得到响应 resp_json

// 3. 解码响应为文本
let reply = prism.decode_response(resp_json)
// Ok("Hi there! How can I help you today?")
```

### 带参数的对话

```moonbit
let opts = PrismOptions::new(
  model: Some("gpt-4o"),
  temperature: Some(0.7),
  max_tokens: Some(4096),
  store: Some(false),
  extras: None,
)

let req_json = prism.encode_request("写一首诗", opts)
```

### 切换 provider

```moonbit
// 改为 Anthropic 只需改一行
let prism = Prism::new().with_provider("anthropic")

let req_json = prism.encode_request("写一首诗", opts)
// req_json 现在是对应 Anthropic 格式的 JSON
```

---

## L2：框架作者 —— 事件循环

```moonbit
/// === 构建上下文 ===
let ctx = Context::new()
  .add_system("你是一个有用的助手")
  .add_user("帮我查北京的天气")
  .add_tools([
    SdkTool {
      name: "get_weather",
      description: "获取城市天气",
      parameters_json: "{\"type\":\"object\",\"properties\":{\"city\":{\"type\":\"string\"}}}",
    },
  ])

/// === 流式请求 ===
let req_json = prism.encode_stream_request("帮我查天气", opts)
// Host 发送 HTTP 请求，收到 SSE 流

// 解码 SSE 为事件
match prism.decode_sse(sse_text) {
  Ok(events) => {
    for event in events {
      match event {
        TextDelta(s) => ui.append(s)                  // 文本输出
        ToolCall(tc) => {                             // 工具调用
          let result = execute_tool(tc.name, tc.arguments_json)
          ctx.add_assistant("工具已执行")
        }
        Thinking(t) => ui.show_thinking(t.text)        // 推理过程
        Finish(r) => {                               // 结束
          print("完成，原因: \{r}")
          break
        }
        _ => ()
      }
    }
  }
  Err(e) => print("错误: \{e}")
}
```

### Agent 循环模式

```moonbit
/// 简化的 Agent 循环伪代码（两层循环：工具执行 → 继续对话）
fn run_agent(text: String, tools: Array[SdkTool]) {
  let prism = Prism::new().with_provider("openai")
  let mut ctx = Context::new()
    .add_system("你是一个助手，可以使用工具完成任务")
    .add_user(text)
    .add_tools(tools)

  loop {
    match prism.decode_sse(prism.encode_stream_request("继续", opts)) {
      Ok(events) => {
        let mut has_tool = false
        for event in events {
          match event {
            ToolCall(tc) => {
              let result = execute_tool(tc)  // 执行工具
              ctx = ctx.add_assistant("工具结果: \{result}")
              has_tool = true
            }
            Finish(_) => if !has_tool { return }  // 没有工具调用则结束
            _ => ()
          }
        }
        if !has_tool { return }
      }
      Err(e) => { print("错误: \{e}"); return }
    }
  }
}
```

---

## L2+：能力查询

```moonbit
/// 在注册工具前确认 provider 支持什么
let caps = prism.capability("anthropic")
match caps {
  Some(c) => {
    if c.capabilities.tool_calling != Absent {
      // 确认支持工具调用
    }
    if c.capabilities.multimodal_input != Absent {
      // 可以传入图片
    }
    if c.capabilities.reasoning != Absent {
      // 可以启用推理
    }
  }
  None => print("provider 不存在")
}
```

---

## L2+：精细参数控制

```moonbit
/// 通过 extras 传入厂商特有参数
let opts = PrismOptions::new(
  model: Some("gpt-4o"),
  temperature: Some(0.7),
  max_tokens: Some(4096),
  store: Some(false),
  extras: Some({
    "logprobs": True,              // OpenAI Chat 特有
    "reasoning_effort": "high",    // 推理力度
  }),
)
```

---

## 完整示例：从编码到解码

```moonbit
/// === L1：完整请求-响应流程 ===
fn complete(prompt: String) {
  let prism = Prism::new().with_provider("openai")

  // 编码请求
  let req = prism.encode_request(prompt, PrismOptions::default())
  match req {
    Ok(json) => {
      // 此时 json 就是 OpenAI 格式的请求体
      // Host 负责发送 HTTP 请求和注入认证信息
      let resp_json = send_http_post(
        "https://api.openai.com/v1/responses",
        "Authorization: Bearer sk-xxx",
        json,
      )
      match prism.decode_response(resp_json) {
        Ok(text) => print(text)
        Err(e) => print("解码失败: \{e}")
      }
    }
    Err(e) => print("编码失败: \{e}")
  }
}
```

---

## 支持的 provider 名

| 传入名 | 实际协议 |
|--------|---------|
| `"openai"` / `"openai-responses"` | OpenAI Responses API |
| `"openai-chat"` | OpenAI Chat Completions |
| `"anthropic"` | Anthropic Messages API |
| `"gemini"` / `"google"` | Google Gemini API |

---

## 来源元信息（ConversionMeta）

多协议混流场景（中转站/多厂商流程）中，多个 provider 的响应都会被解码为
LUX 语义，此时需要区分"这个结果是从哪个协议来的"。SDK 提供
`decode_response_with_meta` / `convert_response_with_meta`，返回
`DecodedResponse` / `ConvertMetaResult`，附带 `meta.source_provider`。

**主路径代码只写一次，特殊协议按来源特判：**

```moonbit
match prism.decode_response_with_meta(resp_json) {
  Ok(decoded) => {
    let answer = decoded.text              // 99% 代码：只用文本，跨协议一致
    match decoded.meta.source_provider {   // 1% 情况：按来源特判
      "openai-responses" => handle_openai_special(decoded.meta.provider_payload)
      "azure-openai" => handle_azure_special(decoded.meta.provider_payload)
      "anthropic" => handle_anthropic_special(decoded.meta.extra_fields)
      _ => ()                              // 其余协议：什么都不用做
    }
  }
  Err(e) => print("解码失败: \{e}")
}
```

`meta.source_provider` 为运行时从注册表解析的规范名（精确匹配/别名/模型正则归一），
切换 provider 后特判分支自动跟随来源，无需硬编码。

**中转站（场景 2）**：`convert_response_with_meta(source, json, target)` 返回
`ConvertMetaResult { value, meta }`，`meta.source_provider` 为 source 侧规范名，
`meta.diagnostics` 合并了解码与编码两侧的转换诊断。

---

## 传输可插拔（Transport，多语言客户端）

转换核心运行在 Prism daemon 中，客户端 SDK（`clients/go`、`clients/python`）
只做序列化 + 网络 IO。同一套业务 API 可绑定到 HTTP / UDS / WebSocket，
**切换传输只需一行配置**：

**Go（`clients/go`）：**

```go
// HTTP
client := prism.NewClient(prism.NewHTTPTransport("http://127.0.0.1:8765/v1"))
// UDS（Linux/macOS）
client = prism.NewClient(prism.NewUDSTransport("/tmp/prism.sock"))
// WebSocket
client = prism.NewClient(prism.NewWSTransport("ws://127.0.0.1:8766/ws"))

env, _ := client.EncodeRequest(ctx, "openai-chat", "Hi")   // 协议转换零改动
```

**Python（`clients/python`）：**

```python
from prism.client import PrismClient
from prism.transport import HTTPTransport, UDSTransport, WSTransport

client = PrismClient(HTTPTransport("http://127.0.0.1:8765/v1"))   # 默认
client = PrismClient(UDSTransport("/tmp/prism.sock"))             # 切 UDS 一行
client = PrismClient(WSTransport("ws://127.0.0.1:8766/ws"))       # 切 WS 一行

env = client.encode_request("openai-chat", "Hi")  # 其余代码不变
```

**传输语义一致性**：三端（HTTP/UDS/WS）共享同一 JSON-RPC 方法集与 D5 信封
（`{value, diagnostics}`），`clients/go` 与 `clients/python` 的同一套测试
对三种传输分别运行（可插拔契约测试）；UDS 在无 `socket.AF_UNIX` 的平台
（Windows 走 Named Pipe）自动跳过。流式方法（`decode_sse` / `convert_stream`）
在 HTTP 上以 SSE、UDS 上以 JSON lines、WS 上以多帧表达，事件序列语义一致。

**启动 daemon（HTTP + UDS + WS 全开）：**

```bash
prism-daemon --wasm _build/wasm/debug/build/cmd/main/main.wasm \
  --listen 127.0.0.1:8765 --uds /tmp/prism.sock --ws 127.0.0.1:8766
```
