# 03-架构与 ADR

> TL 主导维护。**架构的单一事实源是 [`docs/architecture.md`](../../docs/architecture.md)**
> （分层、包职责、依赖方向、Current decisions）；本文件只登记团队流程产生的增量决策
> （ADR），不复制架构内容，两者冲突时以 `docs/architecture.md` 为准并回改本文件。

## 架构总览（速览，详见正式文档）

```
OpenAI JSON ──[decode]──► Lucent IR ──[encode]──► Anthropic JSON
Gemini JSON ◄──[encode]── Lucent IR ◄──[decode]── OpenAI JSON
                              │
                 your code here (audit / rewrite / route / filter)
```

| 层 | 位置 | 职能 |
|---|---|---|
| Core | `src/lux/` | Lucent IR：类型、序列化、诊断、流事件（零 IO、零厂商绑定） |
| Adapters | `src/provider/*` | 每协议一包，统一 6 函数 encode/decode 契约 |
| SDK | `src/sdk/` | `Prism` 门面 + registry + 路由 + Context（唯一收敛点） |
| Transport | `src/wasm/`、`src/cmd/main` | WASM 字符串 ABI（HTTP/IPC 为 future，M1 不做） |

## ADR 列表

```
### ADR-001 团队协作文档落位 .agent-team/（项目内）
- 状态：已接受（2026-10-25，用户决策）
- 背景：上一轮把需求池/任务板等写在 DSH 全局侧 default-workspace/team-workspace/，
  不随项目走，换机器/项目即失联；且与"共享文档随项目"规范冲突
- 决策：迁入项目根 .agent-team/docs/（git 跟踪），随项目走；AGENTS.md 同步修订
- 备选方案：①保留全局侧 ②迁入项目 docs/ 与技术文档混放 ③gitignore
- 放弃原因：①不随项目走 ②流程文档与技术文档受众/生命周期不同，混放会让
  docs/README 索引膨胀 ③历史不可追溯
- 何时重构：若未来 DSH 提供项目级共享工作区原生支持，可整体迁移
```

```
### ADR-002 M1 里程碑定调「生态可用性」，wrappers POC 先行
- 状态：已接受（2026-10-25，用户决策）
- 背景：wrappers 历史记录声称 Complete 但仓库无目录（RISK-001），是唯一阻塞
  对外可用的高优项；用户澄清"还没做好，问题很大，后面再做"
- 决策：M1 主线 = wrappers 单语言（TS）端到端链路 + CI 化；POC 先行不承诺工期；
  IR 治理（REQ-002）与协议扩展（第五协议）分列 M2/M3
- 备选方案：①先做 IR 治理（质量优先）②先扩第五协议（覆盖面优先）
- 放弃原因：①四项均有 adapter 级缓解，不阻塞外部用户 ②无市场信号支撑
- 何时重构：M1 完成评审时（RISK-001 降级/关闭）重新排序 M2/M3
```

### 历史架构裁决（登记于正式文档，此处仅索引）

| 裁决 | 位置 |
|---|---|
| lux/sdk 不拆包、registry 模型、导航式组织 | `docs/architecture.md` Current decisions |
| BlockDiscard 保留 + deprecated（CR-003 决策 B） | `docs/cr/CR-003-block-discard-proposal.md` |
| finish_reason 目标白名单裁决模型 | `docs/design/finish-reason-contract.md` |
| CR-006 方案 A（Finish 载荷破坏性变更） | `docs/cr/CR-006-stream-termination.md` |
