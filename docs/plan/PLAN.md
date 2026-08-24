# Prism 迭代计划

> 立项日期：2026-08-21
> 范围状态：已签署
> 需求来源：`docs/requirements.md`

---

## 1. 范围冻结

### In Scope（本次必须交付）

| # | 交付物 | 链接需求 | 说明 |
|---|--------|---------|------|
| S1 | L1 零配置 API 验证 | REQ-001 | 验证现有 `Prism::complete()` 可用性 |
| S2 | L2 Agent 循环 API 验证 | REQ-008 | 验证现有 `Prism::stream()` + 5 事件 |
| S3 | 配置管理验证 | REQ-009 | 验证 PrismOptions + extras 透传 |
| S4 | 错误处理验证 | REQ-010 | 验证 Result[String, String] 错误分类 |
| S5 | SDK 使用文档 | — | Getting Started + API Reference |
| S6 | SDK 层测试补充 | REQ-001~010 | 覆盖 L1/L2/配置/错误场景 |

### Out of Scope（本次不做）

| # | 推迟项 | 链接需求 | 推迟原因 |
|---|--------|---------|---------|
| O1 | L3 精细控制 | T1 | 非核心用户群 |
| O2 | gRPC binding | T2 | 传输层已有 HTTP/UDS/WS |
| O3 | SDK 自动生成 | T3 | 可先手动维护 |
| O4 | Daemon 原生化 | T4 | Go+wazero 可用 |
| O5 | 生产部署方案 | T5 | 先确保 SDK 可用 |
| O6 | 监控/可观测性 | T6 | 非 MVP 必须 |

---

## 2. 架构约束（已锁定）

### 2.1 执行模型

**MoonBit = 同步纯函数，无原生 async。**

IO 通过回调注入桥接：
```
Host 调用者 ──send(json)──▶ SDK ──encode──▶ Provider JSON
Host 调用者 ◀──text─────── SDK ◀──decode─── Provider Response
```

SDK 不持有 HTTP 客户端，不执行网络请求。所有 IO 由 Host（调用者）通过 `send` 回调注入。

### 2.2 分层架构

```
┌─────────────────────────────────┐
│  应用开发者代码                    │
│  prism.complete("Hello")         │  ← L1 零配置
│  prism.stream(ctx, send)         │  ← L2 Agent 循环
├─────────────────────────────────┤
│  SDK 层（MoonBit）                │
│  Prism / Context / PrismEvent    │  ← 纯编解码 + 事件映射
├─────────────────────────────────┤
│  IR 层（Lucent IR）               │
│  LucentRequest / LucentResponse  │  ← 厂商无关中间表示
├─────────────────────────────────┤
│  适配器层（7 Provider）            │
│  6 函数契约 per provider          │  ← 双向转换
└─────────────────────────────────┘
```

### 2.3 WASM 目标

- 编译目标：`wasm-gc`
- 导出契约：String 进出，15 个导出函数
- 宿主集成：Go (wazero) / TypeScript / Python wrapper

---

## 3. API 设计

### 3.1 L1 零配置 API

**目标：** 3 行代码完成一次跨 Provider 的 AI 调用。

```moonbit
// 回调注入模式（推荐）
let prism = Prism::new().with_provider("openai")
let result = prism.complete("Hello", PrismOptions::default(), my_http_send)
// result = Ok("Hi there! How can I help you?")

// Provider 切换：只改 provider 名
let prism = Prism::new().with_provider("anthropic")
let result = prism.complete("Hello", { model: Some("claude-sonnet-4"), ..PrismOptions::default() }, my_send)
```

### 3.2 L2 Agent 循环 API

**目标：** Context + 5 事件流 + 工具注册。

```moonbit
let prism = Prism::new().with_provider("openai")
let ctx = Context::new()
  .add_system("你是一个天气助手")
  .add_user("北京今天天气如何？")

let events = prism.stream(ctx, my_sse_send)
// events = [TextDelta("北京今天"), TextDelta("晴，25°C"), Finish(Stop)]
```

**5 种事件类型：**

| 事件 | 含义 | 数据 |
|------|------|------|
| `TextDelta(text)` | 文本增量 | 累加得到完整文本 |
| `ToolCall({id, name, args})` | 工具调用 | 需要 Host 执行并返回结果 |
| `ToolResult({id, content, is_error})` | 工具结果 | 注入 Context 继续循环 |
| `Thinking({text, signature, redacted})` | 推理过程 | 可展示或忽略 |
| `Finish(reason)` | 本轮结束 | Stop/Length/ToolCalls/Error |

### 3.3 配置管理

```moonbit
let opts = PrismOptions::new(
  model: Some("gpt-4o"),
  temperature: Some(0.7),
  max_tokens: Some(4096),
  store: None,
  extras: Some(Map::singleton("logprobs", Json::bool(true))),
)
```

- API Key / Base URL：由 Host 在 `send` 回调中注入，SDK 不存储
- 厂商特有参数：通过 `extras` 透传

### 3.4 错误处理

**当前模型：** `Result[String, String]` — 成功返回值，失败返回错误字符串。

| 错误类型 | 来源 | 处理方式 |
|---------|------|---------|
| 编码错误 | SDK 内部 | `Err("encode error: ...")` |
| 解码错误 | SDK 内部 | `Err("decode error: ...")` |
| Provider 错误 | Host send 回调 | `Err(send 返回的错误)` |
| 转换诊断 | ConversionDiagnostic | `Degraded`/`Unsupported` 标记 |

---

## 4. 主干冻结 + 柔性预留

### 冻结项（不可变更）

1. **IR 中心辐射式架构** — 所有转换必经 Lux IR
2. **6 函数适配器契约** — 每 Provider 实现 6 个纯函数
3. **String 进出** — WASM 导出零摩擦
4. **回调注入模式** — SDK 不持有 HTTP 客户端
5. **5 种事件类型** — Text/ToolCall/ToolResult/Thinking/Finish

### 柔性预留（可配置化/参数化）

1. **Provider 配置格式** — 当前 `PrismOptions`，后续可扩展为结构化配置
2. **错误处理策略** — 当前 `Result[String, String]`，后续可扩展为 `PrismError` 枚举
3. **事件类型扩展** — 当前 5 种，后续可新增（如 `Usage`、`Metadata`）
4. **重试/限流策略** — 当前由 Host 实现，后续可内置
5. **默认模型** — 当前硬编码 `"gpt-4o"`，后续可配置

### 状态预留

1. **L3 精细控制** — `ProviderCapability` 已实现，API 表面待设计
2. **gRPC binding** — 传输层架构已预留，实现待排期
3. **SDK 自动生成** — `.mbti` 接口文件已就绪，生成 pipeline 待设计

---

## 5. 风险清单

| # | 风险 | 影响 | 缓解措施 |
|---|------|------|---------|
| 1 | MoonBit 异步能力不足 | L2 流式 API 体验受限 | 回调注入模式已验证可行 |
| 2 | Provider API 变更频繁 | 适配器维护成本高 | 6 函数契约隔离变更影响 |
| 3 | WASM 性能瓶颈 | 大量并发请求时延迟高 | 纯函数无状态，可水平扩展 |
| 4 | 错误信息不够结构化 | 调试困难 | 当前 String 可用，后续可扩展 |
| 5 | 缺少 HTTP 客户端 | SDK 无法独立运行 | 回调注入模式，Host 负责 IO |

---

## 6. 成功标准

1. ✅ 应用开发者可以用 3 行代码完成一次跨 Provider 的 AI 调用
2. ✅ `moon test` 全部通过（现有 715 测试 + 新增 SDK 测试）
3. ✅ SDK 文档可让新开发者在 10 分钟内完成第一次调用
