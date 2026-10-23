# finish_reason 枚举契约的设计（CR-005 重新设计）

> 2026-10-24 · 取代 `src/provider/meta/finish.mbt` 的第一版实现
> 关联：[`cr/CR-005-stop-sequence-carrier.md`](cr/CR-005-stop-sequence-carrier.md)、
> [`fidelity-matrix.md`](fidelity-matrix.md) §3.14

## 1. 第一版错在哪

第一版按 **IR 枚举** match，给每个变体写出目标值，`Native(s)` 无条件透传。
八个建模值确实修好了，但留下一个**结构性漏洞**，实测可复现：

```
messages 源 stop_reason="pause_turn"（Anthropic 合法值）
  → IR Native("pause_turn")
  → openai 出站 "finish_reason":"pause_turn"   ← OpenAI 非法枚举
```

根因不是「映射表少了一行」，而是**裁决方向错了**：

> 合法性是**目标槽位的属性**，不是 IR 值的属性。

一个字符串是否合法，只取决于它要去的那个协议的封闭枚举，与 IR 是否认识它
无关。按 IR 枚举分支再对 `Native` 开个透传口子，**天然不可能封闭** —— 每漏
一个 `Native` 分支就又是一条溢出路径。

## 2. 正确的模型

```text
每个目标协议有一个封闭合法值集合 legal(T)      ← 官方 schema 决定
每个 IR 值先做语义映射 candidate(fr)           ← 建模值才有意义
输出 = arbitrate(candidate, legal(T), fallback)
```

`arbitrate` 只有两条出路：

| 条件 | 动作 |
|---|---|
| `candidate ∈ legal(T)` | 原样输出，`Exact` |
| `candidate ∉ legal(T)` | 收敛到 `fallback`（∈ legal(T)），打诊断 |

这条规则**统一处理**建模值与 `Native`，不需要为 `Native` 写特例。同时它带来
一个反直觉但正确的性质：

> 同一个 `Native("pause_turn")`，在 messages 目标是 `Exact`，在 openai 目标
> 必须收敛。**目标决定合法性，不是值本身。**

实测验证（三种目标 × 七种 Native 值，7×3 全部落在各自合法集合内）：

| Native 值 | messages | openai | gemini |
|---|---|---|---|
| `pause_turn` | ✅ 透传 | ✅→`stop` | ✅→`OTHER` |
| `model_context_window_exceeded` | ✅ 透传 | ✅→`stop` | ✅→`OTHER` |
| `LANGUAGE` | ✅→`end_turn` | ✅→`stop` | ✅ 透传 |
| `BLOCKLIST` | ✅→`end_turn` | ✅→`stop` | ✅ 透传 |
| `safety` | ✅→`end_turn` | ✅→`stop` | ✅→`OTHER` |
| `nft` | ✅→`end_turn` | ✅→`stop` | ✅→`OTHER` |

## 3. 一个极易写错的坑：诊断判据

**「值合法」≠「无信息损失」。** 这是重新设计时踩到的第二个坑。

`responses` 目标里 `Safety → "failed"`：`failed` **是合法值**，所以
`arbitrate` 返回 `degraded = false`，只按这个标志判断就**不会报警**。但 IR 的
`Safety`（安全拦截）和 `Error`（执行失败）语义完全不同，共压成 `failed`
是有损的。

因此诊断有两个来源：

1. **值不合法**（`arbitrate.degraded`）→ 必须报；
2. **值合法但语义共压**（`Safety`/`Recitation`/`MalformedToolCall` → `failed`）
   → 也必须报。

第一版就是漏了第 2 类，导致 responses 的 `Safety` 静默变成 `failed`。

> 对照：messages / openai 的对应候选是 `"safety"` / `"recitation"` 这种
> **本就不在合法集合内**的字符串，所以 `degraded = true` 天然会报。只有
> responses 存在「合法但共压」的情形 —— 这是目标协议的事实差异，不是设计
> 不一致。

## 4. 各目标的映射与依据

### messages（Anthropic `stop_reason`）

合法集合（7）：`end_turn` / `max_tokens` / `stop_sequence` / `tool_use` /
`refusal` / `pause_turn` / `model_context_window_exceeded`

| IR | 候选 | 结果 |
|---|---|---|
| `Stop` | `end_turn` | Exact |
| `Length` | `max_tokens` | Exact |
| `ToolCalls` | `tool_use` | Exact（**不是 `tool_calls`**） |
| `ContentFilter` | `refusal` | Exact |
| `Safety`/`Recitation`/`MalformedToolCall`/`Error` | 自身拼写 | 收敛 `end_turn` + 诊断 |
| `Native(s)` | `s` | 在集合内透传，否则收敛 + 诊断 |

### openai（Chat `finish_reason`）

合法集合（5）：`stop` / `length` / `tool_calls` / `content_filter` /
`function_call`（vendored OpenAPI）

| IR | 候选 | 结果 |
|---|---|---|
| `Stop` / `Length` / `ToolCalls` / `ContentFilter` | 对应值 | Exact |
| 其余建模值 | 自身拼写 | 收敛 `stop` + 诊断 |
| `Native(s)` | `s` | 在集合内透传，否则收敛 + 诊断 |

### gemini（`finishReason`，全大写）

合法集合（16，含 `FINISH_REASON_UNSPECIFIED` / `STOP` / `MAX_TOKENS` /
`SAFETY` / `RECITATION` / `LANGUAGE` / `OTHER` / `BLOCKLIST` /
`PROHIBITED_CONTENT` / `SPII` / `MALFORMED_FUNCTION_CALL` / `IMAGE_SAFETY` /
`UNEXPECTED_TOOL_CALL` / `TOO_MANY_TOOL_CALLS` / `MALFORMED_RESPONSE` /
`MISSING_THOUGHT_SIGNATURE`）

| IR | 候选 | 结果 |
|---|---|---|
| `Stop` / `Length` / `Safety` / `Recitation` / `MalformedToolCall` / `Error` | 对应值 | Exact |
| `ToolCalls` | `STOP` | **语义对等**（Gemini 无工具调用结束原因，由 `functionCall` part 表达）→ 不诊断 |
| `ContentFilter` | `SAFETY` | **更改**：此前收敛到 `STOP`，把「被拦截」伪装成「正常结束」；`SAFETY` 是 Gemini 侧内容拦截的真实语义载体 |
| `Native(s)` | `s` | 在集合内透传（`LANGUAGE`/`BLOCKLIST`/`SPII` 等是 Gemini 自己的值），否则收敛 `OTHER` + 诊断 |

### responses（`status`）

合法集合（6）：`completed` / `failed` / `in_progress` / `cancelled` /
`queued` / `incomplete`（vendored OpenAPI `Response.status`）

`incomplete_details.reason` 合法集合（4）：`max_output_tokens` /
`max_messages` / `content_filter` / `steered`

| IR | status | incomplete_details.reason | 诊断 |
|---|---|---|---|
| `Stop` / `ToolCalls` | `completed` | — | 无（语义对等） |
| `Length` | `incomplete` | `max_output_tokens` | 无（对等） |
| `ContentFilter` | `incomplete` | `content_filter` | 无（对等） |
| `Error` | `failed` | — | 无（对等） |
| `Safety` / `Recitation` / `MalformedToolCall` | `failed` | — | **有**（共压损失） |
| `Native(s)` | `s` 若合法，否则 `completed` | — | 不合法时有 |

## 5. 这些约定是否有意义 —— 逐条审视

我重新检验了仓库里与本主题相关的几条既有约定，结论如下。

### 5.1 「`extra` / `provider_payload` / `Native` 是无损透传的安全阀」—— ✅ 有意义，但需限定

**有意义的理由**：厂商私有字段/取值如果不透传，跨端就是硬丢失，且无法预测
厂商未来新增什么。放行的失败模式（目标收到一个它不认识的键）轻于误丢。

**必须限定的部分**：透传**只对开放槽位成立**。`finish_reason` / `status` /
`stop_reason` 是**封闭枚举**（官方 schema 明确列举），在这些槽位里「透传未知
值」不是无损，而是**制造非法报文**。第一版把两者混为一谈，`Native(s) => s`
无条件放行，于是 `pause_turn` 溢进了 openai。

> **修正后的约定**：扩展通道（开放槽位）透传；枚举槽位先过目标白名单。
> 两类槽位必须分开对待，判据不是「值来自哪」，而是「目标槽位是否封闭」。

### 5.2 「流式与非流式必须解出同一 IR 值」—— ✅ 有意义，且是本次最强的检验

这条约定直接命中了缺陷 B：`stop_sequence` 流式 → `Native("stop_sequence")`，
非流式 → `Stop`。同一语义两个入口两个结果，任何依赖该不变量的下游都会出错。

**进一步推论**：既然解码侧要求两路一致，**编码侧也必须两路共用同一实现**。
第一版的收敛器虽然抽到了 `meta`，但 responses 的非流式还留着一份独立 match，
于是又漂移了（非流式对 `Native` 无条件诊断，流式按白名单裁决）。现已全部
统一。

> **加强后的约定**：不只是「解出的 IR 值相同」，而是「**同一协议的非流式与
> 流式编码路径必须调用同一收敛函数**」。测试应断言两条路径对同一输入的输出
> 形态一致。

### 5.3 「收敛必须留诊断」—— ✅ 有意义，但判据要修正

原表述隐含「发生收敛才有诊断」。重新设计后精确化：

> 诊断的判据是**信息损失**，不是「值被改动」。
> - 值被改动且信息损失 → 诊断（如 `Safety → failed`）
> - 值被改动但语义对等 → **不**诊断（如 `ToolCalls → STOP`、`Stop → end_turn`）
> - 值未被改动但被共压 → 诊断（如三个 IR 原因共压 `failed`）

第三类是第一版完全遗漏的。没有这条精确化，「必须留诊断」会被实现成「只要
没触发白名单拒绝就不报」，从而放走真实损失。

### 5.4 「诊断键用目标协议的真实字段名」—— ⚠️ 此前不一致，已统一

历史实现里，messages 的诊断键写作 `choices.finish_reason`，但该协议字段叫
`stop_reason`。诊断键与真实字段名不符会让使用者按文档去找却找不到。

现统一为 `目标协议字段名`：`choices.stop_reason` / `choices.finish_reason` /
`candidates.finishReason` / `choices.status`。测试按此断言。

### 5.5 `LucentFinishReason` 的 8 个建模值是否够用 —— ❌ 不够，有真实损失

实测往返暴露了两处**IR 建模粒度不足**导致的信息丢失（不在本次修复范围，
记录为技术债）：

1. **`stop_sequence` 命中值**：messages → IR → messages 得 `null`
   （`stop_sequence` 字段无 IR 载体，CR-005 缺陷 A，待决策）。
2. **`function_call` vs `tool_calls`**（**本次新发现**）：OpenAI 的这两个值
   是合法枚举里的**两个不同项**，但 IR 都映射到 `ToolCalls`，回程一律输出
   `tool_calls`。即 OpenAI → IR → OpenAI 无法保住 `function_call`。

第 2 条此前无人记录。它的修复需要 IR 增变体或加子类型字段，属破坏性/
新变体变更，须走治理 —— 与缺陷 A 一并等决策。

## 6. 不变量（实现保证 + 测试锁定）

1. 任何出站 `finish_reason` / `stop_reason` / `finishReason` / `status`
   **一定落在目标合法集合内**（`arbitrate` 是唯一出口）。
2. `Native(s)` 在目标合法时**不被改动**（无损透传），非法时**一定被收敛**。
3. 信息损失**一定有 Unsupported 诊断**，键名为目标真实字段名。
4. 同一 IR 值在**同一协议的非流式与流式**路径产出相同枚举值。

回归：`src/sdk/test/finish_reason_contract_test.mbt`。
三处反向验证（回退 `arbitrate` 白名单 / 回退流式收敛 / 回退 `from_string`）
均确认测试会失败。
