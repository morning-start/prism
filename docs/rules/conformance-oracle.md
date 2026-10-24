# 官方 Schema 校验（Conformance Oracle）

> 目的：用**官方 SDK 的类型定义**当裁判，验证 Prism 的产出会被真实 API 接受。
> 这是 MoonBit 测试无法覆盖的一层 —— 后者只能证明「Prism 与自己一致」，
> 证明不了「Prism 与官方协议一致」。

## 为什么需要它

逐字段手写断言会漏掉两类问题（均在本仓库真实发生过）：

| 问题 | 逐字段测试 | 本校验 |
|---|---|---|
| 白名单漏了官方值（Gemini `NO_IMAGE` 等 5 个） | ❌ 不知道官方还有这些值 | ✅ 与官方枚举逐值比对 |
| 白名单编造了不存在的值（`MALFORMED_RESPONSE`） | ❌ 自测自过 | ✅ 官方无此值即报错 |
| 官方 error 帧是扁平结构，实现按嵌套读 | ❌ 两种写法都能编译 | ✅ schema 必填字段校验 |
| 源协议词汇泄漏到目标槽位（`pause_turn` → openai） | ❌ 需穷举所有组合 | ✅ 逐值过目标白名单 |

## 为什么用 Node + JSON Schema

实测过三条路线（2026-10-24）：

| 路线 | 枚举约束 | 结论 |
|---|---|---|
| **Node + TS 类型 → JSON Schema** | ✅ 完整保留 | **采用** |
| Go + `invopop/jsonschema` 反射 | ❌ 只剩 `{"type":"string"}` | 排除：无法校验值 |
| Python + pydantic | ✅ 完整保留 | 可行，但需要另起运行时且无真实 HTTP 回放能力 |

Go 被排除的根本原因：官方 Go SDK 把枚举定义成 `type X string` + 一组常量，
**类型系统里没有约束**，反射拿不到取值集合，只能校验"是不是字符串"。

Node 另有一项独有能力：可以起真实 HTTP 服务器，让官方 SDK 通过真实 socket
消费 Prism 产出的 SSE，做端到端回放。

## 快速开始

```bash
# 首次
cd tools/conformance && npm install

# 全量校验（与 CI 完全一致）
node tools/conformance/run-all.mjs
```

或在仓库根目录：

```bash
./scripts/verify.sh            # MoonBit + Node 全部
./scripts/verify.sh --oracle   # 仅 Node 层
```

## 五组检查

> 2026-10-24 起扩展为**七组**：新增 [6] 真实流式管线与 [7] 真实 socket 回放
> （见「局限」节的说明），run-all 步骤编号 6/7/8 对应本文件 [5]/[6]/[7] 组。

### [1] 权威枚举 vs 仓库白名单

从官方 SDK 抽取取值集合，与 `src/provider/meta/finish.mbt` 里的三个白名单数组逐值比对：

- **缺失**（官方有、仓库无）→ 会把合法值误判为非法，导致同源往返被降级
- **编造**（仓库有、官方无）→ 会放行官方不认可的取值

> 这一组上线时立刻抓到 Gemini 白名单漏 5 个官方值、多 2 个假值。

### [2] 校验器自检

用「已知合法必须通过、已知非法必须拒绝」的样本验证裁判本身没失效。
**这一组的意义是防止校验器静默失效**（例如 schema 编译失败但被当成通过）。

### [3] 跨协议词汇泄漏

逐值检查源协议的词不会出现在目标协议的槽位里。
本仓库最容易出错的地方（CR-005 的 `pause_turn` 泄漏即此类）。

### [4] golden 回放

从 vendored 的 `schemas/endpoints/openai-openapi.yaml`（官方仓库，MIT）里
抽出真实响应体与 SSE 帧，逐条过 schema。零成本、离线、无 license 风险。

### [5] 真实管线校验（核心）

前四组校验的是手写样本；这一组校验 **Prism 真实转换的产出**：

```
官方形态输入 → Prism js-driver（零编组）→ 真实产出 → 官方 schema / 权威枚举
```

实现：`src/cmd/repl`（仅 js target 编译）把 wasm 层的转换函数挂到
`globalThis.__prism`，Node 侧 `tools/conformance/prism.mjs` 加载产物后直接调用
——同一套 ABI（String 进/出 + JSON 信封），无任何文件编组。

校验矩阵：每家源协议的官方样本 decode → IR，再 encode 到全部 4 家目标，
对产出做官方 schema / Message 形态 / 权威枚举三重校验。

> **缺陷注入验证**（2026-10-24）：把 messages 编码器的 `stop_reason` 键名
> 改成 `stop_reason_typo` 后重跑，管线校验精确报出
> `/stop_reason: must have required property`，2 处失败、CI 退出非零；
> 恢复后回到全绿。这证明本组抓的是**真实管线缺陷**，不是样本摆设。

> 附带发现：往 messages 收敛器注入 `Stop => "stop"`（openai 词汇）**不会**逃逸
> ——`arbitrate` 白名单裁决器把它收敛回 `end_turn` 并打诊断。CR-005 的修复
> 仍然有效，这本身也是一次有价值的回归确认。

## 产物与漂移

生成物**入库**，这样官方 SDK 升级导致的枚举变化会体现在 `git diff` 里：

```
tools/conformance/schemas/
  authority.json                    # 三家权威枚举（人可读）
  anthropic-message.json
  anthropic-stream-event.json
  openai-chat-chunk.json
  openai-chat-response.json
  openai-responses-response.json
  gemini-candidate.json
fixtures/golden/
  *.json                            # 从官方 spec 抽出的真实样本
```

CI 里有一道 `Assert generated artifacts are up to date`：若生成物与仓库不一致，
构建失败并提示提交 —— 避免「官方加了新值但我们悄悄没跟上」。

## 噪音过滤与豁免（重要）

官方 schema 比本仓库建模的范围大得多，直接校验会产生大量噪音。为此有三级过滤：

1. **NOISE_KNOWN** — 本仓库不建模的可选字段（`speed`、`cache_creation` 等）缺失时不报
2. **LATE_ADDED_FIELDS** — 官方 SDK 新增、但 vendored spec 的旧示例尚未包含的字段
3. **UPSTREAM_BUGS** — 逐条登记的上游 schema 缺陷，**必须写明依据且只豁免具体实例**

> 例：官方 SDK 把 `Response.user` 声明为 `string`（漏 nullable），
> 但真实 API 返回 `null`，vendored spec 的示例里也是 `null`。

**护栏**：`self-check.mjs` 专门验证这些豁免不会放过枚举与结构错误。
修改豁免列表后必须跑它 —— 否则豁免机制会退化成掩盖问题的后门。

## 局限（诚实声明）

- **只校验结构合法性，不校验语义正确性**。它证明「这份 JSON 会被官方接受」，
  不证明「这份 JSON 表达的意思和源一致」。语义一致性由 MoonBit 侧的往返测试保证。
- **OpenAI 覆盖最全**（有 vendored 官方 OpenAPI + 官方 SDK），
  Anthropic / Gemini 只覆盖 SDK 类型能表达的字段。
  `responses` / `gemini` 目标目前只校验关键结构字段（object/candidates 存在性），
  完整 schema 校验待补（需先解决两家 SDK 类型与 wire 形态的已知偏差）。
- **不能替代真实 API 调用**。schema 通过 ≠ API 接受（服务端可能有额外校验）。
  拿到 API key 后应补录制真实流量（VCR 风格）作为最终验证。
- **流式管线已接入（[6] 组，`pipeline-stream.mjs`）**：官方 SSE 帧序列 →
  Prism `convert_stream` → 目标协议 SSE → 逐帧官方形态 + 帧序契约
  （首帧 / 终止帧唯一且在最后 / content block 生命周期 / 终止枚举），
  含 CR-006 批次 1 修复的四类终止输入双重锁定。
  2026-10-24 首跑即实锤 4 类真实缺陷（gemini 分帧符、双逗号 JSON、
  responses extra 捕获口径、gemini usage/finish 帧序）并全部修复。
  尚未覆盖：逐帧增量路径（StreamConverter feed 语义）、工具调用全链路流。
- **真实 socket 回放已接入（[7] 组，`replay.mjs`）**：本地协议服务器 +
  三家官方 SDK 全链路 —— SDK 发出真实 HTTP 请求（auth 头 / URL 形态 /
  wire 请求体进 Prism 请求解码）→ 服务器回放源协议流 → Prism 真实转换 →
  官方 SDK 解析器逐帧消费（文本拼接 / 终止原因 / usage 聚合 /
  error → APIError 不静默）。跨协议中转用 fetch 包装层实现
  （包装必须先于 SDK 构造 —— anthropic SDK 构造时绑定全局 fetch，实测）。
  SDK 解码器的硬约束（anthropic 跳过无 `event:` 行的帧）本身成为
  回放组合选取的依据。
- **js driver 产物不入库**（_build 下，每次 run-all 现场构建），
  MoonBit 编译器版本变化会导致产物字节级不同，但这不影响校验语义。
