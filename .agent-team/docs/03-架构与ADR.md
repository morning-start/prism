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

```
### ADR-003 wasm 导出 ABI 按后端条件编译：线性内存指针技巧仅限纯 wasm，
### wasm-gc/js 走降级实现 + js-string-builtins
- 状态：已接受（2026-10-25，TL 决策，TASK-2b 方案 A，commit d9ceb41）
- 背景：POC-1（Node 加载验证）发现 memory.mbt 的 scratch/log ABI 用
  `= "%identity"` 把 Int32 强转为 Bytes/FixedArray 引用——该技巧依赖
  纯 wasm 后端的引用计数非移动 GC；wasm-gc 下类型是 GC 托管结构，
  生成的模块被 V8 校验直接拒绝，22 项合法转换导出被连坐（RISK-006）。
  另发现 moon.pkg 的 link.exports 从未声明 wasm-gc 后端（f1e3311 修复）
- 决策：①memory ABI 按后端拆分——memory.mbt 限 [wasm, native, llvm]，
  新增 memory_wasmgc.mbt 限 [wasm-gc, js]，降级实现签名与原 ABI 一致
  （scratch/log 返回 0/错误信封，trace 直调转换）；②wasm-gc 开启
  use-js-builtin-string（String ABI = JS string，宿主直传原生字符串），
  常量命名空间 "_"；③宿主契约：instantiate 须传 builtins:['js-string']
  + importedStringConstants:'_'（Node ≥ 22 无需 flag）
- 备选方案：B）用 wasm-gc 合法方式完整重建大字符串/日志通道 ——
  放弃原因：工期 2~3d 且 MVP 不依赖这 6 个导出，列技术债 TD-004 待偿；
  C）wasm-pack 中间层 —— 放弃原因：POC 证明裸 import 即可，多一层
  打包徒增维护面
- 后果：wasm-gc 下 scratch/log 6 导出降级（调用得错误信封而非数据），
  wrapper 层须在文档中声明；ACC-001 验收标准不受影响（不依赖这 6 导出）
- 何时重构：wrappers MVP 落地后，若宿主确需 wasm-gc 大字符串/日志通道，
  启动方案 B（TD-004 偿还）
```

```
### ADR-004 WASM 产物加载冒烟进 CI（TASK-2c）
- 状态：已实现（2026-10-25，commit 4d0f446；CI job `wasm-smoke`）
- 背景：POC-1 暴露 ABI 假阴性——moon test 的 wasm-gc runner 不校验主模块
  导出段，1442 tests 全绿但产物在真实引擎无法加载（RISK-007）；QA 验收
  TASK-2b 时确认修复新增的两个配置面（targets 拆分 / wasm-gc link options）
  也无护栏，且 moonc 对 exports 清单中不存在的函数静默忽略（P2-1 根因）
- 决策：CI 新增 wasm-smoke job：Node 22 引擎加载两后端产物，断言
  ①导出数 ≥25 且 29 项关键锚点在位（QA P2-2 宽松口径，不用精确计数避免
  _start 干扰）②abi=1 ③每后端 1 次真实转换 + 诊断透出 ④wasm-gc 降级
  语义（scratch=0/错误信封）⑤js-string-builtins 宿主契约负向验证
  （缺 options 实例化必须失败）⑥流会话含 finished 自查 ⑦纯 wasm scratch
  协议全链路。脚本 scripts/wasm_smoke.mjs 可独立运行
- 备选方案：不加 —— 放弃原因：ABI 回归只能在消费者侧发现，本次两起缺陷
  （POC-1 / P2-1）均为测试全绿假阴性
- 何时重构：无（长期护栏）；wrappers 集成测试（TASK-5）落地后，本冒烟
  作为其前置快速检查保留
```

### 历史架构裁决（登记于正式文档，此处仅索引）

| 裁决 | 位置 |
|---|---|
| lux/sdk 不拆包、registry 模型、导航式组织 | `docs/architecture.md` Current decisions |
| BlockDiscard 保留 + deprecated（CR-003 决策 B） | `docs/cr/CR-003-block-discard-proposal.md` |
| finish_reason 目标白名单裁决模型 | `docs/design/finish-reason-contract.md` |
| CR-006 方案 A（Finish 载荷破坏性变更） | `docs/cr/CR-006-stream-termination.md` |
