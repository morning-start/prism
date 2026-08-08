# 当前代码与实际缺口审计

> 基于三层原则、五道门分类标准、"普遍存在"标准检查当前代码库。
> 日期：2026-07-26

---

## 审计结果：3 个缺口，但都非阻塞

### 🔴 缺口 1：`LucentOptions.seed` 在错误的位置

**问题：** `seed` 仅 OpenAI Chat 支持（Responses 明确不支持）。按五道门判定，应走 `extras`。但当前是 `LucentOptions` 的一等字段。

**影响：** 低。不会导致功能错误，只是语义归类不精确。

**建议：** 加 `@deprecated` 注释标记，v2 移除。

```moonbit
pub struct LucentOptions {
  ...
  @deprecated("仅 OpenAI Chat 使用，后续移入 extras")
  seed : Int?
  ...
}
```

### ✅ 缺口 2：`store` 和 `extras` 未接入适配器编解码 — **已解决**（Phase 2）

> **状态更新**（2026-08-08）：`store`/`extras` 已接入 4 基础适配器
> （OpenAI 原生支持，Anthropic/Gemini `Unsupported` 诊断 + extras 往返）。
> 详见 `docs/status.md` Phase 2。

**问题：** `LucentOptions.store` 和 `LucentOptions.extras` 已在 IR 结构体中，但没有任何适配器：

- 从协议 JSON 中 **读取** `store` 并存入 `LucentOptions.store`
- 从 `LucentOptions.store` **写出** 到协议 JSON
- 从协议 JSON 中 **读取** `extras` 中的参数并存入 `LucentOptions.extras`
- 从 `LucentOptions.extras` **写出** 到协议 JSON

只是存储了但没连通。

**影响：** 低。`store` 和 `extras` 是为 SDK 表面 API 准备的——SDK 用户通过命名参数传入，SDK 内部构造 IR。在 SDK 表面 API 建成之前，适配器不读写它们不影响功能。

**建议：** 等 SDK 表面 API 实现时一并接入。适配器层的 `parse_options()` 函数届时批量添加。

### 🔴 缺口 3：`LucentAgentAction` 占位未实现

**问题：** `LucentAgentAction` 结构体已定义，但没有任何适配器使用它。`computer_call`、`browser_action` 等 Agent 动作类型没有实现在任何适配器中。

**影响：** 中。L2 框架作者如果需要 `ComputerUse` 类型的工具，当前 IR 无法承载。但当前协议的 `computer_use` 工具已经通过 `LucentToolKind::ComputerUse` 支持了工具定义层面——不支持的只是响应中的 Agent 动作记录。

**建议：** v2 实现。当前覆盖工具定义足够。

---

## 总结

| # | 缺口 | 优先级 | 需要立即修？ |
|---|------|--------|:----------:|
| 1 | `seed` 在错误位置 | 低 | ❌ 标记 deprecated 即可 |
| 2 | `store`/`extras` 未连通 | ~~低~~ | ✅ Phase 2 已解决 |
| 3 | AgentAction 未实现 | 中 | ❌ v2 范围 |
| 4 | `wasm_sdk_decode_sse` / `wasm_sdk_capability` 无诊断源 | 低 | ❌ 形状已对齐（恒 `diagnostics: []`），待 SDK 补 `*_with_diagnostics` |

**当前 IR 可以冻结。** 前三个缺口都不阻塞功能，也不会影响未来 SDK 表面 API 的设计。建议在启动 SDK 表层 API 开发时同步处理。

> **缺口 4（2026-08-02 Phase 3 收尾记录）：** Task 2 将 5 个 `wasm_sdk_*` 统一为
> 信封输出。其中 `wasm_sdk_encode_request` / `wasm_sdk_decode_response` 已接入
> `encode_request_with_diagnostics` / `decode_response_with_diagnostics`
> （真实 schema 校验诊断）；`wasm_sdk_encode_stream` / `wasm_sdk_decode_sse` /
> `wasm_sdk_capability` 无诊断源，输出 `diagnostics: []` 保持形状一致。待 SDK
> 补对应 `*_with_diagnostics` 后接入。
