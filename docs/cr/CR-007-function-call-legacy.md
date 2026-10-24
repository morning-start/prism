# CR-007：旧式 `function_call` 的解码丢失（内容 + 枚举区分度）

> 状态：**§1 已实施（2026-10-24，本提交）；§2 提案待批准**
> 提出：2026-10-24
> 依据：`docs/rules/lucent-ir-evolution.md` §2「影响面声明」、§5「破坏性变更判定」、
> §6「非破坏性变更」
> 来源：CR-005 §6.7 登记的技术债「`function_call` / `tool_calls` 区分度」。
> 本轮按「先实测、再定形状」的既定方法重查该债，**发现它的真实形状与
> 原登记完全不同** —— 原描述只讲「枚举区分度」（保真度问题），实测出的
> 主因是「内容整体丢失」（数据丢失问题），严重度差一个数量级。

---

## 1A. 已实施（2026-10-24）：缺陷 1/2 + 连带发现的 caller required 缺失

### 修复清单

| # | 修复 | 位置 |
|---|---|---|
| 1 | 非流式 `message.function_call` 解码（合成 id `call_fn_0`，决策点一 A） | `src/provider/openai/response.mbt` |
| 2 | 流式 `delta.function_call` 解码（占索引 0，先闭 text 块；**不闭 thinking**） | `src/provider/openai/stream_decode.mbt` |
| 3 | 出站 `tool_use` 补 `caller:{"type":"direct"}`（官方 ToolUseBlock required） | `src/provider/messages/request_encode.mbt` ×2 + `stream_encode.mbt` |
| 4 | drift 字段集增 `caller` | `scripts/check_schema_drift.ps1` |
| 5 | oracle [5] 组新增 `openai-legacy-fc` 样本 + **真相断言**（IR 保留 tool_use / messages content 非空 / stop_reason 一致） | `tools/conformance/pipeline.mjs` |

### 实施中的两个补充发现

**发现 A：缺陷 1/2 修复时又抓出第 4 类缺陷** —— oracle 首次把工具调用样本送进
[5] 组矩阵，立刻实测出 messages 出站 `tool_use` 缺 `caller`（新版 SDK 类型的
required 字段），官方 schema 拒绝。此前 [5] 组样本全是纯文本，这个缺口一直隐形。
取值 `{"type":"direct"}` 是事实正确的（Prism 出站的 tool_use 恒为模型直接发起；
`ServerToolCaller` 仅用于 code_execution 类服务端工具）。

**发现 B：死代码自查** —— 流式 fc 分支第一版照抄 tool_calls 分支写了
`idx == thinking_block_idx` 的闭合保护，但 `idx` 恒为 0（单数载体不支持并行），
该分支**永不可达**。事件序列断言 + coverage 阈值配平把它抓了出来：照抄来的
代码掩盖了「fc 与 thinking 不冲突」这个事实。已删除并留注释说明。

### 验证（全绿）

```
MoonBit   1439×2 全过（native + wasm-gc；+4 wbtest：fc 解码×2 + fc 流式×2）
coverage  204/204（新分支全部配平；fc 防御路径由混合序列测试覆盖）
run-all   8 步全绿（[5] 组 16→27 项，含 legacy-fc 矩阵 + 真相断言）
drift     -Strict PASS（字段集 +caller）
```

### 回归

- `src/provider/openai/openai_wbtest.mbt`：`legacy function_call decoded` /
  `legacy function_call stream` / `legacy function_call after text block` /
  `legacy function_call closes conflicting blocks`（事件序列断言）
- `src/provider/messages/messages_wbtest.mbt`：tool_use 编码断言 +`caller`
- oracle：`pipeline.mjs` 源协议 `openai-legacy-fc`（decode 真相 + 四目标 schema +
  messages 工具体幸存断言）

---

## 0. 摘要与决策请求

CR-005 §6.7 记的技术债表述为：

> OpenAI `finish_reason` 的 `function_call` 与 `tool_calls` 是合法枚举里的两个不同项，
> 但 IR 都映射到 `ToolCalls`，回程一律输出 `tool_calls` —— 即 OpenAI → IR → OpenAI
> 保不住 `function_call`。

实测后发现这句话**低估了问题**：`function_call` 形态的响应，其**工具调用内容本身
就丢了**，不只是枚举值退化。

| # | 输入 | 当前产出 | 严重度 | 归类 |
|---|---|---|---|---|
| 1 | `message.function_call: {name, arguments}`（非流式） | `content: []`（**工具调用整体消失**） | 🔴 **数据丢失** | 纯 bug |
| 2 | `delta.function_call`（流式） | 无 `BlockStart` / `BlockDelta`（**同上，静默空流**） | 🔴 **数据丢失** | 纯 bug |
| 3 | `finish_reason: "function_call"` | IR `ToolCalls` → 回程 `tool_calls` | 🟡 保真度退化 | 治理 §6 |

且缺陷 1 的后果具有**误导性**：转 messages 后得到

```json
{"role":"assistant","content":[],"stop_reason":"tool_use"}
```

即「声称调用了工具，却没有任何工具调用内容」—— 下游 Agent 会解析出一个空工具调用
列表，行为不可预测；且**诊断 0 条**，完全静默。

**决策请求**（两部分，可分别批准）：

- **§1 立即修复（不需要治理批准）**：缺陷 1/2 是纯解码 bug，无论 §2 如何决策都必须修。
- **§2 治理提案（需批准）**：缺陷 3 的区分度保真。方案按 CR-005 §6.7 已给出的正确
  方向 —— `LucentChoice` 加可选子类型标记（非破坏性，§6），**不扩
  `LucentFinishReason` 枚举**。选项 A/B 见 §2.2。

---

## 1. 实测证据

方法：给解码器喂官方形态的响应/帧，打印产出 IR 与诊断数。

### 1.1 非流式：工具体丢失（OpenAI 官方旧式形态）

```
输入:
  {"id":"c2","object":"chat.completion","created":1,"model":"gpt-4o",
   "choices":[{"index":0,
     "message":{"role":"assistant","content":null,
                "function_call":{"name":"search","arguments":"{\"q\":\"x\"}"}},
     "finish_reason":"function_call"}]}

IR:  finish_reason = tool_calls
     message.content = []           ← 🔴 工具调用丢失
诊断: 0 条                          ← 🔴 静默

转 messages 后:
  {"role":"assistant","content":[],"stop_reason":"tool_use"}
                                    ← 🔴 声称调了工具但没有工具内容
```

对照：新式 `tool_calls` 形态工作正常（`content: [tool_use]`）。

根因在 `src/provider/openai/response.mbt:26-51`：解码器只读 `tool_calls[]`，
**完全没有 `function_call` 分支**。

### 1.2 流式：同样的丢失

```
输入（三帧）:
  delta: {"role":"assistant","function_call":{"name":"search","arguments":""}}
  delta: {"function_call":{"arguments":"{\"q\":1}"}}
  delta: {}, finish_reason: "function_call"

转 messages 产出: 3 帧
  message_start / message_delta(stop_reason=tool_use) / message_stop
                        ← 🔴 无 content_block_start / input_json_delta
诊断: 0 条              ← 🔴 静默
```

根因在 `src/provider/openai/stream_decode.mbt`：只匹配 `delta.tool_calls`（L227），
无 `delta.function_call` 分支。

### 1.3 缺陷 3：枚举区分度（CR-005 §6.7 原登记项）

`src/lux/helpers.mbt:269`：

```moonbit
"tool_calls" | "tool_use" | "function_call" => ToolCalls
```

三家词汇表在 IR 上收敛为同一个 `ToolCalls`，回程由
`src/provider/meta/finish.mbt:188` 输出 `"tool_calls"`：

```
openai finish_reason="function_call" → IR ToolCalls → openai finish_reason="tool_calls"
                                                       ← 🟡 值变了
```

### 1.4 官方状态：`function_call` 确为 deprecated 但仍在枚举内

`schemas/endpoints/openai-openapi.yaml` 的 `finish_reason` 枚举含 5 个值：
`stop` / `length` / `tool_calls` / `content_filter` / `function_call`，
其中 `function_call` 标注 `deprecated`。

`tools/conformance/schemas/authority.json` 的 `openai.finish_reason` 已收录该值，
oracle [5] 组会校验出站值 ∈ 该集合 —— 故**输出 `function_call` 是合法的**，
不存在「输出非法值」风险。

> 关键判据：**deprecated ≠ 可以丢数据**。字段被标注淘汰，指的是「新流量不会再产生」，
> 不是「老流量可以静默损坏」。中转中间件恰恰要处理存量流量。

---

## 2. 治理提案（按 `lucent-ir-evolution.md` 模板）

### 2.1 缺陷 1/2 的修复（不需要治理）

- **影响面**：协议转换
- **变更类型**：非破坏性（纯解码 bug 修复，不动 IR 类型）
- **保真度预期**：`Exact`

修复方式：

- `src/provider/openai/response.mbt`：在 `tool_calls[]` 分支旁增加
  `message.function_call` 分支 → `LucentContent::tool_use(id, name, args, None)`。
  旧式 `function_call` **没有 `id` 字段**（这是它与 `tool_calls[]` 的结构差异），
  需合成稳定 id（见 §2.3 决策点一）。
- `src/provider/openai/stream_decode.mbt`：`delta.function_call` 按
  `delta.tool_calls` 的同一套块管理逻辑处理（首次出现 → `BlockStart`，
  后续 `arguments` → `tool_arguments_delta`）。

### 2.2 缺陷 3 的区分度（需批准）

CR-005 §6.7 已定性：**不给 `LucentFinishReason` 加变体**（35 处穷尽 match 全受影响，
为 deprecated 值不值）。正确方向是「可选子类型标记，与 `stop_sequence` 同构」。

#### IR 变更提案：`LucentChoice` 增加可选的工具调用形态标记

- **影响面**：**两者兼有**（协议转换 + SDK/Agent 消费——消费者可读到新字段）
- **变更类型**：**非破坏性**（§6「新增可选标准字段 `T?` 类型，默认 null」）
- **保真度预期**：`Exact`
- **涉及字段/类型**：
  - `LucentChoice.tool_call_style`：新增 `String?`，默认 `None`

```moonbit
pub struct LucentChoice {
  index : Int32
  message : LucentMessage
  finish_reason : LucentFinishReason
  stop_sequence : String?        // CR-005 已加
  tool_call_style : String?      // 新增：工具调用的 wire 风格标记
} derive(Eq, Debug)
```

取值语义（封闭小集合，非自由字符串）：

| 值 | 含义 | 来源 |
|---|---|---|
| `None` | 未标注 / 中立（默认） | 大多数情况 |
| `Some("function_call")` | 源协议用的是旧式单数 `function_call` 载体 | OpenAI 旧式 |
| `Some("tool_calls")` | 源协议用的是复数 `tool_calls` 载体 | OpenAI 新式（可不标） |

- **provider 适配影响**：
  - `openai` 解码：`finish_reason=="function_call"` **或** 消息含旧式
    `function_call` 字段 → `tool_call_style = Some("function_call")`；
    `tool_calls[]` → `Some("tool_calls")`（或保持 `None`，见决策点二）
  - `openai` 编码：`tool_call_style == Some("function_call")` 时输出
    `finish_reason:"function_call"`——它在该值 ∈ 目标白名单（§1.4 已证），
    因此不会触发 `arbitrate` 降级诊断
  - `messages` / `responses` / `gemini` 编码：**忽略**该字段（三家的协议无此区分，
    `ToolCalls → tool_use / completed / STOP` 的既有映射不变，不产生新诊断）
  - `messages` / `responses` / `gemini` 解码：恒 `None`

- **迁移策略**（虽然是非破坏性，仍说明兼容性）：
  - `LucentChoice::new` 签名**是否变更** 是两个子选项（见决策点三）。
    若保持不变（推荐），则既有 88 处调用**零改动**，新字段默认 `None`。
  - IR JSON 序列化：新字段 `null` 时可省略或写 `null`（与 `stop_sequence` 同规则）。
  - `schemas/lux-ir-v1.json`：作为 optional property 加入，
    `scripts/check_schema_drift.ps1 -Strict` 需同步。

### 2.3 三个决策点

**决策点一：旧式 `function_call` 没有 `id`，合成什么？**

| 选项 | 做法 | 评价 |
|---|---|---|
| **A（推荐）** | 合成 `"call_fn_0"` 形式的确定性 id | 下游可读；`tool_result` 回程时能对上；**同源往返会造出源没有的 id**（已存在的模式：responses 的 `msg_0` / `fc_0` 前缀就是同类做法） |
| B | 空串 `""` | 与既有 `field_str(...).unwrap_or("")` 风格一致；但下游按 id 索引会撞车 |
| C | `None`（需把 `tool_use` 的 id 改可选） | 破坏性，且 `tool_use` 的 id 在 messages 语义里是必需 |

**决策点二：新式 `tool_calls` 是否也标注 `Some("tool_calls")`？**

- 标 → 区分度更完整（能区分「源用了复数形态」），但大多数流量会带一个冗余字段。
- **不标（推荐）** → `None` 表示「默认/复数形态」，只有旧式才标
  `Some("function_call")`。信息量等价（二值），字段出现率最低。

**决策点三：`LucentChoice::new` 是否加参数？**

- **不变（推荐）**：保持 `new(index, message, finish_reason, stop_sequence)`，
  新字段由 `LucentChoice::with_tool_call_style(choice, style)` 补充。
  与 `LucentResponse::with_provider_payload` 同构，88 处调用零改动。
- 加参数：需改 88 处调用 + 破坏性签名（不推荐）。

---

## 3. 本次不做

- **`function_call` 的请求侧**（`messages[].function_call` / `functions` 参数）：
  OpenAI 的 legacy function calling 请求形态同样 deprecated，且 Prism 的请求侧
  工具模型已统一为 `LucentTool`。存量请求若带 `function_call` 字段，当前是
  `extra` 兜底（不报错）。实测未见数据损坏，故不在本 CR 范围。
- **流式 `Finish` 载荷**（CR-006 §6.8）：与本 CR 正交。

---

## 4. 验收清单

### §1（纯 bug，立即做）

- [ ] `openai` 非流式：`message.function_call` → IR `tool_use`（id 按决策点一）
- [ ] `openai` 流式：`delta.function_call` → `BlockStart` + `tool_arguments_delta`
- [ ] 上述两条均有 wbtest（正向 decode 断言 + 转 messages 后 `tool_use` 幸存断言）
- [ ] oracle [5] 组：新增 `function_call` 样本（`openai → 4 target` 矩阵），
      断言 messages 产出 `content` 含 `tool_use` 且 `stop_reason="tool_use"`
- [ ] 中间态回归：`function_call` 源 → messages，`content` **非空**

### §2（批准后）

- [ ] `LucentChoice.tool_call_style : String?`（默认 `None`）
- [ ] `LucentChoice::with_tool_call_style` 构造器；`new` 签名不变
- [ ] openai 编码：`Some("function_call")` → `finish_reason:"function_call"`
- [ ] openai 同源往返测试：`function_call` → IR → `function_call`（**Exact**）
- [ ] 跨协议：`function_call` → messages 仍是 `tool_use`（无新诊断）
- [ ] `schemas/lux-ir-v1.json` + drift `-Strict` 同步
- [ ] G5 差分不变量：新增生成器维度后仍四端点一致

---

## 5. 与既有决策的关系

| 文档 | 关系 |
|---|---|
| CR-005 §6.7 | 本 CR 是该技术债的实施方案；**修正其严重度定性**（内容丢失 > 枚举退化） |
| CR-005 §0 选型表 | 当时 A vs `function_call` 二选一的结论不变（A 优先）；本 CR 用非破坏性方案补上另一半 |
| `docs/fidelity-matrix.md` §3.14 | 末尾「IR 建模粒度不足（新发现，记为技术债）」第 2 条待本 CR 闭环 |
| `docs/rules/lucent-ir-evolution.md` §6 | 本提案属「新增可选标准字段」，走轻量流程 |

---

## 6. 状态：待决策

请批准：

1. **§1 立即修复**（缺陷 1/2，纯 bug，无需治理批准）——建议无论 §2 结论如何都先做；
2. **§2 方案**：`LucentChoice.tool_call_style : String?`（非破坏性），
   决策点一选 **A（合成确定性 id）**、决策点二选 **不标**、决策点三选 **不变**。
