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

## 四组检查

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
- **不能替代真实 API 调用**。schema 通过 ≠ API 接受（服务端可能有额外校验）。
  拿到 API key 后应补录制真实流量（VCR 风格）作为最终验证。
- **流式只校验单帧**。帧序列的合法性（顺序、配对）由 MoonBit 侧的
  `stream_event_coverage_test` 覆盖。
