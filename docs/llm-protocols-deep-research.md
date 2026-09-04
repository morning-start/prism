# LLM 协议深度研究：做法、协议要求与跨端转换

> 研究日期：2026-09-01
> 适用对象：Prism 协议转换层（OpenAI Chat / Responses ↔ Anthropic Messages ↔ Google Gemini）
> 数据来源：OpenAI / Anthropic / Google 官方文档与 API 参考，以及聚合网关（RouterHub、UniRouter、AnyInt）的实测行为。所有 URL 见文末「参考来源」。

---

## 0. 结论速览（给转换层的硬约束）

1. **传输层**：三家文本流式全部基于 **SSE（`text/event-stream`）**，HTTP 单向推送。但**流结束信号三者各不相同**：
   - OpenAI Chat：`data: [DONE]`
   - Anthropic：`event: message_stop`（命名事件，无 `[DONE]`）
   - Gemini：**无 `[DONE]`**，靠连接关闭 + 末块 `finishReason` 判定结束（部分网关会补 `[DONE]`，不可依赖）
2. **角色命名**：OpenAI 用 `assistant`；Gemini 用 `model`；Anthropic 不用 role 区分工具，而是用 content block 的 `type`。
3. **工具结果回填**：OpenAI `role:"tool"` → Gemini `role:"user"` + `functionResponse` part → Anthropic `role:"user"` + `tool_result` block。**这是转换最易错处**。
4. **参数形态**：OpenAI / Gemini 的工具参数 `arguments` / `args` 是 **JSON 字符串或对象**（聊天侧为字符串）；Anthropic 的 `input` 是**原生 JSON 对象**，必须 `parse/stringify` 互转。
5. **强约束字段**：
   - Anthropic `max_tokens` 是**必填顶层字段**（无默认值），转换 OpenAI→Anthropic 时必须补。
   - Gemini 角色只能是 `user` / `model`，且首条通常 `user`；`systemInstruction` 是独立字段。
   - OpenAI Responses 已**移除 `n` 参数**（单一生成），`store` 控制服务端存储。

---

## 1. 传输层：SSE 协议要求（公共地基）

所有主流 LLM 流式响应都遵循 SSE（Server-Sent Events，W3C 草案，2006 年即存在，比 WebSocket 早）。

### 1.1 协议格式要求

```
Content-Type: text/event-stream
Cache-Control: no-cache
Connection: keep-alive
```

每个事件：
- 以 `field: value` 行组成，字段间用 `\n` 分隔；
- 一个事件以**双换行 `\n\n`** 结束；
- `data:` 前缀承载载荷（最常见）；
- 可选 `event:`（命名事件类型）、`id:`（断线重连用）、`retry:`（重连间隔）；
- `:` 开头的行是注释，客户端忽略（常用于心跳保活）。

### 1.2 各家事件结构差异

| 维度 | OpenAI Chat | Anthropic Messages | Google Gemini |
|---|---|---|---|
| 事件命名 | 无 `event:`，纯 `data:` | **有 `event:` 命名**（如 `event: content_block_delta`） | 无 `event:`，纯 `data:`（每块即一个 `GenerateContentResponse`） |
| 数据形态 | `{"choices":[{"delta":{...}}]}` | `{"type":"...","index":0,"delta":{...}}` | `{"candidates":[{"content":{"parts":[...]}}]}` |
| 结束信号 | `data: [DONE]` | `event: message_stop` | **无**；连接关闭即结束 |
| usage 位置 | 需 `stream_options.include_usage=true`，末尾 chunk 带 `usage` | `message_start`（input）+ `message_delta`（output，累计） | 末块顶层 `usageMetadata` |
| 流保活 | 偶发注释行 | `event: ping` | 偶发注释行 |

> 工程要求：Prism 的 `LucentStreamEvent` 必须归一化掉「命名事件 / 裸 data / 有无 [DONE]」的差异，统一为 `message_start / text_delta / tool_call_*_delta / message_done` 等 IR 事件，再编码回目标格式。

---

## 2. OpenAI Chat Completions（`/v1/chat/completions`）

OpenAI 协议的「事实工业标准」，绝大多数国产模型（DeepSeek、Kimi、通义、智谱）与本地引擎（Ollama）均兼容。

### 2.1 请求要求

- `model`（必填）、`messages`（必填，数组）、`stream`（bool）。
- `messages[].role` ∈ `system | user | assistant | tool | developer`。
- 多模态时 `content` 由字符串变为 **数组** `content: [{type:"text",...},{type:"image_url",...}]`。
- 工具：`tools:[{type:"function", function:{name, description, parameters(JSON Schema), strict?}}]`。
- `tool_choice`：`none | auto | required | {type:"function", function:{name}}`。
- `parallel_tool_calls`（bool，默认 true）。
- 流式 usage：`stream_options:{include_usage:true}`。

### 2.2 非流式响应

```json
{
  "id": "chatcmpl-xxx", "object": "chat.completion",
  "created": 1756315657, "model": "gpt-5.5",
  "choices": [{
    "index": 0,
    "message": {"role": "assistant", "content": "..."},
    "finish_reason": "stop"
  }],
  "usage": {"prompt_tokens": 20, "completion_tokens": 50, "total_tokens": 70}
}
```

### 2.3 流式 chunk（`data:` 前缀，结束于 `[DONE]`）

```json
data: {"id":"chatcmpl-xxx","object":"chat.completion.chunk","choices":[{"index":0,"delta":{"role":"assistant","content":""},"finish_reason":null}]}
data: {"id":"chatcmpl-xxx","choices":[{"index":0,"delta":{"content":"你"},"finish_reason":null}]}
data: {"choices":[{"index":0,"delta":{},"finish_reason":"stop"}],"usage":{...}}
data: [DONE]
```

`finish_reason` ∈ `stop | length | tool_calls | content_filter | function_call(废弃)`。

### 2.4 工具调用（Chat 侧）

模型返回 `assistant` 消息携带 `tool_calls`：

```json
{"role":"assistant","content":null,
 "tool_calls":[{"id":"call_1","type":"function",
   "function":{"name":"get_weather","arguments":"{\"city\":\"上海\"}"}}]}
```

回填工具结果（**独立 role**）：

```json
{"role":"tool","tool_call_id":"call_1","content":"{\"temp\":26}"}
```

> 注意 `arguments` 是 **JSON 字符串**。

---

## 3. OpenAI Responses API（`/v1/responses`）

OpenAI 的新一代原语（2025 起，官方推荐用于所有新项目），把 Chat Completions 与 Assistants 能力统一为一个 **agentic loop**。

### 3.1 与 Chat 的核心差异

| 维度 | Chat Completions | Responses |
|---|---|---|
| 输入单位 | `messages[]`（Message 数组） | `input`（字符串 或 Item 列表） |
| 系统指令 | `messages[].role=system` | 顶层 `instructions` |
| 输出单位 | `choices[].message` | `output[]`（Items，typed） |
| 多并行生成 | `n`（>1） | **已移除**（仅单生成） |
| 工具调用 | `message.tool_calls[]` | `output[].type=function_call` |
| 工具结果回填 | `role:"tool"` | `{type:"function_call_output", call_id, output}` |
| 服务端状态 | `store:false` 关闭 | `store`（默认 true），支持 `previous_response_id` 续接 |
| 流式 | `delta.*` chunk | **命名事件** `response.*`（见 3.3） |

### 3.2 请求示例

```json
POST /v1/responses
{
  "model": "gpt-5.6",
  "instructions": "You are a helpful assistant.",
  "input": [
    {"role":"user","content":[{"type":"input_text","text":"查上海天气"}]},
    {"type":"function_call","call_id":"call_1","name":"get_weather",
     "arguments":"{\"city\":\"上海\"}"},
    {"type":"function_call_output","call_id":"call_1","output":"{\"temp\":26}"}
  ],
  "tools": [{"type":"function","name":"get_weather",
    "parameters":{"type":"object","properties":{"city":{"type":"string"}},"required":["city"]},
    "strict":true}],
  "store": true
}
```

### 3.3 流式事件（命名 SSE 事件）

关键事件（已验证 2026 实际行为）：

| 阶段 | 事件 | 关键字段 |
|---|---|---|
| 生命周期 | `response.created / in_progress / completed / incomplete / failed` | `response` 对象、`sequence_number` |
| 文本 | `response.output_item.added` → `response.output_text.delta` → `response.output_text.done` → `response.output_item.done` | `item_id, output_index, content_index, delta, text` |
| 函数工具 | `response.output_item.added (function_call)` → `response.function_call_arguments.delta` → `response.function_call_arguments.done` | `item_id, name, arguments (JSON 字符串)` |
| 自定义工具 | `response.custom_tool_call_input.delta / .done` | `item_id, input` |
| MCP 工具 | `response.mcp_call_arguments.delta / .done / .in_progress / .completed / .failed` | `item_id, server_label` |
| 推理摘要 | `response.reasoning_summary_text.delta / .done` | 与私有 CoT 分离的可展示摘要 |
| 内置工具 | `response.web_search_call.*` / `response.file_search_call.*` / `response.code_interpreter_call.*` / `response.image_generation_call.*` | 各自状态事件 |

> 工程要求：Responses 事件带 `sequence_number` 和 `output_index`，转换层必须维护 item 缓冲与顺序，不能简单按到达顺序拼文本。Prism 当前第一版互转**明确排除**内置工具、reasoning 项、MCP 专属项（见 `docs/api-protocol-converter.md`「不在第一版互转范围的内容」）。

### 3.4 内置工具（Responses 独有，非公共交集）

`web_search`、`file_search`、`computer_use`、`code_interpreter`、`image_generation`、`remote MCP servers`、`shell`、`skills`。这些在跨协议转换时属于**能力缺失（Unsupported）**，必须显式报错，不能静默丢弃。

---

## 4. Google Gemini API（`generateContent` / `streamGenerateContent`）

Gemini 使用 `contents[].parts[]` 结构，**没有 messages 数组概念**，角色用 `user` / `model`。

### 4.1 端点

```
POST https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent
POST https://generativelanguage.googleapis.com/v1beta/models/{model}:streamGenerateContent?alt=sse
认证：URL 参数 ?key= 或 Header x-goog-api-key / Authorization: Bearer
```

### 4.2 非流式请求/响应

```json
{
  "contents": [
    {"role":"user","parts":[{"text":"你好"}]},
    {"role":"model","parts":[{"text":"你好！有什么可以帮你？"}]}
  ],
  "systemInstruction": {"parts":[{"text":"You are a helpful assistant."}]},
  "generationConfig": {"temperature":0.7,"maxOutputTokens":1024},
  "safetySettings": [{"category":"HARM_CATEGORY_DANGEROUS_CONTENT","threshold":"BLOCK_MEDIUM_AND_ABOVE"}]
}
```

响应（注意 `candidates[].content.parts[]`，role 是 `"model"`）：

```json
{"candidates":[{"content":{"role":"model","parts":[{"text":"你好！..."}]},"finishReason":"STOP","index":0}],
 "usageMetadata":{"promptTokenCount":11,"candidatesTokenCount":50,"totalTokenCount":61},
 "modelVersion":"gemini-2.5-pro"}
```

### 4.3 流式 SSE（**无 [DONE]**）

```
data: {"candidates":[{"content":{"role":"model","parts":[{"text":"Hel"}]}}],"modelVersion":"gemini-2.5-pro"}
data: {"candidates":[{"content":{"role":"model","parts":[{"text":"lo"}]}}],"modelVersion":"gemini-2.5-pro"}
data: {"candidates":[{"content":{"role":"model","parts":[{"text":"!"}]},"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":5,"candidatesTokenCount":3,"totalTokenCount":8}}
```

完成判定：**末块携带 `finishReason`**（`STOP | MAX_TOKENS | SAFETY | OTHER`），连接随后关闭。部分网关（如 opencode 反向代理）会补 `[DONE]`，但**原生 Gemini 不保证**，客户端应以「连接关闭 / 末块 finishReason」为准。

> 关键差异：**Gemini 默认不增量流式工具参数**——`functionCall` 作为完整 part 一次性给出（除非请求 `stream_function_call_arguments:true`）。这与 OpenAI/Anthropic 的增量 `arguments.delta` 行为不同，转换层需特殊处理。

---

## 5. Anthropic Messages API（`/v1/messages`）

Prism 的第三个目标端点。结构最严格（顺序、必填字段、content block 模型）。

### 5.1 请求要求（强约束）

- **`max_tokens` 必填顶层字段**（无默认值，缺失即 400）。
- `system` 是**顶层独立字段**，不是 messages 里的 role。
- `messages[].content` 是 **content block 数组**（`type: text | image | tool_use | tool_result | thinking`）。
- 顺序强制：首条必须 `user`；`user` 与 `assistant` 必须**严格交替**；`assistant(tool_use)` 后必须紧跟 `user(tool_result)`。
- 认证：`x-api-key` + `anthropic-version: 2023-06-01`。

```json
POST /v1/messages
{
  "model":"claude-sonnet-4-7","max_tokens":1024,
  "system":"You are a helpful assistant.",
  "messages":[
    {"role":"user","content":[{"type":"text","text":"查上海天气"}]},
    {"role":"assistant","content":[{"type":"tool_use","id":"call_1","name":"get_weather","input":{"city":"上海"}}]},
    {"role":"user","content":[{"type":"tool_result","tool_use_id":"call_1","content":"{\"temp\":26}"}]}
  ],
  "tools":[{"name":"get_weather","description":"获取天气","input_schema":{"type":"object","properties":{"city":{"type":"string"}},"required":["city"]}}]
}
```

### 5.2 流式 SSE（命名事件）

顺序：`message_start` → 每个 content block 的 `content_block_start` → 若干 `content_block_delta` → `content_block_stop` → 若干 `message_delta` → `message_stop`。可穿插 `ping`。

工具参数增量（`input_json_delta` 携带 `partial_json` 字符串片段，需累积到 block 结束再 `json.loads`）：

```
event: content_block_start
data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"toolu_1","name":"get_weather"}}

event: content_block_delta
data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"city\":"}}

event: content_block_delta
data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"\"上海\"}"}}

event: content_block_stop
data: {"type":"content_block_stop","index":1}

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{"output_tokens":15}}

event: message_stop
data: {"type":"message_stop"}
```

`stop_reason` ∈ `end_turn | tool_use | max_tokens | stop_sequence | pause_turn`。
`tool_choice`：`{type: none|auto|any|tool}`；`disable_parallel_tool_use`（bool，与 OpenAI `parallel_tool_calls` **语义反向**）。

---

## 6. 工具调用（Tool Calling）跨协议要求对照

### 6.1 定义映射

| 项目 | OpenAI Chat | OpenAI Responses | Gemini | Anthropic |
|---|---|---|---|---|
| 工具定义包装 | `tools[].function.parameters` | `tools[].name + parameters` | `tools[].functionDeclarations[].parameters` | `tools[].input_schema` |
| Schema 规范 | JSON Schema（支持 `strict`） | JSON Schema（`strict`） | **OpenAPI 3.0** Schema（`type` 用大写 `STRING/OBJECT/...`） | JSON Schema |
| 调用触发控制 | `tool_choice: none/auto/required/指定` | 同 Chat | `functionCallingConfig.mode: AUTO/NONE/ANY` + `allowed_function_names` | `tool_choice: {type:none/auto/any/tool}` |
| 强制调用 | `required` | `required` | `mode:ANY` | `type:any` |
| 并行控制 | `parallel_tool_calls`（默认 true） | 同 | 并行默认支持（多 functionCall part） | `disable_parallel_tool_use`（默认 false） |

### 6.2 调用与回填映射（转换核心）

```
模型输出工具调用：
  OpenAI Chat : assistant.tool_calls[] = [{id, type:"function", function:{name, arguments:"<json字符串>"}}]
  OpenAI Resp : output[] item {type:"function_call", call_id, name, arguments:"<json字符串>"}
  Gemini      : model content part {functionCall:{name, args:<json对象>}}
  Anthropic   : assistant content[] block {type:"tool_use", id, name, input:<json对象>}

工具结果回填：
  OpenAI Chat : {role:"tool", tool_call_id, content:"<json字符串>"}
  OpenAI Resp : {type:"function_call_output", call_id, output:"<json字符串>"}
  Gemini      : {role:"user", parts:[{functionResponse:{name, response:<json对象>}}]}
  Anthropic   : {role:"user", content:[{type:"tool_result", tool_use_id, content}]}
```

### 6.3 转换硬规则（Prism IR 必须保证）

1. `arguments`(字符串) ↔ `input`/`args`(对象)：必须做 `JSON.parse / JSON.stringify`。
2. `role:"tool"` 不能直接传给 Gemini / Anthropic，必须包成各自的结构。
3. Gemini `functionResponse.response` 与 Anthropic `tool_result.content` 都是**对象**，而 OpenAI 的 `tool` content 是**字符串**——注意双层序列化陷阱。
4. Gemini 流式默认不增量工具参数；若要逐字流式，需 `stream_function_call_arguments:true`，且转换层要能合并。
5. `thought_signature`（Gemini 多步工具）需随下一轮回传以维持上下文——转换到无此概念的目标端时作为扩展字段（extension）保留或丢弃并告警。

---

## 7. 多模态（Multimodal）输入编码要求

三家共识：**文本转多模态时，content 从字符串变为有序的「part 数组」**，顺序有意义（图在前、问在后 vs 问在前、图在后 是不同输入）。图片只出现在 **user 轮**。

| 项目 | 图片载体字段 | base64 形态 | MIME 处理 | 特殊字段 |
|---|---|---|---|---|
| OpenAI | `content[].image_url.url` | **必须带 `data:image/png;base64,` 前缀**（裸 base64 报错） | 前缀内嵌 | `detail: low/high/auto`（控制分辨率与 token 成本） |
| Anthropic | `content[].image.source.data` | **裸 base64（无前缀）**，前缀会被拒 | 独立 `media_type` 字段 | 另支持 `type:"url"`；PDF 用 `document` 类型 |
| Gemini | `parts[].inline_data.data` | **裸 base64（无前缀）** | 独立 `mime_type` 字段 | JS SDK 用驼峰 `inlineData`/`mimeType`；大文件用 `file_data{file_uri}` 引 GCS |

**最常见的转换 bug**：拆分 `data:` URL 时忘记解析逗号前的 MIME 类型，导致目标端声明类型错误被拒。Prism 转换层应：
- OpenAI→其他：剥离/解析 `data:` 前缀，拆出 MIME + 裸 base64；
- 其他→OpenAI：把独立 MIME + 裸 base64 拼成 `data:<mime>;base64,<data>`；
- 音频：OpenAI 用 `input_audio{base64, format}`；Gemini 用 `inline_data` 带 `audio/` MIME；Anthropic 用 `audio` source（较新能力）。
- 视频：Gemini 原生支持 `video/` MIME 与 GCS `file_uri`；OpenAI/Anthropic 多模态输入以图像为主，视频常走文件/外部方式。

---

## 8. 流式事件互转要求（Prism IR 设计）

统一 `LucentStreamEvent` 后再编码，不要直接改字段。核心映射：

| IR 事件 | OpenAI Chat SSE | OpenAI Responses SSE | Anthropic SSE | Gemini SSE |
|---|---|---|---|---|
| `message_start` | `delta.role=assistant`（首块） | `response.output_item.added` | `event: message_start` | 首块 candidates |
| `text_delta` | `delta.content` | `response.output_text.delta` | `content_block_delta(text_delta)` | parts[].text |
| `tool_call_start` | `delta.tool_calls[{index,id,name}]` | `response.output_item.added(fc)` | `content_block_start(tool_use)` | functionCall part（整体） |
| `tool_call_arguments_delta` | `delta.tool_calls[{index,arguments}]` | `response.function_call_arguments.delta` | `content_block_delta(input_json_delta)` | 仅 `stream_function_call_arguments:true` 时增量 |
| `message_done(stop)` | `finish_reason=stop` + `[DONE]` | `response.completed` | `message_delta` + `message_stop` | 末块 `finishReason=STOP` |
| `message_done(tool_calls)` | `finish_reason=tool_calls` + `[DONE]` | `response.completed` | `message_delta(tool_use)` + `message_stop` | `finishReason` + functionCall |

**必须维护的状态**：content block index、`tool_call` index、已累计 `partial_json`、当前 `stop_reason`、各家 usage 的累计方式（Anthropic 在 message_delta 累计；OpenAI 末块；Gemini 末块顶层）。

---

## 9. 协议转换工程要求清单（给 Prism 的实现路线）

依据 `docs/api-protocol-converter.md` 的 6-函数契约与 12 例最小测试矩阵，落地时必须满足：

1. **先归一化到 Lucent IR，再编码**——不要写 N×(N-1) 组两两直连转换器。
2. **对外是客户端期望格式，对内是目标 API 原生格式。**
3. **不支持的能力显式报错**（内置工具、reasoning 项、MCP 专属、音频专属、provider 实验字段）——勿静默丢弃。
4. **扩展字段（extension）永远可选**：反序列化遇到未知扩展字段不得失败，应降级（丢弃或经 `extra`/`provider_payload` 保留）+ 发 `ConversionDiagnostic`。
5. **每个不支持/降级字段发 `ConversionDiagnostic`**（Exact / Degraded / Unsupported 保真度分级）。
6. **顺序校验**：Anthropic 要求 user/assistant 严格交替、tool_use 后紧跟 tool_result——顺序错误必须显式报错（测试矩阵 #9）。
7. **必填字段补齐**：OpenAI→Anthropic 必须补 `max_tokens`；Gemini 角色必须映射为 `user`/`model`。
8. **流式边界处理**：正确处理三家不同的结束信号（`[DONE]` / `message_stop` / 连接关闭 + `finishReason`）。
9. **partial_json 合并**：OpenAI/Anthropic 工具参数增量需累积到 block 结束再解析；Gemini 默认整体。
10. **非法 JSON arguments 显式报错**（测试矩阵 #11）；未支持 content/output 类型显式报错（#12）。

---

## 10. 一页总览对比表

| 维度 | OpenAI Chat | OpenAI Responses | Gemini | Anthropic |
|---|---|---|---|---|
| 端点 | `/v1/chat/completions` | `/v1/responses` | `:generateContent` / `:streamGenerateContent` | `/v1/messages` |
| 认证 | `Bearer` | `Bearer` | `?key=` / `x-goog-api-key` | `x-api-key` + `anthropic-version` |
| 消息结构 | `messages[]` role 数组 | `input` Items | `contents[].parts[]` | `messages[].content[]` blocks |
| system | `role:system` | `instructions` | `systemInstruction` | 顶层 `system` |
| 角色名 | `assistant` | `assistant`（item 内） | `model` | 无 role，用 block type |
| 多生成 | `n` 支持 | **移除** | 单候选（candidates[0]） | 单消息 |
| 工具定义 | `function.parameters` | `parameters` | `functionDeclarations[].parameters` | `input_schema` |
| 参数格式 | JSON Schema(+strict) | JSON Schema(+strict) | OpenAPI 3.0 | JSON Schema |
| 调用输出 | `tool_calls[]`（字符串 args） | `function_call` item | `functionCall` part（对象 args） | `tool_use` block（对象 input） |
| 结果回填 | `role:tool` | `function_call_output` | `functionResponse` part | `tool_result` block |
| 流式协议 | SSE 裸 `data:` | SSE **命名事件** | SSE 裸 `data:` | SSE **命名事件** |
| 结束信号 | `[DONE]` | `response.completed` | **无**（连接关闭+`finishReason`） | `message_stop` |
| 必填强约束 | — | `store` 语义 | role∈{user,model} | **`max_tokens` 必填** |
| 多模态 | image_url(data URL+detail) | input_image / content parts | inline_data（裸 base64） | image.source（裸 base64 / url） |
| 推理/thinking | 部分模型 reasoning | `reasoning_summary` 事件 | `thought` part + `thoughtSignature` | `thinking` block + `signature` |

---

## 参考来源

- OpenAI Responses API 参考（Java/REST）：https://developers.openai.com/api/reference/java/resources/responses
- OpenAI 迁移到 Responses：https://developers.openai.com/api/docs/guides/migrate-to-responses/
- OpenAI Responses 流式事件社区指南：https://community.openai.com/t/responses-api-streaming-the-simple-guide-to-events/1363122
- OpenAI Function Calling 指南：https://platform.openai.com/docs/guides/function-calling
- OpenAI Chat 参考：https://developers.openai.com/api/reference/resources/chat/
- Azure OpenAI Responses（区域/模型清单）：https://learn.microsoft.com/en-us/azure/ai-foundry/openai/how-to/responses
- Gemini 流式（Chrome 文档，原生 SSE 无 [DONE]）：https://developer.chrome.com/docs/ai/streaming
- Gemini 聚合网关 SSE 行为（确认无 [DONE]）：https://doc.routerhub.ai/streaming.html
- Gemini Function Calling 参考（functionCall/Response/Config）：https://cloud-dot-devsite-v2-prod.appspot.com/vertex-ai/generative-ai/docs/model-reference/function-calling
- Gemini Function Calling 入门：https://googledevai-dot-devsite-v2-prod-3p.appspot.com/gemini-api/docs/generate-content/function-calling
- Gemini Live API（WebSocket 实时语音/视频）：https://www.datacamp.com/nl/tutorial/gemini-live-api
- Anthropic 流式文档：https://docs.anthropic.com/es/api/streaming
- Anthropic Messages SSE 事件序列与工具 JSON 坑：https://hivebook.wiki/wiki/anthropic-messages-api-streaming-sse-event-sequence-and-tool-json-gotchas
- 多模态图像输入三方对比：https://base64.dev/articles/base64-images-ai-vision ；https://dev.to/multigrid/mapping-image-and-file-inputs-between-chat-apis-2ic2
- SSE 标准与工程实践（字节）：https://youthcamp.bytedance.com/post/7661833071122464814
- SSE 格式（Cloudflare）：https://developers.cloudflare.com/agents/runtime/communication/http-sse
- LLM 流式跨提供商对比（TokenMix）：https://tokenmix.ai/blog/how-to-stream-ai-api-response
- 项目既有文档：`docs/llm-protocols-overview.md`、`docs/provider-guide.md`、`.agent-workplace/research/api-protocol-converter/SKILL.md` 及其 `references/`
