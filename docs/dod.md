---
source: retired process workspace (iteration-004 release checklist)
source_version: 2026-09-21T00:00:00Z
source_confidence: 0.95
promoted_by: fst-promote
promoted_at: 2026-09-21T00:00:00Z
approver: user
approved_at: 2026-09-21T00:00:00Z
---

# 迭代验收 Checklist（DoD）— CR-001 流式 usage 保真修复

- 变更单：[`cr/CR-001.md`](cr/CR-001.md) · 迭代：iteration-004
- 分支：`feat/CR-001`（已合并主干 `8f100cc`，分支已删除）
- 核销方式：`target.acceptance` 逐条核销 + 核心回归
- 核销时间：2026-09-21

## 1. 核销项

| key | 项 | 必须 | 通过 | 证据 |
|---|---|---|---|---|
| `functional` | 核心功能完成 | ✅ | ✅ | 4 处改动全部落地并由主干代码承载：`src/provider/messages/stream_decode.mbt`、`src/provider/messages/stream_encode.mbt`、`src/provider/gemini/stream_decode.mbt`、`src/provider/openai/request_encode.mbt`、`src/sdk/convert.mbt`、`src/sdk/codec_pipeline.mbt` |
| `targeted_tests` | 变更针对性测试 | ✅ | ✅ | [`test-report.md`](test-report.md)：改动点 6 项 + 关联影响点 5 类全绿；缺陷复现测试由红转绿 |
| `regression` | 核心主干回归 | ✅ | ✅ | `moon test` **1196 passed / 0 failed**（native + wasm-gc）；4×4 转换矩阵与 1 字节切分一致性不变 |
| `docs_synced` | 文档同步 | ✅ | ✅ | [`fidelity-matrix.md`](fidelity-matrix.md) 新增 §3.5 流式 usage + §4 技术债 5–8；[`status.md`](status.md) 测试统计 995→1196 与 Known Limitations「流式 usage（CR-001）」 |
| `change_archived` | 变更记录归档 | ✅ | ✅ | [`cr/CR-001.md`](cr/CR-001.md)（commit `6816c85`）+ `state/document-status.json` 溯源条目 |
| `pending_excluded` | 待定需求不纳入验收 | — | ✅ | D5 / A1 / A3 / A4 / A5 已登记技术债，未纳入本次交付验收 |

**all_passed: true**

## 2. `target.acceptance` 逐条核销

| # | 断言 | 测试 | 结果 |
|---|---|---|---|
| 1 | messages→openai 的 `prompt_tokens` = 源 `message_start.usage.input_tokens`、`total_tokens` 含输入侧；缓存计费项映射到 IR 并在目标端输出 | T1.1 / T1.1b（openai 目标 `cached_tokens`）/ T1.2（messages 目标 `cache_read_input_tokens` + `cache_creation_input_tokens`） | ✅ |
| 2 | messages→messages 只含一条带 usage 的 `message_delta`（值 = 上游值）、无 `output_tokens: 0`；messages→openai 无重复 `finish_reason` 帧 | T1.2 / T1.2b | ✅ |
| 3 | `StreamConverter` 1 字节输出与整缓冲 `convert_stream` 逐字节一致（messages→openai、messages→messages） | T1.2b | ✅ |
| 4 | gemini→openai 的 usage 帧早于 `data: [DONE]`（同帧与分离两帧 × batch/incremental）；gemini→messages 的 `output_tokens` 正确 | T1.3 / T1.3b | ✅ |
| 5 | 目标 openai 且 `stream=true` 且调用方未提供 `stream_options` 时注入 `include_usage`；调用方值优先；非流式不注入 | T1.4 / T1.4b | ✅ |
| 6 | `moon test` 全绿；快照/断言变更经审阅并逐处解释 | 1196/1196；3 处既有断言变更的解释见 [`test-report.md`](test-report.md) §4 | ✅ |

测试文件：`src/sdk/test/stream_usage_cr001_test.mbt`（T1.1–T1.4）。

## 3. 遗留（不阻塞放行，已入技术债）

- **D5**：Gemini 中间帧若携带 `usageMetadata`，逐帧路径可能提前发出 Done —— **代码推断，未经线上核实**，建议灰度期重点观察 gemini 链路。
- **A1**：Gemini 流解码不发 `ConversationStart`（`gemini→messages` 缺 `message_start`）。
- **A3**：messages 编码器在 IR 事件序 `[Usage, Finish]` 时清零用量（真实解码器不可达）。
- **A4**：`message_start` 的缓存计费项无 IR 载体。
- **A5**：`StreamConverter` 对无 Finish 的截断流不合成 `BlockEnd`。

## 4. 结论

DoD 全部 ✅，方程 `target = change(current)` 成立，可进入发布决策（本轮决定：**暂不发布**，先由下游以源码/分支验证）。

## 5. 迭代内其它变更

本迭代还包含 **CR-002（相邻缺口收敛：A1 / D5 / A4 / A3 / A5）**。其 6 条 `target.acceptance`
的核销记录、既有断言变更的逐处解释与残余项见 [`cr/CR-002.md`](cr/CR-002.md) §5；
本文件保持 **CR-001 范围**的 DoD 核销，不改写 CR-001 的结论。

- CR-001（本文件）：流式 usage 保真（D1–D4），全量回归 1196/1196
- CR-002（见 CR 文档）：流式首帧与终止语义、messages 编码器与缓存载体，全量回归 **1201/1201**
- 上述残余项 D5 / A1 / A3 / A4 / A5 **均已由 CR-002 修复**；CR-002 之后的残余见
  [`fidelity-matrix.md`](fidelity-matrix.md) §4 第 5–8 条。
