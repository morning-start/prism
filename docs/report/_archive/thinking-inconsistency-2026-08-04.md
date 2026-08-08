# Thinking/Reasoning 协议不一致问题 — 全面调研报告

> **归档状态**：本文档是 2026-08-04 的一次性行业调研产物。其结论（4 种结构类型、
> 跨协议映射）已被正式吸收至 `docs/adr/ADR-008-thinking-reasoning-unification.md`
> 与 `docs/lux-ir-design.md` §9.1（消息级 reasoning 承载与跨协议映射表）。此后以
> 规范文档为准，本文作为历史溯源保留。

> 调研日期：2026-08-04
> 方法：按 litellm providers 分类，逐厂商调研 API 文档 + 响应格式
> 范围：11 个主流厂商/API 形态，含 4 种结构类型

## 1. 厂商与格式全览

### 1.1 按结构类型分类

| 结构类型 | 厂商 | 位置 | 字段名 | 传递方式 |
|---------|------|------|--------|---------|
| **A. 消息级额外字段** | OpenAI Chat (o-series) | `usage.reasoning_tokens` | 隐藏，不可见 | 仅 Token 计数 |
| | **vLLM** | `message.reasoning` | `reasoning` | 额外字段 |
| | **DeepSeek** | `message.reasoning_content` | `reasoning_content` | 额外字段 |
| | **Fireworks AI** | `message.reasoning_content` | `reasoning_content` | 额外字段 |
| | **Groq** | 无原生 | — | 依赖后端模型 |
| | **Together AI** | 无原生 | — | 依赖后端模型 |
| **B. Content block 变体** | **Anthropic** | `content[]` block | `thinking` | content block |
| | **Mistral** | `content[]` chunk | `thinking` (ThinkChunk) | content chunk |
| | **Cohere** | `content[]` chunk | `thinking` | content chunk |
| **C. 独立 Item/步类型** | **OpenAI Responses** | `output[]` Item | `reasoning` | 独立 Item |
| | **Gemini (Interactions)** | `steps[]` 步 | `thought` | 独立步 |
| **D. 布尔标记** | **Gemini (generateContent)** | `part` 对象 | `thought: true` | 布尔标记 |

### 1.2 各厂商详细格式

#### OpenAI Chat Completions（o-series, GPT-5+）

- **请求参数**：`reasoning_effort`（none/minimal/low/medium/high/xhigh/max）、`reasoning.summary`（auto/concise/detailed）、`reasoning.mode`（standard/pro）
- **响应格式**：`usage.output_tokens_details.reasoning_tokens`（隐藏推理 token 计数，不暴露内容）
- **流式**：仅 Token 计数，无 `reasoning_content` 字段
- **多轮**：通过 `previous_response_id` 自动管理推理状态
- **特别注意**：`o1-mini` 不支持 `reasoning_effort`；`gpt-5-pro` 只支持 `high`；`reasoning_effort` 默认值因模型而异

#### OpenAI Responses API

- **请求参数**：`reasoning: {effort, generate_summary, summary}`
- **响应格式**：`output[]` 中 `type: "reasoning"` 的 `ResponseReasoningItem`：
  ```json
  {"id": "rs_xxx", "type": "reasoning", "summary": [{"type": "summary_text", "text": "..."}], "status": "completed", "encrypted_content": "..."}
  ```
- **流式**：SSE event 流式传输 reasoning item
- **多轮**：`previous_response_id` 或手动传递 reasoning item（含 `encrypted_content` 用于 ZDR 场景）
- **加密**：`include: ["reasoning.encrypted_content"]` 获取加密推理 token（仅 ZDR 场景）

#### Anthropic

- **请求参数**：`thinking: {type: "enabled", budget_tokens: N}`（extended thinking，Claude 4.6 及更早）
- **响应格式**：`content[]` 中 `type: "thinking"` block：
  ```json
  {"type": "thinking", "thinking": "推理文本...", "signature": "sig-xxx"}
  {"type": "redacted_thinking", "signature": "sig-xxx", "data": "encrypted..."}
  ```
- **流式**：`content_block_start(type: "thinking")` → `content_block_delta(type: "thinking_delta", thinking: "增量")` → `signature_delta(signature: "sig")` → `content_block_stop()`
- **多轮**：signature 自动管理，`redacted_thinking` 的加密数据回传时自动解密
- **签名**：`signature` 字段是完整性校验关键，任何 thinking block 都必须包含
- **配置演进**：Claude 4.7+ 改用 adaptive thinking（`thinking.type: "enabled"` 被拒绝，返回 400）
- **兼容性**：不支持 temperature/top_p/top_k；`budget_tokens` 必须 >= 1024 且 < `max_tokens`

#### DeepSeek

- **请求参数**：`thinking: {type: "enabled"}`（`extra_body` 中）+ `reasoning_effort`（high/medium/low）
- **响应格式**：`message.reasoning_content`（字符串，与 `content` 同级）
  ```json
  {"role": "assistant", "content": "最终答案", "reasoning_content": "推理过程..."}
  ```
- **流式**：`delta.reasoning_content`（增量推理 token）
- **多轮关键规则**：
  - 无 tool call 时：`reasoning_content` 在后继轮次中被忽略，**不需要**回传
  - **有 tool call 时**：`reasoning_content` **必须**回传，否则 API 返回 400 错误
- **注意**：`deepseek-reasoner` 是专用推理模型端点；`deepseek-v4-pro` 通过 `thinking` 参数启用思维模式

#### Gemini（generateContent API）

- **请求参数**：`generationConfig.thinkingConfig: {includeThoughts: true, thinkingBudget: N}`
- **响应格式**：`part` 对象上的布尔标记：
  ```json
  {"parts": [{"text": "推理文本...", "thought": true}, {"text": "最终答案"}]}
  ```
- **流式**：`thought: true` 标记
- **无签名**：generateContent API 无 signature 概念

#### Gemini（Interactions API — 新）

- **请求参数**：`thinking_level`（minimal/low/medium/high）、`thinking_summaries`（none/concise/auto）
- **响应格式**：`steps[]` 中 `type: "thought"` 步：
  ```json
  {"type": "thought", "signature": "encrypted...", "summary": [{"type": "text", "text": "..."}]}
  ```
- **流式**：`step.delta` 中 `thought_summary`（增量内容）+ `thought_signature`（最后一个 delta 的签名）
- **多轮**：stateful 模式自动管理；stateless 模式必须回传所有 `thought` 步
- **签名**：加密签名，用于多轮连续性
- **定价**：`total_thought_tokens` 在 usage 中，按完整思维 token 计费（非仅摘要）

#### Mistral

- **请求参数**：`reasoning_effort`（high/none）
- **响应格式**：`message.content` 是 chunks 列表（非纯字符串）：
  ```json
  {"content": [{"type": "thinking", "thinking": [{"type": "text", "text": "..."}]}, {"type": "text", "text": "最终答案"}]}
  ```
- **流式**：`delta.content` 在 thinking 阶段是 `ThinkChunk` 列表，transition 阶段混合，答案阶段是纯字符串
- **多轮**：必须保留完整的 `ThinkChunk` 在历史中（否则降低输出质量）
- **注意**：`reasoning_effort="none"` 时，`content` 是纯字符串（无 thinking chunk）

#### Cohere

- **请求参数**：`prompt_mode = "reasoning"`
- **响应格式**：`content` 数组含 `thinking` 和 `text` 类型：
  ```json
  {"content": [{"type": "thinking", "thinking": [{"type": "text", "text": "..."}]}, {"type": "text", "text": "最终答案"}]}
  ```
- **流式**：类似 Mistral 的分块模式

#### Fireworks AI

- **请求参数**：`reasoning_effort`（medium/high 等）+ `thinking`（Anthropic 兼容，不能同时使用）
- **响应格式**：`message.reasoning_content`（与 DeepSeek 同模式）
- **流式**：`delta.reasoning_content`
- **多轮**：有 tool call 时 `reasoning_content` **必须**回传（与 DeepSeek 一致）
- **注意**：Fireworks 同时支持 `reasoning_effort` 和 Anthropic 风格的 `thinking` 参数，但不能同时指定

#### Azure OpenAI

- 与 OpenAI 完全一致（o-series + GPT-5+）
- `reasoning_effort`：low/medium/high（GPT-5 额外支持 minimal）
- `reasoning_tokens` 在 `completion_tokens_details` 中
- **额外陷阱**：
  - API 版本选择复杂（`2025-04-01-preview` vs `preview` vs GA）
  - `reasoning_effort` 默认值因模型而异
  - 并行工具调用在 `reasoning_effort="minimal"` 时不可用
  - 推理延迟需考虑入口超时（Azure Container Apps 默认 240 秒）

#### vLLM

- **请求参数**：`--reasoning-parser` + `--reasoning-config`（服务端配置）；`extra_body: {include_reasoning: true/false}` + `extra_body: {chat_template_kwargs: {enable_thinking: true}}`
- **响应格式**：`message.reasoning`（字符串，与 `content` 同级）
  ```json
  {"role": "assistant", "content": "最终答案", "reasoning": "推理过程..."}
  ```
- **流式**：`delta.reasoning`
- **预算控制**：`thinking_token_budget`（采样参数）
- **注意**：`reasoning` 字段名曾用 `reasoning_content`（已迁移）；`include_reasoning: false` 可抑制输出

## 2. 问题类别分析

### 2.1 结构类型差异（核心）

四种结构类型之间的转换是全项目最复杂的工程挑战：

| 转换方向 | 问题 | 难度 |
|---------|------|------|
| A→B（消息字段→Content block） | 需要在 `content` 数组前插入 thinking block，语义对齐 | 🟡 中 |
| A→C（消息字段→独立 Item） | 结构扁平化，需重新组织 response 结构 | 🟢 低 |
| A→D（消息字段→布尔标记） | 需将 `reasoning` 字符串拆为多个 `thought: true` part | 🟡 中 |
| B→A（Content block→消息字段） | 需从 `content[]` 提取 thinking block 转为 `message.reasoning` | 🟢 低 |
| B→C（Content block→独立 Item） | 需将 block 映射为独立 Item 类型 | 🟢 低 |
| B→D（Content block→布尔标记） | 需将 thinking content 放入 `thought: true` part | 🟢 低 |
| C→B（独立 Item→Content block） | 需将 reasoning Item 转为 content block 插入 `content[]` | 🟡 中 |

### 2.2 签名完整性（跨协议丢失）

| 协议 | 有签名 | 签名类型 | 备注 |
|------|--------|---------|------|
| Anthropic | ✅ | 明文签名 `signature` | 完整性校验，redacted_thinking 加密 |
| OpenAI Responses | ✅ | ID 引用 `encrypted_content` | 加密 reasoning token 用于多轮 |
| Gemini (Interactions) | ✅ | 加密签名 `signature` | 多轮连续性 |
| DeepSeek | ❌ | 无签名 | 多轮依赖 `reasoning_content` 回传 |
| Mistral | ❌ | 无签名 | 多轮依赖完整 ThinkChunk 回传 |
| Cohere | ❌ | 无签名 | 多轮依赖完整 chunk 回传 |
| vLLM | ❌ | 无签名 | 多轮依赖 `reasoning` 回传 |
| Gemini (generateContent) | ❌ | 无签名 | 无多轮连续性概念 |

**影响**：当从有签名的协议（Anthropic/OpenAI Responses）转换到无签名的协议时，签名信息必然丢失。这不应是 `Unsupported` 错误（因为 thinking 内容可以转换），而应是 **`Degraded`** 诊断。

### 2.3 隐藏/不可见 thinking

| 协议 | 隐藏机制 | 能否转换 |
|------|---------|---------|
| Anthropic | `redacted_thinking`（加密数据） | 🔴 不可逆—加密数据只有 Anthropic 后端能解密 |
| OpenAI Chat | 隐藏推理 token（仅计数） | 🔴 不可见—内容本身不暴露 |
| OpenAI Responses | `encrypted_content` + `summary` | 🟡 只能看到摘要，加密内容不可见 |
| Gemini (Interactions) | 签名加密，但 `summary` 可见 | 🟢 摘要可见 |
| 其他 | 无隐藏机制 | — |

**影响**：Anthropic 的 `redacted_thinking` 和 OpenAI 的隐藏推理 token 是两个极端——前者有加密数据但不可读，后者完全不暴露。转换到可见 thinking 格式时，无法还原这些内容。

### 2.4 配置参数差异

| 参数 | OpenAI | Anthropic | DeepSeek | Gemini | Mistral | vLLM |
|------|--------|-----------|----------|--------|---------|------|
| 启停参数 | `reasoning_effort` | `thinking.type` | `thinking.type` | `thinking_level` | `reasoning_effort` | `--reasoning-parser` |
| 预算控制 | `max_completion_tokens` | `budget_tokens` | N/A | `thinkingBudget` | N/A | `thinking_token_budget` |
| 努力级别 | none/minimal/low/medium/high/xhigh/max | enabled/disabled | high/medium/low | minimal/low/medium/high | high/none | 无（由 parser 控制） |
| 摘要控制 | `reasoning.summary` | N/A | N/A | `thinking_summaries` | N/A | `include_reasoning` |
| 模式选择 | `reasoning.mode`(standard/pro) | N/A | N/A | N/A | N/A | `--reasoning-config` |

**影响**：`reasoning_effort` 在各个协议中的值域和语义都不同，直接映射会丢失精度。例如 OpenAI 的 `max` 在 Mistral 中不存在，OpenAI 的 `none` 在 Anthropic 中对应 `thinking.disabled`。

### 2.5 流式格式差异

| 协议 | 流式格式 | 事件生命周期 |
|------|---------|-------------|
| OpenAI Chat | 无 `reasoning_content` 字段 | 只有 token 计数 |
| OpenAI Responses | SSE event 流式 transport | item 级别 |
| Anthropic | `content_block_start/delta/stop` | block 生命周期 |
| DeepSeek | `delta.reasoning_content` | 消息级别字段 |
| Gemini (Interactions) | `step.delta`(thought_summary/thought_signature) | 步生命周期 |
| Gemini (generateContent) | `thought: true` 标记 | 无独立生命周期 |
| Mistral | `delta.content` 变化类型 | thinking→text 两阶段 |
| vLLM | `delta.reasoning` | 消息级别字段 |

**影响**：流式格式差异极大，从简单的消息级别字段（DeepSeek/vLLM）到复杂的 block 生命周期（Anthropic）再到步级别生命周期（Gemini Interactions）。Lux IR 的 `StreamEvent`（BlockStart/BlockDelta/BlockEnd）最能匹配 Anthropic 的 block 生命周期，但与其他格式映射时需要合成/简化事件序列。

## 3. 影响范围与建议

### 3.1 当前最紧急的修复

1. **openai-chat 适配器**：捕获 `message.reasoning` / `delta.reasoning`（vLLM 后端）和 `message.reasoning_content` / `delta.reasoning_content`（DeepSeek/Fireworks 后端）
2. **流式适配器**：处理 vLLM/DeepSeek 的 `delta.reasoning`/`delta.reasoning_content` 字段，映射为 `BlockStart(Thinking)` + `ThinkingDelta`
3. **诊断升级**：对缺少 signature 的 thinking 内容产生 `Degraded`（而非 `Unsupported`）诊断

### 3.2 中期优化

1. **Lux IR 扩展**：考虑在 `LucentResponse` 中增加消息级 `reasoning` 字段（纯字符串，无签名），兼容 vLLM/DeepSeek/Fireworks 风格
2. **配置映射表**：建立 `LucentReasoningConfig` 到各协议配置参数的映射表，处理 `reasoning_effort` 值域差异
3. **流式事件归一化**：统一不同协议的流式 thinking 事件到 Lux IR 的 `StreamEvent` 体系

### 3.3 长期架构

1. **签名分层**：在 `LucentThinking` 中区分 `signature`（Anthropic 风格）和 `encrypted_id`（OpenAI Responses 风格）
2. **隐藏 thinking 协议**：定义 `LucentThinking.redacted` 语义，处理 `redacted_thinking` 和 `encrypted_content` 的不可逆性
3. **多轮连续性**：定义清晰的 thinking 回传规则（参考 DeepSeek/Fireworks 的「有 tool call 必回传」模式）

## 4. 总结

| 影响类型 | 严重度 | 涉及的厂商 | 建议修复路径 |
|---------|--------|-----------|-------------|
| `message.reasoning` 未被捕获 | 🔴 高 | vLLM, DeepSeek, Fireworks | 修改 openai-chat 入站解析 |
| `delta.reasoning` 流式未被捕获 | 🔴 高 | vLLM, DeepSeek, Fireworks | 修改流式解析器 |
| 签名跨协议丢失 | 🟡 中 | Anthropic→vLLM/DeepSeek/Mistral | `Degraded` 诊断 |
| `redacted_thinking` 不可逆 | 🟡 中 | Anthropic→其他 | `Degraded` 诊断 + 保留加密数据 |
| `reasoning_effort` 值域差异 | 🟡 中 | 跨协议配置映射 | 配置映射表 |
| 隐藏推理 token 不可见 | 🟢 低 | OpenAI Chat | 不处理（按设计不可见） |
| 流式事件生命周期差异 | 🟡 中 | 跨协议流式转换 | 归一化到 Lux IR StreamEvent |
| 多轮回传规则差异 | 🟡 中 | DeepSeek/Fireworks vs 其他 | 统一规则定义 |