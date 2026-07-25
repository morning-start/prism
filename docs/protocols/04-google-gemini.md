# Google Gemini 协议

> 端点：`POST /v1beta/models/{model}:generateContent`
> OMP 传输层：`google-generative-ai`、`google-vertex`
> 官方文档：https://ai.google.dev/api/generate-content

> **兼容性说明：** Vertex AI 和 Gemini public API 使用相同的 JSON 接口，仅端点 URL 和认证方式不同。Vertex 端点格式为 `https://{location}-aiplatform.googleapis.com/v1/projects/{project}/locations/{location}/publishers/google/models/{model}:generateContent`。

## 请求 (Request)

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
| `parts[].functionResponse.name` | string | — | 函数名 |
| `parts[].functionResponse.response` | object | — | 返回值（含 `name` 和 `content`） |
| `tools` | array | — | 工具定义 |
| `tools[].functionDeclarations` | array | — | 函数声明数组 |
| `tools[].functionDeclarations[].name` | string | **是** | 函数名 |
| `tools[].functionDeclarations[].description` | string | — | 函数描述 |
| `tools[].functionDeclarations[].parameters` | object | — | JSON Schema 参数（OpenAPI 子集） |
| `toolConfig.functionCallingConfig.mode` | enum | — | `AUTO` / `ANY` / `NONE` |
| `generationConfig` | object | — | 生成参数 |
| `generationConfig.temperature` | number | — | 0~2 |
| `generationConfig.topP` | number | — | 核采样 |
| `generationConfig.topK` | int | — | top-k 采样 |
| `generationConfig.maxOutputTokens` | int | — | 最大输出 token |
| `generationConfig.stopSequences` | array | — | 停止序列 |
| `generationConfig.candidateCount` | int | — | 候选数量 |
| `generationConfig.responseMimeType` | string | — | 响应 MIME 类型 |
| `generationConfig.responseSchema` | object | — | 结构化输出 Schema |
| `generationConfig.thinkingConfig` | object | — | 思考配置 |
| `generationConfig.thinkingConfig.thinkingBudget` | int | — | 思考 token 预算 |
| `generationConfig.thinkingConfig.includeThoughts` | bool | — | 是否返回思考内容 |
| `safetySettings` | array | — | 安全过滤配置 |

---

## 响应 (Response) — 非流式

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
  "modelVersion": "gemini-2.5-pro"
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
| `parts[].thought` | bool/string | 思考标识（true 表示该 part 是思考内容） |
| `candidates[].finishReason` | enum | `STOP` / `MAX_TOKENS` / `SAFETY` / `RECITATION` / `MALFORMED_FUNCTION_CALL` / `OTHER` |
| `candidates[].safetyRatings` | array | 安全评级 |
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

## 与 Lucent IR 的映射要点

| Gemini | Lucent IR |
|--------|-----------|
| `systemInstruction.parts[].text` | `LucentRequest.instructions`（LucentContent::Text） |
| `contents[?role=user/model].parts[].text` | `LucentContent::Text` |
| `contents[?role=user].parts[].inlineData` | `LucentContent::Image` |
| `contents[?role=user].parts[].fileData` | `LucentContent::Image` |
| `contents[?role=model].parts[].functionCall` | `LucentContent::ToolUse`（args → arguments_json） |
| `contents[?role=tool].parts[].functionResponse` | `LucentContent::ToolResult` |
| `tools[].functionDeclarations` | `LucentTool`（parameters → parameters_json） |
| `generationConfig.temperature` | `LucentOptions.temperature` |
| `generationConfig.maxOutputTokens` | `LucentOptions.max_output_tokens` |
| `generationConfig.topP` | `LucentOptions.top_p` |
| `generationConfig.stopSequences` | `LucentOptions.stop` |
| `candidates[0].content.parts[].text` | `LucentContent::Text` |
| `candidates[0].content.parts[].functionCall` | `LucentContent::ToolUse` |
| `candidates[0].content.parts[].thought` | `LucentContent::Thinking` |
| `finishReason: STOP` | `LucentFinishReason::Stop` |
| `finishReason: MAX_TOKENS` | `LucentFinishReason::Length` |
| `finishReason: SAFETY` | `LucentFinishReason::ContentFilter` |
| `usageMetadata.promptTokenCount` | `LucentUsage.prompt_tokens` |
| `usageMetadata.candidatesTokenCount` | `LucentUsage.completion_tokens` |

### 关键差异 vs 其他协议

1. **角色名不同**：`model` 而非 `assistant`，`tool` 而非 `tool`（相同）
2. **系统指令**：`systemInstruction` 是顶层对象，含 `role` + `parts`
3. **工具定义**：`tools[].functionDeclarations[]` 是数组嵌套，与 OpenAI 的 `tools[].function` 不同
4. **工具参数**：`args` 是 JSON 对象，非字符串
5. **工具结果**：`functionResponse.response` 含 `name` + `content`，非简单字符串
6. **`generationConfig`**：生成参数嵌套在 `generationConfig` 对象中
7. **思考模型**：`thought: true` 布尔标记，非独立 content block 类型
8. **安全设置**：`safetySettings` 是独立数组，`safetyRatings` 在响应中返回
9. **流式格式**：每行独立的 JSON 对象，非 OpenAI 的 delta 增量模型
10. **Vertex 差异**：JSON 接口相同，仅端点 URL 包含项目/位置路径，认证使用 GCP IAM