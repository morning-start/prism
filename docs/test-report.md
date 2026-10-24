---
source: retired process workspace (iteration-004 CR-001 test report)
source_version: 2026-09-21T00:00:00Z
source_confidence: 0.95
promoted_by: fst-promote
promoted_at: 2026-09-21T00:00:00Z
approver: user
approved_at: 2026-09-21T00:00:00Z
---

# 测试报告 — CR-001 流式 usage 保真修复

- 变更单：[`cr/CR-001.md`](cr/CR-001.md) · 迭代：iteration-004
- 分支：`feat/CR-001`（已合并 `8f100cc`）
- 判定式：`target = change(current)`

## 1. 改动点 → 断言 → 测试映射

| 改动点（change.items） | target.acceptance | 测试 | 结果 |
|---|---|---|---|
| 1 · messages 解码 `message_delta.usage` 读输入侧 + 缓存项 | 1 | `stream_usage_cr001_test.mbt` T1.1 / T1.1b / T1.2 | ✅ |
| 2 · `StreamConverter` 会话级 Finish 去重 | 2、3 | T1.2（单条 message_delta）/ T1.2b（逐字节一致） | ✅ |
| 3 · 增量路径 usage 回填（`prompt_tokens` + 缓存项，经 `ConversationMeta.extra` 扩展载体） | 1、3 | T1.1 / T1.2b | ✅ |
| 4 · Gemini Done 收尾排在 usage 之后（含转换器延迟终止） | 4 | T1.3（同帧 + 分离两帧 × batch/incremental）/ T1.3b | ✅ |
| 5 · openai 出站注入 `stream_options.include_usage` | 5 | T1.4 / T1.4b（调用方值优先、非流式不注入） | ✅ |
| 6 · 测试补面 + 文档同步 | 6 | 全量回归 + [`fidelity-matrix.md`](fidelity-matrix.md) §3.5 / [`status.md`](status.md) | ✅ |

## 2. 关联影响点（改动点相邻功能）

| 影响点 | 命令 | 结果 |
|---|---|---|
| messages 编解码全量（thinking / tool_use / SSE 往返） | `moon test -p morning-start/prism/messages` | ✅ 92/92 |
| gemini 流事件序（thinking / text / functionCall / 兜底 Done） | `moon test -p morning-start/prism/gemini` | ✅ 90/90 |
| openai 请求编码（extras 透传 / previous_response_id / structured_output） | `moon test -p morning-start/prism/openai` | ✅ 93/93 |
| 跨协议矩阵与 `StreamConverter` 不变量 | `moon test -p morning-start/prism/sdk/test` | ✅ 315/315 |
| 4×4 转换矩阵 + 1 字节切分一致性 | `convert_matrix_test.mbt` / `stream_converter_test.mbt` | ✅ |

## 3. 缺陷修复判定式（复现测试由红转绿）

红态原始输出属过程态工作区（已退役 2026-10-24）；六项红态与逐条失败原因见本文档 §3。

| 测试 | 修复前（红） | 修复后 |
|---|---|---|
| T1.1 / T1.1b | `prompt_tokens` / `cached_tokens` 断言失败（恒 0 或缺失） | ✅ |
| T1.2 | `2 != 1`（两条 `message_delta`） | ✅ 一条 |
| T1.2b | 增量输出含重复 `finish_reason` 帧与空 SSE 块、`prompt_tokens: 0` | ✅ 与整缓冲逐字节一致 |
| T1.3 | usage 帧落在 `data: [DONE]` 之后 | ✅ 早于 `[DONE]` |
| T1.4 | 出站请求无 `stream_options` | ✅ 已注入 |

## 4. 有意变更的既有断言（逐处解释）

| 文件 | 原断言 | 新断言 | 原因 |
|---|---|---|---|
| `src/provider/gemini/test/gemini_test.mbt:1167` | `S0D0E0FXU` | `S0D0E0FUX` | CR-001 D3：Done 必须排在 usage 之后（否则 usage 落到 `[DONE]` 之后） |
| 同上 `:1169` | `events[5]` 为 `Usage` | `events[4]` 为 `Usage` | 同上，索引前移一格 |
| `src/sdk/test/branch_coverage_test.mbt`（×2） | 依赖空 SSE 块凑 `frames.length() >= 1` | fixture 携带 content delta，断言输出含 `"content":"a"` / `"content":"b"` | 空块被丢弃属修复（逐字节一致所必需），原断言失去意义 |

## 5. 核心回归

- `moon test` 全量：**1196 passed / 0 failed**（native + wasm-gc）
- `moon check --target native`、`moon fmt --check`：通过（pre-commit 钩子 L1 全绿）

## 6. 结论

改动点与关联影响点全部覆盖且通过，缺陷复现测试由红转绿 ⇒ `target = change(current)` 成立。

## 7. 迭代内其它变更（CR-002）

本迭代还包含 **CR-002（相邻缺口收敛：A1 / D5 / A4 / A3 / A5）**，其变更针对性测试为
`src/sdk/test/stream_meta_cr002_test.mbt`（5 项断言先红后绿 + 1 项 `finish()` 幂等），
关联影响点（messages / gemini / sdk 包回归）、既有断言变更的逐处解释与契约变化说明见
[`cr/CR-002.md`](cr/CR-002.md) §5；本轮全量回归为 **1201 passed / 0 failed**。
本文件 §1–§6 保持 **CR-001 范围**的结论。
