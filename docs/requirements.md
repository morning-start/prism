# Prism — 需求与设计文档

## 项目类型

`lib` + `wasm` — 核心协议转换库，编译目标 `wasm-gc`，后续扩展 HTTP 网关 CLI。

## 架构总览

```
MidProtocol (纯数据结构)             ← 根包 prism.mbt
    │
    ├── openai/  适配器               ← 当前：Phase 1.2
    ├── claude/  适配器               ← Phase 1.5
    ├── ollama/  适配器               ← Phase 1.6
    │
    └── wasm/  导出层                 ← Phase 1.4
```

每一层都是纯函数：`String JSON → Result[MidProtocol, Error]`

## Phase 1 路线图

| Phase | 内容 | 验证 |
|-------|------|------|
| 1.1 | 中间协议数据结构 ✅ | `moon test` 11 passed |
| 1.2 | OpenAI Chat Completion 编解码（非流式） | 输入 OpenAI JSON → 输出 MidRequest / 反向 |
| 1.3 | OpenAI 流式适配器（SSE chunk ↔ MidStreamChunk） | chunk-by-chunk 转换 |
| 1.4 | WASM 导出层 | 宿主语言调用 WASM 验证 |
| 1.5 | Claude Messages API 适配器 | 同上 |
| 1.6 | Ollama / vLLM 适配器 | 同上 |

## Phase 1.2 详细设计

### 分包结构

```
prism/
├── moon.pkg                     # 根库包，导出 MidProtocol 类型
├── prism.mbt                    # MidProtocol 类型定义 (done)
├── prism_wbtest.mbt             # 白盒测试 (done)
├── openai/
│   ├── moon.pkg                 # 依赖根包 + moonbitlang/x/json
│   ├── chat.mbt                 # OpenAI Chat Completion 编解码
│   └── chat_test.mbt            # 测试
│
├── docs/requirements.md         # ← 本文件
└── ...
```

### 依赖

```toml
# openai/moon.pkg
import "morning-start/prism"
import "moonbitlang/x/json"
```

```bash
moon add moonbitlang/x/json
```

### API 表面

```moonbit
/// 解析 OpenAI Chat Completion 请求 JSON → MidRequest
/// 支持: text content, tool_calls, tools, temperature, max_tokens
pub fn openai_chat_to_mid_request(json: String) -> Result[MidRequest, String]

/// 将 MidResponse 序列化为 OpenAI Chat Completion 响应 JSON
/// 支持: choices, usage, finish_reason
pub fn mid_response_to_openai_chat(resp: MidResponse) -> Result[String, String]
```

### 映射规则

#### OpenAI Request → MidRequest

| OpenAI 字段 | MidRequest 字段 | 说明 |
|-------------|----------------|------|
| `model` | `.model` | 直接映射 |
| `messages[].role` | `.messages[].role` | system→System, user→User, assistant→Assistant, tool→Tool |
| `messages[].content` (string) | `.messages[].content[Text]` | 单字符串 |
| `messages[].content` (array) | `.messages[].content[Text/ToolResult]` | 多 content part（跳过 image_url） |
| `messages[].tool_calls` | `.messages[].content[ToolUse]` | 每个 tool_call 转 ToolUse |
| `messages[].tool_call_id` | `.messages[].content[ToolResult]` | tool 角色的响应 |
| `temperature` | `.temperature` | Option 映射 |
| `max_tokens` | `.max_tokens` | Option 映射 |
| `stream` | `.stream` | 直接映射 |
| `tools` | `.tools` | 取 function 内部字段 |

#### MidResponse → OpenAI Response

| MidResponse 字段 | OpenAI 字段 | 说明 |
|-----------------|-------------|------|
| `.id` | `id` | 直接映射 |
| `.model` | `model` | 直接映射 |
| `object` | 固定 `"chat.completion"` | 硬编码 |
| `.choices[].message.role` | `choices[].message.role` | 直接映射 |
| `.choices[].message.content` | `choices[].message.content` | Text parts 拼接为字符串 |
| `.choices[].message.tool_calls` | `choices[].message.tool_calls` | ToolUse→function call |
| `.choices[].finish_reason` | `choices[].finish_reason` | 直接映射 |
| `.usage` | `usage` | 直接映射 |

### 测试场景（11 + 5 个）

新增 5 个测试：

| # | 场景 | 输入 | 验证 |
|---|------|------|------|
| 1 | 标准用户对话 | 单 user message + content string | MidRequest.model == "gpt-4o" |
| 2 | 系统 + 用户消息 | system + user | messages 长度为 2 |
| 3 | 工具定义 | 带 tools 数组 | MidRequest.tools 非 None |
| 4 | Assistant ToolCall | 带 tool_calls 的 assistant | content 含 ToolUse |
| 5 | 带 usage 的响应 | 完整 MidResponse | OpenAI JSON 含 usage 字段 |

### 目标平台

`wasm-gc`（与根模块一致）

## 开发原则

1. **纯函数** — 无 IO、无状态、无副作用
2. **String 进出** — 输入输出均为 JSON 字符串，WASM 导出自然
3. **JSON 健壮性** — 使用 `@json.JsonValue` AST 处理，不依赖正则
4. **可测试** — 每个转换都有独立测试，覆盖正常/缺失字段/非法输入
5. **失败即返回 String 错误** — 不抛异常，`Result` 表达
