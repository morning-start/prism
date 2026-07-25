# Anthropic Messages 协议

> 端点：`POST /v1/messages`
> OMP 传输层：`anthropic-messages`
> 官方文档：https://docs.anthropic.com/en/api/messages

## 请求 (Request)

```json
{
  "model": "claude-sonnet-4-20250514",
  "system": [
    {
      "type": "text",
      "text": "You are a helpful assistant.",
      "cache_control": {"type": "ephemeral"}
    }
  ],
  "messages": [
    {
      "role": "user",
      "content": [
        {
          "type": "text",
          "text": "Hello!"
        }
      ]
    },
    {
      "role": "assistant",
      "content": [
        {
          "type": "text",
          "text": "Hi there! How can I help?"
        },
        {
          "type": "tool_use",
          "id": "toolu_abc123",
          "name": "get_weather",
          "input": {
            "city": "Beijing"
          }
        }
      ]
    },
    {
      "role": "user",
      "content": [
        {
          "type": "tool_result",
          "tool_use_id": "toolu_abc123",
          "content": [
            {
              "type": "text",
              "text": "{\"temp\": 25}"
            }
          ],
          "is_error": false
        }
      ]
    }
  ],
  "tools": [
    {
      "name": "get_weather",
      "description": "获取指定城市的天气",
      "input_schema": {
        "type": "object",
        "properties": {
          "city": {
            "type": "string",
            "description": "城市名称"
          }
        },
        "required": ["city"]
      }
    }
  ],
  "tool_choice": {
    "type": "auto"
  },
  "max_tokens": 1024,
  "temperature": 0.7,
  "top_p": 1.0,
  "top_k": 5,
  "stop_sequences": ["\n\nHuman:"],
  "stream": false,
  "thinking": {
    "type": "enabled",
    "budget_tokens": 1024
  },
  "metadata": {
    "user_id": "user_123"
  }
}
```

### 请求字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|:---:|------|
| `model` | string | **是** | 模型 ID |
| `system` | string/array | — | 系统指令（字符串或 content block 数组） |
| `system[].type` | enum | — | `text`（支持 `cache_control`） |
| `messages` | array | **是** | 消息数组 |
| `messages[].role` | enum | **是** | `user` / `assistant` |
| `messages[].content` | array | **是** | content block 数组 |
| `messages[].content[].type` | enum | **是** | `text` / `tool_use` / `tool_result` / `image` / `thinking` / `redacted_thinking` |
| `messages[].content[].text` | string | — | 文本 |
| `messages[].content[].id` | string | — | tool_use 唯一 ID |
| `messages[].content[].name` | string | — | 工具名称 |
| `messages[].content[].input` | object | — | 工具参数（JSON 对象） |
| `messages[].content[].tool_use_id` | string | — | tool_result 关联的工具调用 ID |
| `messages[].content[].content` | array | — | tool_result 的内容（content block 数组） |
| `messages[].content[].is_error` | bool | — | tool_result 是否为错误 |
| `messages[].content[].source` | object | — | image 的 source（`{type:"base64", media_type, data}` 或 URL） |
| `messages[].content[].thinking` | string | — | thinking 内容 |
| `messages[].content[].signature` | string | — | thinking 签名 |
| `tools` | array | — | 工具定义 |
| `tools[].name` | string | **是** | 函数名 |
| `tools[].description` | string | — | 函数描述 |
| `tools[].input_schema` | object | **是** | JSON Schema（注意：是 `input_schema` 不是 `parameters`） |
| `tool_choice` | object | — | `{"type":"auto"}` / `{"type":"any"}` / `{"type":"tool","name":"x"}` |
| `max_tokens` | int | **是** | 最大输出 token 数（必填！） |
| `temperature` | number | — | 0~1 |
| `top_p` | number | — | 核采样 |
| `top_k` | int | — | top-k 采样 |
| `stop_sequences` | array | — | 停止序列 |
| `stream` | bool | — | 是否流式 |
| `thinking` | object | — | `{"type":"enabled","budget_tokens":N}` / `{"type":"disabled"}` |
| `metadata` | object | — | 自定义元数据 |
| `metadata.user_id` | string | — | 用户标识 |

### 多模态 image 格式

```json
{
  "type": "image",
  "source": {
    "type": "base64",
    "media_type": "image/png",
    "data": "iVBORw0KGgo..."
  }
}
```

---

## 响应 (Response) — 非流式

```json
{
  "id": "msg_abc123",
  "type": "message",
  "role": "assistant",
  "model": "claude-sonnet-4-20250514",
  "content": [
    {
      "type": "thinking",
      "thinking": "I need to analyze the user's request...",
      "signature": "EqwBCkkI..."
    },
    {
      "type": "text",
      "text": "Hello! How can I assist you today?"
    },
    {
      "type": "tool_use",
      "id": "toolu_abc123",
      "name": "get_weather",
      "input": {
        "city": "Beijing"
      }
    }
  ],
  "stop_reason": "end_turn",
  "stop_sequence": null,
  "usage": {
    "input_tokens": 50,
    "output_tokens": 100,
    "cache_creation_input_tokens": 0,
    "cache_read_input_tokens": 0
  }
}
```

### 响应字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | string | 响应唯一 ID |
| `type` | string | 固定 `"message"` |
| `role` | string | 固定 `"assistant"` |
| `model` | string | 实际使用的模型 |
| `content[]` | array | content block 数组 |
| `content[].type` | enum | `text` / `tool_use` / `thinking` / `redacted_thinking` |
| `content[].text` | string | 文本 |
| `content[].id` | string | tool_use ID |
| `content[].name` | string | 工具名称 |
| `content[].input` | object | 工具参数（JSON 对象，非字符串！） |
| `content[].thinking` | string | 思考内容 |
| `content[].signature` | string | 思考签名 |
| `stop_reason` | string | `end_turn` / `max_tokens` / `tool_use` / `stop_sequence` |
| `stop_sequence` | string/null | 触发的停止序列 |
| `usage.input_tokens` | int | 输入 token |
| `usage.output_tokens` | int | 输出 token |
| `usage.cache_creation_input_tokens` | int | 缓存创建 token |
| `usage.cache_read_input_tokens` | int | 缓存命中 token |

---

## 流式响应 (SSE)

```
event: message_start
data: {"type":"message_start","message":{"id":"msg_abc","type":"message","role":"assistant","model":"claude-sonnet-4-20250514","usage":{"input_tokens":50}}}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"I need"}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"signature_delta","signature":"EqwB..."}}

event: content_block_stop
data: {"type":"content_block_stop","index":0}

event: content_block_start
data: {"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}

event: content_block_delta
data: {"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Hello"}}

event: content_block_stop
data: {"type":"content_block_stop","index":1}

event: content_block_start
data: {"type":"content_block_start","index":2,"content_block":{"type":"tool_use","id":"toolu_abc","name":"get_weather","input":{}}}

event: content_block_delta
data: {"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":"{\"city\":"}}

event: content_block_delta
data: {"type":"content_block_delta","index":2,"delta":{"type":"input_json_delta","partial_json":"\"Beijing\"}"}}

event: content_block_stop
data: {"type":"content_block_stop","index":2}

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":100}}

event: message_stop
data: {"type":"message_stop"}
```

### 流式事件类型

| 事件 | 说明 |
|------|------|
| `message_start` | 消息开始，含 `id`、`model`、`usage.input_tokens` |
| `content_block_start` | 内容块开始，含 `index` 和块类型 |
| `content_block_delta` | 增量：`text_delta` / `thinking_delta` / `signature_delta` / `input_json_delta` |
| `content_block_stop` | 内容块结束 |
| `message_delta` | 消息增量：`stop_reason`、`usage.output_tokens` |
| `message_stop` | 消息流结束 |
| `error` | 错误 |

---

## 与 Lucent IR 的映射要点

| Anthropic | Lucent IR |
|-----------|-----------|
| `system` | `LucentRequest.instructions` |
| `messages[?role=user].content[?type=text]` | `LucentContent::Text` |
| `messages[?role=user].content[?type=image]` | `LucentContent::Image` |
| `messages[?role=assistant].content[?type=tool_use]` | `LucentContent::ToolUse`（input → arguments_json） |
| `messages[?role=user].content[?type=tool_result]` | `LucentContent::ToolResult`（content 为 Array[LucentContent]） |
| `messages[?role=assistant].content[?type=thinking]` | `LucentContent::Thinking` |
| `tools[].input_schema` | `LucentTool.parameters_json` |
| `max_tokens` | `LucentOptions.max_output_tokens` |
| `stop_sequences` | `LucentOptions.stop` |
| `content[?type=text].text` | `LucentContent::Text` |
| `content[?type=tool_use]` | `LucentContent::ToolUse`（input → arguments_json） |
| `content[?type=thinking]` | `LucentContent::Thinking` |
| `stop_reason: end_turn` | `LucentFinishReason::Stop` |
| `stop_reason: max_tokens` | `LucentFinishReason::Length` |
| `stop_reason: tool_use` | `LucentFinishReason::ToolCalls` |
| `usage.input_tokens` | `LucentUsage.prompt_tokens` |
| `usage.output_tokens` | `LucentUsage.completion_tokens` |

### 关键差异 vs Chat Completions

1. **无 `tool` 角色**：工具结果由 `user` 角色发送，内含 `tool_result` content block
2. **系统指令**：顶层 `system` 字段，可以是 content block 数组
3. **`input` 是 JSON 对象**：工具参数格式为 `{"city":"Beijing"}`，非 JSON 字符串
4. **`input_schema` 非 `parameters`**：工具定义使用 `input_schema` 字段
5. **`max_tokens` 必填**：没有默认值，必须显式指定
6. **思考块**：`thinking` 有 `signature` 完整性校验，`redacted_thinking` 表示被隐藏
7. **流式格式**：使用 `content_block_start/delta/stop` 块生命周期模型
8. **工具结果**：`tool_result.content` 是 content block 数组，支持多块返回