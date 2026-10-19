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

### 3.7 `extras` 透传的两个缺陷（跨协议出站）

- **键撞名 → 重复 JSON 键（结构非法）**：`merge_extras_json` 把 extras 直接
  字符串拼接在已编码片段之后，不检查键是否与 body 已有字段同名。同源配对即可
  复现：messages 源带 `disable_parallel_tool_use=true`（合法官方参数）→ 落入
  extras → 编码到 messages 目标时编码器自己也会发出该键 → 同一对象出现重复键
  （严格解析器拒绝、宽容解析器静默丢弃先前那个键）。已由
  `@internal.merge_extras_json_dedup` 修复：跳过撞名键并返回被跳过的键，
  调用方经 `@lux.push_extras_collisions` 补 Degraded 诊断。不安全的
  `merge_extras_json` 已删除，杜绝再被误用。回归见
  `src/sdk/test/extras_duplicate_key_test.mbt`。
- **IR 有载体却走 extras**：源协议 wire 字段若与 IR 标准字段同名同义
  （`top_k`、`n`），此前会落入 extras 并被原样回写到**任意**目标协议的请求体
  （目标不认识 → 可能 400）。现提升为标准字段，跨端时按 §3.6 处理。

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

9. **`extras` 的跨端语义（已部分修复，剩余属设计决策）**：`options.extras`
   的本意是"厂商私有扩展软失败保留"，但它同时被用作出站透传通道 ——
   源协议的 wire 专属字段会被**原样回写**到任意目标协议的请求体里。本次已处理
   两类：
   - 与 IR 标准字段同名同义的（`top_k` / `n`）→ 提升为标准字段（§3.6）；
   - 与目标自产键撞名的（`disable_parallel_tool_use` 等）→ 跳过并打诊断（§3.7）。

   **仍存在**：纯源协议专属、IR 无载体的字段（openai 的 `seed`、`logit_bias`、
   `frequency_penalty`、`stream_options`；responses 的 `truncation`、`include`、
   `background`）转出到其它协议时仍会被回写，目标收到不认识的字段可能 400。
   这**不是本次引入的缺陷**，但也不应继续沉默。可选方向（需治理决策，未在本次实施）：
   - A：出站时按目标的已知字段白名单过滤 extras，被剔除的键打 Unsupported 诊断；
   - B：给 extras 增加来源标记，仅回写到**同源**协议；
   - C：维持现状，但在 §3.7 明示"跨端透传 extras 需调用方自行保证目标可接受"。
   选 A/B 会让同一份 IR 在不同目标下产出不同 diagnostics，属行为变更，故留待决策。

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
