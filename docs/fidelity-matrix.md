# Prism 转换保真度矩阵（Fidelity Matrix）

> 版本：v1（2026-09-09，iteration-009 T9 产出，随 release 更新）
> 用途：中间件（场景 2）在把流量切到某条 provider 链路前，按本表评估
> 可接受的降级；每格论断均有测试编号可查。
> 保真度定义（`docs/rules/lucent-ir-evolution.md` §3）：
> **Exact** 完全对等 · **Degraded** 近似映射（打诊断） ·
> **Unsupported** 目标不支持（剔除+诊断，无历史时拒绝） · **Invalid** 格式错误（Err）

## 1. 能力声明底盘（各 provider `capability.mbt`）

| 能力 | openai-chat | responses | messages | gemini |
|---|---|---|---|---|
| tool_calling | Full | Full | Full | Full |
| parallel_tool_calls | Absent* | Absent* | Absent* | Full |
| reasoning | Full | Full | Full | Full |
| multimodal_input | Full | Full | Full | Full |
| structured_output | Full | Full | Full | Full |
| 输入模态 | Text, Image | Text, Image, Pdf | Text, Image | Text, Image, Audio, Video, Pdf |
| 输出模态 | Text | Text | Text | Text |

\* 声明为 Absent 但协议实际支持并行工具调用（extras 语义反传已实现双向测试）；
声明待修正，属已知技术债（不影响转换正确性）。

## 2. 公共交集（12 条最小矩阵）——**全格 Exact**

文本 / 工具调用 / 流式三大交集在全部 16 个 provider 配对（含自身往返）
上均为 Exact，逐条覆盖于 `src/provider/*/*_wbtest.mbt` 与
`src/sdk/test/cross_protocol_test.mbt`（12 条验收标准见
`docs/api-protocol-converter.md`，总数 812+）：

| # | 用例 | 保真度 |
|---|---|---|
| 1 | 纯文本非流式 | Exact |
| 2 | 纯文本流式 | Exact |
| 3 | 单工具调用非流式 | Exact |
| 4 | 单工具调用流式参数增量 | Exact |
| 5 | 多工具调用非流式 | Exact |
| 6 | 多工具调用流式 | Exact |
| 7 | assistant 文本 + tool call 混合 | Exact |
| 8 | tool_result 回填第二轮 | Exact |
| 9 | Claude 顺序错误报错 | Invalid（显式） |
| 10 | previous_response_id 无历史跨端 | Unsupported（显式拒绝） |
| 11 | 非法 JSON arguments 报错 | Invalid（显式） |
| 12 | 未支持 output/content 类型报错 | Unsupported（显式） |

配对矩阵（request / response / stream 三向各 16 格）由
`src/sdk/test/convert_matrix_test.mbt` 的 24 个配对测试覆盖。

## 3. 高级能力保真度（按 source → target）

图例：✅ Exact · 🟡 Degraded（打诊断） · ❌ Unsupported（剔除+诊断/拒绝）

### 3.1 responses（OpenAI Responses）

| 能力 | → responses | → openai-chat | → messages | → gemini |
|---|---|---|---|---|
| 文本/工具/流式 | ✅ | ✅ | ✅ | ✅ |
| previous_response_id | ✅（服务端续接） | ❌ 拒绝/剔除 | ❌ 拒绝/剔除 | ❌ 拒绝/剔除 |
| reasoning 项 | ✅ | 🟡  effort→reasoning_effort；thinking 块无载体 → Unsupported 诊断 | ✅（adaptive/enabled thinking） | 🟡 thinkingConfig；effort 档位降级 |
| reasoning.effort=minimal | 🟡 → Low（gpt-5 家族实际值保留于 extras 时） | 🟡 → Low + 诊断 | 🟡 → XHigh 附近档 | 🟡 → Low + 诊断 |
| structured_output | ✅ text.format | ✅ response_format | ✅ output_config.format | ✅ responseSchema |
| store | ✅ | ✅ | ❌ 诊断剔除 | ❌ 诊断剔除 |
| 内置工具/MCP 项（非 function kind） | ❌ 诊断剔除 | ❌ 诊断剔除 | ❌ 诊断剔除 | ❌ 诊断剔除 |
| 图像输入 | ✅ | ✅ | ✅ | ✅ |
| PDF 输入 | ✅ | ❌（File 内容无载体） | ❌ | ✅ |
| 音频/视频输入 | ❌ | ❌ | ❌ | ✅ |

### 3.2 openai-chat

| 能力 | → responses | → openai-chat | → messages | → gemini |
|---|---|---|---|---|
| 文本/工具/流式 | ✅ | ✅ | ✅ | ✅ |
| parallel_tool_calls（extras） | ✅ | ✅ | ✅ 语义反传（T3 修复） | ✅ |
| reasoning_effort | ✅ | ✅ | ✅ adaptive + output_config | 🟡 档位降级 |
| 消息级 reasoning_content | ✅ reasoning 项 | 🟡 透传 reasoning_content | ✅ thinking 块 | ✅ thoughts |
| response_format | ✅ | ✅ | ✅ output_config.format | ✅ responseSchema |
| store | ✅ | ✅ | ❌ | ❌ |
| 非 function 工具 kind | ❌ 诊断剔除 | ❌ 诊断剔除 | ❌ 诊断剔除 | ❌ 诊断剔除 |
| 图像输入 | ✅ | ✅ | ✅ | ✅ |
| 音频/视频/File 内容 | ❌ | ❌ | ❌ | ✅（gemini 入站模态最宽） |

### 3.3 messages（Anthropic）

| 能力 | → responses | → openai-chat | → messages | → gemini |
|---|---|---|---|---|
| 文本/工具/流式 | ✅ | ✅ | ✅ | ✅ |
| thinking + signature | ✅ reasoning 项 | ❌ signature 无载体（诊断）；effort 可映射 | ✅ | ✅ thoughts（signature 🟡） |
| disable_parallel_tool_use（extras） | ✅ | ✅ 语义反传 | ✅ | ✅ |
| 服务端工具（bash/code_execution 等非 function kind） | ❌ 诊断剔除 | ❌ 诊断剔除 | ✅ | ❌ 诊断剔除（gemini 仅 functionDeclarations） |
| 图像输入 | ✅ | ✅ | ✅ | ✅ |

### 3.4 gemini

| 能力 | → responses | → openai-chat | → messages | → gemini |
|---|---|---|---|---|
| 文本/工具/流式 | ✅ | ✅ | ✅ | ✅ |
| functionResponse.name | 🟡 id→name 回查表重建；orphan 时 Degraded 回退 | 🟡 同上 | 🟡 同上 | ✅ |
| 音频/视频输入 | ❌ | ❌ | ❌ | ✅ |
| thinking + thoughtSignature | ✅ | 🟡 部分载体 | ✅ | ✅ |
| 全量帧覆盖（BlockDiscard） | 🟡 语义近似 | 🟡 语义近似 | 🟡 语义近似 | ✅ |

### 3.5 流式 usage（token 计量，CR-001）

| 能力 | → responses | → openai-chat | → messages | → gemini |
|---|---|---|---|---|
| 流式 usage（输入 / 输出 / 缓存计费项） | ✅ | ✅ | ✅ | ✅ |

- **输入侧**：Anthropic 的 `message_start.usage.input_tokens` 与
  `cache_read_input_tokens` / `cache_creation_input_tokens` 现在会并入 `Usage` 事件
  （此前 `prompt_tokens` 恒 0、`total_tokens` 只含输出侧）。
- **帧序**：OpenAI 目标的 usage 帧必须早于 `data: [DONE]`；Gemini 源的 Done 收尾
  排在 usage 之后（此前 usage 落到 `[DONE]` 之后，客户端停止消费即丢用量）。
- **增量路径**：`StreamConverter` 逐帧输出与整缓冲 `convert_stream` 逐字节一致；
  Anthropic 源的 `message_stop` 帧不再产生第二个 `message_delta(usage: 0)`。
- **出站请求**：目标为 openai-chat 且 `stream=true` 且调用方未提供 `stream_options`
  时，注入 `{"include_usage": true}`（OpenAI 仅在此时于末帧返回 usage；调用方显式
  提供时以其为准）。
- **终止符契约（CR-002）**：IR 流的终止符由会话层唯一产生 —— 解码器在流中途发出的
  `Done` 一律丢弃（Gemini 的帧级兜底 `Done` 会落在 usage / 后续内容之前），整缓冲路径
  在编码前补一个、逐帧路径在 `finish()` 补一个。因此下游**必须**调用
  `StreamConverter::finish()` 才能拿到尾部帧与终止符。
- 测试：`src/sdk/test/stream_usage_cr001_test.mbt`（T1.1–T1.4）+ 1 字节切分一致性；
  残余限制见 §4 第 5–8 条。

## 4. 已知技术债（不影响上表论断，随 iteration 推进）

1. **ToolResult name carrier**：`LucentToolResult` 仅携带 `tool_use_id`，
   gemini `functionResponse.name` 需回查 ToolCall 重建 id→name 映射
   （`src/provider/gemini/request_encode.mbt` `build_tool_name_map`）；
   orphan tool result 走 Degraded 回退。IR 载体提案见
   `.agent-workplace/docs/report/`（待治理）。
2. **reasoning.encrypted_content**（Responses 无状态推理续接凭据）无 IR
   载体，decode 打 Degraded 诊断。
3. **parallel_tool_calls 能力声明**与协议实际能力不一致（§1 注释）。
4. **ReasoningEffort 档位**：`minimal`（openai）与 `max`（anthropic）
   在跨端时降级到最近档位并打诊断。

5. **Anthropic `message_start` 的 `output_tokens`**：编码器只输出 `input_tokens`
   （+ 缓存项），不含官方同时给出的 `output_tokens: 1`；属归一化差异，未修。
6. **Gemini 空流**：整段输入没有任何可解析帧时不发 `ConversationStart`，故
   `gemini→messages` 对退化空流不会有 `message_start`（仅异常/空流场景）。
7. **裸解码仍带帧级 `Done`**：`wasm_sse_to_events` 与各 provider 的 `events_decode`
   不经会话层，Gemini 的帧级兜底 `Done` 仍出现在其返回值中；自行拼装编码器的消费方
   需自己保证终止符唯一（`convert_stream` / `StreamConverter` 已保证）。
8. **StreamConverter 的半帧依赖 `finish()`**：没有结束空行的尾部半帧只在 `finish()`
   冲刷；宿主若异常终止而不调用 `finish()`，尾部内容与终止符都会缺失。

> CR-002 已修复本节原先的第 5–8 条（Gemini 终止语义 / Gemini 流元信息 /
> messages 事件序与缓存载体 / 截断流未闭合块），回归见
> `src/sdk/test/stream_meta_cr002_test.mbt` 与 [`cr/CR-002.md`](cr/CR-002.md)。

## 5. 使用建议（中间件切流前检查单）

1. 确认目标链路只依赖 §2 公共交集 → 任意切流，保真度 Exact。
2. 用到 §3 中标 🟡/❌ 的能力 → 开启诊断收集（T10 DiagnosticCollector），
   按租户统计降级率后再放量。
3. Responses 有状态续接（previous_response_id）转无状态端点 → 必须部署
   会话快照存储（T8 `convert_request_with_store`），否则第二轮必拒。
4. 音频/视频流量只能落在 gemini 链路；PDF 落在 responses/gemini 链路。

## 6. 维护规则

- 任何 IR/provider 变更影响上表论断时，同 commit 更新本表并引用新测试编号
- 每 release 前重跑 `moon test`，确认 12 条矩阵与配对矩阵全绿
- 本表是"敢不敢切流量"的决策依据：论断必须可追溯到测试，不允许无据断言
