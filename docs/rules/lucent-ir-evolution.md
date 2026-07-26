# Lucent IR 演进与字段归类规则

> 本文档规定 Lucent IR 的设计原则、字段归类标准和演进策略。
> 具体的类型定义和适配器契约见 [`docs/lux-ir-design.md`](../lux-ir-design.md)。

---

## 0. 设计目标与使用场景

Lucent IR 同时服务两个场景，优先级不可倒置：

1. **协议转换基础设施**：供中间站、网关、代理和兼容层通过 `Source -> Lucent -> Target` 转换请求、响应与流事件。硬门槛是**转换保真、显式能力边界和不静默丢失**。
2. **工作流与 Agent SDK**：供应用直接构造上下文、注册工具、消费生成、提交工具结果并判断下一步。目标是**稳定、任务导向、可组合、可发现且容易写对**。

场景一的正确性是场景二的前置条件。不得为了 SDK 表面简洁牺牲转换语义，也不得为了保留 Provider 原始形状把 SDK 核心退化为不透明 JSON。

---

## 1. 设计原则

1. **转换正确性优先** —— 精确、有损、不支持和无效输入必须可区分；不得把有损转换伪装成成功。
2. **SDK 面向任务而非字段表** —— 公共类型围绕 Agent/工作流状态转换设计，常用路径通过稳定构造器和 helper 使用。
3. **以「会话事件流」为骨干**，不以「消息数组」为骨干 —— `LucentConversationItem` 异质平级，自然承载所有 Item 模型。
4. **内容类型用代数和 + 元数据侧信道** —— 不强行统一各家不一致字段，给「不一致部分」留类型化侧信道。
5. **流式选 Anthropic 块生命周期作 canonical**，补齐四类缺失事件（Discard / Meta / Annotations / 错误结构化）。
6. **用量统计面向 reasoning 时代** —— 思考 token、缓存 token 一等公民。
7. **能力分级：标准化能力 / 厂商标识 / 不透明透传** —— 三层清晰，新增厂商按层归类。
8. **版本化治理** —— `schema_version: "v1"` 顶层声明，未来 breaking change 走 v2，不破坏已部署 WASM 调用方。

---

## 2. 字段归类五道门

一个字段应该放在 IR 的哪个位置？按以下五道门顺序判定：

### 第一道门：是否改变了对话/事件的"形状"？

> 当这个字段的值不同时，SDK 消费方处理 content / conversation 的逻辑是否必须不同？

```
是 → 核心类型候选（例：tool_use vs text, phase: commentary vs final_answer）
否 → 继续下一道门
```

### 第二道门：是否跨 Provider 具有稳定同构的控制语义？

> 多家厂商用不同字段名表达同一语义，语义足够稳定不会频繁变动？

```
是 → 可移植控制候入选（例：temperature, max_tokens）
否 → 继续下一道门
```

### 第三道门：是否转换过程中不能丢失，但语义尚未成熟？

> 该字段有一定的跨厂商意义，但当前只有一两家支持，或者语义还在演进？

```
是 → 类型化孵化区（经评审入 IR 但标记 experimental）
     或有序 Native（统一 key 名，不收任意 JSON）
否 → 继续下一道门
```

### 第四道门：是否仅控制特定 Provider 行为？

> 该字段语义绑定到特定厂商的能力，无跨厂商意义？

```
是 → 命名空间化请求扩展（extra Map，key 加 provider 前缀）
否 → 继续下一道门
```

### 第五道门：是否改变 HTTP、后台任务或轮询生命周期？

> 该字段控制的是调用方式（同步/异步/轮询）而不是生成行为本身？

```
是 → Transport 层（不在 IR 内）
```

### 示例判定

| 字段 | 形状改变 | 跨厂商 | 判定结果 |
|------|---------|--------|---------|
| `tool_use` vs `text` | ✅ 是 | ✅ 是 | **核心类型** |
| `phase: commentary\|final_answer` | ✅ 是 | ❌ Codex 独有 | **核心类型**（孵化区） |
| `thinking` block | ✅ 是 | ✅ 三家 | **核心类型** |
| `temperature` | ❌否 | ✅ 是 | **可移植控制** |
| `max_tokens` | ❌否 | ✅ 是 | **可移植控制** |
| `seed` | ❌否 | ❌ OpenAI 独有 | **extra** |
| `logprobs` | ❌否 | ❌ OpenAI 独有 | **extra** |
| `background` | ❌否 | ❌ 否，Transport | **Transport 层** |
| `store` | ❌否 | ❌ 否，Provider 行为 | **extra** |
| `parallel_tool_calls` | ❌否 | ⚠️ 有语义但不稳定 | **extra**（暂定） |
| `tool kind` (FileSearch vs Function) | ✅ 是 | ✅ 三家 | **核心类型** |
| `mediaResolution` | ❌否 | ❌ Gemini 独有 | **extra** |

---

## 3. 能力分级

新增厂商时按此三层归类能力：

| 层级 | 归宿 | 举例 |
|------|------|------|
| **标准化能力**（多家厂商共有） | 提升为 IR 一等字段 | `tool_calling` / `parallel_tool_calls` / `reasoning` / `structured_output` / `multimodal_input` |
| **厂商独有但语义清晰** | 类型化占位 | `LucentReasoningConfig.effort`（Anthropic/OpenAI/Gemini 都有推理配置，字段不同语义同构） |
| **完全私有**（无跨厂商语义） | `extra: Map[String, Json]` | `truncation` / `include` / `safetySettings` |

---

## 4. 转换契约

无论字段归属何处，适配器都必须明确给出以下四种结果之一，**不得通过忽略字段伪装成功**：

| 结果 | 含义 |
|------|------|
| `Exact` | 字段完全对等映射，无信息丢失 |
| `Degraded` | 字段被近似映射，部分语义丢失（例如结构化输出降级为 JSON 文本） |
| `Unsupported` | 字段不被目标协议支持，已舍弃 |
| `Invalid` | 字段格式错误或值非法 |

---

## 5. 向后兼容策略

| 变化类型 | 策略 |
|---------|------|
| 新增枚举变体 | 安全——已有 `match` 的 `_ =>` 兜底，Native 默认处理 |
| 新增 struct 可选字段 | 安全——`None` 缺省，旧 JSON 反序列化不崩溃 |
| 废弃字段 | 加 `@deprecated` 注释，v2 移除 |
| 重命名字段/类型 | Breaking——走 v2，旧 v1 数据保持可读 |
| 删除类型 | Breaking——走 v2 |

---

## 6. 字段升格流程

extra → IR 正式字段需要满足：

1. 至少 2 家主流 Provider 支持
2. 至少在实际项目中验证过一个完整迭代
3. 语义稳定（未在 3 个月内被厂商废弃或改名）
4. 经设计评审确认归类正确
