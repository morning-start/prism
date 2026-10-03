# Prism Project Status

> Last updated: 2026-09-09（iteration-009 架构优化后）

## Module Completion

| Module | Status | Notes |
|--------|--------|-------|
| `src/lux` (Lucent IR) | ✅ Stable | v1 schema, types + builders + stream events + diagnostics；T8 新增 previous_response_id 标准字段 + ConversationSnapshot |
| `src/internal` | ✅ Stable | JSON helpers, SSE parser（含 T5 增量 SseFrameSplitter）, shared primitives |
| `src/sdk` | ✅ Stable | Facade, context, registry+match（T6 动态注册 + endpoint 配置）, pipeline/codec_pipeline, convert（T4 钩子链 / T5 StreamConverter / T8 快照还原）, hooks, error（T7 类型化）, diagnostics（T10 策略+聚合）, snapshot |
| `src/wasm` | ✅ Stable | 28 exported functions (per `src/cmd/main/moon.pkg` exports list; check via `scripts/export_count.sh`), scratch memory, log buffer；T5 增量会话句柄 ABI + T11 ABI 版本导出 |
| `src/provider/openai` | ✅ Complete | Chat Completions + stream + capability |
| `src/provider/messages` | ✅ Complete | Anthropic Messages API + extended thinking |
| `src/provider/responses` | ✅ Complete | OpenAI Responses API |
| `src/provider/gemini` | ✅ Complete | Google Gemini API + Vertex variant |
| `src/cmd/main` | ✅ Complete | WASM exports only |
| `wrappers/ts` | ⚠️ 不在本仓库快照 | 历史记录声称 Complete，但工作区无此目录（T11 澄清）；接入前需确认仓库同步状态，并纳入 CI（moon build wasm → wrapper 编译 → 集成测试） |
| `wrappers/go` | ⚠️ 不在本仓库快照 | 同上 |

## Implemented Providers (9 adapters)

| Adapter | Protocol | Request | Response | Stream | Capability |
|---------|----------|---------|----------|--------|------------|
| `openai` | OpenAI Chat Completions | ✅ | ✅ | ✅ | ✅ |
| `responses` | OpenAI Responses API | ✅ | ✅ | ✅ | ✅ |
| `messages` | Anthropic Messages API | ✅ | ✅ | ✅ | ✅ |
| `gemini` | Google Gemini API | ✅ | ✅ | ✅ | ✅ |

Provider 主名称与别名（openai["chat"]、responses["openai-responses"]、messages["claude-messages","anthropic"]、gemini["google"]）定义于各 `src/provider/<name>/meta.mbt`；azure/vllm 等部署态变体经运行时 `register_provider` + `with_overrides` 注册（见 `src/sdk/dynamic_registry_wbtest.mbt`），不在静态表中。

## Test Coverage

Tests are organized per package: **blackbox** (`*_test.mbt`, public API only)
live in a dedicated `test/` subpackage (`import ... for "test"`); **whitebox**
(`*_wbtest.mbt`) stay in the package directory (MoonBit requires same-package
compilation to reach non-public members).

- **lux**: Whitebox (`lux_wbtest`, `serialize_wbtest`, `deserialize_wbtest`, `diagnostics_json_wbtest` in `src/lux/`) + blackbox (`lux_test`, `from_json_error_test`, `snapshot_test` in `src/lux/test/`) — extensive
- **sdk**: Cross-protocol (`cross_protocol_test`), convert matrix (`convert_matrix_test`), registry (`provider_registry_wbtest`, `dynamic_registry_wbtest`), integration (`sdk_test`, `convert_test`), iteration-009 新增：`context_toolcall_test` / `events_to_context_test` / `options_ext_test` / `hooks_test` / `stream_converter_test` / `error_typed_test` / `snapshot_store_test` / `diagnostics_policy_test` — blackbox in `src/sdk/test/`；首字实时增量解码会话：`stream_session_test`（`Prism::stream_session`，逐 chunk feed 即时产出事件，与整批 `decode_sse` 等价）
- **provider/\***: Each adapter has whitebox `_wbtest` (package dir) + blackbox `_test` (`test/` subpackage)
- **wasm**: `wasm_test` + `stream_session_test` + `abi_version_test` covering all exports (in `src/wasm/test/`)
- **internal**: Coverage in `internal/test/` subdirectory（含 T5 SseFrameSplitter 测试）

**Total: 1210 tests passing (native + wasm-gc), 2026-10-03 stream_session 后（`moon test` 全量）。**

### 实时流式（首字延迟）

- **Agent SDK 门面**：`Prism::stream_session()`（拉式会话）——`feed(chunk)` 收到一个上游 chunk 即返回其中完整帧解出的 `PrismEvent`，首字延迟 = 首个完整 SSE 帧；`finish()` 冲刷尾部半帧并闭合未完块（幂等）。与整批 `decode_sse` 事件序列等价（测试锁定），工具调用参数跨帧累积。源码：`src/sdk/event_stream.mbt`。
- **中转 middleware**：`StreamConverter`（逐帧 source→target，T5）与 WASM 会话 ABI `wasm_stream_new/feed/finish`（T5/CR-002）本已实时。
- 终止符契约（CR-002）不变：`finish()` 必须在流结束时调用（建议宿主 `finally`）。

## Known Limitations

- `scripts/check_schema_drift.ps1` runs in report mode by default and can be used with `-Strict` in CI; its self-test covers version, required fields, enums, stream events, and adapter output fields

- `src/lux/types.mbt` remains the type/model hub; codec implementations are split into request/response/stream/primitive files (deserialization further split: `deserialize_helpers` / `deserialize_primitives` / `deserialize_content` / `deserialize_tools` / `deserialize_options`); diagnostics JSON codec lives in `diagnostics_json.mbt`. Package navigation: `src/lux/README.md` and `src/sdk/README.md` provide per-package file maps and dependency rules (MoonBit folders = packages, so intra-package organization uses prefixes + partition comments + index READMEs, iteration-007)
- Provider adapters use a uniform file layout: capability / request_decode / request_encode / response / stream_decode / stream_encode
- JSON Schema (`schemas/lux-ir-v1.json`) remains manually authored, but `scripts/check_schema_drift.ps1` now reports version/required-field/enum/stream-event drift

- `src/internal/sse.mbt` exports `parse_sse_frame` — shared SSE preprocessing pipeline used by messages, openai, and gemini stream decoders; `SseFrameSplitter`（T5）提供 chunk-boundary-safe 增量分帧
- `src/internal/json.mbt` exports JSON field access (`obj_get` / `field_*`) and basic tools (`json_escape` / `parse_string_array` / `parse_content_polymorphic` / …); `extras.mbt` exports `collect_extra_fields` / `merge_extras_json` / `extras_without`; `usage.mbt` exports `parse_usage_json` / `parse_reasoning_tokens` / `parse_cached_tokens` / `parse_cache_creation_tokens` / `parse_cached_tokens_gemini` — shared helpers used by all four providers
- `src/lux/stream.mbt` exports `BlockAccumulator` (public `pub(all)` struct, used by stream accumulation) — extracted from the 290-line stream accumulator function
- `src/lux/helpers.mbt` exports `LucentReasoningEffort::to_string` — outbound effort tier mapping shared by openai / messages / responses (gemini keeps its own downgrade mapping)

### 流式 usage（CR-001）

- **已修**（变更单 [`cr/CR-001.md`](cr/CR-001.md)，回归 `src/sdk/test/stream_usage_cr001_test.mbt`）：
  Anthropic 源流式 `prompt_tokens` 恒 0（`message_start.usage.input_tokens` 未并入 `Usage`）与
  缓存计费项未解析；增量路径重复 Finish 把 `message_delta.usage.output_tokens` 覆盖成 0；
  Gemini 源 usage 帧落在 `data: [DONE]` 之后被客户端丢弃；openai 出站流式请求未注入
  `stream_options.include_usage`（上游整条流因此不带 usage）。
- **残余（CR-003 后收敛，见 [`fidelity-matrix.md`](fidelity-matrix.md) §4 第 5–6 条）**：
  余下两条为**有意保留**：裸解码接口（`wasm_sse_to_events` / `events_decode`）仍带帧级
  `Done`（保持解码器契约，变更需先出 provider 契约提案）；`StreamConverter` 尾部半帧
  依赖宿主调用 `finish()`（宿主应在 `finally` 中调用）。

### 残余收敛（CR-003）

- **已修**（回归 `src/sdk/test/stream_meta_cr003_test.mbt`）：
  ①Anthropic `message_start.usage` 缺 `output_tokens`（首帧语义为 1）——
  messages 目标现同时给出 `input_tokens`（+ 缓存项）与 `output_tokens: 1`；
  ②Gemini 输入整段无可解析帧（空流 / 仅非法帧）时不发会话元信息 ⇒ 退化流的
  `gemini→messages` 缺 `message_start`、`gemini→responses` 缺 `response.created` ——
  现在同样补发一次首帧（字段缺失为 None）。
- **决策记录**：R3（裸解码帧级 `Done`）与 R4（半帧依赖 `finish()`）**不改代码**，
  理由与变更前置条件见 [`fidelity-matrix.md`](fidelity-matrix.md) §4 第 5–6 条。

### 流式首帧与终止语义（CR-002）

- **已修**（变更单 [`cr/CR-002.md`](cr/CR-002.md)，回归 `src/sdk/test/stream_meta_cr002_test.mbt`）：
  Gemini 流式从不发会话元信息 ⇒ `gemini→messages` 缺 `message_start`、`gemini→responses`
  缺 `response.created`、`gemini→openai` 的 `id`/`model` 为空；Gemini 帧级 `Done` 在逐帧
  路径提前发出（usage / 后续内容落到终止符之后）；messages 编码器在 IR 事件序
  `[Usage, Finish]` 下清零用量；`message_start` 丢缓存计费项（`ConversationMeta.extra`
  载体已在 `message_delta` 与 `message_start` 两侧打通）；截断流不闭合 `content_block`。
- **契约变化**：终止符改由会话层唯一产生（`convert_stream` 在编码前补一个、
  `StreamConverter::finish()` 补一个），逐帧消费方**必须**调用 `finish()` 才能拿到尾部帧；
  裸解码接口行为不变。

## Iteration-009 架构优化（2026-09-09）

两类目标用户（Agent Framework SDK / Transit Middleware）驱动的接口边界补全；
审计报告与计划见 `.agent-workplace/docs/`（gitignored）。已完成：

| 项 | 内容 |
|---|---|
| T1 | `Context::add_tool_call` / `SdkMessage::assistant_turn` — agent 循环第二轮不再缺 assistant tool_use 回合 |
| T2 | `Prism::events_to_context` 回填闭环 + 修复 openai/messages 流式 tool call 被完全丢弃的 bug |
| T3 | `PrismOptions` 扩面（tool_choice/reasoning/structured_output/parallel_tool_calls）+ 修复 messages 并行工具语义反传写反 |
| T4 | IR 钩子链 `convert_*_with_hooks` + 5 个内置钩子（policy 落点） |
| T5 | `SseFrameSplitter` + `StreamConverter` + wasm 句柄式增量会话 ABI（1 字节 chunk 与整缓冲逐字节一致） |
| T6 | 运行时 provider 注册（`register_provider`/`unregister_provider`）+ endpoint 配置 + `with_overrides` 薄注册 |
| T7 | `PrismError` 类型化错误入口（保守分类器 + is_retryable） |
| T8 | `previous_response_id` 标准字段 + `ConversationSnapshot` + `convert_request_with_store`（IR 治理提案先行） |
| T9 | `docs/fidelity-matrix.md` 4×4 保真度矩阵（切流决策依据） |
| T10 | `DiagnosticPolicy` + `DiagnosticCollector`（策略熔断 + 降级率统计） |
| T11 | `wasm_abi_version` 导出 + wrappers 状态澄清 |

## IR Evolution Backlog (from 2026-09 protocol audit)

Items identified by the cross-protocol conversion audit (context-continuation
and tool-pairing focus). Adapter-level mitigations are in place; IR-level
carriers are pending governance per `docs/rules/lucent-ir-evolution.md`:

- **ToolResult name carrier**: `LucentToolResult` has only `tool_use_id`;
  Gemini `functionResponse.name` requires the function name, so encoders
  pre-scan `ToolCall` items to rebuild the id→name map (see
  `src/provider/gemini/request_encode.mbt` `build_tool_name_map`). An IR
  carrier would remove the scan and handle orphan tool results cleanly.
- **Reasoning continuation credential side-channel**: Responses
  `reasoning.encrypted_content` (stateless reasoning continuation) has no IR
  carrier; decode emits a Degraded diagnostic instead of preserving it.
- **ReasoningEffort `Minimal` tier**: OpenAI `reasoning_effort: "minimal"`
  (gpt-5 family) degrades to `Low` with a diagnostic; Anthropic `"max"`
  degrades to `XHigh`.
- **parallel_tool_calls as a standard option**: currently exchanged via the
  `extras` map with semantic inversion per target (`parallel_tool_calls` ↔
  `disable_parallel_tool_use`); both directions are tested. SDK 侧已有
  `PrismOptions::with_parallel_tool_calls`（T3），IR 标准字段提升待治理。

## Build & Verify

```bash
moon fmt --check
moon check --warn-list +73 --deny-warn
moon test                      # native + wasm-gc
```
