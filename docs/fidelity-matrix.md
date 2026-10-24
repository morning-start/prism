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
`docs/api-protocol-converter.md`，全仓测试总数见 `docs/status.md`）：

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
| 全量帧覆盖（BlockDiscard） | ❌ 未实现 | ❌ 未实现 | ❌ 未实现 | ❌ 未实现 |

- **`BlockDiscard` 全链路无生产者**：IR 定义并序列化了该事件，但没有任何解码器
  会发出它（`src/provider/gemini/stream_decode.mbt` 明写"不做 full-frame diff、
  也不发 BlockDiscard"：Gemini 官方 chunk 的 `parts[].text` 本就是增量语义，
  "全量帧覆盖"这一前提不成立）。编码侧收到它只打 Degraded 诊断。本行因此从
  "✅ 已实现"更正为"❌ 未实现"——原论断描述的是一条不会被触发的路径。

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
  该不变量此前**只在纯文本 fixture 上成立**：流式编解码的跨帧状态
  （块→输出索引映射、跨帧累积的工具参数、块生命周期）位于 provider 的
  函数局部变量，逐帧调用即被重置 —— 工具调用场景下 `openai→responses`
  会丢失 `function_call_arguments.done`、`openai→gemini` 的 `args` 恒为 `{}`、
  混合流的 `content_block_stop` 与整批逆序。已由**流式会话化**修复：
  `@lux.LucentStreamEncoder` / `LucentStreamDecoder`（`src/lux/stream_codec.mbt`）
  让两条路径共享同一套跨帧状态机；回归见
  `src/sdk/test/stream_tool_equivalence_test.mbt`（17 用例，4 源 × 多目标）、
  `src/sdk/test/stream_session_isolation_test.mbt`（任意切分点 / 截断流 / 幂等 / 隔离）、
  `src/sdk/test/stream_semantic_test.mbt`（语义完整性，非仅两路径相等）。
- **出站请求**：目标为 openai-chat 且 `stream=true` 且调用方未提供 `stream_options`
  时，注入 `{"include_usage": true}`（OpenAI 仅在此时于末帧返回 usage；调用方显式
  提供时以其为准）。
- **终止符契约（CR-002）**：IR 流的终止符由会话层唯一产生 —— 解码器在流中途发出的
  `Done` 一律丢弃（Gemini 的帧级兜底 `Done` 会落在 usage / 后续内容之前），整缓冲路径
  在编码前补一个、逐帧路径在 `finish()` 补一个。因此下游**必须**调用
  `StreamConverter::finish()` 才能拿到尾部帧与终止符。
- 测试：`src/sdk/test/stream_usage_cr001_test.mbt`（T1.1–T1.4）+ 1 字节切分一致性；
  残余限制见 §4 第 5–8 条。

### 3.6 标准生成参数（LucentOptions）跨端保真度

> 本节为 2026-10-19 audit 新增。原矩阵未覆盖 `options` 内部字段的逐格保真度，
> 而实测发现 **11 个静默丢弃格**（标准字段在无载体目标上被整体丢弃且无诊断），
> 违反 AGENTS.md 硬规则「不支持的能力必须显式报错」。现已全部补齐诊断，
> 逐格断言见 `src/sdk/test/option_matrix_contract_test.mbt`。

图例：✅ Exact（目标原生字段） · 🟡 Degraded / ❌ Unsupported（**均带诊断，不再静默**）

| 字段 | → openai-chat | → responses | → messages | → gemini |
|---|---|---|---|---|
| temperature / top_p | ✅ | ✅ | ✅ | ✅（`topP`） |
| top_k | ❌ 诊断 | ❌ 诊断 | ✅ `top_k` | ✅ `topK` |
| max_output_tokens | ✅ `max_tokens` | ✅ `max_output_tokens` | ✅ `max_tokens` | ✅ `maxOutputTokens` |
| stop | ✅ `stop` | ❌ 诊断 | ✅ `stop_sequences` | ✅ `stopSequences` |
| stream | ✅ | ✅ | ✅ | ✅ 路径承载（Exact 诊断说明落点） |
| candidate_count | ✅ `n` | ❌ 诊断 | ❌ 诊断 | ✅ `candidateCount` |
| store | ✅ | ✅ | ❌ 诊断 | ❌ 诊断 |
| structured_output=JsonObject | ✅ | ✅ | 🟡 拓宽为 `{"type":"object"}` + 诊断 | ✅ |
| structured_output=JsonSchema | ✅ | ✅ | ✅ | ✅ `responseSchema` |
| structured_output=Text | ✅ | ✅ | ✅ | ❌ 诊断（Gemini 无显式 text 模式，默认即 text） |
| structured_output=Native | ❌ 诊断 | ❌ 诊断 | ❌ 诊断 | ❌ 诊断 |

修正的三处具体缺陷：

1. **`top_k` / `candidate_count` 静默丢弃**：二者是 **IR 标准字段**
   （`schemas/lux-ir-v1.json`），却只在能承载它们的 gemini（+ messages 的
   `top_k`）被编码，其余目标整体丢弃且无诊断。
2. **`n` ↔ `candidate_count` 语义未接**：OpenAI 官方 spec 对 `n` 的定义是
   "How many chat completion choices to generate for each input message"，
   与 IR `candidate_count` 同义，此前只落在 `extras` 里被原样透传（跨端时
   变成目标协议不认识的字段）。
3. **`messages` 的 `JsonObject` 伪造空 schema**：产出
   `{"type":"json_schema","schema":{}}`，而空对象**不是**合法 JSON Schema，
   上游会拒绝或退化为"必须返回空对象"。改为最宽合法形式
   `{"type":"object"}` 并打 Degraded 诊断。

判定依据为仓库内 vendored 的官方 OpenAPI
（`schemas/endpoints/openai-openapi.yaml`，MIT，version 2.3.0）：`CreateChatCompletionRequest`
含 `n`/`stop`，`CreateResponse` 含 `stop`/`n` 之外的 `max_output_tokens`，
二者均无 `top_k` —— 故 `top_k` 对 OpenAI 两个端点都按 Unsupported 诊断处理
（OpenAI 兼容网关如 vLLM 仍可在解码侧接受它，不拒绝）。

### 3.7 扩展通道的四个缺陷（跨协议出站）

IR 有两个扩展载体，文档语义不同（见 `docs/lux-ir-design.md`「扩展通道」）：

- `LucentRequest.extra` —— 程序作者**显式给定**的目标端扩展；作者知道目标是谁，
  出站时始终下发。
- `LucentOptions.extras` —— **解码侧**填充的源协议 wire 遗留
  （`schemas/lux-ir-v1.json` 对该字段的说明：「厂商私有扩展（软失败保留）」）；
  来源天然是源协议。

audit（2026-10-19 / 2026-10-22 两轮）共发现四个缺陷，均已修复：

1. **`request.extra` 是死载体（静默丢弃）**：4 个 request encoder 没有一个读
   `req.extra`，SDK 用户写入的扩展在出站 body 里完全不出现、也没有任何诊断。
   现 4 端均下发：gemini 落**请求体顶层**（请求级扩展位置：`safetySettings` /
   `cachedContent` / `toolConfig` 都在顶层），其余端同样落顶层。
2. **`extras` 跨端原样回写**：纯源协议专属、IR 无载体的键被回写到**任意**目标
   （openai 的 `seed` / `logit_bias` / `frequency_penalty` / `stream_options`；
   responses 的 `truncation` / `include` / `background`），目标收到不认识的字段
   会导致 400。现按**归属过滤**（规则见 §3.8）。
3. **键撞名 → 重复 JSON 键（结构非法）**：`merge_extras_json` 把 extras 直接
   字符串拼接在已编码片段之后，不检查键是否与 body 已有字段同名。同源配对即可
   复现：messages 源带 `disable_parallel_tool_use=true`（合法官方参数）→ 落入
   extras → 编码到 messages 目标时编码器自己也会发出该键 → 同一对象出现重复键
   （严格解析器拒绝、宽容解析器静默丢弃先前那个键）。已由
   `@internal.merge_extras_json_dedup` 修复：跳过撞名键并返回被跳过的键，
   调用方经 `@lux.push_extras_collisions` 补 Degraded 诊断。不安全的
   `merge_extras_json` 已删除，杜绝再被误用。
4. **IR 有载体却走 extras**：源协议 wire 字段若与 IR 标准字段同名同义
   （`top_k`、`n`），会落入 extras 并被原样回写到任意目标协议的请求体。
   现提升为标准字段，跨端时按 §3.6 处理。

回归见 `src/sdk/test/extras_duplicate_key_test.mbt` 与
`src/sdk/test/extension_channel_test.mbt`。

### 3.8 扩展通道的落点、优先级与归属过滤

| 维度 | `request.extra` | `options.extras` |
|---|---|---|
| 谁写 | 程序作者（显式） | 解码侧（自动保留） |
| 语义 | 目标端厂商扩展 | 源协议 wire 遗留（软失败保留） |
| 落点 | 请求体顶层 | 生成参数位（gemini 为 `generationConfig`） |
| 跨端过滤 | **不过滤**（作者对目标负责） | 只剔除「可证明属于其它协议」的键 |
| 未知键 | 原样下发 | 原样下发 |

优先级：**目标按 IR 编码出的字段 > `request.extra` > `options.extras`**。
任一方被覆盖或被剔除都留 Degraded / Unsupported 诊断，绝不静默；同名键在
body 里**只出现一次**（gemini 此前会把同名键分别写进 `generationConfig` 与顶层，
属语义歧义，已修）。

归属过滤的判定方向（实现与依据见 `src/internal/protocol_keys.mbt`）：

> 键 k 在目标 T 上被剔除 ⟺ k ∉ native(T) 且 ∃S≠T, k ∈ native(S)

刻意**不**采用「白名单内才放行」：

- 未知键（厂商私有键、未来新增字段）一律放行 → 同源往返（openai→openai 的
  `seed`、未来新参数）与厂商注入都不受影响；
- 表**漏项**只降低过滤强度、不会误丢数据；表**多列**才可能误丢，而每次剔除
  都带诊断、可被发现。

因此各表力求「该协议自己的顶层字段完备」。`openai` / `responses` 的原生表由
仓库内 vendored 官方 OpenAPI 按 `allOf`/`$ref` 展开得到（`CreateChatCompletionRequest`
/ `CreateResponse`）；`messages` / `gemini` 无 vendored spec，按公开 API 手工维护。

代价（**行为变更，中间件需知悉**）：同一份 IR 在不同目标下产出不同
diagnostics —— 例如 `seed` 转 openai/gemini 保留（gemini 落
`generationConfig.seed`），转 responses/messages 剔除并报 Unsupported。


### 3.9 响应侧（response）保真度 —— 六个静默缺陷

> 2026-10-22 audit 新增。前两轮矩阵都只覆盖**请求**侧（§3.6 生成参数、
> §3.7/§3.8 扩展通道），响应侧从未建过逐格断言。补建后实测发现 6 个缺陷，
> 全部是「目标协议无法承载 → 数据消失，且无诊断」，且**1354 个测试全绿**下长期
> 存在 —— 它们不是分支没覆盖，而是从没有断言问过这个问题。

| # | 目标 | 缺陷 | 现状 |
|---|---|---|---|
| 1 | openai | `finish_reason` 直接输出 IR 词表（`safety`/`recitation`/`malformed_tool_call`/`error`），**不是** OpenAI 的合法枚举 | 收敛为 `stop` + Unsupported 诊断 |
| 2 | responses | 官方 `RefusalContent` 键是 **`refusal`**，解码只读 `text` → 官方形态 refusal **整块静默丢弃** | 两种键都读，`refusal` 优先 |
| 3 | responses / messages | 单结果协议，`choices[1..]` 静默丢弃 | 补 Unsupported 诊断 |
| 4 | messages | `Safety`/`Recitation`/`MalformedToolCall`/`Error` 全压成 `end_turn`，**无诊断** | 保持收敛但补诊断 |
| 5 | gemini | 解码读 `thoughtsTokenCount`/`cachedContentTokenCount`，编码不写 → 往返丢数据（自相矛盾） | 编码侧对称写出 |
| 6 | gemini | `promptFeedback.blockReason`（提示词被整体拦截）一律返回 `Err`，blockReason 与 usage 全丢 | 转为 `finish_reason=Safety` 的空 choice + Degraded 诊断 |

其中 **#2 与 #5 是自相矛盾型**：编码产出的形态解码读不懂（#2），解码读取的
字段编码不写出（#5）。这类缺陷只能由**往返测试**发现，单向断言看不出来。

**判定依据**（均为仓库内 vendored 官方 OpenAPI，MIT）：
- `CreateChatCompletionResponse.choices[].finish_reason` 枚举仅
  `stop` / `length` / `tool_calls` / `content_filter` / `function_call`；
- `RefusalContent` = `{type: "refusal", refusal: <string>}`，`refusal` 为
  required 字段；
- Responses 的 `output` 是单一结果（无 candidate 概念）。

**一个刻意不诊断为缺陷的格子**：gemini 的 `ToolCalls → STOP`。Gemini 的
`FinishReason` 枚举没有「工具调用」项，模型发起函数调用时官方就返回 `STOP`，
属**语义对等**而非丢失。给它加诊断会让每次工具调用都报假 Unsupported，
故明确记录为「不诊断」并写进测试。

回归：`src/sdk/test/response_fidelity_test.mbt`。每个用例都做过
**反向验证**：临时回退修复后测试必须失败，避免写出「永远通过」的断言。

### 3.10 Responses 的 incomplete_details（响应侧第二轮补充）

vendored 官方 OpenAPI 的 **Response 级** `incomplete_details.reason` 枚举是
`max_output_tokens` / `max_messages` / `content_filter` / `steered` —— 注意与
Message 级枚举（`content_filter` / `max_tokens` / `run_cancelled` /
`run_expired` / `run_failed`）**不同**。此前解码只看 `status`，把
`incomplete` 一律压成 `Length`。

| 格子 | 此前 | 现状 |
|---|---|---|
| decode `reason=content_filter` | 压成 `Length`（内容过滤截断被报成「没写完」） | `ContentFilter` |
| decode `reason=max_output_tokens` / `max_messages` | `Length` | `Length`（不变） |
| decode `reason=steered` | `Length`（丢失） | `Native("steered")` 原样保留 |
| decode reason / incomplete_details 缺失 | `Length` | `Length`（保守默认，不变） |
| decode `status=failed` 的 `error` 对象 | **整体丢弃**，调用方不知道失败原因 | Degraded 诊断带出 code + message |
| encode `ContentFilter` | 落进 `_ => "completed"`（截断被报成**成功完成**） | `incomplete` + `reason=content_filter` |
| encode `Length` | 裸 `incomplete`（缺 reason） | 补 `reason=max_output_tokens` |
| encode `Native(s)` | 静默 `completed` | `completed` + Unsupported 诊断（responses 的 status 是封闭枚举，与 openai/messages/gemini 的自由字符串不同） |
| encode `ToolCalls` | `completed` | `completed`（**语义对等**：function_call item 承载工具调用，不诊断） |

往返闭环已断言：`incomplete+content_filter` → IR `ContentFilter` →
`incomplete+content_filter`，截断原因跨往返不退化。`reason=content_filter` 的
encode 侧做过反向验证。

### 3.11 `provider_payload`：响应侧扩展载体从死端改为归属门控

> 2026-10-22 audit（第四轮）新增。IR 的两个**请求**侧扩展通道（§3.8）修完
> 之后，**响应**侧的 `LucentResponse.provider_payload` 还是死端：openai 解码
> 把 `system_fingerprint` / `service_tier` 写进去，四个响应编码器却从不吐出
> —— `openai → IR → openai` 往返丢失响应级元数据，且无诊断。

**语义定位**：`provider_payload` 对称于请求侧的 `options.extras` —— 都是
「源协议 wire 上、IR 未建模字段的软失败保留载体」。因此出站采用**同一套归属
门控**（`@internal.split_provider_payload`，判定方向与 §3.8 一致）：

| 键类别 | 行为 |
|---|---|
| ∈ native_response(T) | 写出到目标响应体 |
| 可证明属于其它协议 | 剔除 + Unsupported 诊断（`provider_payload.<key>`） |
| 未知键（厂商网关自定义） | 放行 |
| `reasoning_field` 等编码旋钮 | **跳过** —— 它们是编码行为开关，不是 wire 数据，既不写出也不报诊断 |
| 与目标自产键撞名 | 跳过 + Degraded 诊断（目标自产值胜，绝不产生重复键） |

响应级原生表（`@internal.protocol_native_response_keys`，依据同 §3.8）：
openai = `system_fingerprint` / `service_tier` / `metadata` / `moderation`
（vendored `CreateChatCompletionResponse` 顶层）；responses = `moderation`
（`service_tier` 只出现在 CreateResponse **请求**侧）；messages = `container`、
gemini = `modelStatus`（无 vendored spec，手工维护）。

同步补齐的**解码侧捕获**：openai 增捕 `metadata` / `moderation`（此前只捕
2 个键）；responses 增捕 `moderation`（此前 `provider_payload` 恒为 `None`）。

一个实现注记：`Json::Object` 构造器对外只读，故解码侧沿用「拼串再
`parse_json_opt`」的模式把捕获值包回载体。

回归：`src/sdk/test/response_fidelity_test.mbt`（死载体往返、旋钮不外泄、
未知键放行、四目标撞名矩阵、原生键逐目标写出、responses 捕获 moderation；
死载体修复做过反向验证）。另见 `src/internal/test/protocol_keys_test.mbt`
的响应表锚定与旋钮跳过断言。

### 3.12 流式侧元数据扩展通道（`ConversationStart.extra`）

> 2026-10-23 audit（第五轮）新增。至此**请求侧**（`request.extra` /
> `options.extras`）与**响应侧非流式**（`provider_payload`）的扩展通道都已按
> 归属门控统一；流式侧的 `ConversationStart.extra` 是最后一块缺口。

四格实测形态（修复前）：

| 协议 | decode 填 extra | encode 读 extra |
|---|---|---|
| openai | 丢弃 `system_fingerprint` 等 → `None` | 不读 |
| responses | 全量保留（无归属判定） | **无门控**直接展开 |
| messages | 只填缓存计费项 | 不读 |
| gemini | `None` | 不处理 `ConversationStart` |

即：**openai/gemini 的元数据根本进不了 IR**（流式丢、非流式留，不一致）；
**responses 的元数据会原样泄漏到任意目标**（源协议的请求字段被写进
`response.created`）。

修复（与 §3.8 / §3.11 同一套判定方向，实现在
`src/provider/meta/extras.mbt` 的 `meta_extra_fragments` / `payload_fragments`）：

- decode：openai 补捕首帧 chunk 顶层的非建模字段；gemini 补捕首帧顶层
  （`modelStatus` 等）；messages 保留既有缓存计费项。
- encode：四端均按归属门控分拣后写出（openai/gemini 写**首帧顶层**，
  messages 写 `message_start`，responses 写 `response.created`）；
  外来键剔除 + Unsupported 诊断；与自产键撞名 → Degraded；旋钮跳过。

一个实现注记：判定需要 `@internal` 的归属表、诊断需要 `@lux` 的类型，
因此共享辅助放在 `provider/meta`（同时依赖两者的 provider 共享叶子包）——
`lux` 反向依赖 `internal` 会破坏分层。这是本轮唯一可行的落点。

回归：`src/sdk/test/stream_meta_channel_contract_test.mbt`（13 用例；responses
无门控泄漏与 openai decode 丢元数据两处均做过反向验证）。

**已知边界**：响应级原生表与请求级原生表是两套。一个**请求**侧字段
（如 responses 的 `parallel_tool_calls`）出现在元数据载体里时，会被判为
「未知键」而放行 —— 它对任何协议都不是**响应**原生字段。若要严格拦截，
需把两张表合并成「协议全部原生字段」并区分请求/响应上下文；当前选择放行，
因为放行的失败模式（目标多收一个请求语义的字段）轻于误丢，且未知键放行
本就是厂商兼容所需。

### 3.13 IR 流事件的生产者/消费者矩阵（第六轮）

> 2026-10-23 audit 新增。前几轮逐格检查了内容、文本、工具、帧序、生成参数、
> 扩展通道，但从未把 **IR 流事件 × provider 的生产者/消费者矩阵**整体铺开。
> 铺开后三类缺陷暴露：

| 事件 | 生产者（decode） | 消费者（encode） | 结论 |
|---|---|---|---|
| `BlockDiscard` | **0 家** | 4 家 | 死事件（CR-003 选 B，保留+标记） |
| `ItemEnd` | 1 家（responses） | 3 家 | **产消失衡**：官方帧被丢弃 |
| `Annotations` | **0 家** | 3 家 | **无生产者**：官方 citation 帧被丢弃 |
| `Error` | 2 家（responses / messages） | 4 家 | **openai 无生产者**：错误帧整帧丢弃 |

三类修复（全部先实测确认缺陷、后反向验证）：

1. **responses `output_item.done` → `ItemEnd`**：该帧携带 item 终态
   （`status` / 完整 content），此前被 `_ => ()` 丢弃。
2. **responses `output_text.annotation.added` → `Annotations`**：注解是引用
   来源（citation），此前整帧丢弃 → 流式路径 citation 全失。官方 `Annotation`
   是 four-way oneOf（`url_citation` / `file_citation` /
   `container_file_citation` / `file_path`，见 vendored OpenAPI），前两者映射
   IR 原生 kind，后两者退化 `Native(type)` 保留类型标签；`annotation: null`
   （官方 anyOf 含 null）不产出事件。
3. **openai 官方错误帧 → `Error`**：`data: {"error":{...}}` 不包 chunk 外壳，
   此前 openai 源整帧丢弃 → 流式错误链路断在解码侧（encode 侧与响应侧一直
   有 error 映射）。同时修 `LucentErrorKind::from_string`：官方 `error.type`
   常量带 `_error` 后缀（`rate_limit_error` 等）此前落到达 `Native` 字符串，
   未映射到语义 kind。

**两个由测试暴露的次生缺陷**（写测试时实测发现，一并修）：

- **openai / messages 错误帧的字符串形态被吞**：`obj_get(jv, "error")` 返回的
  是 **error 键的值本身**，`{"error":"boom"}` 的字符串值会落进对象分支，
  `field_str` 取不到 message/type → 退化成 `"unknown error"`，真正的错误文本
  被丢掉。修法：match 顺序改为 `String → 对象 → 缺失`。messages 侧一条既有
  测试原本断言 `"unknown error"`（把缺陷当预期），已修正。
- **messages 双 Finish 的 usage 重复发射**：`messages_pair_usages` 的
  `consumed[]` 不防重配对 —— 第二个 Finish 的 before 窗口回扫会取走已被
  上一个 Finish 用 after 窗口消费的 Usage，导致同一 usage 跟两个 Finish 各发
  一遍 `message_delta`。修法：before 窗口判 `consumed`。（after 窗口无需判：
  其上界是下一个 Finish，两窗口不重叠。）

顺带补齐 **`message_delta.usage.input_tokens`**：Anthropic 官方只保证
`output_tokens`，故历史上只发 output_tokens + 缓存项；但 IR 的 `prompt_tokens`
在跨协议转换（openai 源）时有值，不发即丢数据。改为有值时补发，字段序与官方
一致（`input_tokens` 在前）。

编码侧对应契约：四个 stream encoder 的 `Annotations` 分支从静默丢弃改为
显式 Degraded（openai / messages / responses / gemini 均无流式注解载体；
空数组不制造噪音诊断）。

回归：`src/sdk/test/stream_event_coverage_test.mbt`（16 用例；
`consumed` 防重与 `input_tokens` 两处均做过反向验证）。

## 4. 已知技术债（不影响上表论断，随 iteration 推进）

1. **ToolResult name carrier**：`LucentToolResult` 仅携带 `tool_use_id`，
   gemini `functionResponse.name` 需回查 ToolCall 重建 id→name 映射
   （`src/provider/gemini/request_encode.mbt` `build_tool_name_map`）；
   orphan tool result 走 Degraded 回退。IR 载体提案待治理
   （登记于 team-workspace/docs/00-需求池.md REQ-002）。
2. **reasoning.encrypted_content**（Responses 无状态推理续接凭据）无 IR
   载体，decode 打 Degraded 诊断。
3. **parallel_tool_calls 能力声明**与协议实际能力不一致（§1 注释）。
4. **ReasoningEffort 档位**：`minimal`（openai）与 `max`（anthropic）
   在跨端时降级到最近档位并打诊断。
5. **响应侧 `stop_sequence` 无 IR 载体**（2026-10-22 记录；**CR-005 已修复**）：
   Anthropic Messages 响应可返回 `stop_sequence`（实际命中的那条停止序列），
   OpenAI Chat 的 `stop` 只存在于**请求**。`LucentResponse` 当时没有承载
   「命中了哪条 stop 序列」的字段，`messages → IR → messages` 往返后
   `stop_sequence` 恒为 `null`。现 `LucentChoice.stop_sequence`（标准可选字段，
   CR-005）承载该事实：messages 源 decode 捕获、encode 写回并强制
   `stop_reason: "stop_sequence"`；跨三端 Unsupported 显式诊断。回归
   `src/sdk/test/stop_sequence_carrier_test.mbt`。流式侧载体见 CR-006 批次 2。

5. **裸解码仍带帧级 `Done`（有意保留，非缺陷）**：`wasm_sse_to_events` 与各 provider 的
   `events_decode` 不经会话层，Gemini 的帧级兜底 `Done` 仍出现在其返回值中。
   理由：①"本段输入处理完即发 Done"是四个解码器一致的既有契约；②裸解码是原语，
   替它发明会话级终止语义会与 `convert_stream` 的保证冲突。转换路径的终止符唯一性
   由会话层保证（见 §3.5）。**若要变更**：需先出 provider 契约提案（`events_decode`
   不再产 Done），并同步 4 个适配器 + wasm ABI 文档 + 全部 provider 测试。
6. **StreamConverter 的半帧依赖 `finish()`（有意保留，非缺陷）**：没有结束空行的尾部半帧
   只在 `finish()` 冲刷。理由：半帧只能由"上游流结束"这一外部信号驱动，转换器无法自行
   判定上游已断，猜测会引入静默截断风险。**正确用法**：宿主在 `finally` 中调用
   `conv.finish()`（幂等，见 CR-002 测试 6）。

> CR-002 修复了本节原先的第 5–8 条（Gemini 终止语义 / Gemini 流元信息 / messages 事件序
> 与缓存载体 / 截断流未闭合块），回归见 `src/sdk/test/stream_meta_cr002_test.mbt` 与
> [`cr/CR-002.md`](cr/CR-002.md)；CR-003 又补齐了 `message_start.output_tokens` 与
> Gemini 空流首帧（回归 `src/sdk/test/stream_meta_cr003_test.mbt`）。

7. **流式跨帧状态（已修复，记录根因）**：provider 的流式编解码原为"整批纯函数"，
   跨帧状态是函数局部变量。整批路径（一次传入整条事件数组）恰好保留状态，
   逐帧路径（`StreamConverter` 每帧一次调用）则每帧重置 —— 于是"增量 == 整批"
   仅在纯文本流上偶然成立。受影响的三个具体点：
   - `openai→responses`：`BlockEnd` 查不到块→item 映射与累积参数 →
     `function_call_arguments.done` **整体消失**、`item_id` 退化为 `item_N`、
     `output_item.done` 把 function_call item 收尾成 message item；
   - `openai→gemini` / `messages→gemini`：跨帧累积被打断 → `functionCall.args`
     恒为 `{}`（工具调用事实上不可用）；
   - `openai→messages`（混合流）：解码器丢失 `current_tool_block` → 工具索引
     切换时不再先补 `BlockEnd(旧)`，改由规整器在 Finish 处逆序补闭合 →
     `content_block_stop` 顺序与整批相反。
   修复方式见 §3.5 的会话化说明；`codec_pipeline.mbt` 的 `close_open_blocks`
   双实现已删除（整批路径改走同一 `EventNormalizer`）。

8. **契约文档端点口径**：`docs/api-protocol-converter.md` 标题为"三端点互转契约"
   （Chat / Responses / Messages），而实现含第四个适配器 Gemini；`AGENTS.md` 亦
   如此表述。形式化契约矩阵暂未给 Gemini 列 —— 切流评估以本矩阵的 §3.4 为准。

9. **`extras` 的跨端语义（已修复，2026-10-22）**：原状是「纯源协议专属、IR 无
   载体的字段被原样回写到任意目标协议的请求体」，例如 openai 的 `seed`、
   `logit_bias`、`frequency_penalty`、`stream_options`；responses 的
   `truncation`、`include`、`background`；目标收到不认识的字段可能 400。
   当时记录的三个候选方向：
   - A：出站时按目标的已知字段白名单过滤 extras，被剔除的键打 Unsupported 诊断；
   - B：给 extras 增加来源标记，仅回写到**同源**协议；
   - C：维持现状，由调用方自行保证目标可接受。

   **最终采用 A 的变体「证明为外来才剔除」**（判定式见 §3.8）：不引入 IR 结构
   变更（B 要给 extras 加来源标记，属 IR 变更、需走
   `docs/rules/lucent-ir-evolution.md` 治理流程），也不接受 C 的静默 400。
   与 A 原型的关键差异是判定方向反过来 —— 未知键一律放行，因此没有「白名单外
   一律丢弃」的副作用，同源往返与厂商私有键注入都不受影响。
   落地：`src/internal/protocol_keys.mbt`、4 个 request encoder、
   `src/sdk/test/extension_channel_test.mbt`；同一轮还修掉了 `request.extra`
   死载体（§3.7 缺陷 1）。

### 3.14 finish_reason 的协议枚举契约（第七轮）

> 2026-10-24 audit 新增。前几轮的保真度矩阵按「字段是否送达」检查，从未检查
> **「送达的值是否是该协议合法枚举」**。铺开这一维度后发现：流式编码器普遍
> 直接把 IR 词汇表写进出口，而非流式路径早已逐协议收敛 —— 同一协议两条路径
> 输出不同词汇表。

| 目标 | 流式（修复前） | 结果 |
|---|---|---|
| messages | `stop` / `length` / `tool_calls` / `safety` / `recitation` / `malformed_tool_call` / `error` / `content_filter` | **8/8 非法**（Anthropic 合法值是 `end_turn` / `max_tokens` / `tool_use` / `refusal` …）|
| openai | `safety` / `recitation` / `stop_sequence` / … | 非法（官方仅 5 值）|
| gemini | `Native(v)` → 兜底 `STOP` | **数据丢失**（同协议非流式是透传）|

典型危害：messages 流式的 `ToolCalls` 输出 `tool_calls`，而 Anthropic 的合法值
是 `tool_use`；messages 源解出的 `Native("stop_sequence")` 经 openai 流式出站会
变成 `"finish_reason":"stop_sequence"` —— 非 OpenAI 合法枚举，严格校验的对端
会**拒绝整条流**（不是降级，是协议契约破坏）。

修复（**第二版设计，见 [`design/finish-reason-contract.md`](design/finish-reason-contract.md)**）：
新增 `src/provider/meta/finish.mbt`，四个目标共用**目标白名单裁决**：

```text
candidate = 语义映射(fr)          # 建模值才有意义
value     = candidate ∈ legal(T) ? candidate : fallback(T)
diagnose  = 值不合法 || 有语义损失
```

**第一版是错的**，教训值得记录：它按 IR 枚举 match、`Native(s)` 无条件透传
—— 于是 `messages` 源解出的 `Native("pause_turn")`（Anthropic 合法）可以原样
溢进 openai 的 `finish_reason`。根因是**裁决方向错了**：

> 合法性是**目标槽位**的属性，不是 IR 值的属性。按 IR 枚举分支再给 `Native`
> 开透传口子，天然不可能封闭。

第二版让所有值（含 `Native`）统一过目标白名单，实测 7 种 Native × 3 目标
全部落在各自合法集合内：

| Native | messages | openai | gemini |
|---|---|---|---|
| `pause_turn` | ✅ 透传 | ✅→`stop` | ✅→`OTHER` |
| `LANGUAGE` | ✅→`end_turn` | ✅→`stop` | ✅ 透传 |
| `nft` | ✅→`end_turn` | ✅→`stop` | ✅→`OTHER` |

**第二个坑：诊断判据**。`responses` 的 `Safety → "failed"` —— `failed` 是合法
值，按「值被改动才报警」就不会报，但 IR 的 `Safety`（安全拦截）与 `Error`
（执行失败）共压成 `failed` 是有损的。故判据精确化为**信息损失**，而非「值
被改动」。三类：值不合法要报、值合法但共压要报、值合法且语义对等（如
`ToolCalls → STOP`）不报。

顺带纠正三处：
- gemini `ContentFilter` 由 `STOP` 改为 `SAFETY` —— 前者把「被拦截」伪装成
  「正常结束」，后者才是 Gemini 侧内容拦截的语义载体。
- responses 流式 `status` 此前把 `Safety`/`ContentFilter` 全落进
  `_ => "completed"`；现 `ContentFilter → incomplete` + `reason=content_filter`,
  其余按语义收敛并诊断。且非流式与流式**共用**同一函数（此前各写一份，已漂移）。
- 诊断键统一为**目标协议真实字段名**（`choices.stop_reason` /
  `candidates.finishReason` / `choices.status`），此前 messages 侧误用
  `choices.finish_reason`。

**IR 建模粒度不足（新发现，记为技术债）**：实测往返发现两处真实丢失 ——
1. `stop_sequence` 命中值无载体（CR-005 缺陷 A）——**已闭环**：响应侧由
   CR-005（`LucentChoice.stop_sequence`，0.1.x）落地；流式侧由 CR-006 批次 2
   （`Finish(reason, stop_sequence?)`，0.2.0）落地，累加器写进同一字段，
   流式累加与非流式解码共享同一词汇表（回归
   `src/sdk/test/stop_sequence_carrier_test.mbt`）；
2. **`function_call` vs `tool_calls`**：OpenAI 合法枚举里这是两个不同项，但
   IR 都映射到 `ToolCalls`，回程一律输出 `tool_calls` —— OpenAI → IR → OpenAI
   无法保住 `function_call`。**2026-10-24 重查修正定性**（[`cr/CR-007`](cr/CR-007-function-call-legacy.md)）：
   枚举退化只是次要面，主因是该形态的**工具体整体丢失**（非流式与流式都是
   静默丢内容、零诊断）——已修（CR-007 §1）；枚举区分度按非破坏性方案
   `LucentChoice.tool_call_style : String?` 提案中（CR-007 §2，待批准）。

回归：`src/sdk/test/finish_reason_contract_test.mbt`（7 用例）。
提案与完整分析见 [`cr/CR-005-stop-sequence-carrier.md`](cr/CR-005-stop-sequence-carrier.md)。

### 3.15 官方-null 输出形状（第八轮，conformance oracle [5] 组驱动）

> 2026-10-24 起 oracle [5] 组对四家目标做**完整官方 schema 校验**（此前
> responses/gemini 只查结构存在性）。升级当日实锤 3 类真实缺陷并修复；
> 本节记录由此确立的**出站形状契约**。

**确立的规则：required 槽位不得缺省 —— 有数据写数据，无数据写"官方-null/默认
值"，绝不编造具体事实。**

| 目标 | 缺陷（修复前） | 修复 |
|---|---|---|
| openai | 文本响应缺 `message.refusal`、`choices[].logprobs`（官方 schema required，缺失会被拒） | 恒写 `refusal:null` / `logprobs:null`（官方-null 形状，诚实表达"未拒绝/无数据"） |
| openai | IR 无时间戳时缺 `created`（required number） | 写 `0` 哨兵；解码把 0 归回 `None`，往返 IR 恒等 |
| responses | 缺成功态常量 `error`/`incomplete_details`/`metadata`（官方成功响应恒为 `null`/`null`/`{}`，依据 = vendored spec 内嵌真实样本 `fixtures/golden/responses-completed.json`） | 恒写 official-null 常量 |
| responses | 缺请求回显槽位 `instructions`/`temperature`/`top_p`/`tool_choice`/`tools`/`parallel_tool_calls`（required；真实 API 回显请求参数） | 按官方可空性写 null 或官方默认值（`tool_choice:"auto"`、`tools:[]`、`parallel_tool_calls:true`）——IR 响应模型不保留请求，**不编造回显内容**，SDK 侧残余差距在 oracle `lib.mjs` UPSTREAM_BUGS 逐字段登记 |
| responses | IR 无时间戳时缺 `created_at` | 写 `0` 哨兵；解码归回 `None`（与 openai 同规则） |
| gemini | oracle 侧 schema 选型错误：只有 Candidate 级，Prism 产出是信封 `GenerateContentResponse` | gen-schemas 增生成信封级 schema（`gemini-response.json`），实测信封直接通过，编码器无需改动 |

**判据**：这是形状合法性（会被 schema/API 拒绝的问题），不是语义保真问题——
所以归编码器修复而非豁免。豁免只留给"官方要求但 IR 无数据来源"的回显槽位
残余差距，且逐字段登记依据。

回归：`src/provider/openai/openai_wbtest.mbt`（official-null refusal/logprobs +
created 哨兵往返）、`src/provider/responses/responses_wbtest.mbt`（official-null
常量 + created 哨兵往返）、oracle `pipeline.mjs` 四目标完整 schema 矩阵。

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
