# Phase 2 SDK 职责收敛实现计划（2026-08-02）

> 来源：`docs/plans/2026-08-01-project-roadmap.md` Phase 2 + `docs/rules/audit-gaps.md`（缺口 1、2）+ `docs/report/architecture-audit-2026-07-28.md` P2。
> 决策：D2 = SDK 定位为纯编解码 façade（已确认），`api_key`/`base_url` 直接移除（项目未上线，沿用 D1 clean cutover 精神）。
> 目标：SDK 无死字段；`store`/`extras` 有往返测试；`Thinking` 事件语义正确。

## 调研结论（2026-08-02 实测）

| 问题 | 现状 | 处置 |
|------|------|------|
| `Prism.api_key`/`base_url` 死字段 | `sdk/prism.mbt:46-52` 字段 + `with_api_key`/`with_base_url`（67-75）存在，仅测试（`sdk_test.mbt:22-42`）与文档（README 等）引用 | **移除**（Task 1） |
| `store`/`extras` 未连通 | `LucentOptions.store/extras` 已在 IR（`lux/lux.mbt:190-191`），`context_to_lux_request` 已传入（`sdk/context.mbt:161-173`），但 4 个基础适配器均未读写（`LucentOptions::new(...)` 末两位恒为 `None, None`） | **接入 4 基础适配器**（Task 2） |
| `ThinkingDelta` 伪装成 `TextDelta` | `sdk/prism.mbt:330-331` 已正确映射为 `Thinking`（旧 audit 行号过时）；但 `lux/stream.mbt:361` 累加器把 ThinkingDelta 拼入 `block_texts`（块类型非 Thinking 时污染文本）；Gemini 流式 thought 标记静默丢弃（`gemini.mbt:953-954`），非流式 thought 同时发 Text + Thinking（`gemini.mbt:36-45`） | **累加器/适配器修正**（Task 3） |
| `seed` 位置错误 | `lux/lux.mbt:187` 已有 `/// @deprecated` 注释（注释形式已满足）；MoonBit `#deprecated` 属性不支持 struct 字段，无法升级 | **验证 + 文档确认**（Task 4） |

**子协议适配器（codex/azure/vertex）** 均为薄包装委托基础适配器（`azure.mbt:13` 委托 responses、`vertex.mbt:9` 委托 gemini 等），基础适配器改完自动透传，无需改动（codex 的 `codex_to_lux_request` 自实现 phase 提取，但调用主包解码逻辑）。

## 文件结构规划

```
sdk/
├── prism.mbt                 # Modify: 移除 api_key/base_url 字段、new()、with_api_key/with_base_url
├── sdk_test.mbt              # Modify: 删除/改写死字段相关测试
lux/
├── stream.mbt                # Modify: ThinkingDelta 独立累加（不污染 block_texts）+ 非 Thinking 块诊断
provider/openai_chat/chat.mbt        # Modify: 请求解码/编码接入 store/extras
provider/openai_responses/responses.mbt  # Modify: 同上
provider/anthropic/anthropic.mbt    # Modify: 同上（store 不支持 → Unsupported 诊断）
provider/gemini/gemini.mbt          # Modify: 同上 + thought 流式不静默丢弃 + 非流式不伪装 Text
provider/gemini/gemini_wbtest.mbt   # Test: thought 语义测试
README.md / README.mbt.md / docs/sdk-usage.md  # Modify: 移除 with_api_key/with_base_url 用法
```

**测试数据原则**（项目约定）：所有进入 `from_json` 的 JSON 由 IR 构造器 `to_json().stringify()` 或适配器编码产生，不手写。

---

## Task 1: 移除 Prism api_key/base_url 死字段

**文件：**
- Modify: `sdk/prism.mbt`（删除字段、`new()` 初始化、`with_api_key`/`with_base_url` 方法）
- Test: `sdk/sdk_test.mbt`（删除/改写 `Prism::with_api_key`、`Prism::with_base_url`、chained construction 中含 api_key/base_url 的断言）
- Docs: `README.md`、`README.mbt.md`、`docs/sdk-usage.md`（移除 `.with_api_key(...)`/`.with_base_url(...)` 用法）

**理由：** D2 已确认 SDK 是纯编解码 façade；认证/端点由 Host/Transport 层负责（Phase 3 引入 `TransportConfig` 承载）。项目未上线，直接移除，不留兼容层（与 D1 一致）。

#### Step 1: 写会失败的测试（sdk_test.mbt 改写）

```moonbit
///|
test "Prism::new - default provider is openai" {
  let p = Prism::new()
  assert_eq(p.provider, "openai")
}

///|
test "Prism::with_provider - chained construction" {
  let p = Prism::new().with_provider("gemini")
  assert_eq(p.provider, "gemini")
}
```
（删除 `api_key`/`base_url` 断言与 `with_api_key`/`with_base_url` 两个测试，chained test 去掉这两项。）

- [ ] **Step 2: 确认测试失败**（预期 FAIL：字段不存在，编译错误）
- [ ] **Step 3: 实现**：`sdk/prism.mbt` 删除 `api_key`/`base_url` 字段（46-52 行附近）、`Prism::new()` 中对应初始化（56-57）、`with_api_key`（67-75）、`with_base_url`（73-75）；同步改 `sdk/pkg.generated.mbti`（最后 `moon info` 统一更新）。
- [ ] **Step 4: 确认测试通过**（预期 PASS）
- [ ] **Step 5: 全量验证** `moon fmt --check && moon check --warn-list +73 && moon test`
- [ ] **Step 6: 文档同步**：`README.md`/`README.mbt.md`/`docs/sdk-usage.md` 移除 `.with_api_key(...)` 用法（保留 `with_provider`）。

---

## Task 2a: store/extras 接入 OpenAI Chat + Responses（原生支持 store）

**文件：**
- Modify: `provider/openai_chat/chat.mbt`
- Modify: `provider/openai_responses/responses.mbt`
- Test: `provider/openai_chat/chat_wbtest.mbt`、`provider/openai_responses/responses_wbtest.mbt`

**现状：**
- Chat 解码 `chat.mbt:290-302`：`LucentOptions::new(...)` 末两位 `None, None`（store, extras）；编码 `chat.mbt:600-654` 未写 store/extras。
- Responses 解码 `responses.mbt:249-261`：同；编码未写。
- 两协议原生支持 `store: bool` 顶层字段；`extras: Map[String, Json]` 应合并进请求 JSON 顶层。

**接口（产出）：**
```moonbit
// 请求解码（openai_chat_to_lux_request / openai_responses_to_lux_request）
// 读取: store = field_bool(jv, "store")；extras = collect_extra_fields(jv, 已知字段集合)
// 请求编码（lux_request_to_openai_chat / lux_request_to_openai_responses）
// 写出: opts.store is Some(b) => "\"store\":<b>"；opts.extras is Some(m) => 每键值对 "\"<k>\":<v.stringify()>"
```

#### Step 1: 写会失败的测试（wbtest 追加，用 IR 构造器产输入）

```moonbit
///|
test "chat store/extras round-trip" {
  let opts = @lux.LucentOptions::default().with_store(Some(true)).with_extras(Some({
    "extra_field": @json.String("v1"),
  }))
  let req = @lux.LucentRequest::new(
    "gpt-4o", None,
    [@lux.LucentConversationItem::message(@lux.LucentMessage::new(@lux.User, [@lux.LucentContent::text("Hi")]))],
    None, None, opts, None, None, None, None,
  )
  match @openai_chat.lux_request_to_openai_chat(req) {
    Ok(cr) => {
      assert_true(cr.value().contains("\"store\":true"))
      assert_true(cr.value().contains("\"extra_field\":\"v1\""))
      match @openai_chat.openai_chat_to_lux_request(cr.value()) {
        Ok(cr2) => assert_eq(cr2.value().options.store, Some(true))
        Err(e) => fail("decode: \(e)")
      }
    }
    Err(e) => fail("encode: \(e)")
  }
}
```

- [ ] **Step 2: 确认测试失败**（预期 FAIL：编码不含 store/extras，解码 store 为 None）
- [ ] **Step 3: 实现**：
  - 解码：`let store = @internal.field_bool(jv, "store")`；extras 收集顶层未被已知字段消费的键值（实现 `fn collect_extra_fields(jv : Json, known : Array[String]) -> Map[String, Json]?`，可放 `provider/internal` 或各包内 helper；已知字段集合 = 该协议解码函数实际读取的顶层字段名）。
  - 编码：`match opts.store { Some(b) => parts.push("\"store\":" + b.to_string()) ... }`；`match opts.extras { Some(m) => for (k, v) in m { parts.push("\"" + k + "\":" + v.stringify()) } ... }`。
- [ ] **Step 4: 确认测试通过**（预期 PASS）
- [ ] **Step 5: 全量验证** `moon fmt --check && moon check --warn-list +73 && moon test`

---

## Task 2b: store/extras 接入 Anthropic + Gemini（store 不支持 → Unsupported 诊断）

**文件：**
- Modify: `provider/anthropic/anthropic.mbt`
- Modify: `provider/gemini/gemini.mbt`
- Test: `provider/anthropic/anthropic_wbtest.mbt`、`provider/gemini/gemini_wbtest.mbt`

**现状：**
- Anthropic 解码 `anthropic.mbt:324-336`、编码 `anthropic.mbt:655+` 未写 store/extras。
- Gemini 解码 `gemini.mbt:326-355`（generationConfig 内）、编码 `gemini.mbt:510+` 未写。
- 两协议**无原生 store**：请求含 `store` 时编码应产生 `Unsupported` 诊断（复用 Phase 1 `ConversionResult.with_diagnostic`）；`extras` 仍合并进请求 JSON 顶层（Anthropic 顶层 / Gemini `generationConfig` 内）。

#### Step 1: 写会失败的测试（wbtest 追加）

```moonbit
///|
test "anthropic store unsupported diagnostic" {
  let opts = @lux.LucentOptions::default().with_store(Some(true))
  let req = @lux.LucentRequest::new(
    "claude-4", None,
    [@lux.LucentConversationItem::message(@lux.LucentMessage::new(@lux.User, [@lux.LucentContent::text("Hi")]))],
    None, None, opts, None, None, None, None,
  )
  match @anthropic.lux_request_to_anthropic(req) {
    Ok(cr) => {
      assert_true(cr.diagnostics().length() > 0)
      // 且编码 JSON 不含 "store"
      assert_false(cr.value().contains("\"store\""))
    }
    Err(e) => fail("encode: \(e)")
  }
}
```
（Gemini 同构：`@gemini.lux_request_to_gemini`。）

- [ ] **Step 2: 确认测试失败**（预期 FAIL：当前无诊断）
- [ ] **Step 3: 实现**：
  - 解码：`store` 字段两协议均无 → 保持 `None`；extras 收集（同 Task 2a helper）。
  - 编码：`match opts.store { Some(_) => result = result.with_diagnostic(ConversionDiagnostic::new("options.store", Unsupported, Some("provider has no store field"))) ... }`；`extras` 合并（Anthropic 顶层 parts / Gemini generationConfig parts）。
- [ ] **Step 4: 确认测试通过**（预期 PASS）
- [ ] **Step 5: 全量验证** `moon fmt --check && moon check --warn-list +73 && moon test`

---

## Task 3: ThinkingDelta 事件语义修正（不伪装成 TextDelta）

**文件：**
- Modify: `lux/stream.mbt`（累加器）
- Modify: `provider/gemini/gemini.mbt`（thought 流式 + 非流式）
- Test: `lux/lux_wbtest.mbt`（或 `lux/serialize_wbtest.mbt`）、`provider/gemini/gemini_wbtest.mbt`

**现状（三处语义问题）：**
1. `lux/stream.mbt:361`：`ThinkingDelta(s) => block_texts[idx] = block_texts[idx] + s` —— 思考增量拼入文本缓冲。若块类型是 `Thinking`（`flush_block` 273-286 正确产出 `Thinking` 内容）尚可；但若 ThinkingDelta 到达时块类型为 `Text`/未显式 `BlockStart(Thinking)`，思考内容会污染最终文本 → **必须独立累加**。
2. `provider/gemini/gemini.mbt:953-954`：流式 `thought` 标记"仅检查，不产生额外事件" → **静默丢弃**，应产出事件或诊断。
3. `provider/gemini/gemini.mbt:36-45`：非流式 `thought:true` 同时发 `LucentContent::text(t)` 和 `LucentThinking` → **思考内容伪装成文本**，应只发 `Thinking`（或带诊断说明）。

**接口（产出）：**
```moonbit
// lux/stream.mbt 累加器内部：
// 新增侧信道 block_thinking : Array[String]（与 block_texts 平行）
// ThinkingDelta(s) => block_thinking[idx] += s；块类型非 Thinking 时附加 Degraded 诊断
// flush_block(Thinking) 优先取 block_thinking（无则回退 block_texts，兼容旧事件流）
// 编码: gemini thought part → 仅 LucentThinking（不产 text）
// 流式: thought part → BlockStart(Thinking) + BlockDelta(ThinkingDelta)（复用块索引递增逻辑）
```

#### Step 1: 写会失败的测试（lux_wbtest / gemini_wbtest 追加）

```moonbit
///|
test "accumulate - thinking delta does not leak into text" {
  // 先 Text 块收 TextDelta，再 Thinking 块收 ThinkingDelta
  let events : Array[@lux.LucentStreamEvent] = [
    @lux.BlockStart(0, @lux.Text),
    @lux.BlockDelta(0, @lux.LucentBlockDelta::text_delta("visible")),
    @lux.BlockStart(1, @lux.Thinking),
    @lux.BlockDelta(1, @lux.LucentBlockDelta::thinking_delta("hidden")),
    @lux.BlockEnd(1),
    @lux.BlockEnd(0),
    @lux.Finish(@lux.Stop),
    @lux.Done,
  ]
  let acc = @lux.lucent_stream_events_to_accumulated(events, "r1", "m1")
  let text = @lux.lucent_response_text(acc.response)
  assert_true(text.contains("visible"))
  assert_false(text.contains("hidden")) // 思考内容不得进入文本
  // Thinking 内容存在于 response 的 Thinking content 中
  assert_true(acc.response.choices[0].message.content contains content is Thinking(_))
}
```

```moonbit
///|
test "gemini thought part - only Thinking, no text placeholder" {
  // 用 IR 构造器或适配器编码产输入（不手写 JSON）
  let json = "{\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"think...\",\"thought\":true}]},\"finishReason\":\"STOP\"}]}"
  // 注：若 from_json 严格，则改为构造 part JSON 后经 gemini 编码往返
  match @gemini.gemini_to_lux_response(json) {
    Ok(cr) => {
      let has_thinking = cr.value().choices[0].message.content contains content is Thinking(_)
      let has_plain_text = cr.value().choices[0].message.content contains content is Text(_)
      assert_true(has_thinking)
      assert_false(has_plain_text) // 不伪装成文本
    }
    Err(e) => fail("decode: \(e)")
  }
}
```
（注：以实际 lux/gemini API 为准；若 handcrafted JSON 触发 from_json 严格校验，改为 IR 构造器产出输入。）

- [ ] **Step 2: 确认测试失败**（预期 FAIL：当前 thinking 泄漏进文本 / gemini 同时发 Text）
- [ ] **Step 3: 实现**：
  - `lux/stream.mbt`：新增 `block_thinking` 平行数组（`ensure_block` 同步 push 空串）；`BlockDelta(ThinkingDelta)` 累加到 `block_thinking`；若 `block_types[idx]` 非 `Thinking`，追加 `Degraded` 诊断（"thinking delta on non-thinking block"）；`flush_block(Thinking)` 优先取 `block_thinking`（空则回退 `block_texts`）；`discard_block` 清空两者；末尾未闭合块 flush 条件加入 `block_thinking` 非空。
  - `gemini.mbt` 非流式：`parse_part` 中 `thought:true` → 仅 `[LucentThinking]`，不再发 `LucentContent::text`。
  - `gemini.mbt` 流式：`parts[j]` 有 `thought` 且含 text → 产 `BlockStart(thinking_idx, Thinking)` + `BlockDelta(thinking_idx, ThinkingDelta(t))`（与 text block 共用一个递增索引，参考 functionCall 的分块模式）。
- [ ] **Step 4: 确认测试通过**（预期 PASS）
- [ ] **Step 5: 全量验证** `moon fmt --check && moon check --warn-list +73 && moon test`

---

## Task 4: seed @deprecated 验证与文档确认

**文件：**
- Verify: `lux/lux.mbt:187`（注释已存在）
- Test: `lux/lux_wbtest.mbt`（可选：确认 seed 序列化不受影响）

**现状：** `lux.mbt:187` 已有 `/// @deprecated 仅 OpenAI Chat 使用，非通用生成参数，后续移入 extras` 注释；`docs/protocols/field-audit.md:69` 已记录。MoonBit `#deprecated` 属性不支持 struct 字段（文档限定 top-level fn/type/enum/trait），无法升级为编译器属性。

#### Step 1: 验证现状
- [ ] 确认 `lux/lux.mbt` seed 字段带 `@deprecated` 注释（已存在，无需改动）
- [ ] 确认 `docs/protocols/field-audit.md` 已标注 seed 走 extras 的处置（已存在）
- [ ] 运行 `moon test -f "seed"` 确认 seed 编解码测试仍通过

#### Step 2: 收尾文档
- [ ] 若 `field-audit.md` 状态列未标记"已 @deprecated"，补标注（本次仅文档微调，无代码变更）

---

## 依赖顺序

```
Task 1（移除死字段）          → 独立，可先做
Task 2a（Chat/Responses）    → 与 Task 2b 并行（不同适配器文件）
Task 2b（Anthropic/Gemini）  → 与 Task 2a 并行
Task 3（ThinkingDelta 修正） → 独立；gemini.mbt 与 Task 2b 有文件重叠 → 顺序执行或同批提交
Task 4（seed 验证）          → 独立，纯验证
```

**文件冲突提示：** Task 2b 与 Task 3 都改 `provider/gemini/gemini.mbt`，建议同批提交或按 2b → 3 顺序执行；`lux/stream.mbt` 仅 Task 3 触碰。

## 验证命令汇总

| 阶段 | 命令 | 预期 |
|------|------|------|
| 单任务 | `moon test -f "<test_name>"` | FAIL → PASS |
| 全量 | `moon fmt --check && moon check --warn-list +73 && moon test` | 0 errors，全绿 |
| 接口收尾 | `moon info && moon fmt` | `.mbti` 按预期更新（Prism 移除 2 方法） |

## 收尾（全任务完成后）

- [ ] `moon info && moon fmt`，核对 `.mbti` diff：`Prism` 不再导出 `with_api_key`/`with_base_url`；`lux`/`provider` 无意外新导出。
- [ ] 更新 `docs/requirements.md`：SDK 职责收敛 ✅（无死字段、store/extras 往返测试、Thinking 语义正确）。
- [ ] 更新 `.moonbit-pipeline.json`：phase=implement 完成后推进下一阶段（P3 Transport 扩展规划）。

## 未来演进（不在本计划内）

- `TransportConfig` 承载 api_key/base_url（Phase 3，daemon/HTTP 认证层）
- `logprobs` 等其余单协议字段移入 extras（field-audit.md 门 4 清单）
- `LucentAgentAction` 适配器实现（audit-gaps 缺口 3，v2 范围）

---
