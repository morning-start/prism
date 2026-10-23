# IR 变更提案：`stop_sequence` 的 IR 载体（CR-005）

> 状态：**已决策并实施（选项 B）** —— 缺陷 A / B / C 全部修复。
> 提出：2026-10-23 · B/C 修复：2026-10-24 · A 实施：2026-10-24
> 依据：`docs/rules/lucent-ir-evolution.md` §2「影响面声明」、§4「标准 vs 扩展」、
> §6「非破坏性变更」
> 触发：第七轮审计（IR 字段级往返完整性）中发现 messages 源 `stop_sequence`
> 在 IR 中无载体，并顺带实证两条路径的行为矛盾与一个**非法枚举溢出**

## 0. 最终选型（2026-10-24）

在 A（`stop_sequence` 载体）与「`function_call` / `tool_calls` 区分度」两个
候选之间，**选 A**。依据：

| 维度 | A：`stop_sequence` | `function_call` 区分度 |
|---|---|---|
| 上游状态 | Anthropic **活跃功能** | OpenAI 官方 schema 标注 **`(deprecated)`** |
| 信息价值 | 区分「命中 END」与「模型自然说完」 | 保住一个正在淘汰的遗留值 |
| 结构冲击 | 加**可选字段**：`LucentChoice::new` 签名不变，88 处调用**零改动** | 加**枚举变体**：`LucentFinishReason` 有 35 处穷尽 match，**全部编译失败** |
| 治理类型 | 非破坏性（§6） | 破坏性（§5） |

`function_call` 那条记为技术债（见 §7），不实施 —— 为其加永久 IR 变体，
投入产出不匹配。

## 1. 现状事实（已实证）

### 1.1 三条独立缺陷，严重度递增

用探针实测 `stop_reason: "stop_sequence", stop_sequence: "END"` 的往返：

**缺陷 A（非流式）：命中序列被静默丢弃，且无诊断**

`src/provider/messages/response.mbt:20-27`：

```moonbit
let finish = match @internal.field_str(jv, "stop_reason") {
  Some("stop_sequence") => Stop      // ← 与 end_turn 收敛为同一个 IR 值
  ...
}
```

实测结果：

```
输入:  {"stop_reason":"stop_sequence","stop_sequence":"END"}
IR:    finish_reason = stop          （"命中自定义终止序列" 的信息丢失）
诊断:  0 条                          （连 Degraded 都没有）
回写:  {"stop_reason":"end_turn","stop_sequence":null}
```

即 messages → IR → messages 的往返把「被 `END` 截断」变成「模型自然说完」，
且 `stop_sequence` 恒写 `null`（`response.mbt:187`）。调用方无法区分这两种
语义完全不同的结束。

**缺陷 B（流式）：同一源值解出不同的 IR 值 —— 两条路径自相矛盾**

`src/provider/messages/stream_decode.mbt:186-198` 走的是通用
`LucentFinishReason::from_string("stop_sequence")`，而该函数（
`src/lux/helpers.mbt:245`）没有 `stop_sequence` 分支 → 落入 `Native(other)`。

实测同一份语义的两个入口：

| 路径 | IR `finish_reason` |
|---|---|
| `messages_to_lux_response`（非流式） | `Stop` |
| `messages_sse_to_events`（流式） | `Native("stop_sequence")` |

违反「流式与非流式必须解出同一 IR」这一本仓既有的等价性不变量。

**缺陷 C（流式 + openai 目标）：非法枚举值溢出到对端**

`openai` 流式编码（`src/provider/openai/stream_encode.mbt:161-167`）直接写
`fr.to_string()`，**绕过了非流式路径的 `openai_finish_reason` 收敛器**
（`src/provider/openai/response.mbt:101`，该函数明确注释「OpenAI 官方枚举只有
5 个值」并做收敛 + 诊断）。实测输出：

```
data: {...,"choices":[{"delta":{},"finish_reason":"stop_sequence"}]}
                                        ^^^^^^^^^^^^^ 非 OpenAI 合法枚举
```

OpenAI Chat 官方 `finish_reason` 合法值只有 `stop` / `length` / `tool_calls` /
`content_filter` / `function_call`（vendored OpenAPI
`schemas/endpoints/openai-openapi.yaml`）。严格校验的对端会**拒绝整条流**。

这是三者中最严重的：前两个是保真度问题（丢信息），这个是**协议契约破坏**。

### 1.2 各协议的 `stop_sequence` 原生形状

| 协议 | 字段 | 形状 | 有无 IR 载体 |
|---|---|---|---|
| messages | `stop_sequence`（响应顶层） | `String?`，仅在 `stop_reason=="stop_sequence"` 时非 null | ❌ |
| messages 流 | `message_delta.delta.stop_sequence` | 同上 | ❌ |
| openai-chat | `stop`（**请求**侧） | `String \| Array[String]` | ✅ `options.stop` |
| gemini | `stopSequences`（**请求**侧） | `Array[String]` | ✅ `options.stop` |
| responses | 无（无自定义终止序列概念） | — | — |

关键区分：**请求侧的「候选终止序列」已有标准载体 `LucentOptions.stop`**
（`src/lux/types.mbt:429`）。缺的是**响应侧的「实际命中哪一个」**。两者是
不同的事实，不能合并。

## 2. 治理提案（按模板）

### IR 变更提案：为响应侧新增 `stop_sequence` 载体

- **影响面**：**两者兼有**
  - 协议转换：messages 源的响应解码/编码填入与读出；openai/responses/gemini
    目标无载体 → 需显式诊断。
  - SDK/Agent 消费：`LucentChoice` 新增可选字段；`LucentStreamEvent::Finish`
    的载荷结构若变更则影响匹配（见 §2.2 决策点）。
- **变更类型**：**非破坏性**（治理 §6「新增可选标准字段（`T?` 类型，默认
  null）」）。不改任何既有字段的类型/必选性，不新增必选字段。
- **保真度预期**：
  - messages → IR → messages：`Degraded` → **`Exact`**
  - messages → IR → openai/responses/gemini：`Unsupported` + 显式诊断
    （此前 openai 流式是**静默非法输出**，无诊断）
- **涉及字段/类型**：
  - `LucentChoice`：新增 `stop_sequence : String?`（默认 `None`）
  - `LucentStreamEvent::Finish`：见 §2.2（两个方案二选一）
  - `docs/lux-ir-design.md` + `schemas/lux-ir-v1.json`：同步 `LucentChoice`
  - `src/lux/helpers.mbt`：`LucentFinishReason` 新增 `StopSequence` 变体
    **或**保持 `Stop` 并由 `stop_sequence` 字段承载（见 §2.1）

### 2.1 决策点一：`finish_reason` 是否需要新变体？

| 方案 | 描述 | 优点 | 缺点 |
|---|---|---|---|
| **A. 新增 `StopSequence` 变体** | `LucentFinishReason::StopSequence`，解码 `"stop_sequence"` → 该变体 | 语义自明；下游可仅凭 `finish_reason` 分支；消除流式/非流式矛盾 | **新增枚举变体**（治理 §6 列为非破坏性，但所有 provider 的 `match finish_reason` 会触发穷尽性告警 → 需全量补分支）；且 `LucentChoice` 已有 `stop_sequence` 时信息冗余 |
| **B. 复用 `Stop` + 仅加 `stop_sequence : String?`** | 保持 `finish_reason = Stop`，命中序列由新字段承载；`stop_sequence.is_some()` 即表示「因命中序列而停」 | 不触碰枚举；无穷尽性波及；语义「正常结束 + 命中序列」完整 | 只读 `finish_reason` 的调用方仍无法区分（但可读新字段） |

**建议：选 B。** 理由：
1. Anthropic 自己的语义就是 `stop_reason: "stop_sequence"` **外加**独立的
   `stop_sequence` 字段——「原因」与「命中值」是两个事实，IR 若把二者塞进
   一个枚举，`Native` 兜底 + 独立字段会造成双载体、可能不一致。
2. A 的枚举变体会让四个 provider 的 `finish_reason` match 全部触发
   穷尽性检查，改动面远超「补一个字段」，且与「一次一个特性」的提交纪律
   不符。
3. B 保留了向 A 演进的可能（未来若确有需要，`StopSequence` 可从
   `Stop + stop_sequence.is_some()` 派生并作为兼容读取）。

**但 B 必须解决缺陷 B 的路径矛盾**：流式侧不能再用 `from_string` 兜底成
`Native("stop_sequence")`。规定：`from_string("stop_sequence") → Stop`
（与 `"end_turn"` 同义，官方语义确实都是「非异常终止」），命中值另走新字段。

> 注：当前 `from_string` 没有该键，因此落入 `Native`。补这一条即同时修好
> 缺陷 B，且不改变任何枚举。

### 2.2 决策点二：流式侧命中值往哪放？

`Finish(LucentFinishReason)` 只有一个位置参数。

| 方案 | 描述 | 评价 |
|---|---|---|
| **A. 改 `Finish` 载荷为 `(reason, stop_sequence: String?)`** | 破坏性变更（治理 §5「修改 stream event 的载荷结构」） | 需 major 版本 + 全链路适配，成本与收益不匹配 |
| **B. 复用 `ConversationStart.extra` 元数据通道** | 命中值属会话级元信息 | 语义不当：`extra` 是「协议原生未建模字段」的载体，而 `stop_sequence` 是**跨协议标准语义**，塞进扩展通道违反 §4 分类 |
| **C. 新增独立的流事件 `FinishDetail`** | 与 `Finish` 配对发出 | 新事件变体，下游需学习；但非破坏性 |
| **D. 本轮不做流式侧，只做非流式** | 缺陷 A 修完即止 | 缺陷 B/C 仍在（但见下） |

**建议：本轮选 D（非流式先行）+ 独立修缺陷 C（非法枚举溢出）。**

理由：
1. **缺陷 C 是协议契约破坏，必须无条件修**，且它**不依赖**新字段——只需让
   openai 流式编码复用 `openai_finish_reason` 收敛器（与非流式一致），
   把 `Native("unknown")` 收敛为 `stop` + Unsupported 诊断。这是纯 bug fix，
   不需治理。
2. **缺陷 B 也只需一行**：`from_string` 补 `"stop_sequence" => Stop`。
3. **缺陷 A 的流式部分**（命中值在流式 IR 中无载体）留作 §3 的后续提案——
   它需要 `Finish` 载荷变更或新事件，属破坏性/新事件，值得单独决策。

这样把「一个破坏性 IR 决策」拆成「两个纯 bug fix + 一个字段提案」，符合
最小改动原则，也让流式载荷的决策有充分时间。

### 2.3 provider 适配影响

| provider | 解码（→IR） | 编码（IR→） |
|---|---|---|
| `messages` | `stop_reason=="stop_sequence"` → `Stop` + `choice.stop_sequence = Some(v)`；流式同上（`message_delta.delta.stop_sequence`） | `choice.stop_sequence.is_some()` → `stop_reason="stop_sequence"` + `"stop_sequence":"<v>"`；否则保持 `stop_reason` 映射、`stop_sequence:null` |
| `openai` | 无原生 `stop_sequence`（`finish_reason` 无此值）→ `stop_sequence` 恒 `None` | `stop_sequence` 有值 → **Unsupported 诊断**（OpenAI 无响应侧命中值载体），不写任何字段 |
| `responses` | 同上，恒 `None` | 有值 → Unsupported 诊断（Responses 无自定义终止序列概念） |
| `gemini` | 同上，恒 `None` | 有值 → Unsupported 诊断（`finishReason` 枚举无此值） |

**关键：解码侧不得因为该字段存在而报错**（扩展/可选字段软失败，治理 §4）。

### 2.4 迁移策略

非破坏性变更，无需迁移：
- 新字段可选、默认 `None`；旧 IR 文档缺该字段时解为 `None`（等价于「未命中
  自定义序列」）——与现状行为一致。
- JSON 输出侧：`None` 时**不输出**该键（而非输出 `null`），保证与今日字节
  形态一致，不扰动任何既有快照测试。
- schema 的 `LucentChoice.required` 不加入该字段。

## 3. 本次不做（明确决策 + 后续）

- **流式侧命中值载体**（§2.2 的方案 A/C）留作独立提案。当前流式的
  `stop_sequence` **值**仍会丢失（但不再产生非法枚举、不再与非流式矛盾）。
  这是**有意识的 Degraded**，需在流式解码处打诊断：「命中值在流式 IR 无载体」。
- 不把命中值塞进 `ConversationStart.extra`（理由见 §2.2 B）。
- 不新增 `LucentFinishReason::StopSequence`（理由见 §2.1）。

## 4. 验收清单

- [ ] `LucentChoice` 新增 `stop_sequence : String?`（`derive(Eq, Debug)` 同步）
- [ ] `LucentChoice::new` 签名变更（新增末位可选参数）→ 全仓调用点适配
- [ ] messages 响应解码：`stop_reason=="stop_sequence"` → `Stop` +
      `stop_sequence = Some(v)`（此前静默丢弃，无诊断）
- [ ] messages 响应编码：有值 → `stop_reason="stop_sequence"` + 写值；
      无值 → 保持现状（`stop_sequence:null`）
- [ ] `from_string("stop_sequence") → Stop`（消除流式/非流式矛盾）
- [ ] **openai 流式编码复用 `openai_finish_reason`**（消除非法枚举溢出）
- [ ] openai/responses/gemini 编码：有值 → Unsupported 诊断
- [ ] messages 流式解码：命中值无载体 → Degraded 诊断（有意识降级）
- [ ] schema + `docs/lux-ir-design.md` 同步（`drift -Strict` 必须 PASS）
- [ ] 回归：新增 `src/sdk/test/stop_sequence_carrier_test.mbt`
      （同源往返 Exact、跨端 Unsupported、流式/非流式 IR 值一致、
      非法枚举不再溢出），每处修复做**反向验证**
- [ ] 全部门禁：fmt / check(+73, deny-warn) / native + wasm-gc / drift / coverage ≤ 200

## 5. 与既有决策的关系

- 与 **CR-004 变更 1**（`LucentFinishReason::to_string` 的 wire 值对齐 schema）
  相关但不同：CR-004 修的是**已有变体**的输出拼写，本提案涉及的是**缺失的
  响应侧字段**与**非法值溢出**。
- 缺陷 C（openai 流式绕过收敛器）**应先以独立 bug fix 提交**，不等本提案
  批准——它是协议契约破坏，与是否新增 IR 字段无关。

## 6. 已实施（2026-10-24）：缺陷 B / C

按「把破坏性 IR 决策拆成纯 bug fix + 字段提案」的思路，B 与 C 不依赖任何
新增 IR 字段，已先落地。**A 仍未实施**（需按 §2 走治理）。

### 6.1 新增共享收敛器 `src/provider/meta/finish.mbt`

三个纯函数，**非流式与流式共用**，杜绝两路径词汇表漂移：

| 函数 | 目标 | 合法枚举 |
|---|---|---|
| `messages_stop_reason_json` | Anthropic | `end_turn` / `max_tokens` / `tool_use` / `stop_sequence` / `refusal` / `pause_turn` / `model_context_window_exceeded` |
| `openai_finish_reason_json` | OpenAI Chat | `stop` / `length` / `tool_calls` / `content_filter` / `function_call` |
| `gemini_finish_reason_string` | Gemini | `STOP` / `MAX_TOKENS` / `SAFETY` / `RECITATION` / `OTHER` / … |

落点选 `meta` 的理由与 `extras.mbt` 相同：需要 `@lux` 类型 + `@internal`
转义，且要被四个 provider 共享；放 `lux` 破坏分层，四处复制会漂移。

### 6.2 修复清单

- **缺陷 C（messages 流式）**：`Finish(fr)` 此前直接写 `fr.to_string()` ——
  实测 **8 个 IR 值里 8 个非法**（`stop` / `length` / `tool_calls` / `safety` /
  `recitation` / `malformed_tool_call` / `error` / `content_filter` 均非
  Anthropic `stop_reason`）。特别是 `ToolCalls` 输出 `tool_calls`，而 Anthropic
  的合法值是 **`tool_use`**。现改用共享收敛器。
- **缺陷 C（openai 流式）**：此前绕过非流式已有的 `openai_finish_reason`，
  直接把 IR 词汇表写进 `finish_reason`（含 messages 源解出的
  `Native("stop_sequence")` → 输出 `"finish_reason":"stop_sequence"`，非法）。
  现改用共享收敛器；非流式侧同时删除了「剥引号」的包装函数，调用点直接
  使用返回带引号字面量的收敛器（避免一层无意义转换与一个不可达分支）。
- **缺陷 C（gemini 流式，顺带发现）**：流式自带一份简化映射，`Native(v)` 走
  `_ => "STOP"` 兜底 —— **静默吞掉厂商自定义值**（如 gemini 自己解出的
  `LANGUAGE` / `BLOCKLIST` / `SPII`），而同协议非流式是原样透传。现统一为透传。
- **缺陷 B**：`LucentFinishReason::from_string` 补 `"stop_sequence" => Stop`。
  此前无该分支 → 流式落入 `Native("stop_sequence")`，而非流式（messages
  `response.mbt`）映射为 `Stop` —— 同一语义两个入口解出不同 IR 值。

### 6.3 一处既有测试修正

`src/provider/gemini/gemini_wbtest.mbt` 的流式映射用例原断言
`(Native("nft"), "STOP")` —— 它锁定的正是上述数据丢失（兜底吞掉自定义值），
已改为 `"nft"`（透传），与同协议非流式契约一致。

### 6.4 回归与验证

`src/sdk/test/finish_reason_contract_test.mbt`（7 用例）：
- messages / openai 流式逐值断言**只输出合法枚举**；
- `ToolCalls → tool_use`（不是 `tool_calls`）定点锁定；
- messages 源 `stop_sequence` 不再泄漏进 openai 流；
- 流式与非流式对同值解出**同一** IR 值；
- gemini `Native` 原样透传；
- 无对等值的收敛必须带 Unsupported 诊断。

四处修复均做过**反向验证**（回退修复 → 测试必须失败），命中记录：
- messages 流式回退 → `"tool_calls" != "tool_use"` + 合法枚举断言失败
- openai 流式回退 → 合法枚举断言失败
- gemini `Native` 回退为 STOP → 透传断言失败
- `from_string` 回退 → `Native("stop_sequence") != Stop`
- **`arbitrate` 白名单回退为无条件透传** → 三个"只输出合法枚举"用例失败

门禁：fmt / check(+73, deny-warn) / native + wasm-gc **1409/1409** /
drift `-Strict` PASS / coverage **199**（阈值 200）。

### 6.5 重新设计（2026-10-24，第二版）

§6.1–6.4 记录的是**第一版**实现。第一版有一个结构性漏洞，已在第二版修正，
完整设计见 [`design/finish-reason-contract.md`](../design/finish-reason-contract.md)。

**漏洞**：第一版按 IR 枚举 match，`Native(s)` 无条件透传。实测
`messages` 源 `Native("pause_turn")`（Anthropic 合法值）会原样溢进 openai 的
`finish_reason`。根因：**合法性是目标槽位的属性，不是 IR 值的属性**；按 IR
枚举分支再给 `Native` 开口子，天然无法封闭。

**第二版模型**：所有值（含 `Native`）统一过**目标白名单**：

```text
value    = candidate ∈ legal(target) ? candidate : fallback(target)
diagnose = 值不合法 || 有语义损失
```

新增：`responses_status_json` / `responses_incomplete_reason`（responses 的
status 也是封闭枚举，第一版完全没纳入）；非流式 responses 也改为调用共享
函数（此前它与流式各写一份 match，已漂移）。

**第二个坑（诊断判据）**：`Safety → "failed"` 的 `failed` 是合法值，按「值被
改动才报警」不报 —— 但 IR `Safety`（安全拦截）与 `Error`（执行失败）共压成
`failed` 是有损的。判据精确化为**信息损失**而非「值被改动」。

**顺带纠正**：gemini `ContentFilter` 由 `STOP` 改为 `SAFETY`（前者把「被拦截」
伪装成「正常结束」）；诊断键统一为目标真实字段名。

**新发现的技术债（不在本次范围）**：OpenAI 的 `function_call` 与 `tool_calls`
是合法枚举里的两个不同项，但 IR 都映射到 `ToolCalls`，回程一律输出
`tool_calls` —— OpenAI → IR → OpenAI 无法保住 `function_call`。此前无人记录。
修复需增 IR 变体（破坏性），与缺陷 A 一并等决策。

### 6.6 缺陷 A 实施（2026-10-24，选项 B）

`LucentChoice` 新增 `stop_sequence : String?`（治理 §6「新增可选标准字段」）。

**结构选择的理由**：`LucentChoice::new` 保持 4 参数不变，88 处调用点零改动；
需要携带时用新 builder `with_stop_sequence`（沿用本仓既有 `with_*` 惯例与
`{ ..self, ... }` 结构更新）。若改为扩构造参数，88 处调用全部破坏，而该字段
只在 messages 解码路径才可能非 `None`。

**实施清单**：

- `src/lux/types.mbt`：`LucentChoice` 加字段 + 文档语义；
- `src/lux/helpers.mbt`：`LucentChoice::new` 默认 `None`；新增
  `with_stop_sequence` builder；
- `src/lux/serialize_response.mbt`：`Some` 输出键、`None` **不输出**（保持既有
  字节形态，不扰动快照）；
- `src/lux/deserialize_response.mbt`：缺失 / 空串 / 类型不符一律软失败为 `None`
  （可选字段不得因反序列化失败报错，治理 §4）；
- `src/provider/messages/response.mbt` 解码：仅在 `stop_reason=="stop_sequence"`
  时携带命中值（官方语义：该字段只在此情形非 null）；
- `src/provider/messages/response.mbt` 编码：既有值时**强制**写
  `stop_reason:"stop_sequence"` 并回写真实值（两字段必须自洽）；否则保持
  收敛结果 + `stop_sequence:null`；
- `openai` / `responses` / `gemini` 编码：无载体 → **Unsupported 诊断**；
- `messages` 流式解码：命中值无 IR 载体 → **Degraded 诊断**（有意识降级，
  不能静默）。为此给 `messages_decode_frames` 补了诊断通道。

**实测结果**：

```
输入 {"stop_reason":"stop_sequence","stop_sequence":"END_TURN"}
  解码: stop_sequence = Some("END_TURN"), finish_reason = Stop
  回写: {"stop_reason":"stop_sequence","stop_sequence":"END_TURN"}   ← Exact
  跨端: openai / responses / gemini 各 1 条 Unsupported 诊断
  流式: 1 条 Degraded 诊断（值确实丢弃，但有告知）
end_turn + stop_sequence:null → None，回写仍 null（字节形态不变）
```

回归：`src/sdk/test/stop_sequence_carrier_test.mbt`（7 用例）。
**反向验证**：回退解码捕获 → `None != Some("END_TURN")`；回退编码回写 →
往返断言失败。两处均确认。

### 6.7 仍未做：`function_call` / `tool_calls` 区分度（新技术债）

实测往返发现：OpenAI `finish_reason` 的 `function_call` 与 `tool_calls` 是
**合法枚举里的两个不同项**，但 IR 都映射到 `ToolCalls`，回程一律输出
`tool_calls` —— 即 OpenAI → IR → OpenAI 保不住 `function_call`。

**决策：不实施。** 理由见 §0 —— 官方 schema 在 `finish_reason` 的说明里明确
标注 `function_call (deprecated)`，字段定义亦带 `deprecated: true`。为一个正在
淘汰的遗留值给 IR 加永久枚举变体（35 处穷尽 match 全部受影响），投入产出不
匹配。

若未来确有需要，正确做法是在 `LucentChoice` 上加一个可选的子类型标记
（与 `stop_sequence` 同构，非破坏性），而不是扩 `LucentFinishReason`。

### 6.8 流式载荷（仍未做，需独立提案）

流式的「命中序列」值至今无 IR 载体：`LucentStreamEvent::Finish` 只有一个
位置参数。当前处理是**有意识降级 + 诊断**（§6.6）。

改 `Finish` 的载荷结构属治理 §5 明列的破坏性变更（「修改 stream event 的
载荷结构」），需 major 版本与全链路适配。可选方向已在 §2.2 列出：
A 改载荷（破坏性）/ C 新增 `FinishDetail` 事件（非破坏但需下游学习）。
留待独立提案决策。
