# Prism 当前状态

> 项目各模块的完成度追踪。架构设计见 [`architecture.md`](./architecture.md)，路线图见
> `.agent-workplace/docs/plan/2026-08-01-project-roadmap.md`（Agent 私有工作区）。

---

## 模块状态

| 模块 | 状态 | 测试数 |
|------|------|--------|
| `lux/` 核心类型定义 | ✅ **已完成** | 34+ 类型，`pub(all) enum` |
| `lux/` JSON 序列化 (to_json) | ✅ **已完成** | 结构化测试覆盖 |
| `lux/` JSON 反序列化 (from_json) | ✅ **已完成** | round-trip 测试覆盖 |
| `lux/` 流式事件 + 累加器 | ✅ **已完成** | 块生命周期模型；AgentAction/Annotations/NativeDelta 经 `AccumulatedResponse` 保留并携带诊断 |
| `lux/` 转换诊断类型 | ✅ **已完成** | `ConversionResult` + 信封 JSON 编解码（`conversion_json.mbt`）已接入 SDK/WASM 诊断 API |
| `schemas/lux-ir-v1.json` | ✅ **已完成** | JSON Schema v1 |
| 7 个 Provider 适配器 | ✅ **已完成** | 六函数契约切换为 `ConversionResult`；媒体/推理/事件边界均显式报告 `Degraded`/`Unsupported` 诊断，无静默语义损失 |
| `sdk/` 表层 API | ✅ **纯编解码 façade + L1/L2** | `convert_*` 组合入口、`Context::add_tool_result`、`Prism::complete/stream` 已实现；不负责 HTTP、认证或 Agent Runtime |
| `wasm/` 导出层 | ✅ **已实现** | 15 个导出函数（见 `scripts/export_count.sh`，以 `.mbti` 为唯一真值）；Go / TypeScript / Python wrapper ABI 已完成 |
| 跨协议一致性测试 | ✅ | 当前 `moon test` 共 715 个测试通过（含保真度契约矩阵：断言 value **和** diagnostics） |
| 保真度契约（Exact/Degraded/Unsupported/Invalid） | ✅ **已完成** | Phase 1 收尾：信封 JSON、六函数契约切换、流式累加器信息保留、各适配器诊断、契约测试矩阵全部落地 |
| SDK 职责收敛（Phase 2） | ✅ **已完成** | 无死字段：`Prism` 移除 `api_key`/`base_url`；`store`/`extras` 接入 4 基础适配器（OpenAI 原生支持，Anthropic/Gemini `Unsupported` 诊断 + extras 往返）；`ThinkingDelta` 独立累加不污染文本，Gemini thought 不再伪装 Text |
| 来源元信息（Phase 2b，D8） | ✅ **已完成** | `ConversionMeta`/`DecodedResponse` + `Prism::decode_response_with_meta`、`convert_response_with_meta`（`ConvertMetaResult`）：多协议混流时按 `meta.source_provider` 溯源特判；IR 结构体零改动 |
| Transport 扩展（phase3b） | ✅ **已完成** | UDS/NamedPipe（JSON lines）+ WebSocket binding + `decode_sse_stream` session 模型（D7 交付）；`clients/go`、`clients/python` 客户端 SDK（HTTP/UDS/WS 传输可插拔）；复用 `ServeRPC`/`Backend` 零新增转换逻辑 |
| 质量收口（Phase 4） | ✅ **已完成** | `unnecessary_annotation` 警告 506 → 0（CI `--deny-warn` 门禁）；导出数清单生成式维护（`scripts/export_count.sh`，以 `.mbti` 为真值）；文档能力边界同步 |

## 当前边界

- **已实现**：`transport/` 三传输 daemon（HTTP + UDS/NamedPipe + WebSocket，`transport/daemon/`，Go + wazero），含 HTTP SSE 流式与 `decode_sse_stream` 会话式逐块解码；`clients/go`、`clients/python` SDK（传输可插拔）。
- **已实现**：Go / TypeScript / Python wrapper 真实 WASM 字符串 ABI（classic `wasm` 目标，UTF-16 线性内存约定）。
- **未实现**：gRPC binding（ARCHITECTURE §5.4）、客户端 SDK 生成 pipeline（§9 Phase 5）、Daemon MoonBit 原生化（§9 Phase 6）。
