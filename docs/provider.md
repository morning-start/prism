### **LLM AI 接口交互协议全面分析与对比**

> 原文作者：一枚后端攻城狮

---

### **一、协议全景概览**

目前 LLM 领域的接口交互协议可分为以下几大类：

- **标准化协议**：OpenAI API 协议（事实标准）、Anthropic API 协议、MCP 协议（模型上下文协议）
- **厂商私有协议**：Google Gemini API、百度文心 API、阿里通义 API、讯飞星火 API 等
- **开放标准协议**：OpenAPI Spec、gRPC / Protobuf、GraphQL
- **Agent/工具层协议**：MCP、LangChain Tool Protocol、Function Calling 规范、OpenAI Agents SDK

---

### **二、OpenAI API 协议（事实工业标准）**

**核心接口结构：**

```json
POST https://api.openai.com/v1/chat/completions
Authorization: Bearer {API_KEY}
Content-Type: application/json

// 请求体
{
  "model": "gpt-4o",
  "messages": [
    {"role": "system", "content": "You are a helpful assistant."},
    {"role": "user",   "content": "你好，介绍一下自己"}
  ],
  "temperature": 0.7,
  "max_tokens": 1024,
  "stream": false,
  "tools": [
    {
      "type": "function",
      "function": {
        "name": "get_weather",
        "description": "获取天气信息",
        "parameters": {
          "type": "object",
          "properties": {
            "city": {"type": "string"}
          }
        }
      }
    }
  ]
}

// 响应体
{
  "id": "chatcmpl-xxx",
  "object": "chat.completion",
  "created": 1710000000,
  "model": "gpt-4o",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "你好！我是 GPT-4o..."
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 20,
    "completion_tokens": 50,
    "total_tokens": 70
  }
}
```

**流式响应（SSE）：**

```
data: {"choices":[{"delta":{"content":"你"},"index":0}]}
data: {"choices":[{"delta":{"content":"好"},"index":0}]}
data: [DONE]
```

**主要端点：**

| 端点                       | 功能             |
| -------------------------- | ---------------- |
| `/v1/chat/completions`     | 对话补全（核心） |
| `/v1/completions`          | 文本补全（旧版） |
| `/v1/embeddings`           | 向量嵌入         |
| `/v1/images/generations`   | 图像生成         |
| `/v1/audio/transcriptions` | 语音转文字       |
| `/v1/models`               | 模型列表         |
| `/v1/moderations`          | 内容审核         |

---

### **三、Anthropic API 协议**

**核心接口结构：**

```json
POST https://api.anthropic.com/v1/messages
x-api-key: {API_KEY}
anthropic-version: 2023-06-01
Content-Type: application/json

// 请求体（system 为独立字段，非 messages 内）
{
  "model": "claude-3-5-sonnet-20241022",
  "max_tokens": 1024,
  "system": "You are a helpful assistant.",
  "messages": [
    {
      "role": "user",
      "content": [                            // content 支持数组（多模态）
        {
          "type": "text",
          "text": "分析这张图片"
        },
        {
          "type": "image",
          "source": {
            "type": "base64",
            "media_type": "image/jpeg",
            "data": "/9j/4AAQ..."
          }
        }
      ]
    }
  ],
  "tools": [
    {
      "name": "get_weather",
      "description": "获取天气",
      "input_schema": {              // 注意：是 input_schema，非 parameters
        "type": "object",
        "properties": {
          "city": {"type": "string"}
        }
      }
    }
  ]
}

// 响应体
{
  "id": "msg_xxx",
  "type": "message",
  "role": "assistant",
  "content": [
    {
      "type": "text",
      "text": "好的，我来分析..."
    }
  ],
  "model": "claude-3-5-sonnet-20241022",
  "stop_reason": "end_turn",
  "usage": {
    "input_tokens": 25,
    "output_tokens": 60
  }
}
```

**独有特性——扩展思考（Extended Thinking）：**

```json
{
  "thinking": {
    "type": "enabled",
    "budget_tokens": 5000
  }
}

// 响应中包含思考过程
{
  "content": [
    {
      "type": "thinking",
      "thinking": "让我仔细分析这个问题..."
    },
    {
      "type": "text",
      "text": "最终答案是..."
    }
  ]
}
```

---

### **四、MCP 协议（Model Context Protocol）**

MCP 由 Anthropic 提出并开源，已获得 OpenAI、Google 等主流厂商支持，是目前 Agent 工具层最重要的标准协议。

**MCP 的定位——解决 N×M 问题：**

传统方式：每个模型与每个工具需单独开发桥接；MCP 方式：统一协议，一次接入，处处可用。

**MCP 架构：**

```
┌─────────────────────────────────────┐
│           MCP Host (宿主)            │
│  (Claude Desktop / VSCode / IDE)    │
│                                     │
│  ┌──────────┐    ┌──────────────┐  │
│  │MCP Client│◄──►│   LLM Model  │  │
│  └────┬─────┘    └──────────────┘  │
└───────┼─────────────────────────────┘
        │ MCP Protocol
        ▼
┌───────────────────────────────────┐
│           MCP Server              │
│  ┌────────┐ ┌───────┐ ┌───────┐  │
│  │ Tools  │ │Prompts│ │  Re-  │  │
│  │(工具)  │ │(提示) │ │sources│  │
│  └────────┘ └───────┘ └───────┘  │
└───────────────────────────────────┘
```

**通信协议（JSON-RPC 2.0）：**

```json
// 工具列表请求
{"jsonrpc": "2.0", "id": 1, "method": "tools/list"}

// 工具列表响应
{
  "jsonrpc": "2.0",
  "id": 1,
  "result": {
    "tools": [
      {
        "name": "read_file",
        "description": "读取文件内容",
        "inputSchema": {
          "type": "object",
          "properties": {
            "path": {"type": "string"}
          }
        }
      }
    ]
  }
}

// 工具调用请求
{
  "jsonrpc": "2.0",
  "id": 2,
  "method": "tools/call",
  "params": {
    "name": "read_file",
    "arguments": {"path": "/home/user/test.txt"}
  }
}
```

**传输方式：** `stdio`（标准输入输出，本地进程通信）或 `SSE`（Server-Sent Events，远程 HTTP 通信）

---

### **五、主流厂商私有协议**

**Google Gemini API：**

```json
POST https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent

{
  "contents": [
    {
      "role": "user",
      "parts": [{"text": "你好"}]   // parts 数组，非 content 字符串
    }
  ],
  "generationConfig": {
    "temperature": 0.7,
    "maxOutputTokens": 1024
  },
  "safetySettings": [...]
}
```

**百度文心 API：** 兼容 OpenAI messages 格式，含 `user_id` 私有字段，认证方式为 `access_token` 参数（非 Bearer Token）。

**阿里通义千问 API：** messages 嵌套在 `input` 字段中，参数在 `parameters` 字段中，认证使用 Bearer Token。

**讯飞星火 API：** 使用 WebSocket 协议，需要 HMAC-SHA256 签名认证，支持实时双向通信。

---

### **六、其他重要协议与规范**

**OpenAI 兼容层（广泛采用）：** 大量厂商提供 OpenAI 兼容接口，只需修改 `base_url`：

```python
from openai import OpenAI

# 月之暗面 Kimi
client = OpenAI(api_key="...", base_url="https://api.moonshot.cn/v1")

# DeepSeek
client = OpenAI(api_key="...", base_url="https://api.deepseek.com/v1")

# 智谱 AI
client = OpenAI(api_key="...", base_url="https://open.bigmodel.cn/api/paas/v4/")

# 本地 Ollama
client = OpenAI(api_key="ollama", base_url="http://localhost:11434/v1")
```

**LangChain 抽象层协议：** 统一接口调用，屏蔽底层协议差异。

**Ollama 本地协议：** 本地部署 LLM 的事实标准，兼容 OpenAI 格式。

**HuggingFace Inference API：** 通过 `model_id` 指定模型，使用 `inputs` 和 `parameters` 字段。

---

### **七、全面对比分析**

**核心维度对比：**

| 维度        | OpenAI API       | Anthropic API    | MCP 协议         | Google Gemini     | 国内厂商私有    |
| ----------- | ---------------- | ---------------- | ---------------- | ----------------- | --------------- |
| 协议类型    | REST/HTTP        | REST/HTTP        | JSON-RPC 2.0     | REST/HTTP         | REST/HTTP/WS    |
| 认证方式    | Bearer Token     | x-api-key Header | 无（本地）/Token | API Key 参数      | 各异            |
| 流式支持    | SSE              | SSE              | SSE/stdio        | SSE               | SSE/WebSocket   |
| 多模态      | ✅                | ✅                | ✅（资源层）      | ✅                 | 部分支持        |
| 工具调用    | Function Calling | Tool Use         | 原生支持         | Function Calling  | 部分支持        |
| System 消息 | messages 内      | 独立字段         | N/A              | systemInstruction | 各异            |
| 兼容性      | 事实标准         | 独立生态         | 跨模型标准       | 部分兼容          | 多数兼容 OpenAI |
| 开源程度    | 闭源             | MCP 开源         | 完全开源         | 闭源              | 闭源            |
| 生态成熟度  | ⭐⭐⭐⭐⭐            | ⭐⭐⭐⭐             | ⭐⭐⭐⭐             | ⭐⭐⭐⭐              | ⭐⭐⭐             |

**消息结构对比：**

- **OpenAI：** `messages: [{role: "system", content: "..."}, {role: "user", ...}, {role: "assistant", ...}]`
- **Anthropic：** `system` 为独立字段，`messages` 中 content 为数组，无 system role，必须交替 user/assistant
- **Google Gemini：** `contents` 中 role 为 "model" 而非 "assistant"，`systemInstruction` 为独立字段

**工具调用对比：**

- **OpenAI：** `tools[].function.parameters`
- **Anthropic：** `tools[].input_schema`
- **MCP：** `inputSchema`（驼峰命名），通过独立 Server 暴露

---

### **八、选型建议**

| 场景              | 推荐方案                           |
| ----------------- | ---------------------------------- |
| 个人/小团队开发   | OpenAI API 协议 + Ollama 本地备选  |
| 企业级 Agent 系统 | MCP 协议 + OpenAI/Anthropic 双模型 |
| 国内商业应用      | 阿里通义/百度文心（OpenAI 兼容层） |
| 多模型路由        | LiteLLM 统一代理层                 |
| 离线/私有化       | Ollama + Open WebUI                |

---

### **九、未来趋势**

1. **MCP 成为 Agent 工具层标准：** OpenAI、Google 相继支持，MCP 正在成为 AI 工具互操作的 "USB-C"
2. **OpenAI 格式持续主导：** 兼容 OpenAI 格式已成为新模型上线的基本要求
3. **协议融合趋势：** 各厂商逐步向 OpenAI 兼容靠拢，同时扩展私有能力字段
4. **本地协议崛起：** Ollama 等本地部署方案推动边缘 AI 协议标准化