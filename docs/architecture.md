# Prism 架构设计

> Prism 核心架构、双场景设计与适配器契约。
> 本文件是架构设计的 source of truth；当前状态见 [`status.md`](./status.md)。

---

## 项目类型

`lib` + `wasm` — 核心协议转换库，编译目标 `wasm-gc`，后续扩展 HTTP 网关 CLI。

## 架构总览

```
src/lux/      ← Lucent IR 核心（纯数据结构，无 IO、无厂商绑定）
    │
    ├── src/provider/openai_chat/      ← OpenAI Chat 适配器 ✅
    ├── src/provider/openai_responses/ ← OpenAI Responses 适配器 ✅
    ├── src/provider/openai_codex/     ← OpenAI Codex 变体 ✅
    ├── src/provider/openai_azure/     ← Azure OpenAI 变体 ✅
    ├── src/provider/anthropic/        ← Anthropic Messages 适配器 ✅
    ├── src/provider/gemini/           ← Google Gemini 适配器 ✅
    ├── src/provider/gemini_vertex/    ← Google Vertex AI 变体 ✅
    │
    └── src/wasm/                      ← WASM 导出层（15 个导出函数，以 .mbti 为真值）✅
```

每一层都是纯函数；公开转换契约通过 `ProviderRegistration` 注册表（6 个纯函数）分发，`ConversionResult` 已接入请求/响应校验（`decode_response_with_diagnostics` / `encode_request_with_diagnostics`）。

## 分包结构

```
prism/
│
├── moon.mod                     # 模块元数据，name = "morning-start/prism"，source = "src"
│
├── src/                         # 源码根（source = "src"）
│   ├── moon.pkg                 # 根包：类型提升（Prism/PrismOptions/PrismEvent 等）
│   ├── prism.mbt                # 根包入口，use morning-start/prism 即用
│   │
│   ├── lux/                     # Lucent IR 核心包
│   │   ├── moon.pkg             # 依赖 moonbitlang/core/json
│   │   ├── lux.mbt              # 34+ 核心类型定义
│   │   ├── stream.mbt           # 流式事件枚举 + 累加器
│   │   ├── serialize.mbt        # to_json() 显式序列化
│   │   ├── deserialize.mbt      # from_json() 显式反序列化
│   │   ├── lux_wbtest.mbt       # 核心类型白盒测试
│   │   ├── serialize_wbtest.mbt # 序列化白盒测试
│   │   └── deserialize_wbtest.mbt # 反序列化 round-trip 测试
│   │
│   ├── provider/                # 厂商适配器
│   │   ├── openai_chat/
│   │   │   ├── moon.pkg         # 依赖 lux + moonbitlang/core/json
│   │   │   ├── chat.mbt         # 6 函数（双向转换 + 流式）
│   │   │   └── chat_wbtest.mbt  # 35+ 测试
│   │   │
│   │   ├── anthropic/           # Anthropic Messages 适配器
│   │   ├── openai_responses/    # OpenAI Responses 适配器
│   │   ├── openai_codex/        # OpenAI Codex 变体
│   │   ├── openai_azure/        # Azure OpenAI 变体
│   │   ├── gemini/              # Google Gemini 适配器
│   │   └── gemini_vertex/       # Google Vertex AI 变体
│   │
│   ├── sdk/                     # Provider 注册表 + Prism/Context/Event
│   │
│   └── wasm/                    # WASM 导出层
│       ├── moon.pkg             # 依赖 sdk + lux
│       └── wasm.mbt             # 15 导出函数（以 .mbti 为真值，见 scripts/export_count.sh）
│
├── schemas/
│   └── lux-ir-v1.json           # JSON Schema v1（事实标准）
│
└── docs/
    ├── architecture.md           # ← 本文件
    ├── status.md                 # 当前状态追踪
    ├── lux-ir-design.md          # Lux IR 形式规范
    ├── sdk-usage.md              # SDK 使用指南
    └── protocols/                # 厂商协议规格参考
```

## 6-Function 适配器契约

每个适配器实现 6 个纯函数，String 进出，附带 `ConversionResult` 信封（含诊断）。
完整签名与契约不变性见 [`lux-ir-design.md` §10](./lux-ir-design.md#10-6-function-适配器契约)。

## 映射规则（以 OpenAI Chat 为例）

#### OpenAI Request → LucentRequest

| OpenAI 字段 | LucentRequest 字段 | 说明 |
|-------------|-------------------|------|
| `model` | `.model` | 直接映射 |
| `messages[?role=system].content` | `.instructions` | 抽出为系统指令 |
| `messages[].content` (string) | `.conversation[].Message.content[Text]` | 单字符串 |
| `messages[].content` (array) | `.conversation[].Message.content[Text/Image]` | 多 content part |
| `messages[].tool_calls` | `.conversation[].Message.content[ToolUse]` | 工具调用 |
| `messages[?role=tool]` | `.conversation[].Message.content[ToolResult]` | 工具结果 |
| `temperature` | `.options.temperature` | Option 映射 |
| `max_tokens` | `.options.max_output_tokens` | Option 映射 |
| `stream` | `.options.stream` | 直接映射 |
| `tools` | `.tools` | 工具定义 |
| `tool_choice` | `.tool_choice` | 类型化枚举 |

#### LucentResponse → OpenAI Response

| LucentResponse 字段 | OpenAI 字段 | 说明 |
|---------------------|-------------|------|
| `.id` | `id` | 直接映射 |
| `.model` | `model` | 直接映射 |
| — | `object: "chat.completion"` | 固定值 |
| `.choices[].message` | `choices[].message` | 含 role/content/tool_calls/refusal |
| `.choices[].finish_reason` | `choices[].finish_reason` | 类型化转字符串 |
| `.usage` | `usage` | 直接映射 |

## 测试场景

当前测试覆盖（lux 包）：

| 类别 | 数量 | 说明 |
|------|------|------|
| 类型构造 | 30+ | 覆盖所有 Lucent* 类型 |
| 枚举映射 | 5 | Role / FinishReason / ErrorKind 等 |
| 流式累加 | 12 | 文本/工具调用/思考/拒绝/混合等 |
| to_json 序列化 | 73 | 每类型至少 2 场景 |
| from_json deserialize + round-trip | 31 | construct → to_json → from_json → assert_eq |
| 适配器 6 函数 | 35+ | 全部 6 通路 |

## 目标平台

`wasm-gc`（与根模块一致）

## 开发原则

1. **纯函数** — 无 IO、无状态、无副作用，WASM 安全边界
2. **String 进出** — 输入输出均为 JSON 字符串，WASM 导出零摩擦
3. **Round-trip 安全** — Provider → Lux → Provider 必须保持语义一致
4. **JSON Schema 作为事实标准** — `schemas/lux-ir-v1.json` 定义协议，MoonBit 是参考实现
5. **失败即返回 String 错误** — 不抛异常，`Result` 表达

---

## 双场景设计（2026-08-01 用户确认）

> 本项目的两个核心使用场景，共用一个地基：**Lux IR + 6 函数适配器注册表**。
> 两者只是入口/出口不同，转换逻辑完全复用。

### 场景总览

```
场景 1（开发者 SDK）：  应用代码/心智模型 ──Lux IR──▶ 任意厂商协议
场景 2（中转站转发）：  厂商协议 A(原厂) ──Lux IR──▶ 厂商协议 B(目标)
```

| 维度 | 场景 1：开发者 SDK | 场景 2：中转站 |
|------|------------------|---------------|
| 使用者 | Agent 工作流/应用开发者 | 协议网关、中间站、代理 |
| 核心价值 | 只写一种协议，兼容所有厂商 | 原厂只提供一种接口 → 用户获得多接口能力 |
| 入口 | 高层 API（Context/Event/工具） | 厂商 A 的 JSON/SSE |
| 出口 | 厂商 JSON | 厂商 B 的 JSON/SSE |
| 通路 | 请求/响应/流式 | 请求/响应/流式（全选） |

### 架构决策：A. IR 中心辐射式（已确认）

- 所有转换必经 Lux IR，每厂商只实现「↔ IR」的 6 个纯函数（2N 个，N=7 厂商 → 14 个），
  而非两两直连（N² = 49 个）。
- 语义一致：所有组合 A→B 共享同一 IR 语义，能力边界（`ProviderCapability`）一处声明。
- 已否决：B 两两直连（组合爆炸、维护噩梦）；C 单一协议为准（无法满足「多接口能力」需求）。
- 现有 `provider/` 注册表（`ProviderRegistration` 6 函数 + `match_provider_name`）已在此方向上，
  无需推倒重来，只需补齐两个「表面」。

### 场景 1 设计：开发者 SDK

当前为纯编解码 façade（`encode_request` / `decode_response` / `encode_stream_request` /
`decode_sse` / `capability`），目标补齐高层 Agent API（对应 `docs/rules/sdk-three-layer.md`）：

- **L1 零配置**：`Prism.complete(text)` 文本进出，切换 provider 只改一个参数
- **L2 Agent 循环**：`Context` 消息队列 + 工具注册 + `Prism.stream()` 5 事件循环
  （TextDelta / ToolCall / ToolResult / Thinking / Finish）
- **L3 精细控制**：`ProviderCapability` 自省 + 厂商特有参数命名参数 + `extras`
- **不暴露**：IR 类型、协议差异、厂商特有字段

### 场景 2 设计：中转站（WASM 先行）

组合入口 =「source 解码 + target 编码」，零新增转换逻辑：

| 通路 | 组合函数 |
|------|---------|
| 请求 | `convert_request(source, json_str, target) -> Result[String, String]` |
| 响应 | `convert_response(source, json_str, target) -> Result[String, String]` |
| 流式 | `convert_stream(source, sse_str, target) -> Result[String, String]` |

落地形态（按用户确认的优先级）：

1. **当前：WASM 导出** — `wasm_convert_*` 导出函数，String 进出，宿主语言零摩擦
2. **后续（方法未定，仅加入口层，不动核心）**：
   - HTTP 服务请求方式（`transport/daemon` 雏形可演进）
   - 本地程序进程间通信（UDS / stdio / WebSocket 等，待选型）

> 演进约束：任何新入口形态只复用 `convert_*` 组合逻辑，不触碰 Lux IR 与适配器注册表。

### 未来愿景

作为 **AI 基础设施**：处理各种协议转换逻辑，向上服务开发者生态（场景 1），
向下支撑中转/网关/代理部署（场景 2），二者共享同一 IR 语义与能力边界。
