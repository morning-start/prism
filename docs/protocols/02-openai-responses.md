# OpenAI Responses 协议

> 端点：`POST /v1/responses`
> OMP 传输层：`openai-responses`、`openai-codex-responses`、`azure-openai-responses`
> 官方文档：https://platform.openai.com/docs/api-reference/responses/create

> **兼容性说明：** Codex 和 Azure 变体使用相同的 JSON 接口，仅端点 URL、认证方式和部分特性不同，共用一个适配器实现。
> Codex 变体：使用 `gpt-5.3-codex` 等 Codex 系列模型，特性见下方 "Codex 特定字段"。
> Azure 变体：使用 Azure OpenAI `/openai/v1/responses` 端点，内含 `content_filters` Azure 扩展字段。

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
  "parallel_tool_calls": true,
  "stream": false,
  "temperature": 0.7,
  "max_output_tokens": 4096,
  "top_p": 1.0,
  "previous_response_id": "resp_abc123",
  "truncation": "auto",
  "include": ["file_search_call.results", "message.input_image.image_url"],
  "reasoning": {
    "effort": "medium",
    "summary": "auto"
  },
  "text": {
    "format": {"type": "text"}
  },
  "store": true,
  "conversation": "conv_abc123",
  "background": false,
  "context_management": [
    {
      "type": "compaction",
      "compact_threshold": 180000
    }
  ]
}
```

### 请求字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|:---:|------|
| `model` | string | **是** | 模型 ID（Azure 上为部署名） |
| `instructions` | string | — | 系统指令，替代 `messages[?role=system]` |
| `input` | string/array | — | 文本字符串或 Item 数组（非 messages！） |
| `input[].type` | enum | **是** | `message` / `function_call` / `function_call_output` / `reasoning` / `item_reference` |
| `input[].role` | enum | — | `user` / `assistant` / `system` / `developer`（仅 message 类型） |
| `input[].content` | array | — | content part 数组 |
| `input[].content[].type` | enum | — | `input_text` / `input_image` / `input_file` |
| `input[].content[].text` | string | — | 文本 |
| `input[].id` | string | — | function_call 的 ID |
| `input[].call_id` | string | — | function_call 的 call_id |
| `input[].name` | string | — | 函数名 |
| `input[].arguments` | string | — | JSON 参数字符串 |
| `input[].output` | string | — | function_call_output 的输出 |
| `input[].summary` | array | — | reasoning 的摘要 |
| `input[].phase` | enum | — | Codex 变体：`commentary` / `final_answer` |
| `tools` | array | — | 可用工具列表 |
| `tools[].type` | enum | — | `function` / `file_search` / `web_search` / `code_interpreter` / `computer_use` / `mcp` / `image_generation` / `shell` |
| `tools[].name` | string | **是** | 函数名（function 类型） |
| `tools[].description` | string | — | 函数描述 |
| `tools[].parameters` | object | — | JSON Schema 参数定义（function 类型） |
| `tool_choice` | string/object | — | `"auto"` / `"none"` / `"required"` / `{"type":"function","name":"x"}` |
| `stream` | bool | — | 是否流式 |
| `temperature` | number | — | 0~2（推理模型必须为 1） |
| `max_output_tokens` | int | — | 最大输出 token（Azure 最小值 16） |
| `top_p` | number | — | 核采样 |
| `parallel_tool_calls` | bool | — | 是否允许并行工具调用 |
| `previous_response_id` | string | — | 链接前一响应（不继承 `instructions`！） |
| `reasoning.effort` | enum | — | `low` / `medium` / `high`（Codex 额外支持 `xhigh`） |
| `reasoning.summary` | enum | — | `auto` / `concise` / `detailed` |
| `text.format` | object | — | `{"type":"text"}` / `{"type":"json_object"}` / `{"type":"json_schema","schema":{...}}` |
| `store` | bool | — | 是否存储响应。默认 true。ZDR 场景设 false |
| `conversation` | string/object | — | Conversation ID 或 `{"id":"conv_123"}` |
| `background` | bool | — | 后台/异步模式（GPT-5.2+），需轮询 GET 结果 |
| `include` | array | — | 额外返回的数据：`file_search_call.results`, `web_search_call.results`, `message.input_image.image_url`, `message.output_text.logprobs`, `reasoning.encrypted_content`, `code_interpreter_call.outputs`, `computer_call_output.output.image_url` |
| `context_management` | array | — | 服务端上下文压缩，`[{"type":"compaction","compact_threshold":180000}]` |
| `moderation` | object | — | 审核配置 |
| `prompt_cache_options` | object | — | 提示缓存选项：`{"ttl":3600}` |
| `agent_reference` | object | — | (Azure 扩展) 代理引用 |

### 多模态 input 格式

```json
{
  "type": "message",
  "role": "user",
  "content": [
    {"type": "input_text", "text": "Describe this image"},
    {"type": "input_image", "image_url": "https://...", "detail": "auto"},
    {"type": "input_file", "file_url": "https://...", "filename": "doc.pdf"}
  ]
}
```

### 提示缓存 (Prompt Caching)

```json
{
  "type": "input_text",
  "text": "Large reusable prefix...",
  "prompt_cache_breakpoint": {"mode": "explicit"}
}
```

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
      "phase": "commentary",
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
      "cached_tokens": 10
    },
    "output_tokens_details": {
      "reasoning_tokens": 30
    }
  },
  "previous_response_id": null,
  "truncation": "auto",
  "parallel_tool_calls": true,
  "content_filters": [
    {
      "blocked": false,
      "source_type": "prompt",
      "content_filter_results": {
        "hate": {"filtered": false, "severity": "safe"}
      }
    }
  ]
}
```

### 响应字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `id` | string | 响应唯一 ID |
| `object` | string | 固定 `"response"` |
| `status` | string | `completed` / `incomplete` / `failed` / `in_progress` |
| `model` | string | 实际使用的模型 |
| `output[]` | array | 输出 Item 数组 |
| `output[].type` | enum | `message` / `function_call` / `reasoning` / `file_search_call` / `web_search_call` / `computer_call` / `code_interpreter_call` / `image_gen_call` |
| `output[].content[].type` | enum | `output_text` / `refusal` |
| `output[].content[].text` | string | 文本 |
| `output[].phase` | enum | `commentary` / `final_answer`（Codex 变体） |
| `output[].name` | string | 函数名 |
| `output[].arguments` | string | JSON 参数字符串 |
| `output[].summary[].text` | string | 推理摘要 |
| `output[].signature` | string | 推理签名 |
| `output[].encrypted_content` | string | 加密推理内容（ZDR 场景） |
| `usage.input_tokens` | int | 输入 token |
| `usage.output_tokens` | int | 输出 token |
| `usage.output_tokens_details.reasoning_tokens` | int | 推理 token |
| `usage.input_tokens_details.cached_tokens` | int | 缓存命中 token |
| `content_filters` | array | (Azure 扩展) 内容过滤结果数组 |

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
data: {"type":"response.output_item.added","output_index":1,"item":{"type":"message","id":"msg_abc","role":"assistant","phase":"commentary"}}

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
| `response.output_item.added` | 新 Item 开始（reasoning/message/function_call/内置工具调用） |
| `response.content_part.added` | 新 content part 开始 |
| `response.output_text.delta` | 文本增量 |
| `response.output_text.done` | 文本完成 |
| `response.reasoning_summary_text.delta` | 推理摘要增量 |
| `response.reasoning_summary_text.done` | 推理摘要完成 |
| `response.function_call_arguments.delta` | 函数参数增量 |
| `response.function_call_arguments.done` | 函数参数完成 |
| `response.file_search_call.search_result.delta` | 文件搜索增量 |
| `response.web_search_call.search_result.delta` | 网络搜索增量 |
| `response.computer_call.code.delta` | Computer Use 代码增量 |
| `response.compaction.upload` | 上下文压缩事件 |
| `response.completed` | 整个响应完成 |
| `error` | 错误（`server_error` / `too_many_requests` / `forbidden` / `user_error`） |

---

## 状态管理

### 1. previous_response_id 链式

```json
// 第一轮
POST /v1/responses
{"input": [{"role": "user", "content": "Hello"}], "store": true}
// 返回 {"id": "resp_1", ...}

// 第二轮 —— 传 previous_response_id，不传完整 history
POST /v1/responses
{"previous_response_id": "resp_1", "input": [{"role": "user", "content": "What's next?"}], "instructions": "..."}
```

### 2. Conversation 持久化

```json
POST /v1/responses
{"conversation": {"id": "conv_abc123"}, "input": [{"role": "user", "content": "Hello again"}]}
```

### 3. 手动状态（ZDR 兼容）

```json
// 完整 replay 所有 output item 到 input 中
POST /v1/responses
{
  "store": false,
  "input": [
    {"role": "user", "content": "Hello"},
    {"type": "reasoning", "id": "rs_1", "summary": [...], "signature": "...", "encrypted_content": "..."},
    {"role": "assistant", "content": [{"type": "output_text", "text": "Hello!"}], "phase": "final_answer"},
    {"role": "user", "content": "What's next?"}
  ]
}
```

### 4. 后台模式 (Background)

```json
// 启动
POST /v1/responses
{"background": true, "stream": false, "model": "gpt-5.2", "input": "复杂任务..."}
// 返回 {"id": "resp_123", "status": "in_progress", ...}

// 轮询
GET /v1/responses/resp_123
// 返回 {"id": "resp_123", "status": "completed", ...}

// 取消
DELETE /v1/responses/resp_123/cancel
```

### 5. 服务端压缩 (Compaction)

```json
// 自动压缩
POST /v1/responses
{
  "context_management": [{"type": "compaction", "compact_threshold": 180000}],
  "input": [...]
}
// 流中会出现 compaction item，之后可截断所有 pre-compaction items

// 独立压缩端点
POST /v1/responses/compact
{"model": "gpt-5.3-codex", "input": [...]}
// 返回新的压缩窗口，直接作为后续 input 使用
```

---

## Codex 特定字段

Codex 变体 (`openai-codex-responses`) 使用 `gpt-5.3-codex` 等 Codex 系列模型，新增以下字段：

### `phase` 字段（Codex 关键特性）

Codex 模型中，assistant message 可标记阶段标签，区分中间思考与最终答案：

| 值 | 含义 |
|----|------|
| `null` | 未分类（旧模型默认） |
| `"commentary"` | 中间思考、状态更新、前置说明 |
| `"final_answer"` | 当前轮次的最终回答 |

**重要：** 将 `phase` 持久化并在下一轮回放时保持原值，否则 Codex 模型性能会显著下降。

### Codex 推理设置

```json
{
  "reasoning": {
    "effort": "medium",
    "summary": "auto"
  }
}
```

| 推理力度 | 说明 |
|---------|------|
| `low` | 适合简单任务，快速响应 |
| `medium` | 默认，适合大多数任务 |
| `high` | 复杂推理任务 |
| `xhigh` | Codex 专属：极高推理深度 |

---

## Azure OpenAI 特定差异

### 端点格式

```
# Chat Completions（旧）
https://{resource}.openai.azure.com/openai/deployments/{deployment}/chat/completions?api-version=2024-12-01-preview

# Responses API（新）
https://{resource}.openai.azure.com/openai/v1/responses
```

- 使用 `OpenAI(base_url=f"{endpoint}/openai/v1/")` 替代 `AzureOpenAI()`
- 无需 `api_version` 参数
- `model` 值为模型部署名，非底层模型名

### Azure 特有扩展字段

| 字段 | 说明 |
|------|------|
| `response.content_filters` | 内容过滤结果数组（Azure 扩展，不在标准 OpenAI schema 中） |
| `response.content_filters[].blocked` | 是否被拦截 |
| `response.content_filters[].source_type` | 过滤源：`prompt` / `completion` |
| `response.content_filters[].content_filter_results` | 各分类过滤结果（hate/sexual/violence/self_harm/jailbreak） |
| `tools[]` 扩展 | Azure 额外支持 `azure_ai_search` / `openapi` / `bing_grounding` / `microsoft_fabric` 等工具 |
| `agent_reference` | Azure AI Agents 引用 |

### Azure 已知限制

- `max_output_tokens` 最小值 **16**
- 部分旧模型（gpt-4o, gpt-4）在 Responses API 上功能受限（不支持 `reasoning`、JSON Schema 不强制）
- GitHub Models (`models.github.ai`) 不支持 Responses API
- 带 streaming 的 background 模式存在性能问题
- 数据默认保留 30 天（可在 Azure 门户调整）

---

## 与 Lucent IR 的映射要点

| Responses | Lucent IR |
|-----------|-----------|
| `instructions` | `LucentRequest.instructions` |
| `input[?type=message].content[]` | `LucentContent::Text` / `Image`(stub) / `File`(stub) |
| `input[?type=function_call]` | `LucentContent::ToolUse` |
| `input[?type=function_call_output]` | `LucentContent::ToolResult` |
| `input[?type=reasoning]` | `LucentContent::Thinking` |
| `input[].phase` | `LucentMessage.phase`（Codex） |
| `tools[].function` | `LucentTool` |
| `max_output_tokens` | `LucentOptions.max_output_tokens` |
| `store` | `LucentOptions.store` |
| `reasoning.effort` | `LucentOptions.reasoning_effort` |
| `previous_response_id` / `conversation` | `LucentRequest.provider_state` |
| `context_management` | `LucentRequest.context_management` |
| `output[?type=message].content[?type=output_text]` | `LucentContent::Text` |
| `output[?type=function_call]` | `LucentContent::ToolUse` |
| `output[?type=reasoning].summary` | `LucentContent::Thinking` |
| `output[].phase` | `LucentMessage.phase`（Codex） |
| `output[].encrypted_content` | `LucentContent::EncryptedThinking` |
| `status` | `LucentFinishReason`（completed→Stop, incomplete→Length, failed→Error） |
| `usage` | `LucentUsage`（input_tokens→prompt_tokens） |
| `usage.output_tokens_details.reasoning_tokens` | `LucentUsage.thinking_tokens` |
| `content_filters` | (存入 `LucentResponse.provider_extensions`) |

### 关键差异 vs Chat Completions

1. **模型不同**：`input[]` 是 Item 数组而非 `messages[]`
2. **系统指令**：`instructions` 是顶层字段，不是 messages 的一部分
3. **推理思考**：原生支持 `reasoning` Item，有 `summary` 和 `signature`
4. **流式格式**：使用 SSE event 类型而非 delta 增量
5. **工具调用**：`function_call` 是独立 Item，不在 message 内部
6. **状态管理**：支持 `previous_response_id`、`conversation`、`context_management` 三种状态策略
7. **后台模式**：支持 `background: true` 异步执行 + 轮询
8. **Codex 变体**：新增 `phase` 字段（`commentary`/`final_answer`），`reasoning.effort` 支持 `xhigh`
9. **Azure 变体**：`content_filters` 扩展字段，工具列表更丰富，`model` 值为部署名
