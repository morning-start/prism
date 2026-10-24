# Changelog

本文件记录 Prism 的用户可见变更。格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)；
0.x 阶段 minor 即 breaking（与 MoonBit 生态惯例一致）。

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
