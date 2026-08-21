# Prism 需求分层清单

> 立项日期：2026-08-21
> 底线确认：✅ AI 协议碎片化 / 应用开发者 / 统一 API 调用
> 范围签署：✅

---

## 三条底线

| # | 底线 | 内容 |
|---|------|------|
| B1 | 核心问题 | AI 协议碎片化 — 多 AI SDK 之间的协议差异 |
| B2 | 目标用户 | 应用开发者 — 在产品中接入多个 AI 后端的开发者 |
| B3 | 基础价值 | 统一 API 调用 — 一套 API 调用多后端，零协议差异 |

---

## 刚性核心（本次必须交付）

### REQ-001 统一 API 表面（L1 零配置）

- **优先级：** P0
- **服务底线：** B3
- **描述：** 应用开发者可以用 3 行代码完成一次跨 Provider 的 AI 调用，切换 provider 只改一个参数
- **验收标准：**
  - [ ] `Prism::new().with_provider("openai")` 构建器可用
  - [ ] `prism.complete(text, opts, send)` 一行调用返回文本结果
  - [ ] 切换 provider 只改 `with_provider()` 参数，其余代码不变
  - [ ] 现有 715 测试全部通过

### REQ-002 多 Provider 支持

- **优先级：** P0
- **服务底线：** B1
- **描述：** 支持 OpenAI / Anthropic / Gemini 等主流 AI 后端的协议转换
- **验收标准：**
  - [ ] 7 个适配器全部可用（openai_chat, openai_responses, openai_codex, openai_azure, anthropic, gemini, gemini_vertex）
  - [ ] 每个适配器实现 6 函数契约
  - [ ] 转换保真度：Exact / Degraded / Unsupported 显式报告

### REQ-003 流式响应支持

- **优先级：** P0
- **服务底线：** B3
- **描述：** 支持流式 SSE 响应，实时返回 AI 生成内容
- **验收标准：**
  - [ ] `prism.stream(ctx, send)` 返回 `Array[PrismEvent]`
  - [ ] 流式事件包含 TextDelta 增量
  - [ ] 流式事件包含 Finish 终止信号

### REQ-004 工具调用支持

- **优先级：** P0
- **服务底线：** B3
- **描述：** 支持 AI 模型调用外部工具（函数调用）
- **验收标准：**
  - [ ] ToolCall 事件包含 id / name / arguments_json
  - [ ] ToolResult 事件可注入 Context 继续循环
  - [ ] 工具定义可通过 Context 注册

### REQ-005 转换保真度契约

- **优先级：** P0
- **服务底线：** B1
- **描述：** 每个字段的转换结果必须显式报告保真度级别
- **验收标准：**
  - [ ] ConversionResult 信封包含 diagnostics 数组
  - [ ] 无静默丢弃（`_ => ()`）的形状字段
  - [ ] 保真度契约测试矩阵覆盖所有基础 provider

### REQ-006 WASM 跨语言嵌入

- **优先级：** P0
- **服务底线：** B1
- **描述：** 核心转换引擎可编译为 WASM，嵌入任意语言环境
- **验收标准：**
  - [ ] 15 个导出函数以 `.mbti` 为真值
  - [ ] Go / TypeScript / Python wrapper ABI 可用
  - [ ] String 进出，零摩擦

### REQ-007 转换诊断

- **优先级：** P0
- **服务底线：** B1
- **描述：** 转换过程中的降级、不支持、无效字段必须有诊断信息
- **验收标准：**
  - [ ] ConversionDiagnostic 包含 target / fidelity / message
  - [ ] 信封 JSON 编解码正确
  - [ ] SDK / WASM 层可访问诊断信息

---

## 弹性细节（本次交付，实现方式可灵活调整）

### REQ-008 L2 Agent 循环 API

- **优先级：** P1
- **服务底线：** B3
- **描述：** Context 消息队列 + 5 事件流 + 工具注册，面向框架作者
- **验收标准：**
  - [ ] Context 支持 add_system / add_user / add_tool_result
  - [ ] 5 种事件类型：TextDelta / ToolCall / ToolResult / Thinking / Finish
  - [ ] 事件类型可扩展（柔性预留）
- **柔性预留：** 事件类型后续可新增（Usage / Metadata 等）

### REQ-009 配置管理

- **优先级：** P1
- **服务底线：** B3
- **描述：** Provider 配置（model / temperature / max_tokens）可注入
- **验收标准：**
  - [ ] PrismOptions 支持 model / temperature / max_tokens / store / extras
  - [ ] extras 支持厂商特有参数透传
  - [ ] API Key / Base URL 由 Host 在 send 回调中注入（SDK 不存储）
- **柔性预留：** 配置格式后续可演进为结构化 ProviderConfig

### REQ-010 错误处理

- **优先级：** P1
- **服务底线：** B3
- **描述：** 编解码错误和 Provider 错误必须有清晰的错误信息
- **验收标准：**
  - [ ] `Result[String, String]` 错误信息包含错误来源
  - [ ] 编码错误和解码错误可区分
  - [ ] Host send 回调的错误正确透传
- **柔性预留：** 后续可扩展为结构化 `PrismError` 枚举

---

## 临时新增（推迟到后续迭代）

| # | 需求 | 推迟原因 |
|---|------|---------|
| T1 | L3 精细控制（ProviderCapability + extras） | 非核心用户群，L1/L2 稳定后再做 |
| T2 | gRPC binding | 传输层已有 HTTP/UDS/WS，非必须 |
| T3 | 客户端 SDK 生成 pipeline | 可先手动维护 |
| T4 | Daemon MoonBit 原生化 | Go+wazero 可用 |
| T5 | 生产部署方案 | 先确保 SDK 可用 |
| T6 | 监控/可观测性 | 非 MVP 必须 |
| T7 | IR Schema 版本策略 | 当前 v1 稳定 |

---

## 已知待确认项（known_gaps）

| # | 待确认项 | 状态 | 说明 |
|---|---------|------|------|
| G1 | 异步模型 | ✅ 已解决 | 回调注入模式（send 参数） |
| G2 | HTTP 客户端 | ✅ 已解决 | Host 负责，SDK 不持有 |
| G3 | 认证配置 | ✅ 已解决 | Host 在 send 回调中注入 |
| G4 | SDK 完整度 | 待验证 | 现有 API 需要测试验证 |
| G5 | 错误策略 | 柔性预留 | 当前 String 足够 |
| G6 | Schema 版本策略 | 推迟 | T7 范围 |
| G7 | 生产部署方案 | 推迟 | T5 范围 |
