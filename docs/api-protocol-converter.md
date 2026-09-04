# API Protocol Converter — 三端点互转契约（正式版）

> 来源：`.agent-workplace/research/api-protocol-converter/SKILL.md`（研究草稿，
> gitignored）。本文档为**正式契约**，是 AGENTS.md / CLAUDE.md 引用的权威版本；
> 详细协议规范与 curl 用例仍在研究目录的 `references/` 中按需查阅。

Prism 在 Lucent IR 与三个 wire protocol（OpenAI `/v1/chat/completions`、
OpenAI `/v1/responses`、Anthropic `/v1/messages`）之间互转。
Adapter 位于 `src/provider/<name>/`，实现统一的 6-函数契约（见
[provider-guide.md](provider-guide.md)）。

## 核心原则

1. **不要写 6 组两两直连转换器**——先归一化到统一中间结构（Lucent IR），
   再从 IR 编码回目标端点
2. **对外永远是客户端期望的格式**，对内永远是目标 API 的原生格式
3. **不支持的能力必须显式报错**，不要静默吞掉
4. **先实现公共交集**（文本、工具调用、流式），再扩展高级能力

## 三端点快速对照

| 维度 | Chat Completions | Responses | Messages (Claude) |
|---|---|---|---|
| 端点 | `/v1/chat/completions` | `/v1/responses` | `/v1/messages` |
| 认证 | `Authorization: Bearer KEY` | `Authorization: Bearer KEY` | `x-api-key: KEY` |
| system 指令 | `messages[].role=system` | `instructions` | 顶层 `system` 字段 |
| 工具定义 | `tools[].function.parameters` | `tools[].parameters` | `tools[].input_schema` |
| 工具选择 | `"none"/"auto"/"required"/指定函数` | 同 Chat | `{type:none/auto/any/tool}` |
| 工具调用输出 | `message.tool_calls[]` | `output[].type=function_call` | `content[].type=tool_use` |
| 工具结果回填 | `role:"tool"` + `tool_call_id` | `function_call_output` | `role:"user"` + `tool_result` |
| 参数类型 | JSON 字符串 | JSON 字符串 | **对象** |
| 停止原因 | `finish_reason: stop/tool_calls/length` | `status: completed` | `stop_reason: end_turn/tool_use/max_tokens` |
| 流式格式 | `data: {chunk}` + `data: [DONE]` | `event: response.*` 系列 | `event: message_start/content_block_delta/message_stop` |

## 五大关键转换点

### 1. system 提取与放置

- Chat `role:system` / Responses `instructions` -> Messages 顶层 `system`
- Messages `system` -> Chat `role:system` / Responses `instructions`
- 多条 system 消息用 `\n\n` 合并

### 2. 工具定义映射

```jsonc
// Chat/Responses 平铺或嵌套形态
{"type": "function", "function": {"name": "get_weather", "parameters": {...}}}
// 或 Responses 形态
{"type": "function", "name": "get_weather", "parameters": {...}}
// -> Messages 形态
{"name": "get_weather", "input_schema": {...}}
```

关键：去掉 `type:"function"` 包装，`parameters -> input_schema`。

### 3. 工具调用与回填（最易出错）

```jsonc
// Chat 工具调用 -> Messages
{"role": "assistant", "tool_calls": [{"id": "call_1", "function": {"name": "get_weather", "arguments": "{\"city\":\"上海\"}"}}]}
// ->
{"role": "assistant", "content": [{"type": "tool_use", "id": "call_1", "name": "get_weather", "input": {"city": "上海"}}]}

// Chat 工具结果 -> Messages
{"role": "tool", "tool_call_id": "call_1", "content": "{\"temp\":26}"}
// ->
{"role": "user", "content": [{"type": "tool_result", "tool_use_id": "call_1", "content": "{\"temp\":26}"}]}
```

**硬规则：**

- `arguments`（字符串）<-> `input`（对象）：必须做 `JSON.parse/stringify`
- `role:tool` 不能直接传给 Claude，必须包进 `role:user` 的 `tool_result`
- Claude 顺序要求最严格：`assistant tool_use` 后必须紧跟 `user tool_result`
- 同一条 `user` 消息里，`tool_result` 排前面，文本排后面

### 4. tool_choice 映射

| 来源 | IR 统一值 | Chat | Responses | Messages |
|---|---|---|---|---|
| 不允许工具 | `{type:"none"}` | `"none"` | `"none"` | `{type:"none"}` |
| 自动选择 | `{type:"auto"}` | `"auto"` | `"auto"` | `{type:"auto"}` |
| 必须调用 | `{type:"required"}` | `"required"` | `"required"` | `{type:"any"}` |
| 指定函数 | `{type:"tool",name:"x"}` | `{type:function,name:x}` | `{type:function,name:x}` | `{type:"tool",name:"x"}` |

并行工具：Chat `parallel_tool_calls=false` <-> Messages `disable_parallel_tool_use=true`（语义反向）。

### 5. 流式事件互转

统一为 IR 流事件再编码，不要直接改字段。核心映射：

| IR 事件 | Chat SSE | Responses SSE | Messages SSE |
|---|---|---|---|
| `message_start` | `delta.role=assistant` | `response.output_item.added` | `event: message_start` |
| `text_delta` | `delta.content` | `response.output_text.delta` | `content_block_delta(text_delta)` |
| `tool_call_start` | `delta.tool_calls[{index,id,name}]` | `response.output_item.added(fc)` | `content_block_start(tool_use)` |
| `tool_call_arguments_delta` | `delta.tool_calls[{index,arguments}]` | `response.function_call_arguments.delta` | `content_block_delta(input_json_delta)` |
| `message_done(stop)` | `finish_reason=stop` + `[DONE]` | `response.completed` | `message_delta` + `message_stop` |
| `message_done(tool_calls)` | `finish_reason=tool_calls` + `[DONE]` | `response.completed` | `message_delta(tool_use)` + `message_stop` |

流式转换必须维护的状态：content block index、tool call index、已累计的
partial_json、当前 stop_reason。

## 最小测试矩阵（12 条验收标准）

至少覆盖以下 12 条才能宣称"三端互转已兼容"：

1. 纯文本，非流式
2. 纯文本，流式
3. 单工具调用，非流式
4. 单工具调用，流式参数增量
5. 多工具调用，非流式
6. 多工具调用，流式
7. assistant 文本 + tool call 混合输出
8. tool_result 回填后的第二轮继续回答
9. Claude 顺序错误时能正确报错
10. Responses 只有 `previous_response_id` 且无历史时能拒绝跨端转换
11. 非法 JSON arguments 时能明确报错
12. 未支持 output/content 类型时能明确报错

> 实现状态：12 条全部有直接测试覆盖（`src/provider/*/*_wbtest.mbt` 与
> `src/sdk/test/cross_protocol_test.mbt`，总数 812）。

## 不在第一版互转范围的内容

以下能力需要单独做能力分层，不要直接纳入公共交集：

- Responses 的内置工具、reasoning 项、MCP 专属项
- Messages 的 thinking、server tools、`pause_turn`
- 各端点的音频专属输出
- 各端点的 provider 专属实验字段
- `previous_response_id` 的跨端点续接（需要本地会话存储支持）

## 实现路线

1. Chat <-> Messages 非流式文本
2. Chat <-> Messages 非流式工具调用
3. Chat <-> Messages 流式文本
4. Chat <-> Messages 流式工具调用
5. Responses <-> IR 非流式
6. Responses <-> IR 流式
7. 最后补 Responses <-> Chat/Messages 完整链路
