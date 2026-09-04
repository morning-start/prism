# Lucent IR 演进治理

> 适用范围：任何修改 Lucent IR 字段、枚举变体、tool model、stream event、
> capability、request extension 或 response payload 的变更。
> 来源：AGENTS.md "Lucent IR evolution" 节 + field classification 规则。

## 核心规则

### 1. 变更前必读

修改任何 IR 元素之前，必须先阅读此文档和 `docs/lux-ir-design.md`，理解
当前契约边界后再动笔。

### 2. 影响面声明

每条提案 MUST 声明影响范围：

| 影响面 | 说明 |
|--------|------|
| **协议转换** | 是否有 provider → IR 或 IR → provider 的路径受改动影响 |
| **SDK/Agent 消费** | `LucentRequest` / `LucentResponse` / `LucentStreamEvent` 的下游消费者是否变更 |
| **两者兼有** | 同时影响上下两条链路 |

### 3. 保真度边界是硬约束

| 等级 | 含义 | 能否降级 |
|------|------|----------|
| `Exact` | 字段完全对等映射，无信息丢失 | ❌ 不允许 |
| `Degraded` | 字段被近似映射，部分语义丢失 | ✅ 允许（需打诊断） |
| `Unsupported` | 字段不被目标协议支持，已舍弃 | ✅ 允许（需打诊断） |
| `Invalid` | 字段格式错误或值非法 | ✅ 允许（Err 返回） |

SDK 易用性（ergonomics）排在保真度之后——能 Exact 就别 Degraded。

### 4. 标准字段 vs 扩展字段

| 分类 | 定义位置 | 约束 |
|------|----------|------|
| **Standard** | `docs/lux-ir-design.md` + `schemas/lux-ir-v1.json` | 必需/可选状态固定，所有 provider 必须支持 |
| **Extension** | 各 adapter 或 `extra`/`Native`/`provider_payload` | 必须可选（`T?` 或空默认 map），缺失时不报错 |

扩展字段**反序列化失败必须是软失败**——未知扩展数据优先保留在
`extra` / `provider_payload` / diagnostics 中，宁可保留不可知字节也不抛错。

### 5. 破坏性变更判定

以下情况视为**破坏性变更**，必须走此治理流程：

- 改变标准字段的 `required` / `optional` 状态
- 新增必选标准字段
- 重命名标准字段或变更类型
- 移除现有枚举变体（即使标记 deprecated）
- 修改 stream event 的载荷结构

### 6. 非破坏性变更

以下变更不需要完整治理，但仍需在提案中声明：

- 新增可选标准字段（`T?` 类型，默认 null）
- 新增枚举变体（向后兼容）
- 扩展 Extension 字段取值空间
- 文档/注释更新

## 提案模板

```markdown
### IR 变更提案：<简短标题>

- **影响面**：[协议转换 / SDK消费 / 两者]
- **变更类型**：[破坏性 / 非破坏性]
- **保真度预期**：[Exact / Degraded / Unsupported]
- **涉及字段/类型**：
  - `<field/type>`：`<当前类型>` → `<新类型>`
- **provider 适配影响**：
  - `openai`：...
  - `messages`：...
  - `responses`：...
  - `gemini`：...
- **迁移策略**（破坏性变更必填）：
  - ...
```

## 与其他文档的关系

- `docs/lux-ir-design.md` — 正式 IR 类型规范，本治理规则 governs 它
- `AGENTS.md` — 高层流程入口，引用本文件作为详细规则
- `schemas/lux-ir-v1.json` — JSON Schema 版本化契约（由 design.md 生成）
