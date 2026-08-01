# Prism — 需求与设计文档

## 项目类型

`lib` + `wasm` — 核心协议转换库，编译目标 `wasm-gc`，后续扩展 HTTP 网关 CLI。

## 架构总览

```
lux/          ← Lucent IR 核心（纯数据结构，无 IO、无厂商绑定）
    │
    ├── provider/openai_chat/      ← OpenAI Chat 适配器 ✅
    ├── provider/openai_responses/ ← OpenAI Responses 适配器 ✅
    ├── provider/openai_codex/     ← OpenAI Codex 变体 ✅
    ├── provider/openai_azure/     ← Azure OpenAI 变体 ✅
    ├── provider/anthropic/        ← Anthropic Messages 适配器 ✅
    ├── provider/gemini/           ← Google Gemini 适配器 ✅
    ├── provider/gemini_vertex/    ← Google Vertex AI 变体 ✅
    │
    └── wasm/                      ← WASM 导出层（11 个 MoonBit 导出函数）✅
```

每一层都是纯函数；当前公开转换契约仍为 `String JSON → Result[T, String]`，`ConversionResult` 仅完成类型定义，尚未接入适配器注册表。

## 当前状态

| 模块 | 状态 | 测试数 |
|------|------|--------|
| `lux/` 核心类型定义 | ✅ **已完成** | 34+ 类型，`pub(all) enum` |
| `lux/` JSON 序列化 (to_json) | ✅ **已完成** | 结构化测试覆盖 |
| `lux/` JSON 反序列化 (from_json) | ✅ **已完成** | round-trip 测试覆盖 |
| `lux/` 流式事件 + 累加器 | ✅ **已完成** | 块生命周期模型；部分事件仍需诊断化 |
| `lux/` 转换诊断类型 | 已定义 | `ConversionStatus / ConversionResult` 尚未接入适配器契约 |
| `schemas/lux-ir-v1.json` | ✅ **已完成** | JSON Schema v1 |
| 7 个 Provider 适配器 | ✅ **MoonBit 核心已实现** | 部分媒体/推理/事件边界仍有降级或不支持 |
| `sdk/` 表层 API | ✅ **纯编解码 façade** | 不负责 HTTP、认证或 Agent Runtime |
| `wasm/` 导出层 | ✅ **MoonBit 侧已实现** | 11 个导出函数；宿主 wrapper ABI 仍在实现 |
| 跨协议一致性测试 | ✅ | 当前 `moon test` 共 634 个测试通过 |

**当前边界：** `transport/` 已实现最小 HTTP JSON-RPC Daemon（`transport/daemon/`，Go + wazero）；UDS / WebSocket / 流式 SSE 仍在规划。Go / TypeScript / Python wrapper 已实现真实 WASM 字符串 ABI（classic `wasm` 目标，UTF-16 线性内存约定）。

## 分包结构

```
prism/
│
├── moon.mod                     # 模块元数据，name = "morning-start/prism"
│
├── lux/                         # Lucent IR 核心包
│   ├── moon.pkg                 # 依赖 moonbitlang/core/json
│   ├── lux.mbt                  # 34+ 核心类型定义
│   ├── stream.mbt               # 流式事件枚举 + 累加器
│   ├── serialize.mbt            # to_json() 显式序列化
│   ├── deserialize.mbt          # from_json() 显式反序列化
│   ├── lux_wbtest.mbt           # 核心类型白盒测试
│   ├── serialize_wbtest.mbt     # 序列化白盒测试
│   └── deserialize_wbtest.mbt   # 反序列化 round-trip 测试
│
├── provider/                    # 厂商适配器
│   ├── openai_chat/
│   │   ├── moon.pkg             # 依赖 lux + moonbitlang/core/json
│   │   ├── chat.mbt             # 6 函数（双向转换 + 流式）
│   │   └── chat_wbtest.mbt      # 35+ 测试
│   │
│   ├── anthropic/               # Anthropic Messages 适配器
│   ├── openai_responses/        # OpenAI Responses 适配器
│   ├── openai_codex/            # OpenAI Codex 变体
│   ├── openai_azure/            # Azure OpenAI 变体
│   ├── gemini/                  # Google Gemini 适配器
│   └── gemini_vertex/           # Google Vertex AI 变体
│
├── sdk/                         # Provider 注册表 + Prism/Context/Event
│
├── wasm/                        # WASM 导出层
│   ├── moon.pkg                 # 依赖 sdk + lux
│   └── wasm.mbt                # 42 导出函数，7 provider + SDK
│
├── schemas/
│   └── lux-ir-v1.json           # JSON Schema v1（事实标准）
│
└── docs/
    ├── lux-ir-design.md         # Lux IR 形式规范
    ├── requirements.md          # ← 本文件
    └── protocols/               # 厂商协议规格参考
```

## 6-Function 适配器契约

每个适配器实现 6 个纯函数，String 进出：

| # | 方向 | 解码（外部 → Lux） | 编码（Lux → 外部） |
|---|------|------------------|------------------|
| 1 | 请求 | `ext_to_lux_request(String) → Result[LucentRequest, String]` | `lux_request_to_ext(LucentRequest) → Result[String, String]` |
| 2 | 响应 | `ext_to_lux_response(String) → Result[LucentResponse, String]` | `lux_response_to_ext(LucentResponse) → Result[String, String]` |
| 3 | 流式 | `ext_sse_to_events(String) → Result[Array[LucentStreamEvent], String]` | `lux_events_to_ext_sse(Array[LucentStreamEvent]) → Result[String, String]` |

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
