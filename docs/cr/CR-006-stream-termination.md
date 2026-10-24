# CR-006：流式终止信息的载体（`Finish` 载荷）

> 状态：**批次 1 已落地**（`0.1.5`，commit `d41d6bc`）；批次 2 **待决策**
>（含一个破坏性变更，需治理 §5 批准；推荐方案 A，理由见 §3.3）
> 来源：CR-005 §6.8 遗留项「流式 `stop_sequence` 无 IR 载体」
> 影响面：**协议转换 + SDK/Agent 消费**（两者兼有）
> 变更类型：**破坏性**（§5「修改 stream event 的载荷结构」）+ 5 个非破坏性缺陷修复

---

## 0. 摘要与决策请求

CR-005 遗留的命题是「流式 `stop_sequence` 命中值没有载体」。本轮按「先实测、再定形状」
的既定方法去探查，**发现的问题范围远大于该命题**：

`Finish(LucentFinishReason)` 作为**流式终止状态的唯一载体**已经在丢五类信息，其中四类
都是**静默丢弃、零诊断**（只有第 1 类是 CR-005 已加的 Degraded 诊断）：

| # | 输入（官方协议） | 当前产出 | 严重度 |
|---|---|---|---|
| 1 | Anthropic `message_delta.stop_sequence` | `Finish(Stop)` + 1 条 Degraded 诊断 | 已有告知（CR-005） |
| 2 | Responses `response.incomplete` | **0 个事件**（无 Finish / 无 Error / 无 Done） | **信息全灭** |
| 3 | Responses `response.failed` | **0 个事件** | **信息全灭** |
| 4 | Responses 官方 `error` 事件 | **0 个事件** | **信息全灭** |
| 5 | Gemini 流式 `promptFeedback.blockReason` | 无 `Finish`，累加器默认 `Stop` | **拦截伪装成正常结束** |

> 2/3/4 的「0 个事件」由实测得出（§1.1/§1.2）。即：一个 `response.failed` 的流，经
> Prism 中转后对下游表现为**什么都没有发生**——不是失败，是空流。这违反硬约束
> 「不支持的能力必须显式报错，绝不静默丢弃」。

**因此本提案把命题拆成两部分**：

- **§2（不需要治理）**：表 2–5 这四类终止/错误信息解码静默丢弃，以及流式与非流式对
  同一语义解出不同 IR。纯 bug，无论载荷方案怎么选都必须修。建议先以 `0.1.5` 独立发布。
- **§3–§5（需要治理 §5 批准）**：`Finish` 的载荷结构。这是唯一需要决策的部分，
  建议随 `0.2.0` 发布。

**决策请求**：批准方案 A（`Finish(reason, stop_sequence?)`，破坏性），还是方案 B
（新增 `Termination` 事件，非破坏性）。理由见 §3.3。

> 方案字母以 §3.2 的表为准：A = 改 arity，B = 新增事件，C = 复用 `extra`，
> D = 枚举变体带载荷。

---

## 1. 实测证据

方法：给各解码器喂官方形态的帧，打印产出事件与诊断数。**先看输出，再谈设计。**

### 1.1 Responses 终止事件（三类全灭）

```
输入 response.incomplete（content_filter）      → [0 个事件] diag=0
输入 response.incomplete（max_output_tokens）   → [0 个事件] diag=0
输入 response.incomplete（steered）             → [0 个事件] diag=0
输入 response.failed（code=server_error）       → [0 个事件] diag=0
输入 response.completed
  → [2 个事件] {"event":"finish","finish_reason":"stop"} {"event":"done"} diag=0
```

`schemas/endpoints/openai-openapi.yaml` 的 `ResponseStreamEvent` 联合体明确包含
`ResponseIncompleteEvent` / `ResponseFailedEvent`（第 60936–60937 行），二者都是
**官方终止事件**。当前 `src/provider/responses/stream_decode.mbt` 只处理
`"response.completed"`，其余落入 `_ => ()`，连同 `Done` 一起消失。

### 1.2 Responses 官方 `error` 事件形态不匹配

官方 `ResponseErrorEvent`（spec 第 58391 行）是**扁平**结构：

```json
{"type":"error","code":"server_error","message":"boom","param":null,"sequence_number":3}
```

当前解码器读的是 `jv["error"]`（嵌套）。实测：

```
官方扁平形态                 → 0 个事件
实现假设的 {"error":"..."}   → 1 个事件 {"event":"error",...}
```

即：**按官方文档发错误帧的对端，错误会被完全吞掉**。当前能工作的形态不是官方形态。

### 1.3 Gemini 流式 `promptFeedback.blockReason`

```
输入 {"promptFeedback":{"blockReason":"PROHIBITED_CONTENT"},"usageMetadata":{...}}
  → conversation_start, usage, done          ← 没有任何 Finish
  → 累加器 lucent_stream_events_to_accumulated 默认 finish = Stop

输入 {"candidates":[{"content":{"parts":[]},"finishReason":"SAFETY"}],"promptFeedback":{...}}
  → finish=safety（frame 自带 finishReason 时才对）
```

对比同协议**非流式**（`gemini/response.mbt:79-130`）：`blockReason` 有值 →
`finish_reason = Safety` + Degraded 诊断「prompt blocked by gemini safety policy: …」。

即：同一语义，非流式说「被安全策略拦截」，流式说「正常结束」。**这是流式/非流式
等价性又一次被违反**（CR-005 缺陷 B 是第一例）。

### 1.4 流式与非流式的直接对撞

同一份 `status=incomplete, incomplete_details.reason=content_filter` 响应体：

```
非流式 responses_json_to_lux_response → finish_reason = content_filter
流式   responses_sse_to_events        → 无 Finish（NONE）
```

### 1.5 载荷方案的编译期影响（实测，非估算）

> 踩过的坑：`moon check` 在**首个**失败包就中止，所以第一次探针只看到 lux 包的 24 条；
> 修完 lux 再跑，又暴露出下一批包。**只跑一次 `moon check` 得到的数字一定是错的**，
> 下面的 103 是逐处 `grep` + 逐处确认枚举归属后的最终数。

| 方案 | 编译期暴露 | 静默风险 |
|---|---|---|
| **A：`Finish(reason, String?)`** | **103 处全量**硬错误（生产 19 / 测试 84） | **零**（每一处都是硬错误） |
| **B：新增 `Termination(String?)`** | 仅 **3 个包**（messages / openai / responses 的 stream_encode） | **有，且已验证**（见下） |

B 的静默风险是实测出来的：加变体并修好 lux 的穷尽性后，`moon check` 只报三处
`partial_match`，而下列位置**因 `_ =>` 兜底而静默通过**：

| 文件 | 兜底 | 后果 |
|---|---|---|
| `src/provider/gemini/stream_encode.mbt:313` | `_ => ()` | 新事件被丢弃 |
| `src/sdk/pipeline.mbt:180` | `_ => ()` | 同上 |
| `src/sdk/convert.mbt:460` | `_ => ()` | 同上 |

**这正是本 CR 要消灭的失败模式**：一个「非破坏性」的方案，把编译器能抓的错误
转化为运行期静默。

### 1.6 A 方案的真实代码影响面

先用 `grep` 抓取所有 `Finish(` 站点，再**逐处确认它属于哪个枚举**——`PrismEvent`
也有一个 `Finish(PrismFinishReason)` 变体，且 sdk 层大量代码同时处理两个枚举。排除
`PrismEvent` 站点后的准确结果：

| 类别 | 站点数 | 非测试 | 测试 |
|---|---|---|---|
| 构造 `Finish(...)` | **80** | **6** | 74 |
| 模式 `Finish(x) =>` | **23** | **13** | 10 |
| 合计 | **103** | **19** | **84** |

排除的 `PrismEvent` 站点（**不受影响**，不在本 CR 范围内）：
模式 —— `src/sdk/prism.mbt:456`、`src/wasm/convert.mbt:219`、
`src/examples/sdk-basic/main.mbt:287`；
构造 —— `src/sdk/pipeline.mbt:177`、`src/sdk/event_stream.mbt:414`。

关键结论：**生产代码只需改 19 处，其余 84 处是测试里的字面量**，改法是机械的
`Finish(Stop)` → `Finish(Stop, None)`。且全部是编译错误，不存在漏改。

19 处生产站点清单（`Finish` 属 `LucentStreamEvent`）：

**构造（6 处）**

| 位置 |
|---|
| `src/lux/deserialize_stream.mbt:112` |
| `src/provider/gemini/stream_decode.mbt:235` |
| `src/provider/messages/stream_decode.mbt:193` / `:259` |
| `src/provider/openai/stream_decode.mbt:301` |
| `src/provider/responses/stream_decode.mbt:194` |

**模式（13 处）**

| 位置 |
|---|
| `src/lux/serialize_stream.mbt:90` |
| `src/lux/stream.mbt:658`（累加器） |
| `src/provider/gemini/stream_encode.mbt:258` |
| `src/provider/messages/stream_encode.mbt:66` / `:73` / `:86` / `:273` |
| `src/provider/openai/stream_encode.mbt:161` |
| `src/provider/responses/stream_encode.mbt:535` |
| `src/sdk/convert.mbt:493`（`ends_with_finish`） |
| `src/sdk/event_stream.mbt:133`（规整器）/ `:406`（事件映射） |
| `src/sdk/pipeline.mbt:169` |

---

## 2. 不需要治理的部分：终止/错误事件的解码修复

这四项与载荷方案**正交**，无论选 A 还是 C 都必须修。建议先以 `0.1.5` 发布。

### 2.1 根因不是「漏了分支」，是「两路径各写一份映射」

`responses` 的 status→finish_reason 映射在**非流式**里是对的（`response.mbt:168-207`，
含 `incomplete_details.reason` 的细分），而**流式**里根本不存在这份逻辑。CR-005 缺陷 C
的教训是「流式绕过了非流式的收敛器」——这里是同一错误模式的第二次出现。

**统一做法**：抽出到 `@meta`，两条路径共用：

```moonbit
// src/provider/meta/termination.mbt（新增）
/// Responses 终止帧的 (status, incomplete_details.reason) → IR 终止原因
pub fn responses_termination_reason(
  status : String,
  incomplete_reason : String?,
) -> @lux.LucentFinishReason
```

映射与现有非流式**逐值一致**，不改任何语义：

| status | incomplete_details.reason | IR |
|---|---|---|
| `completed` | — | `Stop` |
| `incomplete` | `content_filter` | `ContentFilter` |
| `incomplete` | `max_output_tokens` / `max_messages` | `Length` |
| `incomplete` | `steered` 等其它 | `Native(reason)`（原样保留，由编码侧白名单裁决） |
| `incomplete` | 缺失 | `Length`（保守默认，同非流式） |
| `failed` | — | `Error` |
| 其它/缺失 | — | `Native(status)` / `Stop`（同非流式） |

### 2.2 三个终止事件都要被识别

- `response.completed` → 现状（`Finish` + `Usage` + `Done`）
- `response.incomplete` → `Finish(...)` + `Usage` + `Done`
- `response.failed` → `Error(LucentError)` + `Finish(Error)` + `Done`
  - 官方 `error` 对象 `{code, message}`：`code` 经 `LucentErrorKind::from_string`
    映射（`server_error` → `ServerError`），原文进 `provider_code`，`message` 进 message
- 官方扁平 `error` 事件 → `Error(...)`；**保留**对非官方嵌套形态的兼容读取
  （先判扁平 `code`/`message`，再判 `jv["error"]`，都不中才丢弃）

### 2.3 Gemini 流式补 `promptFeedback`

`candidates` 缺失、或 `finishReason` 缺失时，若 `promptFeedback.blockReason` 有值 →
`Finish(Safety)` + Degraded 诊断（带出 `blockReason`），诊断键与非流式同为
`promptFeedback.blockReason`。

### 2.4 为什么这四项都不需要新字段

见 §3.1 的统一载体对照表——那四项都有现成载体，**只有 `stop_sequence` 的值无处安放**，
这也是为什么本 CR 必须拆成「修解码」与「改载荷」两批。

---

## 3. 需要治理的部分：`Finish` 载荷

### 3.1 五类信息逐条对照：真正需要载体的只有一项

| # | 信息 | 是否已有 IR 载体 | 结论 |
|---|---|---|---|
| 1 | Anthropic `stop_sequence` 命中值 | ❌ **无** —— 它是**自由字符串**，不是「原因枚举」的任何取值；塞进诊断属滥用（诊断表达**损失**，不是表达**数据**） | **需要新载体**（§3） |
| 2 | Responses `incomplete_details.reason` | ✅ 它就是 `finish_reason` 的**细分来源**（content_filter→ContentFilter，max_*→Length，steered→Native） | 修解码即可（§2） |
| 3 | Responses `error` 对象（`failed`） | ✅ 独立的 `Error(LucentError)`，含 kind/message/provider_code | 修解码即可（§2） |
| 4 | Responses 官方扁平 `error` 事件 | ✅ 同上 | 修解码即可（§2） |
| 5 | Gemini `blockReason` | ✅ 映射为 `Safety`，原文进诊断（同非流式） | 修解码即可（§2） |

**这就是关键判断**：CR-005 遗留的命题之所以看起来「必须改载荷」，是因为把五类信息
（§0 表 1–5）混在一起看了。逐条拆开后，四类都有现成载体，只有 `stop_sequence` 的值
真的无处安放。

### 3.2 方案选型

| 方案 | 形态 | 评价 |
|---|---|---|
| **A. 改 arity** `Finish(LucentFinishReason, String?)` | 第二位置参数 = 命中序列 | ✅ 与 `LucentChoice.stop_sequence` **完全同构**，一个事实一种表达；103 处全部编译期暴露（生产仅 19）；JSON 侧加可选键属 §6 非破坏（`None` 不输出，字节形态不变）<br>❌ MoonBit 枚举 arity 变更属 §5 破坏性变更 |
| **B. 新增 `Termination(String?)` 事件** | 与 `Finish` 配对发出 | ✅ 不破坏 arity<br>❌ 引入**配对语义**（规整器只留首个 `Finish`，需同步去重）；3 处 `_ =>` 已验证会**静默吞掉**；一个事实拆成两个事件 |
| **C. 复用 `ConversationStart.extra`** | 会话级元数据 | ❌ CR-005 §2.2 B 已否决：`extra` 是「协议原生未建模字段」的载体，`stop_sequence` 是跨协议标准语义，且这是**轮次级**事实，塞进**会话级**通道 |
| **D. 枚举变体带载荷** `StopSequence(String)` | 并入 `LucentFinishReason` | ❌ 与 `LucentChoice.stop_sequence` 冗余（同一事实两种表达）；**决定性理由**：`schemas/lux-ir-v1.json:386-389` 把该枚举定义为 `{"type":"string","enum":[...]}`，**带载荷变体无法表达进 JSON Schema 的 `enum`**——要么把 schema 改成 oneOf，破坏既有校验契约，要么让值携带的信息在 JSON 层直接丢失（比现在更糟）；另有 `from_string`/`to_string` 双向映射无法表达载荷。CR-005 §2.1 已否决同族方案 |

**推荐 A。**

### 3.3 为什么 A 优于 B（尽管 B 自称「非破坏」）

仓库的优先级是 **「绝不静默丢弃」> SDK 易用性**（治理 §3）。按这条尺子：

- **A 的破坏是「响亮的」**：103 处 arity 不匹配，编译器逐处指出；生产代码只 19 处，
  其余 84 处是测试字面量。没有一处能悄悄通过。
- **B 的破坏是「安静的」**：编译通过，但 §1.5 实测的三处 `_ =>` 会把新事件直接扔掉 ——
  **正是本 CR 要消灭的失败模式**。且未来每新增一种终止细节，都要再赌一次
  「记得处理配对事件」。

用一次响亮的破坏换掉一个长期的静默风险源，是合算的。

### 3.4 形态

```moonbit
pub(all) enum LucentStreamEvent {
  ...
  /// 结束原因 + 命中的自定义终止序列（仅目标协议有该概念时非 None）
  Finish(LucentFinishReason, String?)
  ...
}
```

配套便利构造器（与 `LucentBlockType::text()` / `LucentError::simple()` 同风格），
让「只关心原因」的调用点保持可读：

```moonbit
pub fn LucentStreamEvent::finish(reason : LucentFinishReason) -> LucentStreamEvent {
  Finish(reason, None)
}
```

- **解码**：`messages` 的 `message_delta` 同时读 `stop_reason` 与 `stop_sequence`，
  命中时发 `Finish(Stop, Some(v))`。其余三端恒 `None`。
- **编码**：`messages` 在 `Some(v)` 时写 `"stop_sequence":"<v>"` 并强制
  `stop_reason: "stop_sequence"`（与 CR-005 非流式编码同规则）；其余三端在 `Some(v)`
  时打 Unsupported 诊断（与非流式同规则）。
- **JSON**：`None` 时不输出 `stop_sequence` 键，保持既有字节形态。
- **累加器**：`lucent_stream_events_to_accumulated` 把 `ss` 写进
  `LucentChoice.stop_sequence`，从而**流式累加结果与非流式解码结果完全一致**。

最后一条是本方案最大收益：`LucentChoice.stop_sequence` 在两条路径上由同一字段承载，
流式/非流式不再有第二套词汇表。

---

## 4. provider 适配影响

**载荷部分（§3）**

| provider | 解码（→IR） | 编码（IR→） |
|---|---|---|
| `messages` | `stop_reason` + `stop_sequence` → `Finish(reason, Some(v))` | `Some(v)` → `stop_reason:"stop_sequence"` + 写值；`None` → 现状 |
| `openai` | 无该概念 → 恒 `None` | `Some(v)` → Unsupported 诊断 |
| `responses` | 无该概念 → 恒 `None` | `Some(v)` → Unsupported 诊断 |
| `gemini` | 无该概念 → 恒 `None` | `Some(v)` → Unsupported 诊断 |

**终止修复部分（§2）**

| provider | 变更 |
|---|---|
| `responses` | 识别 `response.incomplete` / `response.failed` / 官方扁平 `error`；status 映射改调 `@meta.responses_termination_reason`（与非流式共用） |
| `gemini` | 流式补 `promptFeedback.blockReason` → `Safety` + 诊断 |
| `openai` / `messages` | 无（两者已有官方错误帧处理） |

---

## 5. 迁移策略（破坏性部分）

`Finish` arity 从 1 变 2，属治理 §5 明列的破坏性变更。

1. **版本**：`0.1.5`（§2 修复）→ `0.2.0`（§3 载荷）。0.x 语义下 minor 即 breaking。
2. **迁移机械式**：`Finish(x)` → `Finish(x, None)` 或 `finish(x)`；
   模式 `Finish(p)` → `Finish(p, _)`。103 处全部由编译器指出，生产代码 19 处。
3. **JSON / ABI 兼容**：`stop_sequence` 为可选键，`None` 时不输出 —— 存量 JSON 与
   WASM 字符串 ABI 字节形态**不变**，只读 `finish_reason` 的旧消费端不受影响。
4. **schema**：`LucentStreamEvent` 的 finish 分支加可选 `stop_sequence`，
   `required` 不变（§6 非破坏）。
5. **SDK 层**：`PrismEvent`（`src/sdk/event.mbt`）本轮**不动**——命中序列是协议保真
   事实，SDK 的 `Finish(PrismFinishReason)` 是面向 agent 循环的简化视图；加字段会把
   协议细节漏进 SDK 词汇表。若 agent 侧确需该值，另立提案。

---

## 6. 验收清单

**批次 1（`0.1.5`，不需要治理）— ✅ 已全部落地（2026-10-24，commit `d41d6bc`）**

- [x] `responses`：`response.incomplete` → `Finish` + `Usage` + `Done`，
      `incomplete_details.reason` 逐值对齐非流式
- [x] `responses`：`response.failed` → `Error`（含 code/message）+ `Finish(Error)` + `Done`
- [x] `responses`：官方扁平 `error` → `Error`；保留非官方嵌套形态兼容
- [x] `@meta.responses_termination_reason` 抽出，非流式与流式**共用**（非流式行为零变化）
- [x] `gemini`：流式 `promptFeedback.blockReason` → `Finish(Safety)` + Degraded 诊断
- [x] 回归：`src/sdk/test/stream_termination_test.mbt`
      （五类终止/错误输入 × 生产；流式与非流式对同一响应体解出**同一** `finish_reason`；
      官方 error 帧不再被吞；`response.failed` 的流不再是空流）
- [x] 每处修复做**反向验证**（回退后测试必须失败）
- [x] 门禁全绿（fmt 0 / check(+73, deny-warn) 0 / native+wasm-gc 1426×2 /
      oracle run-all 6 步（validate 23 + pipeline 14 + self-check 7）/
      drift `-Strict` PASS / coverage 203≤204；`moon.mod` → `0.1.5`）

**批次 2（`0.2.0`，需 §5 批准）**

- [ ] `Finish` arity → `(LucentFinishReason, String?)`；便利构造器 `finish(reason)`
- [ ] `messages` 流式解码携带命中值；编码写回 `stop_sequence` 并强制 `stop_reason`
- [ ] `openai` / `responses` / `gemini` 编码：有值 → Unsupported 诊断
- [ ] 累加器把命中值写进 `LucentChoice.stop_sequence`（流式累加 == 非流式解码）
- [ ] JSON 序列化/反序列化：`Some` 输出、`None` 省略、缺失/类型不符软失败为 `None`
- [ ] `schemas/lux-ir-v1.json` + `docs/lux-ir-design.md` + `docs/fidelity-matrix.md`
      同步（`check_schema_drift.ps1 -Strict` 必须 PASS）
- [ ] `moon.mod` → `0.2.0`
- [ ] 回归：`stop_sequence` 流式往返 Exact、跨三端 Unsupported、
      流式累加与非流式解码逐字段相等
- [ ] 门禁全绿：fmt / check(`+73, --deny-warn`) / native + wasm-gc / drift / coverage ≤ 200

---

## 7. 与既有决策的关系

- **CR-005 缺陷 A**（非流式 `stop_sequence` 载体）：已落地。批次 2 把同一事实补到
  流式侧，复用 `LucentChoice.stop_sequence`，不新增概念。
- **CR-005 §6.8**（流式载荷「仍未做」）：本 CR 就是它要求的独立提案。
- **CR-005 缺陷 B/C 的教训**（流式与非流式必须共用同一收敛函数）：§2.1 把 responses
  的 status 映射也抽进 `@meta` 共用，是同一原则的第三次应用。
- **CR-003 选项 B**（`BlockDiscard` 保留并标废弃、不轻言破坏）：不冲突——CR-003 是
  「无真实用例支撑破坏」，本 CR 是「有真实信息在丢，且破坏是编译器可穷举的」。
- **CR-002 D5 / CR-001 D2**（规整器：Done 丢弃、Finish 只留首个）：方案 A 不改这两条；
  方案 B 会要求它们增加配对事件的去重规则，是 B 的额外成本。
