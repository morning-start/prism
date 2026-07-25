# Prism 协议适配规划

> 参考 OMP（Open Model Protocol）`custom-models` 文档，分析 LLM 厂商协议接口兼容性。

## 协议分组

7 种传输层归并为 **4 个独立协议接口**：

| 适配器 | 协议接口 | 包含的 OMP 传输层 |
|--------|---------|------------------|
| A | OpenAI Chat Completions | `openai-completions` |
| B | OpenAI Responses | `openai-responses`、`openai-codex-responses`、`azure-openai-responses` |
| C | Anthropic Messages | `anthropic-messages` |
| D | Google Gemini | `google-generative-ai`、`google-vertex` |

**分组原则：** 接口相同但仅提供商/认证/端点不同的，只需一个适配器实现。

## 4 个适配器的核心差异

| 维度 | Chat Completions | Responses | Anthropic Messages | Gemini |
|------|:---:|:---:|:---:|:---:|
| 消息模型 | `messages[]` 数组 | `input[]` Item 数组 | `messages[]` + `system` | `contents[]` 数组 |
| 系统指令 | 首条 system 消息 | `instructions` 字段 | 顶层 `system` 字段 | `systemInstruction` 字段 |
| 工具定义 | `tools[].function` | `tools[].function` | `tools[].input_schema` | `tools[].functionDeclarations` |
| 工具调用 | `tool_calls[]` 在 assistant 消息中 | `function_call` Item | `tool_use` content block | `functionCall` part |
| 工具结果 | `role: tool` + `tool_call_id` | `function_call_output` Item | `tool_result` content block | `functionResponse` part |
| 流式格式 | SSE delta 增量 | SSE event 事件 | SSE content_block 事件 | SSE chunk 增量 |
| 推理/思考 | 无原生支持 | `reasoning` Item | `thinking` content block | `thought` 字段 |
| 多模态 | `content` 数组含 `image_url` | `input_image` / `input_file` | `image` content block | `inlineData` / `fileData` part |
| 必填字段 | `model` | `model` | `model` + `max_tokens` | 无（全可选） |

## 文件索引

- [01 — OpenAI Chat Completions](./01-openai-completions.md)
- [02 — OpenAI Responses（含 Codex/Azure）](./02-openai-responses.md)
- [03 — Anthropic Messages](./03-anthropic-messages.md)
- [04 — Google Gemini（含 Vertex）](./04-google-gemini.md)