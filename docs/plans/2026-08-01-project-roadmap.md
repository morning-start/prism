# Prism 项目规划（2026-08-01）

> 基于全仓调研（源码 + audit 报告 + 需求/设计文档 + 验证结果）产出的项目路线图。
> 依据：`docs/report/architecture-audit-2026-07-28.md`、`docs/rules/audit-gaps.md`、
> `docs/requirements.md`（双场景设计）、`transport/ARCHITECTURE.md`、`docs/protocols/README.md`。
> 事实均以 2026-08-01 当天验证结果为准（660 测试全绿）。

---

## 0. 现状基线（已验证）

| 模块 | 状态 | 验证证据 |
|------|------|---------|
| `lux/` IR 核心（34+ 类型、流式、序列化/反序列化） | ✅ 完成 | round-trip 测试 |
| 7 个 Provider 适配器（6 函数契约） | ✅ 完成 | `ProviderRegistration` 注册表 + 跨协议测试 |
| SDK 编解码 façade（encode/decode × 4 + capability） | ✅ 完成 | 645+ 测试 |
| 双场景核心：`convert_*` 组合入口 + `wasm_convert_*` 中转导出 | ✅ 完成（2026-08-01） | 新 13 测试，`.mbti` 核对 |
| SDK L1/L2：`Prism::complete` / `Prism::stream` / `Context::add_tool_result` | ✅ 完成（2026-08-01） | mock transport 测试 |
| WASM 导出层 | ✅ 15 个导出函数（以 `.mbti` 为真值，见 `scripts/export_count.sh`） | wrapper ABI（Go/Py/TS）已联通 |
| `transport/daemon`（Go + wazero，HTTP JSON-RPC） | 🟡 部分实现 | `POST /v1` + `GET /health`，8 个 RPC 方法 |
| 质量门禁 | ✅ | `moon fmt --check` / `moon check` 0 错误 / `moon test` 660/660 / `--target all` 通过 |

**双场景架构（已确认）**：A. IR 中心辐射式，场景 1 开发者 SDK + 场景 2 中转站共用 Lux IR 与 6 函数注册表地基。

---

## 1. 规划维度

| 维度 | 现状问题 | 规划方向 |
|------|---------|---------|
| **正确性 / 保真度** | 适配器仍返回 `Result[T, String]`，`Exact/Degraded/Unsupported/Invalid` 未贯通到执行路径；存在静默语义损失 | P1 保真度契约贯通 |
| **SDK 职责** | `api_key`/`base_url` 死字段未消费；`store`/`extras` 未连通；`ThinkingDelta` 被映射成 `TextDelta`（语义不一致） | P2 SDK 职责收敛 |
| **中转站形态** | WASM 先行已落地；HTTP daemon 最小可用；UDS/WS/SSE 流式未做 | P3 Transport 扩展 |
| **质量与维护** | 438 个 `unnecessary_annotation` 警告；文档漂移（42 vs 11 导出等）；`moon-audit` 未安装 | P4 质量收口 |

---

## 2. 阶段划分

### Phase 0：双场景核心（✅ 已完成）

`convert_*` 组合入口、`wasm_convert_*` 中转导出、`Prism::complete/stream`、`Context::add_tool_result`。
**验收：** 660/660 测试全绿，`.mbti` 导出符合设计，外部 consumer 可编译。

### Phase 1：保真度契约贯通（短期，建议优先）

> 来源：audit 报告 P1「转换结果模型未接入」。

- 目标：让每个形状字段的 `Exact / Degraded / Unsupported / Invalid` 成为可检测的协议输出，而非静默 `_ => ()`。
- 关键任务：
  1. 设计统一的「带诊断转换信封」：`{ value, diagnostics } | { error, diagnostics }`（String 进出边界不变；**六函数直接切换为新契约，不保留兼容层**——项目未上线，内部 wrapper/daemon 同仓同步改，见决策 D1）。
  2. `ConversionResult` 接入 adapter 内部 → 注册表 → SDK/WASM 信封。
  3. 消除 content/item/event 三类形状字段的静默丢弃：Responses `input_image/input_file`、Chat `Reasoning/AgentAction`、Anthropic 媒体空串、Gemini 媒体文本占位、SSE 非法 data。
  4. 流式累加器保留 `AgentAction` / `NativeDelta` / `Annotations`（或至少进诊断）。
- 验收门槛：
  - 每个基础 provider 的 canonical fixture 断言值 **和** 诊断；
  - 无形状字段裸 `_ => ()`；
  - `moon test` 全绿 + 新增诊断契约测试。
- 前置：IR v1 wire shape 冻结（当前已稳定）。

### Phase 2：SDK 职责收敛（短期）

> 来源：audit P2「SDK 公开承诺与实现职责不一致」+ audit-gaps 缺口 2。

- 目标：SDK 定位与实现一致，消除死字段与语义错位。
- 关键任务：
  1. 移除 `Prism` 未消费的 `api_key` / `base_url`（或移入未来 `TransportConfig`，纯转换 API 不承载）。
  2. `store` / `extras` 接入适配器 `parse_options()`（audit-gaps 缺口 2）。
  3. 修正 `ThinkingDelta` 事件映射（不得伪装成 `TextDelta`），事件降级携带诊断。
  4. `seed` 加 `@deprecated`（缺口 1）。
- 验收门槛：SDK 无死字段；`Thinking` 事件语义正确；`store/extras` 有往返测试。

### Phase 3：Transport 扩展（中期）

> 依据：`transport/ARCHITECTURE.md` Phase 1-6 路线；用户确认「后续支持 HTTP 服务请求方式」。

- 目标：把「WASM 先行」演进为多形态服务，复用 `convert_*` 零新增转换逻辑。
- 关键任务：
  1. HTTP 服务完善：请求/响应/流式三通路端点（复用 `wasm_convert_*` / `convert_*`）。
  2. UDS binding（本地 IPC，Windows 用 Named Pipe）+ Python 客户端。
  3. WebSocket binding + `decode_sse_stream` 逐块流式解码。
- 验收门槛：三通路经 daemon 端到端可转；流式事件语义不被破坏。
- 注意：audit 建议「不引入 HTTP server 前先完成保真度契约」——故本阶段排在 P1 之后。

### Phase 4：质量收口（贯穿各阶段）

- 目标：消除存量警告与文档漂移，建立可信质量基线。
- 关键任务：
  1. 清理 438 个 `unnecessary_annotation` 警告（`moonbit-refactor` 执行）。
  2. 统一导出数清单（生成式维护，杜绝 11/14/24/42 漂移）。
  3. 安装 `moon-audit` 补安全审计；CI 增加 `moon-audit pipeline .`。
  4. 更新 `README` / 需求文档的「当前能力 vs 规划」边界。
- 验收门槛：警告数显著下降；文档与 `.mbti` 一致；CI 含 audit 步骤。

### Phase 5：未来演进（长期，待需求驱动）

- 新厂商接入流程验证（文心 / 讯飞 / Cohere 等，验证「不动 IR 骨干」承诺）。
- 客户端 SDK 生成 pipeline（Node/Rust/Java 半自动输出）。
- Daemon MoonBit 原生化（MoonBit 网络栈成熟时，移除 WASM 间接层）。

---

## 3. 开放决策点（需用户确认）

| # | 决策 | 选项 | 建议 |
|---|------|------|------|
| D1 | 保真度信封兼容策略 | ① 新增带诊断 API，旧 6 函数保留兼容期；② v2 clean cutover | **②（已定）**：项目未上线、无外部消费者，直接切换避免双重维护；内部 wrapper/daemon/测试同仓同步改 |
| D2 | SDK 定位 | ① 纯编解码 façade（推荐，符合 WASM 无网络边界）；② 完整 Agent runtime | ① |
| D3 | 下一阶段优先级 | ① P1 保真度优先（audit 推荐）；② P2 SDK 收敛先行；③ P3 Transport | ① |
| D4 | 本地 IPC 选型（Phase 3） | UDS / stdio / Named Pipe / WebSocket | UDS（Linux/macOS）+ Named Pipe（Windows） |

---

## 4. 执行建议

1. **先做 D3 决策**：audit 明确建议「暂停新增 Provider 和 SDK 表面能力，先完成保真度契约」——推荐 P1 优先。
2. 每个 Phase 走完整管线：`moonbit-plan`（如有新设计）→ `moonbit-writing-plans`（拆任务，**任务拆解文档输出到 `docs/tasks/`**，不使用 `docs/plans/`）→ `moonbit-implement`（TDD）→ `moonbit-code-review` → `moonbit-verify`。
3. 每阶段结束更新 `.moonbit-pipeline.json`，保证跨 session 断点可恢复。
