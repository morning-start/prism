# 04-API 与数据契约

> TL 主导维护，PM 确认业务语义，QA 依据此做契约测试。
> **协议与接口的单一事实源在仓库正式文档**，本文件只做索引 + 团队流程视角的边界声明；
> 冲突时以正式文档为准并回改本文件。

## 契约文档索引（单一事实源）

| 契约 | 位置 | 内容 |
|---|---|---|
| Lucent IR schema | [`docs/lux-ir-design.md`](../../docs/lux-ir-design.md) + [`schemas/lux-ir-v1.json`](../../schemas/lux-ir-v1.json) | 中立 IR 的正式类型规范（互为镜像） |
| 转换契约 | [`docs/api-protocol-converter.md`](../../docs/api-protocol-converter.md) | 4 端点对照 + 12-case 最小矩阵 + 6 函数 encode/decode 契约 |
| 保真度边界 | [`docs/fidelity-matrix.md`](../../docs/fidelity-matrix.md) | 4×4 矩阵，每格 Exact/Degraded/Unsupported/Invalid |
| Adapter 实现契约 | [`docs/provider-guide.md`](../../docs/provider-guide.md) | 新增 provider 的 6 函数 + 文件布局 |
| 字段分类规则 | AGENTS.md §Field classification | standard vs extension（extra/provider_payload 安全阀） |
| WASM ABI | `src/cmd/main/moon.pkg` exports + `wasm_abi_version` | 28 导出字符串 ABI；增量会话句柄 ABI（T5/CR-002） |

## 核心数据流（两消费者类型）

| 角色 | Providers 用量 | 流 |
|---|---|---|
| Agent 框架 SDK | 1 | `Lux → ProviderA`（发出）+ `ProviderA → Lux`（接收） |
| 中转 middleware | 2+ | `PA → Lux → PB`，或 `PA → Lux → PA`（审计/过滤/限流） |

M1 新增第三入口：**wasm 宿主** —— 字符串 ABI 进出（`String in/out`，零 provider 耦合），
wrapper 是 ABI 的类型化包装，**不得**在 wrapper 内重写转换逻辑。

## M1 新增契约（REQ-001，待 POC 后由 TL 细化）

| 接口 | 形态 | 输入 | 输出 | 业务语义确认（PM） |
|---|---|---|---|---|
| `convert(from, to, payload)` | TS 函数 | 协议名 × 协议名 × JSON 字符串 | JSON 字符串 + 诊断 | 与 wasm `wasm_convert_*` 语义一一对应，不做二次抽象 |
| `stream session` | TS 类（句柄式） | 逐 chunk feed | 逐帧事件 | 对应 wasm `wasm_stream_new/feed/finish`；`finish()` 必须在宿主 `finally` 调用（终止符契约） |
| 诊断出口 | 结构化对象 | — | `{ level, code, message, ... }` | **绝不静默丢弃**：wrapper 不允许吞诊断，必须透出给调用方 |

## 错误与异常约定

- 协议层错误：IR 诊断（`Exact/Degraded/Unsupported/Invalid`），见 fidelity-matrix。
- ABI 层错误：非零返回 / 显式错误导出（依 `wasm_abi_version` 对应契约）。
- Wrapper 层约定（新增）：**不吞错、不重试、不降级** —— 三类决定都留给宿主；
  wrapper 只做编解码与类型映射。
