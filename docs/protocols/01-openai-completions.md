# OpenAI Chat Completions 协议

> 端点：`POST /v1/chat/completions`
> OMP 传输层：`openai-completions`
> 官方文档：https://platform.openai.com/docs/api-reference/chat/create

## 请求 (Request)

```json
{
  "model": "gpt-4o",
  "messages": [
    {
      "role": "system",
      "content": "You are a helpful assistant."
    },
    {
      "role": "user",
      "content": "Hello!"
    },
    {
      "role": "assistant",
      "content": "Hi there! How can I help?",
      "tool_calls": [
        {
          "id": "call_abc123",
          "type": "function",
          "function": {
            "name": "get_weather",
            "arguments": "{\"city\":\"Beijing\"}"
          }
        }
      ]
    },
    {
      "role": "tool",
      "tool_call_id": "call_abc123",
      "content": "{\"temp\": 25}"
    }
  ],
  "tools": [
    {
      "type": "function",
      "function": {
        "name": "get_weather",
        "description": "获取指定城市的天气",
        "parameters": {
          "type": "object",
          "properties": {
            "city": {"type": "string"}
          }
        }
      }
    }
  ],
  "tool_choice": "auto",
  "stream": false,
  "temperature": 0.7,
  "max_tokens": 1024,
  "top_p": 1.0,
  "stop": ["\n\n"],
  "response_format": {"type": "json_object"}
}
```

### 请求字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|:---:|------|
| `model` | string | **是** | 模型 ID |
| `messages` | array | **是** | 消息数组，每项含 `role` + `content` |
| `messages[].role` | enum | **是** | `system` / `user` / `assistant` / `tool` / `developer` |
| `messages[].content` | string/array | **是** | 字符串或 content part 数组 |
| `messages[].content[].type` | enum | — | `text` / `image_url` |
| `messages[].tool_calls` | array | — | assistant 消息中的工具调用列表 |
| `messages[].tool_calls[].id` | string | — | 工具调用唯一 ID |
| `messages[].tool_calls[].type` | string | — | 固定 `"function"` |
| `messages[].tool_calls[].function.name` | string | — | 函数名 |
| `messages[].tool_calls[].function.arguments` | string | — | JSON 参数字符串 |
| `messages[].tool_call_id` | string | — | tool 角色消息关联的工具调用 ID |
| `tools` | array | — | 可用工具列表 |
| `tools[].type` | string | — | 固定 `"function"` |
| `tools[].function.name` | string | **是** | 函数名 |
| `tools[].function.description` | string | — | 函数描述 |
| `tools[].function.parameters` | object | — | JSON Schema 参数定义 |
| `tool_choice` | string/object | — | `"auto"` / `"none"` / `"required"` / `{"type":"function","function":{"name":"x"}}` |
| `stream` | bool | — | 是否流式，默认 false |
| `temperature` | number | — | 0~2 |
| `max_tokens` / `max_completion_tokens` | int | — | 最大输出 token 数 |
| `top_p` | number | — | 核采样 |
| `stop` | string/array | — | 停止词 |
| `response_format` | object | — | `{"type":"text"}` / `{"type":"json_object"}` / `{"type":"json_schema","json_schema":{...}}` |

### 多模态 content 格式

```json
{
  "role": "user",
  "content": [
    {"type": "text", "text": "What's in this image?"},
    {"type": "image_url", "image_url": {"url": "https://...", "detail": "auto"}}
  ]
}
```

---

## 响应 (Response) — 非流式

```json
{
  "id": "chatcmpl-abc123",
  "object": "chat.completion",
  "created": 1700000000,
  "model": "gpt-4o-2024-05-13",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "Hello! How can I assist you today?",
        "tool_calls": [
          {
            "id": "call_abc123",
            "type": "function",
            "function": {
              "name": "get_weather",
              "arguments": "{\"city\":\"Beijing\"}"
            }
          }
        ],
        "refusal": null
      },
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 10,
    "completion_tokens": 20,
    "total_tokens": 30
  },
  "system_fingerprint": "fp_abc123"
}
```

### 响应字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | string | 响应唯一 ID |
| `object` | string | 固定 `"chat.completion"` |
| `model` | string | 实际使用的模型 |
| `choices[].index` | int | 候选序号 |
| `choices[].message.role` | string | `"assistant"` |
| `choices[].message.content` | string/null | 文本内容（tool_calls 时可为 null） |
| `choices[].message.tool_calls` | array | 工具调用（同请求格式） |
| `choices[].message.refusal` | string/null | 安全拒绝内容 |
| `choices[].finish_reason` | string | `stop` / `length` / `tool_calls` / `content_filter` |
| `usage.prompt_tokens` | int | 输入 token 数 |
| `usage.completion_tokens` | int | 输出 token 数 |
| `usage.total_tokens` | int | 总计 token 数 |

---

## 流式响应 (SSE)

```
data: {"id":"chatcmpl-abc","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"role":"assistant"},"finish_reason":null}]}

data: {"id":"chatcmpl-abc","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":"Hello"},"finish_reason":null}]}

data: {"id":"chatcmpl-abc","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"content":" world"},"finish_reason":null}]}

data: {"id":"chatcmpl-abc","object":"chat.completion.chunk","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}

data: {"id":"chatcmpl-abc","object":"chat.completion.chunk","choices":[],"usage":{"prompt_tokens":10,"completion_tokens":2,"total_tokens":12}}

data: [DONE]
```

### 流式 delta 字段

| 字段 | 说明 |
|------|------|
| `delta.role` | 首帧出现，值为 `"assistant"` |
| `delta.content` | 文本增量，可为 null |
| `delta.tool_calls[].index` | 工具调用序号 |
| `delta.tool_calls[].id` | 工具调用 ID（首帧） |
| `delta.tool_calls[].function.name` | 函数名（首帧） |
| `delta.tool_calls[].function.arguments` | JSON 参数增量片段 |
| `finish_reason` | 末帧出现：`stop` / `length` / `tool_calls` / `content_filter` |
| `usage` | 可选，最后一帧可能包含 token 统计 |

---

## 与 Lucent IR 的映射要点

| Chat Completions | Lucent IR |
|-----------------|-----------|
| `messages[?role=system].content` | `LucentRequest.instructions` |
| `messages[?role=user/assistant]` | `LucentRequest.messages[]` |
| `messages[].content` (string) | `LucentContent::Text` |
| `messages[].content` (array) | `LucentContent::Text` / `Image`(stub) |
| `messages[].tool_calls[]` | `LucentContent::ToolUse` |
| `messages[?role=tool]` | `LucentContent::ToolResult` |
| `tools[].function` | `LucentTool` |
| `temperature` | `LucentOptions.temperature` |
| `max_tokens` / `max_completion_tokens` | `LucentOptions.max_output_tokens` |
| `stream` | `LucentOptions.stream` |
| `choices[].message.content` | `LucentContent::Text`（拼接） |
| `choices[].message.tool_calls` | `LucentContent::ToolUse` |
| `choices[].message.refusal` | `LucentContent::Refusal` |
| `finish_reason` | `LucentFinishReason`（Stop/Length/ToolCalls/ContentFilter） |
| `usage` | `LucentUsage` |