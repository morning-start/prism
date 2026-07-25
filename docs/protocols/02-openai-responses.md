# OpenAI Responses 协议

> 端点：`POST /v1/responses`
> OMP 传输层：`openai-responses`、`openai-codex-responses`、`azure-openai-responses`
> 官方文档：https://platform.openai.com/docs/api-reference/responses/create

> **兼容性说明：** Codex 和 Azure 变体使用相同的 JSON 接口，仅端点 URL 和认证方式不同，共用一个适配器实现。

## 请求 (Request)

```json
{
  "model": "gpt-5.3-codex",
  "instructions": "You are a helpful coding assistant.",
  "input": [
    {
      "type": "message",
      "role": "user",
      "content": [
        {
          "type": "input_text",
          "text": "Write a function to reverse a string"
        }
      ]
    },
    {
      "type": "function_call",
      "id": "fc_abc123",
      "call_id": "call_abc123",
      "name": "run_code",
      "arguments": "{\"code\":\"print('hello')\"}"
    },
    {
      "type": "function_call_output",
      "call_id": "call_abc123",
      "output": "hello\n"
    }
  ],
  "tools": [
    {
      "type": "function",
      "name": "run_code",
      "description": "Execute Python code",
      "parameters": {
        "type": "object",
        "properties": {
          "code": {"type": "string"}
        }
      }
    }
  ],
  "tool_choice": "auto",
  "stream": false,
  "temperature": 0.7,
  "max_output_tokens": 4096,
  "top_p": 1.0,
  "parallel_tool_calls": true,
  "previous_response_id": "resp_abc123",
  "truncation": "auto",
  "include": ["file_search_call.results", "message.input_image.image_url"],
  "reasoning": {
    "effort": "medium",
    "summary": "auto"
  },
  "text": {
    "format": {"type": "text"}
  }
}
```

### 请求字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|:---:|------|
| `model` | string | **是** | 模型 ID |
| `instructions` | string | — | 系统指令 |
| `input` | array | **是** | Item 数组（非 messages！） |
| `input[].type` | enum | **是** | `message` / `function_call` / `function_call_output` / `reasoning` |
| `input[].role` | enum | — | `user` / `assistant` / `developer`（仅 message 类型） |
| `input[].content` | array | — | content part 数组 |
| `input[].content[].type` | enum | — | `input_text` / `input_image` / `input_file` |
| `input[].content[].text` | string | — | 文本 |
| `input[].id` | string | — | function_call 的 ID |
| `input[].call_id` | string | — | function_call 的 call_id |
| `input[].name` | string | — | 函数名 |
| `input[].arguments` | string | — | JSON 参数字符串 |
| `input[].output` | string | — | function_call_output 的输出 |
| `input[].summary` | array | — | reasoning 的摘要 |
| `tools` | array | — | 可用工具列表 |
| `tools[].type` | string | — | `function` / `file_search` / `web_search` / `code_interpreter` |
| `tools[].name` | string | **是** | 函数名 |
| `tools[].description` | string | — | 函数描述 |
| `tools[].parameters` | object | — | JSON Schema 参数定义 |
| `tool_choice` | string/object | — | `"auto"` / `"none"` / `"required"` / `{"type":"function","name":"x"}` |
| `stream` | bool | — | 是否流式 |
| `temperature` | number | — | 0~2 |
| `max_output_tokens` | int | — | 最大输出 token |
| `top_p` | number | — | 核采样 |
| `parallel_tool_calls` | bool | — | 是否允许并行工具调用 |
| `previous_response_id` | string | — | 链接前一响应 |
| `reasoning.effort` | enum | — | `low` / `medium` / `high` |
| `reasoning.summary` | enum | — | `auto` / `concise` / `detailed` |
| `text.format` | object | — | `{"type":"text"}` / `{"type":"json_object"}` / `{"type":"json_schema","schema":{...}}` |

---

## 响应 (Response) — 非流式

```json
{
  "id": "resp_abc123",
  "object": "response",
  "created_at": 1700000000,
  "status": "completed",
  "model": "gpt-5.3-codex",
  "output": [
    {
      "type": "reasoning",
      "id": "rs_abc123",
      "summary": [
        {
          "type": "summary_text",
          "text": "I need to write a function that reverses a string..."
        }
      ],
      "signature": "abc123..."
    },
    {
      "type": "message",
      "id": "msg_abc123",
      "status": "completed",
      "role": "assistant",
      "content": [
        {
          "type": "output_text",
          "text": "Here's a function to reverse a string:",
          "annotations": []
        }
      ]
    },
    {
      "type": "function_call",
      "id": "fc_abc123",
      "call_id": "call_abc123",
      "name": "run_code",
      "arguments": "{\"code\":\"def reverse(s):\\n  return s[::-1]\"}",
      "status": "completed"
    }
  ],
  "usage": {
    "input_tokens": 50,
    "output_tokens": 100,
    "total_tokens": 150,
    "input_tokens_details": {
      "cached_tokens": 0
    },
    "output_tokens_details": {
      "reasoning_tokens": 30
    }
  },
  "previous_response_id": null,
  "truncation": "auto",
  "parallel_tool_calls": true
}
```

### 响应字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | string | 响应唯一 ID |
| `object` | string | 固定 `"response"` |
| `status` | string | `completed` / `incomplete` / `failed` |
| `model` | string | 实际使用的模型 |
| `output[]` | array | 输出 Item 数组 |
| `output[].type` | enum | `message` / `function_call` / `reasoning` |
| `output[].content[].type` | enum | `output_text` / `refusal` |
| `output[].content[].text` | string | 文本 |
| `output[].name` | string | 函数名 |
| `output[].arguments` | string | JSON 参数字符串 |
| `output[].summary[].text` | string | 推理摘要 |
| `output[].signature` | string | 推理签名 |
| `usage.input_tokens` | int | 输入 token |
| `usage.output_tokens` | int | 输出 token |
| `usage.output_tokens_details.reasoning_tokens` | int | 推理 token |

---

## 流式响应 (SSE)

```
event: response.created
data: {"type":"response.created","response":{"id":"resp_abc",...}}

event: response.output_item.added
data: {"type":"response.output_item.added","output_index":0,"item":{"type":"reasoning","id":"rs_abc"}}

event: response.reasoning_summary_text.delta
data: {"type":"response.reasoning_summary_text.delta","item_id":"rs_abc","output_index":0,"content_index":0,"delta":"I need to..."}

event: response.reasoning_summary_text.done
data: {"type":"response.reasoning_summary_text.done","item_id":"rs_abc",...}

event: response.output_item.added
data: {"type":"response.output_item.added","output_index":1,"item":{"type":"message","id":"msg_abc","role":"assistant"}}

event: response.content_part.added
data: {"type":"response.content_part.added","item_id":"msg_abc","output_index":1,"content_index":0,"part":{"type":"output_text","text":""}}

event: response.output_text.delta
data: {"type":"response.output_text.delta","item_id":"msg_abc","output_index":1,"content_index":0,"delta":"Here's"}

event: response.output_text.done
data: {"type":"response.output_text.done","item_id":"msg_abc",...}

event: response.output_item.added
data: {"type":"response.output_item.added","output_index":2,"item":{"type":"function_call","id":"fc_abc","name":"run_code"}}

event: response.function_call_arguments.delta
data: {"type":"response.function_call_arguments.delta","item_id":"fc_abc","output_index":2,"delta":"{\"code\":"}

event: response.function_call_arguments.done
data: {"type":"response.function_call_arguments.done","item_id":"fc_abc",...}

event: response.completed
data: {"type":"response.completed","response":{"id":"resp_abc","status":"completed","usage":{...}}}
```

### 流式事件类型

| 事件 | 说明 |
|------|------|
| `response.created` | 响应创建 |
| `response.output_item.added` | 新 Item 开始（reasoning/message/function_call） |
| `response.content_part.added` | 新 content part 开始 |
| `response.output_text.delta` | 文本增量 |
| `response.output_text.done` | 文本完成 |
| `response.reasoning_summary_text.delta` | 推理摘要增量 |
| `response.reasoning_summary_text.done` | 推理摘要完成 |
| `response.function_call_arguments.delta` | 函数参数增量 |
| `response.function_call_arguments.done` | 函数参数完成 |
| `response.completed` | 整个响应完成 |
| `error` | 错误 |

---

## 与 Lucent IR 的映射要点

| Responses | Lucent IR |
|-----------|-----------|
| `instructions` | `LucentRequest.instructions` |
| `input[?type=message].content[]` | `LucentContent::Text` / `Image`(stub) |
| `input[?type=function_call]` | `LucentContent::ToolUse` |
| `input[?type=function_call_output]` | `LucentContent::ToolResult` |
| `input[?type=reasoning]` | `LucentContent::Thinking` |
| `tools[].function` | `LucentTool` |
| `max_output_tokens` | `LucentOptions.max_output_tokens` |
| `output[?type=message].content[?type=output_text]` | `LucentContent::Text` |
| `output[?type=function_call]` | `LucentContent::ToolUse` |
| `output[?type=reasoning].summary` | `LucentContent::Thinking` |
| `status` | `LucentFinishReason`（completed→Stop, incomplete→Length） |
| `usage` | `LucentUsage`（input_tokens→prompt_tokens） |
| `previous_response_id` | `LucentResponse.provider_payload` |

### 关键差异 vs Chat Completions

1. **模型不同**：`input[]` 是 Item 数组而非 `messages[]`
2. **系统指令**：`instructions` 是顶层字段，不是 messages 的一部分
3. **推理思考**：原生支持 `reasoning` Item，有 `summary` 和 `signature`
4. **流式格式**：使用 SSE event 类型而非 delta 增量
5. **工具调用**：`function_call` 是独立 Item，不在 message 内部
6. **Codex 变体**：JSON 接口相同，仅 `model` 字段值为 Codex 模型
7. **Azure 变体**：JSON 接口相同，仅端点 URL 和认证方式不同