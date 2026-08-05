# Thinking/Reasoning 统一 — 任务编排（Batch 化）

> 日期：2026-08-05
> 依据：`docs/plans/2026-08-05-thinking-reasoning-unification.md`（计划）
> 治理：`docs/rules/lucent-ir-evolution.md`；IR 变更前必读
> 关联 ADR：`docs/adr/ADR-008-thinking-reasoning-unification.md`

## 编排逻辑（Batch 划分依据）

按「依赖顺序 + 相近任务聚合」分 4 个 Batch，每 Batch 独立可提交、可验收：

| Batch | 主题 | 聚合理由 | 依赖 |
|-------|------|---------|------|
| A | IR 承载硬化 | 同一类型的结构改动（struct + serialize + deserialize + 访问器），一次成型；后续所有 Batch 的前提 | 无 |
| B | openai-chat 非流式捕获/输出 | 同一适配器的入站+出站对称改动，成对验证才完整 | A |
| C | 流式捕获/输出 + 累加器归位 + 诊断 | 流式入站/出站对称 + 累加器一致性，三者共享流事件模型，聚合改动最小 | B |
| D | 跨厂商核查 + 文档收敛 | 只读核查 + 文档/治理收尾，独立于 A/B/C 的代码链路 | A（映射表依赖新字段） |

**并行性**：A 必须先于 B/C/D；B、C 串行（C 复用 B 的入站模式）；D 与 B/C 可并行
（D 只读 + 文档，不触碰 B/C 适配器代码）。

---

## Batch A：IR 承载硬化

> 让 `LucentMessage` 承载消息级 reasoning，序列化闭环，SDK 可访问。解决「基础承载缺失」。

### A1. `LucentMessage` 增加 `reasoning` 字段 + 修正 `with_phase`

- **文件**：`lux/lux.mbt`
- **改动**：
  - `LucentMessage` struct（约 118-123）增加字段：
    ```moonbit
    pub struct LucentMessage {
      role : LucentRole
      content : Array[LucentContent]
      phase : String?
      reasoning : LucentThinking? = None  // 消息级 reasoning（vLLM/DeepSeek/Fireworks）
    }
    ```
  - `LucentMessage::with_phase`（约 652-659）的 record literal `{ role, content, phase }`
    **必须**补 `reasoning: None`——MoonBit record literal 缺默认字段会编译失败。
- **验收**：`moon check` 通过；`LucentMessage::new` 全部 12 处调用点（`lux/stream.mbt:462`、
  `provider/openai_chat/chat.mbt:118/124/712`、`provider/anthropic/anthropic.mbt:134/143/737`、
  `provider/gemini/gemini.mbt:254/718`、`provider/openai_responses/responses.mbt:77/588`、
  `sdk/context.mbt:144`）无需改动即编译。

### A2. 序列化 `reasoning`

- **文件**：`lux/serialize.mbt`（`LucentMessage::to_json`，约 223）、
  `lux/deserialize.mbt`（`LucentMessage::from_json`，约 639）
- **改动**：
  - `to_json`：`reasoning` 为 `Some` 时输出 `"reasoning"` 字段，复用
    `LucentThinking::to_json`（serialize.mbt:104，字段含 `text`/`redacted`/`signature?`/`summary?`）。
  - `from_json`：读取 `"reasoning"`，缺省 `None`（若齐全，也可用 `LucentThinking::from_json`）。
- **验收**：含 reasoning 的 response 序列化→反序列化 round-trip 不丢失。

### A3. `LucentResponse::reasoning()` 便捷访问器

- **文件**：`lux/lux.mbt`（`LucentResponse` 方法区，约 1085 附近）
- **改动**：取 `choices[0].message.reasoning`，`choices` 空时返回 `None`。
  方案 B 是访问器而非字段（`LucentResponse` 是多 choice 容器，reasoning 属于 message）。
- **验收**：`.mbti` 仅新增 `LucentMessage.reasoning` 字段与 `LucentResponse::reasoning` 方法。

### A4. 单测

- **文件**：`lux/lux_wbtest.mbt`
- **用例**：`LucentMessage` 含/不含 reasoning 的 to_json / from_json round-trip；
  `LucentResponse::reasoning()` 空 / 无 reasoning / 有 reasoning。

**Batch A 验收**：`moon check` + `moon test` + `moon info && moon fmt`；`.mbti` diff 符合 A3 预期。

---

## Batch B：openai-chat 非流式捕获/输出

> 解决调研报告最高优先级「❌ `message.reasoning` 未被捕获」。入站+出站成对落地。

### B1. 入站 `parse_choices` 捕获 reasoning

- **文件**：`provider/openai_chat/chat.mbt`，`parse_choices`（约 654-740）
- **改动**：在 `msg_jv`（约 662）处读取：
  - `message.reasoning`（vLLM）→ `LucentThinking::visible(text, None)`
  - `message.reasoning_content`（DeepSeek/Fireworks）→ 同上
  - 构造 `LucentChoice` 时填入 `msg.reasoning`（`parse_choices` 当前用
    `LucentMessage::new(role, content)`，需改为 record literal 或新增 `with_reasoning` 辅助；建议不扩 `new` 签名）。
- **验收**：vLLM 格式与 DeepSeek 格式入站后 `choice.message.reasoning.text` 正确。

### B2. 出站 `lux_response_to_openai_chat` 合成 reasoning

- **文件**：`provider/openai_chat/chat.mbt`，`lux_response_to_openai_chat`（约 762-845）
- **改动**：`c.message.reasoning` 为 `Some` 时在 message 对象（约 790-820 的 `msg_obj`）合成
  `reasoning` 字段。字段名默认 `reasoning`（vLLM），经 `extra`/`ProviderCapability` 显式声明
  `reasoning_field: "reasoning_content"` 时切换；无声明但确需 DeepSeek 形态时给出 `Unsupported`
  显式诊断而非静默。
- **验收**：出站 round-trip 不丢 reasoning；字段名分歧有明确默认。

### B3. 契约测试

- **文件**：`provider/openai_chat/openai_chat_test.mbt`、`lux/cross_protocol_test.mbt`
- **用例**：vLLM 格式入站→出站 round-trip；DeepSeek 格式入站→出站 round-trip。

**Batch B 验收**：`moon test` 通过；B1/B2 单测 + 契约测试全绿；`.mbti` 无意外外部变化。

---

## Batch C：流式捕获/输出 + 累加器归位 + 保真度诊断

> 统一流式表达，消除「流式走 content-Thinking、非流式走 message.reasoning」的分裂。

### C1. 流式入站捕获 `delta.reasoning` / `delta.reasoning_content`

- **文件**：`provider/openai_chat/chat.mbt`，`openai_chat_sse_to_events`（约 860-1030）
- **改动**：在 delta 处理（约 940-985）增加：
  - `delta.reasoning` / `delta.reasoning_content` → `BlockStart(idx, Thinking)` +
    `BlockDelta(ThinkingDelta)`（复用现有块生命周期，与当前 `content` 分支平行）。
  - 注意块索引管理：reasoning 增量需要独立块索引，避免与 content 块冲突。
- **验收**：含 `delta.reasoning_content` 的 SSE 流解码出 Thinking 块事件。

### C2. 流式出站编码 ThinkingDelta

- **文件**：`provider/openai_chat/chat.mbt`，`lux_events_to_openai_chat_sse`（约 1041-1086）
- **改动**：第 1086 行 `ThinkingDelta(_) | SignatureDelta(_) | RefusalDelta(_) => ()`
  —— 目前 ThinkingDelta 被静默忽略。改为对 `ThinkingDelta` 编码 `delta.reasoning` /
  `reasoning_content`（按 C1 对称的字段名规则）。
- **验收**：流式 round-trip（SSE→Lux 事件→目标协议）内容不丢。

### C3. 累加器归位：thinking → `message.reasoning`

- **文件**：`lux/stream.mbt`，`lucent_stream_events_to_accumulated`
- **改动**：`flush_block(Thinking)`（约 243-262）当前把 `Thinking(th)` push 进 `content[]`。
  改为同时（或优先）累积到一个 `LucentThinking?` 变量，最终消息（约 462
  `LucentMessage::new(Assistant, final_content)`）改用该 `message.reasoning`。
  **这是「不评估、必须做」**——否则 SDK 流式累加后 reasoning 又回到 content，
  与非流式不一致，正是最初问题。
- **验收**：同一 reasoning 流经流式累加与非流式入站得到一致的
  `message.reasoning`；`content[]` 不含 Thinking。

### C4. 保真度诊断（签名丢失 → `Degraded`）

- **文件**：`provider/openai_chat/chat.mbt` 出站、`lux/stream.mbt`
- **改动**：出站目标协议丢失 `signature`/`redacted`/`summary` 时产生
  `ConversionDiagnostic(status: Degraded, field: "reasoning.signature"/...)`——
  沿用 stream.mbt 已有 `Degraded` 风格；非 `Unsupported` 也非静默。
- **验收**：签名丢失场景产生 `Degraded` 诊断。

**Batch C 验收**：`moon test`；C1-C3 流式测试 + C4 诊断测试全绿。

---

## Batch D：跨厂商核查 + 文档收敛

> 落定 11 厂商映射表；核查 azure/codex/vertex 复用关系；收敛双载体语义边界。

### D1. 修正跨厂商复用假设（只读核查）

- **文件**：复盘 `provider/openai_azure/azure.mbt`、`provider/openai_codex/codex.mbt`
- **发现（已核验）**：`openai_azure`、`openai_codex` 的 `moon.pkg` **import `openai_responses`**，
  不是 openai-chat；二者是 openai_responses 的薄封装。原计划「azure 复用 openai-chat 核心」
  有误。`gemini_vertex` 复用 `gemini`。
- **改动**：确认 reasoning 是否已通过 openai_responses 的 Item 级
  `Reasoning(LucentThinking)` 流动；gemini_vertex 随 gemini 不涉及消息级 reasoning；
  openai_codex 响应/流式 reasoning 表达需确认。
- **验收**：写清 azure→responses、codex→responses、vertex→gemini 的 reasoning 传递路径。

### D2. 落定映射表 + 收尾未决问题

- **文件**：`docs/lux-ir-design.md`（reasoning 章节）、对照
  `docs/rules/lucent-ir-evolution.md` 治理
- **改动**：
  - 写正式映射表：每厂商 ×（入站承载 / 出站展开 / 流式事件 / 保真度诊断）。
  - 明确的归属：`LucentMessage.reasoning`（消息级）vs `LucentContent::Thinking`（交错位置）vs
    `LucentConversationItem::Reasoning`（Responses Item）。
  - 收尾三个未决问题：(a) 出站字段名分歧（B2 已定默认，此处文档化）；(b) 双载体出站优先级
    ——定为「`LucentMessage.reasoning` 优先，回退 content Thinking，同时存在视为 `Degraded`」；
    (c) 流式/非流式归位（C3 已定，此处文档化）。
- **验收**：映射表评审通过；与 `lucent-ir-evolution.md` 核对；覆盖厂商测试无 `Unsupported`
  静默丢失（与 `Degraded` 区分）。

**Batch D 验收**：文档评审通过；无新增代码缺陷。

---

## 依赖与并行小结

| Batch | 前置 | 可并行 |
|-------|------|--------|
| A | 无 | — |
| B | A | — |
| C | B | — |
| D | A | B、C（只读 + 文档，不碰适配器代码） |

顺序执行：A → (D 可与 B/C 并行) → B → C。每 Batch 独立 `moon check` / `moon test` /
`moon info && moon fmt` 后提交。
