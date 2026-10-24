# Changelog

本文件记录 Prism 的用户可见变更。格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)；
0.x 阶段 minor 即 breaking（与 MoonBit 生态惯例一致）。

## [0.2.0] - 2026-10-24

### 破坏性变更（CR-006 批次 2，治理 §5 —— `Finish` 载荷）

变更单：[`docs/cr/CR-006-stream-termination.md`](docs/cr/CR-006-stream-termination.md) §3–§5。

- **`LucentStreamEvent::Finish` arity 1 → 2**：`Finish(reason)` →
  `Finish(reason, stop_sequence?)`。第二位置参数与 `LucentChoice.stop_sequence`
  **完全同构**——一个事实一种表达，流式侧命中序列从此有 IR 载体
  （此前是「Degraded 诊断 + 丢弃」的有意识降级）。
- **迁移机械式**：构造 `Finish(x)` → `Finish(x, None)` 或便利构造器
  `LucentStreamEvent::finish(x)`；模式 `Finish(p)` → `Finish(p, _)` 或
  `Finish(p, ss)`。全部由编译器穷举暴露（生产 19 处 + 测试字面量），
  不存在静默通过。**JSON / WASM 字符串 ABI 字节形态不变**（`None` 不输出
  `stop_sequence` 键），只读 `finish_reason` 的旧消费端不受影响。
- **行为变化**：
  - `messages` 流式解码：`message_delta.stop_sequence` 有值时随 `Finish`
    携带（不再打 Degraded 诊断）；
  - `messages` 流式编码：`Finish` 携带值时写 `"stop_sequence":"<v>"` 并强制
    `stop_reason: "stop_sequence"`（与非流式同规则）；无值时该键写 `null`
    （官方 message_delta 帧恒带该字段）；
  - `openai` / `responses` / `gemini` 流式编码：携带值 → 显式 `Unsupported`
    诊断（与非流式同规则）；
  - 流式累加器把命中值写进 `LucentChoice.stop_sequence` ——
    **流式累加结果与非流式解码完全一致**（CR-005 缺陷 A 在两条路径上的终局）。
- **schema**：`LucentStreamEvent` finish 分支新增可选键 `stop_sequence`
  （`required` 不变，§6 非破坏）；`docs/lux-ir-design.md`、
  `docs/fidelity-matrix.md` 同步。

### 新增（工程内部）

- `@meta.pair_usages_with_finish`：Usage/Finish 配对预扫描抽为协议无关共享
  （messages 与 gemini 流编码共用；gemini 顺带修复 usageMetadata 必须随
  finishReason 帧发射的帧序违反）。
- 流式管线 oracle（[6] 组，`tools/conformance/pipeline-stream.mjs`）：
  官方 SSE → Prism → 目标 SSE 逐帧形态 + 帧序契约 36 项，首跑实锤并修复
  4 类真实编码缺陷（gemini 分帧符 / 双逗号 JSON / responses extra 捕获口径 /
  gemini usage 帧序）。

## [0.1.5] - 2026-10-24

### 修复（CR-006 批次 1：流式终止事件不再静默丢弃）

变更单：[`docs/cr/CR-006-stream-termination.md`](docs/cr/CR-006-stream-termination.md) §2。

此前 `Finish(LucentFinishReason)` 作为流式终止状态的唯一载体，在四类输入上
**静默丢弃信息、零诊断**（实测见 CR-006 §1）：

- **responses 流式**：`response.incomplete` / `response.failed` / 官方扁平 `error`
  帧落进 `_ => ()` 兜底，产出 **0 个事件** —— 一个失败的流经 Prism 中转后
  对下游表现为「什么都没有发生」。现在：
  - `response.incomplete` → `Finish(<映射>)` + `Usage` + `Done`，
    `incomplete_details.reason` 逐值对齐非流式（`content_filter` → `ContentFilter`、
    `max_*` → `Length`、其它 → `Native(reason)` 保留）
  - `response.failed` → `Error(LucentError)`（kind / provider_code / message）+
    `Finish(Error)` + Degraded 诊断 `response.error` + `Done`
  - 官方扁平 `error` 帧 → `Error` 事件；此前只读非官方的嵌套形态，
    按官方文档发错误帧的对端错误会被完全吞掉。嵌套形态保持兼容。
- **gemini 流式**：`promptFeedback.blockReason` 有值而帧无 `finishReason` 时，
  此前累加器默认 `Stop` —— **安全拦截伪装成正常结束**。现在发
  `Finish(Safety)` + Degraded 诊断（键与非流式同为 `promptFeedback.blockReason`）。
- **语义修正**：`Safety` 在 messages 目标的收敛值从 `"safety"`（不在官方 7 值
  白名单内，会被裁决器收敛成 `end_turn`）改为官方 `"refusal"`
  （官方 SDK 释义："streaming classifiers intervene to handle potential policy violations"）。
  同源往返、`finish_reason_contract_test` 等锁定旧行为的测试已同步更新。

### 新增

- `src/provider/meta/termination.mbt`：`responses_termination_reason` ——
  Responses 的 (status, incomplete_details.reason) → IR 终止原因映射表，
  流式与非流式共用（「两路径各写一份映射」失败模式的第三次收口）。
- `src/sdk/test/stream_termination_test.mbt`：10 个回归 —— 五类终止/错误输入、
  流式与非流式对同一响应体解出同一 `finish_reason` 的不变量、
  `Safety → refusal` 语义锁定。
- **官方 schema 校验系统**（`tools/conformance/`，Node）：以三家官方 SDK 的
  TS 类型为裁判 —— 权威枚举比对、校验器自检、跨协议词汇泄漏、golden 回放、
  **真实管线校验**（js-driver 零编组驱动 Prism 实际转换 → 产出过官方 schema，
  已通过缺陷注入验证）。CI 与本地入口：`node tools/conformance/run-all.mjs`。
  设计与局限见 [`docs/rules/conformance-oracle.md`](docs/rules/conformance-oracle.md)。
- `src/cmd/repl`：js-target driver 包（非 js target 为 stub），把 wasm 层
  转换函数挂到 `globalThis.__prism`，供 Node 校验零编组调用。

### 工程内部

- CI：新增 conformance oracle job（`run-all.mjs` + 生成物漂移断言）；
  覆盖率阈值 200 → 204（`src/cmd/repl/driver_stub.mbt` 为结构性不可测，已登记）。
- `scripts/verify.sh` 增加 `--oracle` / `--no-oracle` 开关。

## [0.1.4] 及更早

见 git 历史（`git log --oneline`）；此前的变更以 `docs/cr/` 变更单与
`docs/status.md` 轮次记录为准。
