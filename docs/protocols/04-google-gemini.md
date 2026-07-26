# Google Gemini 协议

> 端点：`POST /v1beta/models/{model}:generateContent`
> OMP 传输层：`google-generative-ai`、`google-vertex`
> 官方文档：https://ai.google.dev/api/generate-content

> **兼容性说明：** Vertex AI 和 Gemini public API 使用相同的 JSON 接口，仅端点 URL 和认证方式不同。
> - Gemini Public：`https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent`
> - Vertex AI：`https://{location}-aiplatform.googleapis.com/v1/projects/{project}/locations/{location}/publishers/google/models/{model}:generateContent`
>
> **新增：** Gemini 3 系列推荐使用 **Interactions API**（`/v1beta/models/{model}:interact`），提供统一的 agent 交互接口和更完善的思考管理。

## 请求 (Request) — GenerateContent API

```json
{
  "systemInstruction": {
    "role": "system",
    "parts": [
      {
        "text": "You are a helpful assistant."
      }
    ]
  },
  "contents": [
    {
      "role": "user",
      "parts": [
        {
          "text": "Hello!"
        }
      ]
    },
    {
      "role": "model",
      "parts": [
        {
          "text": "Hi there! How can I help?"
        },
        {
          "functionCall": {
            "name": "get_weather",
            "args": {
              "city": "Beijing"
            }
          }
        }
      ]
    },
    {
      "role": "tool",
      "parts": [
        {
          "functionResponse": {
            "name": "get_weather",
            "response": {
              "name": "get_weather",
              "content": {
                "temp": 25
              }
            }
          }
        }
      ]
    }
  ],
  "tools": [
    {
      "functionDeclarations": [
        {
          "name": "get_weather",
          "description": "获取指定城市的天气",
          "parameters": {
            "type": "object",
            "properties": {
              "city": {
                "type": "string"
              }
            }
          }
        }
      ]
    }
  ],
  "toolConfig": {
    "functionCallingConfig": {
      "mode": "AUTO"
    }
  },
  "generationConfig": {
    "temperature": 0.7,
    "topP": 0.9,
    "topK": 40,
    "maxOutputTokens": 1024,
    "stopSequences": ["\n\n"],
    "candidateCount": 1,
    "responseMimeType": "text/plain",
    "responseSchema": {},
    "thinkingConfig": {
      "thinkingBudget": 1024,
      "includeThoughts": true
    }
  },
  "safetySettings": [
    {
      "category": "HARM_CATEGORY_HARASSMENT",
      "threshold": "BLOCK_MEDIUM_AND_ABOVE"
    }
  ]
}
```

### 请求字段说明

| 字段 | 类型 | 必填 | 说明 |
|------|------|:---:|------|
| `systemInstruction` | object | — | 系统指令 |
| `systemInstruction.role` | string | — | 固定 `"system"` |
| `systemInstruction.parts[]` | array | — | content part 数组 |
| `contents` | array | **是** | 对话内容数组 |
| `contents[].role` | enum | **是** | `user` / `model` / `tool` |
| `contents[].parts[]` | array | **是** | content part 数组 |
| `parts[].text` | string | — | 文本 |
| `parts[].inlineData` | object | — | 内联数据：`{mimeType, data}` |
| `parts[].fileData` | object | — | 文件数据：`{mimeType, fileUri}` |
| `parts[].functionCall` | object | — | 工具调用 |
| `parts[].functionCall.name` | string | — | 函数名 |
| `parts[].functionCall.args` | object | — | 函数参数（JSON 对象） |
| `parts[].functionResponse` | object | — | 工具调用结果 |
| `parts[].functionResponse.name` | string | — | 函数名（必须匹配对应 call） |
| `parts[].functionResponse.id` | string | — | 函数调用 ID（Gemini 3+ 必填） |
| `parts[].functionResponse.response` | object | — | 返回值（含 `name` 和 `content`） |
| `tools` | array | — | 工具定义 |
| `tools[].functionDeclarations` | array | — | 函数声明数组 |
| `tools[].functionDeclarations[].name` | string | **是** | 函数名 |
| `tools[].functionDeclarations[].description` | string | — | 函数描述 |
| `tools[].functionDeclarations[].parameters` | object | — | JSON Schema 参数（OpenAPI 子集/完整 JSON Schema） |
| `toolConfig.functionCallingConfig.mode` | enum | — | `AUTO` / `ANY` / `NONE` |
| `toolConfig.functionCallingConfig.allowedFunctionNames` | array | — | 限制可用函数名列表（`ANY` 模式下） |
| `generationConfig` | object | — | 生成参数 |
| `generationConfig.temperature` | number | — | 0~2（Gemini 3 系列不建议修改默认值） |
| `generationConfig.topP` | number | — | 核采样 |
| `generationConfig.topK` | int | — | top-k 采样 |
| `generationConfig.maxOutputTokens` | int | — | 最大输出 token |
| `generationConfig.stopSequences` | array | — | 停止序列 |
| `generationConfig.candidateCount` | int | — | 候选数量 |
| `generationConfig.responseMimeType` | string | — | 响应 MIME 类型（`text/plain` / `application/json`） |
| `generationConfig.responseSchema` | object | — | 结构化输出 Schema（JSON Schema 格式） |
| `generationConfig.thinkingConfig` | object | — | 思考配置（已弃用，改用 `thinking_level`） |
| `generationConfig.thinkingConfig.thinkingBudget` | int | — | 思考 token 预算（已弃用） |
| `generationConfig.thinkingConfig.includeThoughts` | bool | — | 是否返回思考内容 |
| `generationConfig.mediaResolution` | object | — | (Gemini 3+) 媒体分辨率控制 |
| `safetySettings` | array | — | 安全过滤配置 |

### Thinking 配置 — GenerateContent API

> **重要：** `thinkingConfig` + `thinkingBudget`（数值预算）已弃用，推荐使用 `thinking_level`（字符串枚举）。

```json
{
  "generationConfig": {
    "thinking_level": "medium"
  }
}
```

**不能同时使用 `thinkingBudget` 和 `thinking_level`**，否则返回 400。

| 力度 | 说明 | 适用场景 |
|------|------|---------|
| `minimal` | 最优响应速度，极简思考 | 聊天、快速问答、简单工具调用 |
| `low` | 降低延迟和成本 | 代码和 agent 任务、分析写作 |
| `medium` | 默认，最佳质量 | 大多数任务，复杂代码/agent 场景 |
| `high` | 最深推理，动态扩展思考 | 复杂推理、数学、最难的代码/agent 任务 |

### 多模态输入

```json
{
  "role": "user",
  "parts": [
    {"text": "Describe this image"},
    {
      "inlineData": {
        "mimeType": "image/png",
        "data": "iVBORw0KGgo..."
      }
    },
    {
      "fileData": {
        "mimeType": "application/pdf",
        "fileUri": "https://storage.googleapis.com/..."
      }
    }
  ]
}
```

---

## 响应 (Response) — GenerateContent API 非流式

```json
{
  "candidates": [
    {
      "content": {
        "role": "model",
        "parts": [
          {
            "text": "Hello! How can I help you today?"
          },
          {
            "functionCall": {
              "name": "get_weather",
              "args": {
                "city": "Beijing"
              }
            }
          },
          {
            "thought": true
          }
        ]
      },
      "finishReason": "STOP",
      "safetyRatings": [
        {
          "category": "HARM_CATEGORY_HARASSMENT",
          "probability": "NEGLIGIBLE"
        }
      ],
      "citationMetadata": {},
      "index": 0
    }
  ],
  "usageMetadata": {
    "promptTokenCount": 50,
    "candidatesTokenCount": 100,
    "totalTokenCount": 150,
    "thoughtsTokenCount": 30
  },
  "modelVersion": "gemini-3.5-flash"
}
```

### 响应字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| `candidates[]` | array | 候选回复数组 |
| `candidates[].content` | object | 回复内容 |
| `candidates[].content.role` | string | 固定 `"model"` |
| `candidates[].content.parts[]` | array | content part 数组 |
| `parts[].text` | string | 文本 |
| `parts[].functionCall` | object | 工具调用 |
| `parts[].functionCall.name` | string | 函数名 |
| `parts[].functionCall.args` | object | 函数参数（JSON 对象） |
| `parts[].thought` | bool/string | 思考标识（true 表示该 part 是思考内容） |
| `candidates[].finishReason` | enum | `STOP` / `MAX_TOKENS` / `SAFETY` / `RECITATION` / `MALFORMED_FUNCTION_CALL` / `OTHER` |
| `candidates[].safetyRatings` | array | 安全评级 |
| `candidates[].citationMetadata` | object | 引用元数据 |
| `usageMetadata.promptTokenCount` | int | 输入 token |
| `usageMetadata.candidatesTokenCount` | int | 输出 token |
| `usageMetadata.totalTokenCount` | int | 总计 token |
| `usageMetadata.thoughtsTokenCount` | int | 思考 token |
| `modelVersion` | string | 模型版本 |

---

## 流式响应 (SSE)

```
data: {"candidates":[{"content":{"role":"model","parts":[{"text":"Hello"}]}}]}

data: {"candidates":[{"content":{"role":"model","parts":[{"text":" world"}]}}]}

data: {"candidates":[{"content":{"role":"model","parts":[{"functionCall":{"name":"get_weather","args":{"city":"Beijing"}}}]}}]}

data: {"candidates":[{"content":{"role":"model","parts":[{"thought":true}]},"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":50,"candidatesTokenCount":100,"totalTokenCount":150}}
```

### 流式特点

- Gemini 流式格式为 SSE 行，每行一个 `data:` 前缀
- 每个 chunk 包含完整的 `candidates` 数组
- 文本是增量式返回，但 `functionCall` 是一次性完整返回
- `thought: true` 标识思考内容，思考文本可能在其他 part 中
- 最后一帧包含 `finishReason` 和 `usageMetadata`

---

## Interactions API（Gemini 3 系列推荐）

Gemini 3 系列模型（`gemini-3.5-flash`、`gemini-3.1-pro-preview` 等）推荐使用 Interactions API，提供统一接口和更完善的思考管理。

### 端点

```
POST /v1beta/models/{model}:interact
```

### 核心概念

- **Step**：交互中的最小单元，替代 GenerateContent 的 `part`
- **Thought step**：思考块，含 `signature`（加密签名）和 `summary`（摘要数组）
- **状态模式**：支持 stateless（显式传历史）和 stateful（`store: true` + `previous_interaction_id`）

### 思考块格式（Interactions API）

```json
{
  "type": "thought",
  "signature": "eqwBCkkI...",
  "summary": [
    {"type": "text", "text": "**Evaluating the clues**\n\nI'm considering..."}
  ]
}
```

### Thinking Level（Interactions API）

| 模型 | 默认 | 支持的 Level |
|------|------|-------------|
| gemini-3.5-flash | medium | minimal, low, medium, high |
| gemini-3.5-flash-lite | minimal | minimal, low, medium, high |
| gemini-3.1-pro-preview | high | low, medium, high |
| gemini-3-flash-preview | high | minimal, low, medium, high |
| gemini-3-pro-preview | high | low, high |

### 思考签名 (Thought Signatures)

- 必含 `signature` 字段，即使是简洁响应
- Stateful 模式自动管理签名
- Stateless 模式必须回放所有 thought block
- 内置工具（如 Google Search）也携带自己的签名

---

## 结构化输出 (Structured Outputs)

```json
{
  "generationConfig": {
    "responseMimeType": "application/json",
    "responseSchema": {
      "type": "object",
      "properties": {
        "title": {"type": "string"},
        "score": {"type": "integer"}
      },
      "required": ["title", "score"]
    }
  }
}
```

支持的 JSON Schema 特性：`object`、`string`、`number`、`integer`、`boolean`、`array`、`null`（type 数组）、`enum`、`anyOf`、`$ref`（递归 schema）、`additionalProperties`、`prefixItems`、`minItems`/`maxItems`、`minimum`/`maximum`、`format`。

---

## 与 Lucent IR 的映射要点

| Gemini | Lucent IR |
|--------|-----------|
| `systemInstruction.parts[].text` | `LucentRequest.instructions`（LucentContent::Text） |
| `contents[?role=user/model].parts[].text` | `LucentContent::Text` |
| `contents[?role=user].parts[].inlineData` | `LucentContent::Image` |
| `contents[?role=user].parts[].fileData` | `LucentContent::Image` / `File` |
| `contents[?role=model].parts[].functionCall` | `LucentContent::ToolUse`（args → arguments_json） |
| `contents[?role=tool].parts[].functionResponse` | `LucentContent::ToolResult` |
| `contents[?role=model].parts[].thought` | `LucentContent::Thinking` |
| `tools[].functionDeclarations` | `LucentTool`（parameters → parameters_json） |
| `generationConfig.temperature` | `LucentOptions.temperature` |
| `generationConfig.maxOutputTokens` | `LucentOptions.max_output_tokens` |
| `generationConfig.topP` | `LucentOptions.top_p` |
| `generationConfig.stopSequences` | `LucentOptions.stop` |
| `generationConfig.thinkingConfig.thinkingBudget` | `LucentOptions.thinking_budget`（已弃用） |
| `generationConfig.thinking_level` | `LucentOptions.reasoning_effort` |
| `generationConfig.responseSchema` | `LucentOptions.response_schema` |
| `generationConfig.mediaResolution` | `LucentOptions.media_resolution` |
| `toolConfig.functionCallingConfig.mode` | `LucentOptions.tool_choice` |
| `candidates[0].content.parts[].text` | `LucentContent::Text` |
| `candidates[0].content.parts[].functionCall` | `LucentContent::ToolUse` |
| `candidates[0].content.parts[].thought` | `LucentContent::Thinking` |
| `finishReason: STOP` | `LucentFinishReason::Stop` |
| `finishReason: MAX_TOKENS` | `LucentFinishReason::Length` |
| `finishReason: SAFETY` | `LucentFinishReason::ContentFilter` |
| `usageMetadata.promptTokenCount` | `LucentUsage.prompt_tokens` |
| `usageMetadata.candidatesTokenCount` | `LucentUsage.completion_tokens` |
| `usageMetadata.thoughtsTokenCount` | `LucentUsage.thinking_tokens` |

### 关键差异 vs 其他协议

1. **角色名不同**：`model` 而非 `assistant`，`tool` 角色与 OpenAI 相同
2. **系统指令**：`systemInstruction` 是顶层对象，含 `role` + `parts`
3. **工具定义**：`tools[].functionDeclarations[]` 是数组嵌套，与 OpenAI 的 `tools[].function` 不同
4. **工具参数**：`args` 是 JSON **对象**，非字符串
5. **工具结果**：`functionResponse.response` 含 `name` + `content`，非简单字符串
6. **`generationConfig`**：生成参数嵌套在 `generationConfig` 对象中
7. **思考模型**：GenerationConfig 中用 `thought: true` 布尔标记，Interactions API 中用 `thought` step
8. **`thinking_level` 替代 `thinkingBudget`**：推荐使用字符串枚举而非数值预算
9. **安全设置**：`safetySettings` 是独立数组，`safetyRatings` 在响应中返回
10. **流式格式**：每行独立的 JSON 对象，非 OpenAI 的 delta 增量模型
11. **Interactions API**：Gemini 3 系列推荐交互方式，含原生 thought step 支持
12. **Vertex 差异**：JSON 接口相同，仅端点 URL 包含项目/位置路径，认证使用 GCP IAM
