# Thinking/Reasoning 统一实施计划（SDK + 中转站双场景）

> 日期：2026-08-05
> 关联：ADR-008（thinking/reasoning 架构统一，提案）、
> `docs/analysis/thinking-ideal-architecture-2026-08-04.md`（理想架构，未采用其删除方案）、
> `docs/requirements.md`（双场景 source of truth）
> 治理：涉及 IR 演进，需遵循 `docs/rules/lucent-ir-evolution.md`

## 状态

**计划**（2026-08-05）— 待评审后按阶段实施。

## 背景与目标

调研（2026-08-04）确认 11 厂商存在 4 种 thinking/reasoning 结构类型。现有 IR 已具备
`LucentContent::Thinking`（块内交错）与 `LucentConversationItem::Reasoning`（独立平级项）
两类载体，但**消息级 reasoning（vLLM/DeepSeek/Fireworks 的 `message.reasoning` /
`reasoning_content`）在 IR 中无承载**，且 openai-chat 适配器等不捕获它。

本计划面向两个使用场景：

- **场景 1（SDK）**：开发者需要清晰、类型安全的 thinking 访问（`Thinking` 流事件已满足块内场景；
  缺消息级 reasoning 的明确读取入口）。
- **场景 2（中转站）**：网关需要无损捕获一切 thinking + 明确的 `Exact/Degraded/Unsupported` 诊断；
  缺消息级 reasoning 的表达与跨协议映射。

**目标**：在**不删现有载体、不升 v2** 的前提下，补齐消息级 reasoning 的承载与 openai-chat 等
适配器的捕获/输出/流式/保真度，使双场景都能无损工作。

## 架构决策（与 ADR-008 方案 B 对齐，落点归正到 `LucentMessage`）

经现状盘查，现有代码已部分实现"异质平级"（`LucentConversationItem::Reasoning`），优于理想架构文档
假设的"只有 content 一种表达"。因此**不采用**理想架构的删除式重构（删 `LucentContent::Thinking`、
升 v2、新增 ReasoningStart/Delta/End 流事件）——那会丢失块内交错位置（Anthropic/Mistral/Gemini 的
thinking 夹在文本中），破坏中转站的结构保真。

### 三载体职责分工（不互相取代）

| 载体 | 表达 | 主要服务 |
|------|------|---------|
| `LucentContent::Thinking`（块内，已存在） | thinking 在正文中的交错位置 | 中转站结构保真 |
| `LucentConversationItem::Reasoning`（平级项，已存在） | 独立 Item 级思考（OpenAI Responses） | 中转站 |
| `LucentMessage.reasoning : LucentThinking?`（**新增**） | 消息级 reasoning（vLLM/DeepSeek/Fireworks） | SDK + 中转站 |

> 对比：ADR-008 草案建议放 `LucentResponse.reasoning`。经盘查，消息级 reasoning 是
> `LucentMessage` 的属性（vLLM/DeepSeek 在 message 字段内），且 `LucentResponse` 是多 choice
> 容器，故落点归正到 `LucentMessage`（默认 `None`，向后兼容）。`LucentResponse` 仅提供便捷访问
> 方法（取 `choices[0].message.reasoning`），不新增字段。

### 阶段式 vs 一次性成员

本计划分三阶段实施，阶段一解决调研报告标注的最高优先级缺口（openai-chat 消息级 reasoning 未被
捕获），风险最低；阶段二统一流式表达；阶段三重构诊断边界。每阶段独立可提交、可验收。

---

## 阶段一：IR 承载 + openai-chat 非流式捕获/输出

**目标**：让 `LucentMessage.reasoning` 承载消息级 reasoning，openai-chat 非流式入站捕获
`message.reasoning`/`reasoning_content`，出站合成；SDK 可取用。解决「❌ `message.reasoning` 未被
捕获」（调研报告最高优先级）。

### 涉及文件

- `lux/lux.mbt` — `LucentMessage` 增加 `reasoning : LucentThinking? = None` 字段
- `lux/serialize.mbt` — `LucentMessage::to_json` 输出 `reasoning`（`Some` 时）
- `lux/deserialize.mbt` — `LucentMessage::from_json` 读取 `reasoning`（缺省 `None`）
- `lux/lux.mbt` — `LucentResponse` 增便捷访问方法 `reasoning() : LucentThinking?`
- `provider/openai_chat/chat.mbt` — 入站 `parse_choices` 捕获 `message.reasoning` /
  `reasoning_content`；出站 `lux_response_to_openai_chat` 合成
- 测试：`provider/openai_chat/openai_chat_test.mbt`、`lux/lux_wbtest.mbt` 增补用例

### 改动要点

1. **IR**（`lux.mbt`）：
   ```moonbit
   pub struct LucentMessage {
     role : LucentRole
     content : Array[LucentContent]
     phase : String?
     reasoning : LucentThinking? = None  // 新增：消息级 reasoning
   }
   ```
   默认值使所有既有调用点无需改动。

2. **序列化**（`serialize.mbt` / `deserialize.mbt`）：`LucentMessage::to_json` 在
   `reasoning` 为 `Some` 时输出 `"reasoning"` 字段（复用 `LucentThinking::to_json`，若存在）；
   `from_json` 读取并容忍缺失。

3. **响应便捷访问**（`lux.mbt`）：
   ```moonbit
   pub fn LucentResponse::reasoning(self : LucentResponse) -> LucentThinking? {
     if self.choices.length() > 0 {
       self.choices[0].message.reasoning
     } else {
       None
     }
   }
   ```

4. **openai-chat 入站**（`chat.mbt` `parse_choices`，约 662-716）：在 662 `msg_jv` 处读取：
   - `message.reasoning`（vLLM）→ `LucentThinking::visible(text, None)`
   - `message.reasoning_content`（DeepSeek/Fireworks）→ 同上
   - 构造 `LucentChoice` 时填入 `msg.reasoning`

5. **openai-chat 出站**（`chat.mbt` `lux_response_to_openai_chat`）：对 `c.message.reasoning`
   的 `Some` 合成 `reasoning`/`reasoning_content` 字段（按目标模型形态，经 extra 或约定确定字段名；
   默认兼容 vLLM 用 `reasoning`）。

### 验收

- `moon test` 通过；新增单测断言 vLLM 格式（`message.reasoning`）与 DeepSeek 格式
  （`message.reasoning_content`）入站后 `choice.message.reasoning.text` 正确。
- 序列化 round-trip：含 reasoning 的 response 序列化→反序列化不丢失。
- `.mbti` diff 仅新增 `LucentMessage.reasoning` 字段与 `LucentResponse::reasoning` 方法，符合预期。

---

## 阶段二：openai-chat 流式捕获、出站 + 保真度诊断

**目标**：补齐 `delta.reasoning`/`delta.reasoning_content` 流式捕获，流式出站编码 Thinking；
签名丢失等产生 `Degraded` 诊断（调研报告「签名跨协议丢失」）。

### 涉及文件

- `provider/openai_chat/chat.mbt` — 流式入站 `openai_chat_sse_to_events` 处理
  `delta.reasoning`/`delta.reasoning_content`；流式出站 `lux_events_to_openai_chat_sse` 编码
  `ThinkingDelta`
- `lux/stream.mbt` — 累加器在需要时把消息级 thinking 归位（评估是否扩展
  `lucent_stream_events_to_accumulated` 支持 `LucentMessage.reasoning`）
- 测试：openai-chat 流式测试

### 改动要点

1. **流式入站**：在 `chat.mbt` 的 delta 处理（约 922-998）增加：
   - `delta.reasoning` / `delta.reasoning_content` → `BlockStart(idx, Thinking)` + `BlockDelta(ThinkingDelta)`
     （复用现有 block 生命周期；流式暂走 content 的 Thinking block，见「流式/非流式统一」）
2. **流式出站**：`lux_events_to_openai_chat_sse`（约 1041-1086）当前对 `ThinkingDelta` 为 `()` 忽略，
   改为编码 `delta.reasoning`/`reasoning_content`。
3. **保真度**：当出站目标协议丢失 `signature`/`redacted`/`summary` 时，产生
   `ConversionDiagnostic(status: Degraded, field: "reasoning.signature"... )`——沿用 stream.mbt 已有
   `Degraded` 诊断风格。

### 验收

- 流式 round-trip：openai-chat SSE（含 `delta.reasoning_content`）→ Lux 事件 → 目标协议，
  内容不丢。
- 签名丢失场景产生 `Degraded` 诊断（非 `Unsupported` 也非静默）。

---

## 阶段三：跨协议映射表 + 双载体职责收敛

**目标**：将 ADR-008 的入站/出站/流式映射表落定为正式执行文档，覆盖全 11 厂商；收敛
`LucentMessage.reasoning` 与 `LucentContent::Thinking` 的语义边界,消除双载体冗余。

### 涉及文件

- `docs/` — 新增/更新 `docs/lux-ir-design.md` 的 reasoning 章节（映射表）
- `provider/*` — 补 diff：openai_azure、gemini_vertex（当前无 thinking 处理，若复用 openai-chat/gemini
  核心则确认），openai_codex（当前只出站 effort 配置）

### 改动要点

1. 建立正式映射表：每厂商 ×（入站承载 / 出站展开 / 流式事件 / 保真度诊断），确认
   `LucentMessage.reasoning` vs `LucentContent::Thinking` 的归属（见架构决策表格）。
2. 核查 openai_azure / gemini_vertex 是否复用核心逻辑，缺则补齐与 openai-chat/gemini 一致的处理。
3. openai_codex 出站已支持 `reasoning.effort`（含 xhigh），确认响应/流式 reasoning 表达。

### 验收

- 映射表评审通过，写入 `docs/lux-ir-design.md`（与 `lucent-ir-evolution.md` 治理核对）。
- 覆盖厂商测试无 `Unsupported` 静默丢失（与 `Degraded` 区分）。

---

## 未决问题

- **流式/非流式统一**：阶段一流式走 content 的 Thinking block、非流式走 `LucentMessage.reasoning`，
  两者表达同一消息级 reasoning 但位置不同。阶段二评估累加器是否统一归位到
  `LucentMessage.reasoning`（需扩展 `lucent_stream_events_to_accumulated`），或文档化该语义差异。
- **字段名分歧**：vLLM 用 `reasoning`、DeepSeek/Fireworks 用 `reasoning_content`。出站合成时如何
  确定性选字段名（经 extra/ProviderCapability 约定）。
- **`LucentResponse.reasoning` vs `LucentContent::Thinking` 并存时的出站优先级**：当两者都存在时，
  优先用哪个（意向：`LucentMessage.reasoning` 优先，回退 content 的 Thinking block）。
- **Gemini Interactions `thought_summary` 与 `LucentThinking.summary` 融合策略**。

## 影响范围汇总

| 层 | 改动 |
|----|------|
| IR | `LucentMessage.reasoning : LucentThinking? = None`（非 breaking）；`LucentResponse::reasoning()` 访问器 |
| 序列化 | `LucentMessage` 输入/输出 `reasoning` |
| openai-chat | 非流式 + 流式入站捕获、出站合成、保真度诊断 |
| 其他适配器 | 阶段三核查与收敛 |
| 测试 | 逐阶段新增单测 + 契约测试 |
