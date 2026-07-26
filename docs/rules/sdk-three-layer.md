# Prism SDK 三层架构设计

> 本文档定义 Prism SDK 面向不同层级开发者的分层设计策略。
> IR 设计原则见 [lucent-ir-evolution.md](./lucent-ir-evolution.md)，类型规范见 [lux-ir-design.md](../lux-ir-design.md)。

---

## 0. 核心理念

**IR 字段多少 ≠ SDK 用户负担。** 
用户负担取决于 SDK 表面 API 暴露了什么，而不是底层 IR 有多少字段。

Prism SDK 的设计目标是：

> 让每一层开发者只看到他需要的那一层抽象，不暴露下层细节。

---

## 1. 业内共识：三层架构

调研 LangChain、Vercel AI SDK、OpenAI Agents SDK、LangGraph 等框架后，行业已形成三层共识：

| 层级 | 名称 | 代表产品 | 用户群体 |
|------|------|---------|---------|
| **L1** | Agent Framework | LangChain Agent, Vercel AI SDK Core | 应用开发者 |
| **L2** | Agent Runtime / 循环控制 | LangGraph, Vercel WorkflowAgent | 框架作者 |
| **L3** | Agent Harness / 适配器 | Deep Agents, Codex, Claude Code | 系统集成者 |

---

## 2. 三层开发者的需求

### L1：应用开发者（Prism 的主要用户）

**角色：** 构建业务功能，不关心底层实现。

**他们写的是：**
```moonbit
// 一行搞定
let result = agent.run("总结这封邮件").await?

// 或者简单配置
let agent = Agent::new("助手")
  .model("gpt-4o")
  .tools([search, calc])
  .instructions("你是一个有用的助手")
```

**他们需要知道的事：**
- 注册工具（定义函数）
- 给指令（写系统消息）
- 发消息、拿结果
- 切换 provider（改一个参数）

**他们不需要知道的事（由 SDK 内部消化）：**
- ❌ IR 类型（`LucentRequest`, `LucentContent`, `LucentOptions` 等）
- ❌ 协议差异（`messages[]` vs `contents[]` vs `input[]`）
- ❌ 提供商特有字段（`phase`, `store`, `logprobs`, `thinking_level` 等）
- ❌ 系统指令位置（各家 `system` / `instructions` / `systemInstruction` 字段不同）

---

### L2：框架作者（Prism 的次级用户）

**角色：** 构建 Agent 循环引擎、工作流编排框架、中间件系统。

**他们写的是：**
```moonbit
fn my_agent_loop(prism: Prism, ctx: Context) {
  loop {
    let stream = prism.stream(ctx).await?
    for event in stream {
      match event {
        TextDelta(s)    => collect(s)
        ToolCall(tc)    => { execute(tc); ctx.add_result(tc.id, result) }
        Thinking(_)     => skip  // 可忽略
        Finish(r)       => break
      }
    }
  }
}
```

**他们需要感知的语义单位（共 5 种）：**

| 事件类型 | 含义 | 框架作者的处理 |
|---------|------|--------------|
| `Text` / `TextDelta` | 模型输出文本 | 追加到当前消息，流式展示 |
| `ToolCall` | 模型调用工具 | 中断循环，执行工具，结果注入 context |
| `ToolResult` | 工具执行结果 | 追加到 context，继续循环 |
| `Thinking` | 模型推理过程 | 可展示 UI 或忽略，不影响 Agent 状态 |
| `Finish` | 本轮结束 | 检查是否需要继续，决定 break/continue |

这 5 种事件是 Agent 循环的**全部语义单元**。框架作者不需要知道 `phase`、`store`、`logprobs`、`thinking_level`——这些不改变事件流形状。

**他们需要的能力：**
- 上下文管理（消息队列 + 工具结果注入）
- 工具注册与执行
- Provider 切换
- 流式事件循环

**他们不需要的能力：**
- ❌ 构造厂商 JSON（SDK 做）
- ❌ 解析厂商 JSON（SDK 做）
- ❌ 管理 provider 特有字段（SDK 做）

---

### L3：系统集成者（最小众的用户）

**角色：** 将现有 Agent Harness（Codex、Claude Code 等）接入 Prism 生态。

**他们需要：**
```moonbit
// Vercel AI SDK 的做法参考
let harness = HarnessAgent::from("codex", {
  sandbox: my_sandbox,
  instructions: "你是 senior engineer",
  tools: [my_custom_tool],
})
let result = harness.run(task).await?
```

**他们需要感知 Prism 的：**
- 适配器层（协议翻译 6 函数）
- `ProviderCapability`（能力自省）
- 事件流类型（5 种事件）

---

## 3. Prism SDK 建议的三层 API

### 第一层：零配置模式

```moonbit
// 面向 L1 应用开发者
let prism = Prism::new()

// 最简单的对话
let resp = prism.complete("Hello").await?

// 带工具
let resp = prism.complete(
  "查天气",
  tools: [weather_tool],
  model: "gpt-4o",
).await?

// 切换 provider：改一行
let resp = prism.complete(
  "查天气",
  provider: "anthropic",  // ← 只改这里
  model: "claude-sonnet-4",
).await?
```

**不暴露：** IR 类型、协议差异、厂商特有字段。

### 第二层：Agent 循环模式

```moonbit
// 面向 L2 框架作者
let prism = Prism::new().provider("openai")

let ctx = Context::new()
  .system("你是一个助手")
  .message(User, "帮我查天气")
  .tools([weather_tool])

let stream = prism.stream(ctx).await?
for event in stream {
  match event {
    TextDelta(s)  => ui.append(s)
    ToolCall(tc)  => ctx.add_result(tc.id, execute(tc))
    Thinking(t)   => ui.show_thinking(t)
    Finish(r)     => break
  }
}
```

**暴露：** 5 种事件类型、Context 管理、工具注册。
**不暴露：** IR 字段、协议 JSON 格式。

### 第三层：精细控制模式

```moonbit
// 面向 L2/L3 需要精细控制的用户
let caps = prism.capability("anthropic")
if caps.tool_calling {
  // 确认支持工具调用后再注册
}

// 厂商特有参数通过命名参数传入，SDK 内部塞入 extras
let resp = prism.complete("Hello",
  provider: "openai",
  model: "gpt-4o",
  temperature: 0.7,
  max_tokens: 4096,
  // 不改变对话形状的参数走 extras
  extras: { store: false, logprobs: true },
).await?
```

**暴露：** `ProviderCapability`、命名参数形式的厂商参数。
**不暴露：** IR 结构体、协议编解码细节。

---

## 4. 字段可见性规则

| 字段层级 | 示例 | L1 可见 | L2 可见 | L3 可见 |
|---------|------|:------:|:------:|:------:|
| 核心事件 | `Text`, `ToolCall`, `Thinking`, `Finish` | ❌ | ✅ | ✅ |
| 上下文管理 | `Context`, `Message`, `Tool` | ✅ | ✅ | ✅ |
| 标准生成参数 | `temperature`, `max_tokens`, `model`, `provider` | ✅ | ✅ | ✅ |
| 厂商特有参数 | `store`, `logprobs`, `thinking_level` | ❌（SDK 内部传 `extras`） | ❌ | ✅（命名参数） |
| IR 类型 | `LucentRequest`, `LucentContent`, `LucentOptions` | ❌ | ❌ | ❌ |
| 适配器层 | `openai_responses_to_lux_request` | ❌ | ❌ | ✅（仅 Harness 集成者） |

---

## 5. 减负的判定标准

判断 SDK 是否真正减负，不看 IR 有多少字段，而看：

> **开发者从"我只用一家"到"我加第二家"，代码量增长了多少？**

```
理想情况：
  1 家：10 行代码
  2 家：10 行代码（改 provider: 参数）
  3 家：10 行代码（再改 provider: 参数）

反面情况：
  1 家：10 行代码（直接调厂商 SDK）
  2 家：25 行代码（多学一套 API）
  3 家：45 行代码（再学一套，再写一套格式转换）
```

Prism 的目标是实现理想情况。开发者从 1 家切换到 N 家的成本趋近于零。

---

## 6. IR 与 SDK 的分工

```
                   ┌─────────────────────────────┐
                   │     SDK 表层 API              │
                   │  prism.complete(), .stream()  │
                   │  Context, Tool, Event          │
                   │  (开发者看到的全部)              │
                   └──────────┬──────────────────┘
                              │ 内部转换
                   ┌──────────▼──────────────────┐
                   │     IR 层 (Lucent*)           │
                   │  厂商无关的中间表示             │
                   │  (开发者从不直接接触)            │
                   └──────────┬──────────────────┘
                              │ 适配器翻译
          ┌───────────────────┼───────────────────┐
          ▼                   ▼                   ▼
    OpenAI JSON         Anthropic JSON        Gemini JSON
```

**IR 的完整度保证"能适配一切"；SDK 的简洁度保证"用户不感知"。** 两者不矛盾。
