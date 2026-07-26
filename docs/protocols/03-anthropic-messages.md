# Anthropic Messages 协议

> 端点：`POST /v1/messages`
> OMP 传输层：`anthropic-messages`
> 最新文档：https://docs.anthropic.com/en/api/messages

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
  "max_tokens": 16000,
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
| `system` | string/array | — | 系统指令（字符串或 content block 数组，支持 `cache_control`） |
| `system[].type` | enum | — | `text`（支持 `cache_control`） |
| `messages` | array | **是** | 消息数组 |
| `messages[].role` | enum | **是** | `user` / `assistant` |
| `messages[].content` | array/string | **是** | content block 数组或字符串 |
| `messages[].content[].type` | enum | **是** | `text` / `tool_use` / `tool_result` / `image` / `thinking` / `redacted_thinking` |
| `messages[].content[].text` | string | — | 文本 |
| `messages[].content[].id` | string | — | tool_use 唯一 ID |
| `messages[].content[].name` | string | — | 工具名称 |
| `messages[].content[].input` | object | — | 工具参数（JSON **对象**，非字符串！） |
| `messages[].content[].tool_use_id` | string | — | tool_result 关联的工具调用 ID |
| `messages[].content[].content` | array | — | tool_result 的内容（content block 数组） |
| `messages[].content[].is_error` | bool | — | tool_result 是否为错误 |
| `messages[].content[].source` | object | — | image 的 source（`{type:"base64", media_type, data}` 或 URL） |
| `messages[].content[].thinking` | string | — | thinking 内容 |
| `messages[].content[].signature` | string | — | thinking/redacted_thinking 签名 |
| `tools` | array | — | 工具定义 |
| `tools[].name` | string | **是** | 函数名 |
| `tools[].description` | string | — | 函数描述 |
| `tools[].input_schema` | object | **是** | JSON Schema（注意：是 `input_schema` 不是 `parameters`） |
| `tools[].type` | enum | — | `custom` / `text_editor_20250124` / `bash_20250124` / `code_execution_20250522` |
| `tool_choice` | object | — | `{"type":"auto"}` / `{"type":"any"}` / `{"type":"tool","name":"x"}` |
| `max_tokens` | int | **是** | 最大输出 token 数（**必填！**） |
| `temperature` | number | — | 0~1（thinking 启用时必须为 1 或省略） |
| `top_p` | number | — | 核采样（thinking 启用时不兼容） |
| `top_k` | int | — | top-k 采样（thinking 启用时不兼容） |
| `stop_sequences` | array | — | 停止序列 |
| `stream` | bool | — | 是否流式 |
| `thinking` | object | — | 思考配置（见下方详细说明） |
| `metadata` | object | — | 自定义元数据 |
| `metadata.user_id` | string | — | 用户标识 |

### Thinking 配置详解

Anthropic 支持两种思考模式：

#### 1. 扩展思考 (Extended Thinking) — 传统模式

```json
{
  "thinking": {
    "type": "enabled",
    "budget_tokens": 1024
  }
}
```

- `budget_tokens`：思考 token 预算，最小值 1024，**必须小于 `max_tokens`**
- 适用于 Claude 4.5 及更早模型
- Claude Opus 4.6、Sonnet 4.6 仍支持但已弃用
- Claude 4.7 及更新模型拒收此模式（返回 400）

#### 2. 自适应思考 (Adaptive Thinking) — 推荐模式

```json
{
  "thinking": {
    "type": "adaptive"
  }
}
```

- 模型自行决定是否思考及思考深度
- 适用于 Claude Opus 4.6+、Claude Sonnet 4.6+
- 自动支持 **交错思考 (Interleaved Thinking)**，无需 beta header
- 可通过 `output_config.effort` 控制推理力度（见下方 Effort 参数）

#### 3. 思考显示控制 (display 字段)

```json
{
  "thinking": {
    "type": "enabled",
    "budget_tokens": 10000,
    "display": "omitted"
  }
}
```

| `display` 值 | 行为 |
|-------------|------|
| 不设置（默认） | 返回完整 thinking 内容在 `thinking` 字段 |
| `"omitted"` | thinking 字段返回空字符串 `""`，`signature` 始终保留 |

- 不影响计费或推理质量
- `signature` 始终返回，保证多轮连续性

### Effort 参数（自适应思考搭配使用）

```json
{
  "output_config": {
    "effort": "high"
  }
}
```

| 力度 | 说明 |
|------|------|
| `low` | 快速响应，适合简单任务 |
| `medium` | 适用于大多数任务 |
| `high` | 深度推理，复杂问题 |

### 交错思考 (Interleaved Thinking)

模型在一次 assistant turn 内在工具调用之间穿插思考，处理每个工具结果后再决定后续操作。

| 模型 | 启用方式 |
|------|---------|
| Claude Opus 4.5 及更早 | 需 `anthropic-beta: interleaved-thinking-2025-05-14` 请求头 |
| Claude Sonnet 4.6 | beta header 仍可用但已弃用 |
| Claude Opus 4.6 | 仅 adaptive 模式下自动交错，manual 模式不支持 |
| Claude 4.7+ | 自适应思考自动交错 |

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
| `content[].input` | object | 工具参数（JSON **对象**，非字符串！） |
| `content[].thinking` | string | 思考内容（`display:"omitted"` 时为空字符串 `""`） |
| `content[].signature` | string | 思考签名（多轮连续性关键） |
| `stop_reason` | string | `end_turn` / `max_tokens` / `tool_use` / `stop_sequence` |
| `stop_sequence` | string/null | 触发的停止序列 |
| `usage.input_tokens` | int | 输入 token |
| `usage.output_tokens` | int | 输出 token |
| `usage.cache_creation_input_tokens` | int | 缓存创建 token |
| `usage.cache_read_input_tokens` | int | 缓存命中 token |

### redacted_thinking

当 Claude 的思考被安全系统拦截时，部分或全部 `thinking` block 会被加密为 `redacted_thinking`：

```json
{
  "type": "redacted_thinking",
  "data": "encrypted..."
}
```

回传时将 `redacted_thinking` 加入 assistant message，API 自动解密。这不会阻止 Claude 的思考，只是内容对外不可见。

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
| `messages[?role=assistant].content[?type=redacted_thinking]` | `LucentContent::RedactedThinking` |
| `tools[].input_schema` | `LucentTool.parameters_json` |
| `tools[].type` (custom/bash/text_editor/code_execution) | `LucentTool.provider_kind` |
| `max_tokens` | `LucentOptions.max_output_tokens` |
| `thinking.type` + `budget_tokens` | `LucentOptions.thinking` / `LucentOptions.thinking_budget` |
| `thinking.display` | `LucentOptions.thinking_display` |
| `output_config.effort` | `LucentOptions.reasoning_effort` |
| `stop_sequences` | `LucentOptions.stop` |
| `content[?type=text].text` | `LucentContent::Text` |
| `content[?type=tool_use]` | `LucentContent::ToolUse`（input → arguments_json） |
| `content[?type=thinking]` | `LucentContent::Thinking` |
| `content[?type=redacted_thinking]` | `LucentContent::RedactedThinking` |
| `stop_reason: end_turn` | `LucentFinishReason::Stop` |
| `stop_reason: max_tokens` | `LucentFinishReason::Length` |
| `stop_reason: tool_use` | `LucentFinishReason::ToolCalls` |
| `usage.input_tokens` | `LucentUsage.prompt_tokens` |
| `usage.output_tokens` | `LucentUsage.completion_tokens` |

### 关键差异 vs Chat Completions

1. **无 `tool` 角色**：工具结果由 `user` 角色发送，内含 `tool_result` content block
2. **系统指令**：顶层 `system` 字段，可以是 content block 数组，支持缓存
3. **`input` 是 JSON 对象**：工具参数格式为 `{"city":"Beijing"}`，非 JSON 字符串
4. **`input_schema` 非 `parameters`**：工具定义使用 `input_schema` 字段
5. **`max_tokens` 必填**：没有默认值，必须显式指定
6. **思考块**：`thinking` 有 `signature` 完整性校验，`redacted_thinking` 表示被隐藏
7. **思考模式**：支持 `type: "enabled"`（扩展思考，已弃用）和 `type: "adaptive"`（自适应思考）
8. **`display: "omitted"`**：可省略 thinking 内容返回，加速流式响应
9. **交错思考**：adaptive 模式下自动在 tool call 之间穿插思考
10. **流式格式**：使用 `content_block_start/delta/stop` 块生命周期模型
11. **工具结果**：`tool_result.content` 是 content block 数组，支持多块返回
