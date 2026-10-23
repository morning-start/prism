# IR 变更提案：BlockDiscard 的去留

> 状态：**已决策 — 选项 B（保留 + 标记 deprecated）** · 提出日期：2026-10-18 · 决策日期：2026-10-23
> 依据：`docs/rules/lucent-ir-evolution.md` §5「破坏性变更判定」与 §2「影响面声明」
> 触发：流式会话化修复（P0/P1）审计中发现该事件**全链路无生产者**

## 1. 现状事实（已实证）

**结论：`BlockDiscard` 是一个从不会被发出的 IR 事件。**

证据：

1. **无生产者**——全仓检索 `BlockDiscard` 的构造点，生产代码中**零命中**：
   - `src/lux/deserialize_stream.mbt:81`：从 JSON 反序列化（**输入**方向，非生产）
   - `src/lux/serialize_stream.mbt:81`：序列化为 JSON（输出方向）
   - `src/lux/stream.mbt:153`：枚举定义
   - `src/sdk/event_stream.mbt`、`src/sdk/codec_pipeline.mbt`：**消费**分支（处理它，
     但没有任何代码产生它）
   - `src/provider/gemini/stream_encode.mbt:204`：编码侧收到时打 Degraded
   - 四个 provider 的 `stream_decode.mbt` 全部**不产生**该事件

2. **Gemini 明确不用**——`src/provider/gemini/stream_decode.mbt:10` 原文：
   > 「因此这里不做 full-frame diff、也不发 `BlockDiscard`：增量直接透传为
   > `BlockDelta`，与官方 chunk 语义一致」

   依据是 Gemini 官方语义：`parts[].text` 是**增量**（"the new text, not the
   running total. Concatenate; do not replace"），因此「全量帧覆盖前一帧」这一
   `BlockDiscard` 的设计前提**不成立**。

3. **文档与实现矛盾（已修正）**——`docs/fidelity-matrix.md:101` 曾把 Gemini
   「全量帧覆盖（BlockDiscard）」标为 `✅`，其余目标 `🟡`，暗示这是一条已实现的
   路径。本次已更正为 `❌ 未实现`，并在 §4 第 7 条记录根因。

## 2. 治理提案（按模板）

### IR 变更提案：移除 `BlockDiscard` 流事件变体

- **影响面**：协议转换（删除事件变体）+ SDK/Agent 消费（下游匹配该事件的代码路径失效）
- **变更类型**：**破坏性**——§5 明列「移除现有枚举变体（即使标记 deprecated）」为破坏性变更
- **保真度预期**：不影响保真度（该事件当前保真度贡献为 **0**：无生产者、无实际载荷）
- **涉及字段/类型**：
  - `LucentStreamEvent::BlockDiscard(Int32)`：`enum 变体` → `移除`
  - `schemas/lux-ir-v1.json:572`：`"const": "block_discard"` oneOf 分支 → `移除`
  - `src/lux/stream.mbt:153`：注释「Gemini 全量帧覆盖前一帧时用」→ 该断言与
    实现矛盾，需一并处理
- **provider 适配影响**：
  - `openai`：无影响（从不产生、也不消费）
  - `messages`：无影响（同）
  - `responses`：无影响（同）
  - `gemini`：**受益**——移除 `stream_encode.mbt:204` 的 Degraded 死代码分支
    （该分支永不可达）
- **迁移策略**（破坏性变更必填）：
  1. **保留反序列化容错**：`deserialize_stream.mbt` 收到 `block_discard` 时
     不再构造该变体，而是**丢弃 + 打 `Unsupported` 诊断**（符合 governance §4
     「扩展字段反序列化失败必须是软失败」的精神：宁可保留告警也不抛错）。
     这样旧版发出该事件的 JSON 仍可被新版**无损读取**（只是不再有语义载体）。
  2. **schema 版本**：`lux-ir-v1.json` 的 oneOf 分支应同时**接受** `block_discard`
     为合法输入（向后兼容读取）但从**输出**侧移除——若确定为纯输入兼容，
     则不需要 major 版本递增；若移除输入兼容，则需 `v2`。
  3. **SDK 消费方**：`EventNormalizer` / `PrismEventBuffer` / `codec_pipeline`
     的 `BlockDiscard` 匹配分支一并删除（当前均为死代码）。

## 3. 决策选项

| 选项 | 描述 | 代价 | 兼容性 |
|---|---|---|---|
| **A. 完全移除**（推荐） | 删枚举变体 + schema 分支 + 4 处消费分支 + gemini 死分支 | 破坏性变更，需 major 版本 | 旧 JSON 需容错读取 |
| **B. 保留但标记 deprecated** | 仅更新注释与文档，不再声称「Gemini 全量帧覆盖」 | 保留死代码与误导性命名 | 完全兼容 |
| **C. 保留并赋予真实语义** | 为某个真实需要「撤销已发块」的场景实现它 | 需先有真实用例 | 完全兼容 |

**建议：选 B，暂缓 A。**

理由：
1. **当前无真实用例**——移除的收益是「少一段死代码」，成本是一次破坏性
   schema 变更 + 全链路适配。而 §3「保真度边界是硬约束」优先级高于代码整洁。
2. **A 的前置条件未满足**——治理 §1 要求「理解当前契约边界后再动笔」。目前
   尚未确认：「是否存在某个我们未支持的 provider，其流式协议真的需要
   『撤销已发内容块』语义？」（例如上游重试导致的部分流回滚）。在回答该问题前
   移除是**信息不足下的破坏性决策**。
3. **B 已消除主要危害**——本次审计的实质危害是「文档声称已实现、实际未实现」，
   已通过更正 fidelity-matrix 与 IR 注释消除。死代码本身不产生错误行为。

**若后续选择 A**，应作为独立 CR 走完整流程，并附带：
- 确认无外部 SDK 消费方依赖该变体；
- `deserialize_stream` 的容错读取测试（旧 JSON 不报错）；
- schema 版本策略（`v1` 输入兼容 / `v2` 输出契约）。

## 4. 本次已实施的部分（非破坏，无需 A/C）

以下已完成，均属治理 §6「非破坏性变更 / 文档更新」：

- `docs/fidelity-matrix.md`：Gemini 行由 `✅` 更正为 `❌ 未实现`，并加注原因
  （全链路无生产者）。
- `src/lux/stream.mbt`：`BlockDiscard` 的注释由「Gemini 全量帧覆盖前一帧时用」
  更正为「IR 定义保留；当前无解码器生产该事件」。
- `src/sdk/event_stream.mbt`：消费分支加注「当前无解码器生产」。
- `docs/api-protocol-converter.md`：补 Gemini 列与跨帧状态落点硬规则。

## 5. 决策落地（2026-10-23，选项 B）

- [x] 决策 A / B / C —— **选 B**（用户批准）：保留 + 标记 deprecated，暂缓移除。
      C 在无真实用例前不启动；A 的前置问题（是否存在需要「块撤销」语义的
      provider）保持开放，回答为「是」时再以独立 CR 重开。
- [x] `src/lux/stream.mbt`：变体注释升级为完整废弃记录（决策出处、无生产者
      事实、B 的理由、新代码不依赖的告诫；MoonBit `#deprecated` 不支持枚举
      变体级标注——`unused_attribute` 警告，与 `--deny-warn` 门禁冲突——故用
      文档注释表达废弃语义）。
- [x] `src/lux/deserialize_stream.mbt`：`block_discard` 读取分支加注容错语义
      （存量 JSON 可读入；本实现不产出）。
- [x] `schemas/lux-ir-v1.json`：`block_discard` oneOf 分支加 `description`
      废弃标记；保留为**合法输入**（向后兼容读取），输出契约不变。
- [x] `src/provider/gemini/stream_encode.mbt`：Degraded 死分支加注（仅手工
      构造/第三方事件流可达）。
- [x] 事实锁定：`src/sdk/test/stream_event_coverage_test.mbt`
      "no provider decoder emits BlockDiscard" —— 无生产者事实被回归测试
      锚定，未来任何解码器产出该事件都会令测试失败并提示重审本 CR。
- [ ] 若后续选 A：`schemas/lux-ir-v1.json` 版本策略与迁移测试
      （前置：确认无外部 SDK 消费方依赖该变体）。
