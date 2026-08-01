# Phase 1 保真度契约贯通实现计划（2026-08-01）

> 来源：`docs/plans/2026-08-01-project-roadmap.md` Phase 1 + `docs/report/architecture-audit-2026-07-28.md` P1
> 决策：D1 = ② clean cutover（项目未上线，六函数直接切换为新契约，不保留兼容层）
> 目标：让 `Exact / Degraded / Unsupported / Invalid` 成为可检测的协议输出，消除静默语义损失。

## 核心设计：带诊断转换信封

```text
adapter internal: Result[ConversionResult[T], String]   // Err = Invalid（无值失败）
SDK/WASM boundary: { "value": ..., "diagnostics": [...] } | { "error": ..., "diagnostics": [...] }
```

- 六函数签名从 `Result[T, String]` 切换为 `Result[ConversionResult[T], String]`（D1 直接切换）。
- `ConversionResult[T]` 已存在（`lux/lux.mbt:349-374`），`ConversionDiagnostic` / `ConversionStatus` 已存在（`lux/lux.mbt:322-344`）——**缺 JSON 序列化**。
- WASM 边界 String 进出不变，只是返回 JSON 增加 `diagnostics` 数组。

## 文件结构规划

```
lux/
├── conversion_json.mbt      # Create: ConversionStatus/Diagnostic/Result 的 to_json/from_json + 信封 helper
├── conversion_json_wbtest.mbt  # Create: 信封 JSON round-trip 测试
└── stream.mbt               # Modify: 累加器保留 AgentAction/NativeDelta/Annotations 诊断
provider/openai_chat/chat.mbt      # Modify: 六函数签名切换 + 静默分支诊断
provider/openai_responses/responses.mbt  # Modify: 同上
provider/anthropic/anthropic.mbt  # Modify: 同上
provider/gemini/gemini.mbt        # Modify: 同上
provider/openai_codex/codex.mbt   # Modify: 签名切换（薄包装，诊断透传）
provider/openai_azure/azure.mbt   # Modify: 签名切换（薄包装）
provider/gemini_vertex/vertex.mbt # Modify: 签名切换（薄包装）
sdk/
├── provider_capability.mbt  # Modify: 注册表 6 函数字段类型切换
├── prism.mbt                # Modify: decode_to_lux/encode_lux_request 解包 value
├── convert.mbt              # Modify: convert_* 解包 value
└── provider_registry_wbtest.mbt  # Modify: 注册表测试
wasm/wasm.mbt                # Modify: 6 通用转换 + wasm_convert_* 输出信封 JSON
wasm/wasm_test.mbt           # Modify: 信封断言
sdk/cross_protocol_test.mbt  # Modify: 契约测试矩阵（断言 value + diagnostics）
```

**测试数据原则**（项目约定）：所有进入 `from_json` 的 JSON 由 IR 构造器 `to_json().stringify()` 或适配器编码产生，不手写。

---

## Task 1: 信封 JSON 编解码（lux/conversion_json.mbt）

**文件：**
- Create: `lux/conversion_json.mbt`
- Test: `lux/conversion_json_wbtest.mbt`

**接口（产出）：**
```moonbit
pub fn ConversionStatus::to_json(self : ConversionStatus) -> Json
pub fn ConversionStatus::from_json(j : Json) -> Result[ConversionStatus, String]
pub fn ConversionDiagnostic::to_json(self : ConversionDiagnostic) -> Json
pub fn ConversionDiagnostic::from_json(j : Json) -> Result[ConversionDiagnostic, String]
pub fn[T] ConversionResult::to_json(self : ConversionResult[T], encode : (T) -> Json) -> Json
pub fn[T] ConversionResult::from_json(j : Json, decode : (Json) -> Result[T, String]) -> Result[ConversionResult[T], String]
/// 信封：{ "value": value_json, "diagnostics": [...] }
pub fn[T] ConversionResult::envelope_json(self : ConversionResult[T], value_json : Json) -> Json
```

JSON 形状（`conversion_json_wbtest` 断言）：
- `ConversionStatus`：`"exact" | "degraded" | "unsupported" | "invalid"`（小写字符串）
- `ConversionDiagnostic`：`{"field":"...", "status":"...", "detail":"..."}`（detail 可为 null）
- `ConversionResult`：`{"value":<T 的 json>,"diagnostics":[...]}`

#### Step 1: 写会失败的测试（conversion_json_wbtest.mbt）
```moonbit
///|
test "ConversionStatus round-trip - all variants" {
  let all = [Exact, Degraded, Unsupported, Invalid]
  for s in all {
    match ConversionStatus::from_json(s.to_json()) {
      Ok(d) => assert_eq(d, s)
      Err(e) => fail("status round-trip: \(e)")
    }
  }
}

///|
test "ConversionDiagnostic round-trip" {
  let d = ConversionDiagnostic::new("content", Degraded, Some("media as text"))
  match ConversionDiagnostic::from_json(d.to_json()) {
    Ok(dd) => {
      assert_eq(dd.field, "content")
      assert_eq(dd.status, Degraded)
      assert_eq(dd.detail, Some("media as text"))
    }
    Err(e) => fail("diag round-trip: \(e)")
  }
}

///|
test "ConversionResult envelope - value with diagnostics" {
  let r : ConversionResult[String] = ConversionResult::new("ok")
  let r = r.with_diagnostic(ConversionDiagnostic::new("x", Unsupported, None))
  let env = r.envelope_json(@json.String("ok"))
  match @json.parse(env.stringify()) {
    Object(map) => {
      assert_true(map.contains("value"))
      assert_true(map.contains("diagnostics"))
    }
    _ => fail("expected object envelope")
  }
}
```
（注：`with_diagnostic` 已存在于 `lux/lux.mbt:374+`；`@json.parse` 返回 `Json` 需 catch。`\(e)` 插值语法以 `\{e}` 修正。）

- [ ] **Step 2: 确认测试失败** `moon test -f "ConversionStatus round-trip"`（预期 FAIL：函数未定义）
- [ ] **Step 3: 写最小实现**：按上述签名实现；`from_json` 严格校验 status 字符串，未知值返回 `Err`。
- [ ] **Step 4: 确认测试通过**（预期 PASS）
- [ ] **Step 5: 全量验证** `moon fmt --check && moon check --warn-list +73 && moon test`

---

## Task 2: 六函数契约切换（全部适配器 + 注册表）

**文件：**
- Modify: `provider/openai_chat/chat.mbt`、`provider/openai_responses/responses.mbt`、`provider/anthropic/anthropic.mbt`、`provider/gemini/gemini.mbt`
- Modify: `provider/openai_codex/codex.mbt`、`provider/openai_azure/azure.mbt`、`provider/gemini_vertex/vertex.mbt`（薄包装，透传诊断）
- Modify: `sdk/provider_capability.mbt`（注册表 6 字段类型）、`sdk/provider_registry_wbtest.mbt`

**接口（契约切换）：**
```moonbit
// 旧 → 新（每适配器 6 个函数）
// 请求解码: (String) -> Result[LucentRequest, String]      → (String) -> Result[ConversionResult[LucentRequest], String]
// 请求编码: (LucentRequest) -> Result[String, String]      → (LucentRequest) -> Result[ConversionResult[String], String]
// 响应解码: (String) -> Result[LucentResponse, String]     → (String) -> Result[ConversionResult[LucentResponse], String]
// 响应编码: (LucentResponse) -> Result[String, String]     → (LucentResponse) -> Result[ConversionResult[String], String]
// SSE 解码: (String) -> Result[Array[LucentStreamEvent], String] → (String) -> Result[ConversionResult[Array[LucentStreamEvent]], String]
// SSE 编码: (Array[LucentStreamEvent]) -> Result[String, String] → (Array[LucentStreamEvent]) -> Result[ConversionResult[String], String]
```

**机械切换规则（本 Task 不新增诊断语义，仅签名包装）：**
- 成功路径：`Ok(v)` → `Ok(ConversionResult::new(v))`（diagnostics 空数组）
- 错误路径：`Err(e)` → `Err(e)`（不变，= Invalid 无值失败）
- 子协议适配器（codex/azure/vertex）：调用基础适配器后把 `ConversionResult` 原样透传（diagnostics 保留）
- 注册表 `ProviderRegistration` 6 个字段类型同步切换（`sdk/provider_capability.mbt:24-34`）

#### Step 1: 写会失败的测试（provider_registry_wbtest.mbt 追加）
```moonbit
///|
test "registry - request_decode returns ConversionResult" {
  match match_provider_name("openai-chat") {
    Some(reg) =>
      match (reg.request_decode)("{\"model\":\"gpt-4o\",\"messages\":[{\"role\":\"user\",\"content\":\"Hi\"}]}") {
        Ok(cr) => {
          assert_eq(cr.diagnostics().length(), 0)
          assert_eq(cr.value().model, "gpt-4o")
        }
        Err(e) => fail("decode: \(e)")
      }
    None => fail("provider not found")
  }
}
```
（注：源码经 `moon fmt` 后 `\(e)` 自动为 `\{e}`。）

- [ ] **Step 2: 确认测试失败**（预期 FAIL：注册表字段类型未切换，编译不匹配）
- [ ] **Step 3: 机械切换**：7 个适配器 + 注册表按上述规则改签名；同步更新 `provider/*/*_wbtest.mbt` / `*_test.mbt` 中直接调用六函数的测试（`Ok(v)` → `Ok(cr)` 后取 `cr.value()`）。
- [ ] **Step 4: 确认测试通过**（预期 PASS）
- [ ] **Step 5: 全量验证** `moon fmt --check && moon check --warn-list +73 && moon test`
  （注：本步会连带 `sdk/convert.mbt`、`sdk/prism.mbt`、`wasm/wasm.mbt` 编译失败——它们消费注册表；因此本 Task 与 Task 3 必须同批提交，或先改消费方为临时 `cr.value()`。）

---

## Task 3: SDK/WASM 信封接入

**文件：**
- Modify: `sdk/prism.mbt`（`decode_to_lux` / `encode_lux_request` / `decode_sse_inner` 解包 `.value()`）
- Modify: `sdk/convert.mbt`（`decode_encode_request/response/stream` 解包 `.value()`）
- Modify: `wasm/wasm.mbt`（6 通用转换 + `wasm_convert_*` 输出信封 JSON）
- Test: `wasm/wasm_test.mbt`、`sdk/sdk_test.mbt`

**接口（产出）：**
```moonbit
// wasm 成功: {"value":<payload>,"diagnostics":[...]}
// wasm 错误: {"error":"...","diagnostics":[]}
fn wasm_envelope_ok(value_json : String, diags : Array[@lux.ConversionDiagnostic]) -> String
fn wasm_envelope_err(e : String) -> String
```

#### Step 1: 写会失败的测试（wasm_test.mbt 追加）
```moonbit
///|
test "wasm_to_lux_request - returns envelope with value and diagnostics" {
  let json_str = "{\"model\":\"gpt-4o\",\"messages\":[{\"role\":\"user\",\"content\":\"Hi\"}]}"
  let result = wasm_to_lux_request("openai-chat", json_str)
  assert_true(result.contains("\"value\""))
  assert_true(result.contains("\"diagnostics\""))
}

///|
test "wasm_to_lux_request - invalid json returns error envelope" {
  let result = wasm_to_lux_request("openai-chat", "{invalid}")
  assert_true(result.contains("\"error\""))
}
```
- [ ] **Step 2: 确认测试失败**（预期 FAIL：当前返回裸 value，无 envelope）
- [ ] **Step 3: 实现**：`wasm.mbt` 中 6 通用转换函数解包 `ConversionResult` 后拼信封 JSON（`value` 用原序列化，`diagnostics` 用 Task 1 的 `ConversionResult::envelope_json`）；`wasm_convert_*` 同批处理；`sdk` 消费方同步解包 `.value()`。
- [ ] **Step 4: 确认测试通过**（预期 PASS）
- [ ] **Step 5: 全量验证** `moon fmt --check && moon check --warn-list +73 && moon test`

---

## Task 4: 流式累加器信息保留（lux/stream.mbt）

**文件：**
- Modify: `lux/stream.mbt`（`lucent_stream_events_to_response` 及内部辅助）
- Test: `lux/lux_wbtest.mbt` / `lux/serialize_wbtest.mbt`

**现状（信息损失点）：**
- `ItemStart(_, AgentAction(_))` → `()`（`stream.mbt:312`）
- `BlockDelta(_, NativeDelta(_, _))` → `()`（`stream.mbt:342`）
- `Annotations(_, _)` → `()`（`stream.mbt:348`）

**接口（产出）：**
```moonbit
/// 累加器产物：response + 未进入 response 的辅助信息
pub struct AccumulatedResponse {
  response : LucentResponse
  annotations : Array[LucentAnnotation]
  native_events : Array[LucentStreamEvent]
  agent_actions : Array[LucentAgentAction]
  diagnostics : Array[ConversionDiagnostic]
} derive(Eq, Debug)

pub fn lucent_stream_events_to_accumulated(events : Array[LucentStreamEvent]) -> AccumulatedResponse
// 保留原 lucent_stream_events_to_response 作为薄包装（取 .response），后续 refactor 阶段再评估去留
```

#### Step 1: 写会失败的测试（lux_wbtest.mbt 追加）
```moonbit
///|
test "accumulate - annotations and agent actions preserved" {
  let events : Array[LucentStreamEvent] = [
    ItemStart(0, AgentAction({ kind: "computer_call", id: "aa1", call_id: None, name: None, arguments_json: None, result: None, provider_payload: None })),
    Annotations(0, [LucentAnnotation::new("url", "https://x.com", None)]),
    Finish(Stop),
    Done,
  ]
  let acc = lucent_stream_events_to_accumulated(events)
  assert_eq(acc.agent_actions.length(), 1)
  assert_eq(acc.annotations.length(), 1)
  assert_eq(acc.diagnostics.length(), 2) // AgentAction + Annotations 各一条 Unsupported 诊断
}
```
- [ ] **Step 2: 确认测试失败**（预期 FAIL：函数/类型未定义）
- [ ] **Step 3: 实现**：新增 `lucent_stream_events_to_accumulated`；`AgentAction` → `agent_actions` + `Unsupported` 诊断；`Annotations` → `annotations` + `Unsupported` 诊断；`NativeDelta` → `native_events` + `Unsupported` 诊断；原 `lucent_stream_events_to_response` 改为调用它并取 `.response`（保持既有调用方可用）。
- [ ] **Step 4: 确认测试通过**（预期 PASS）
- [ ] **Step 5: 全量验证** `moon fmt --check && moon check --warn-list +73 && moon test`

---

## Task 5: openai_chat 静默分支诊断

**文件：**
- Modify: `provider/openai_chat/chat.mbt`
- Test: `provider/openai_chat/chat_wbtest.mbt`

**现状（audit）：** 编码将 `Reasoning` / `AgentAction` 直接忽略（`chat.mbt:474-502`）。

**目标：** 编码遇 `Reasoning` / `AgentAction` 产生 `Unsupported` 诊断（不阻断成功），不再静默。

#### Step 1: 写会失败的测试（chat_wbtest.mbt 追加）
```moonbit
///|
test "encode - Reasoning content yields Unsupported diagnostic" {
  let req = LucentRequest::new(
    "gpt-4o", None,
    [LucentConversationItem::message(LucentMessage::new(Assistant, [LucentContent::Thinking(LucentThinking::new("think", None, false))]))],
    None, None, LucentOptions::default(), None, None, None, None,
  )
  match lux_request_to_openai_chat(req) {
    Ok(cr) => {
      // 不阻断成功
      assert_true(cr.value().contains("model"))
      // 但必须携带诊断
      let has_unsupported = cr.diagnostics().some(fn(d) { d.status == Unsupported })
      assert_true(has_unsupported)
    }
    Err(e) => fail("encode failed: \(e)")
  }
}
```
- [ ] **Step 2: 确认测试失败**（预期 FAIL：当前 diagnostics 空）
- [ ] **Step 3: 实现**：在编码分支中，`Reasoning`/`AgentAction` 处 `diagnostics.push(ConversionDiagnostic::new("conversation", Unsupported, Some("reasoning/agent_action not supported by openai-chat")))`；通过 `ConversionResult` 累加后返回。
- [ ] **Step 4: 确认测试通过**（预期 PASS）
- [ ] **Step 5: 全量验证** `moon fmt --check && moon check --warn-list +73 && moon test`

---

## Task 6: openai_responses 静默分支诊断

**文件：**
- Modify: `provider/openai_responses/responses.mbt`
- Test: `provider/openai_responses/responses_wbtest.mbt`

**现状（audit）：**
- `input_image` / `input_file` 被忽略（`responses.mbt:36-45`）
- `reasoning` 请求配置解析为空实现（`responses.mbt:148-152`）
- SSE 输入遇非法 data 直接跳过（`responses.mbt:679-725`）

**目标：** `input_image`/`input_file` 解码为 `LucentMultimedia`（可精确映射）或 `Degraded` 诊断；reasoning 空实现产生 `Unsupported` 诊断；SSE 非法 data 产生 `Invalid` 诊断（不吞掉）。

#### Step 1: 写会失败的测试（responses_wbtest.mbt 追加）
```moonbit
///|
test "decode - unsupported reasoning config yields diagnostic" {
  // 经 IR 构造器编码再解码（不手写 JSON）
  let req = LucentRequest::new(
    "o3", None, [LucentConversationItem::message(LucentMessage::new(User, [LucentContent::text("Hi")]))],
    None, None,
    LucentOptions::new(None, None, None, None, None).with_reasoning(None),
    None, None, None, None,
  )
  // 具体以 responses 适配器 reasoning 字段实际编码路径构造；断言解码后 diagnostics 含 Unsupported
}
```
（注：若 `LucentOptions::with_reasoning` 不存在，以 `lux/lux.mbt` 实际构造器为准构造带 reasoning 的请求。）
- [ ] **Step 2: 确认测试失败**（预期 FAIL：诊断缺失）
- [ ] **Step 3: 实现**：按目标逐点补诊断；`input_image`/`input_file` 若 IR 已有 `LucentMultimedia` 则优先精确映射。
- [ ] **Step 4: 确认测试通过**（预期 PASS）
- [ ] **Step 5: 全量验证** `moon fmt --check && moon check --warn-list +73 && moon test`

---

## Task 7: anthropic 媒体空串修复 + 诊断

**文件：**
- Modify: `provider/anthropic/anthropic.mbt`
- Test: `provider/anthropic/anthropic_wbtest.mbt`

**现状（audit）：** `Image/Audio/Video/Native` 编码为空字符串（`anthropic.mbt:416-418`）——空串改变消息形状，不等价于"不支持"。

**目标：** 无法映射的媒体产生 `Unsupported` 诊断并跳过该 content 块（不输出空串）；可映射的（如图片 `LucentMultimedia`）优先编码为 anthropic `image` block。

#### Step 1: 写会失败的测试（anthropic_wbtest.mbt 追加）
```moonbit
///|
test "encode - unsupported media yields diagnostic not empty string" {
  let req = LucentRequest::new(
    "claude", None,
    [LucentConversationItem::message(LucentMessage::new(User, [LucentContent::Image(LucentMultimedia::new("png", "base64", Some("data:image/png;base64,AA")))]))],
    None, None, LucentOptions::default(), None, None, None, None,
  )
  match lux_request_to_anthropic(req) {
    Ok(cr) => {
      // 不得输出空字符串 content
      assert_true(not(cr.value().contains("\"type\":\"text\",\"text\":\"\"")))
      let has_diag = cr.diagnostics().some(fn(d) { d.status == Unsupported or d.status == Degraded })
      assert_true(has_diag)
    }
    Err(e) => fail("encode failed: \(e)")
  }
}
```
- [ ] **Step 2: 确认测试失败**（预期 FAIL：当前输出空串且无诊断）
- [ ] **Step 3: 实现**：媒体分支改为"可映射则编码 image block，否则 Unsupported 诊断并跳过"，绝不出空串。
- [ ] **Step 4: 确认测试通过**（预期 PASS）
- [ ] **Step 5: 全量验证** `moon fmt --check && moon check --warn-list +73 && moon test`

---

## Task 8: gemini 媒体占位修复 + 诊断

**文件：**
- Modify: `provider/gemini/gemini.mbt`
- Test: `provider/gemini/gemini_wbtest.mbt`

**现状（audit）：** `inlineData` / `fileData` 变为文本占位（`gemini.mbt:78-85`）——属 `Degraded`，不得伪装为 `Exact`；IR 已能表示媒体时优先转 `LucentMultimedia`。

**目标：** 解码 `inlineData`/`fileData` 为 `LucentMultimedia`（精确映射）；无法映射时 `Degraded` 诊断。

#### Step 1: 写会失败的测试（gemini_wbtest.mbt 追加）
```moonbit
///|
test "decode - inlineData maps to multimedia or degraded diagnostic" {
  let json = "{\"contents\":[{\"role\":\"user\",\"parts\":[{\"inlineData\":{\"mimeType\":\"image/png\",\"data\":\"AA\"}}]}]}"
  match gemini_to_lux_request(json) {
    Ok(cr) => {
      // 要么精确映射为多媒体，要么携带 Degraded 诊断——不允许静默变文本占位
      let has_image = cr.value().conversation.some(fn(_) { true }) // 占位：实际断言内容含 Image 或诊断
      assert_true(has_image or cr.diagnostics().length() > 0)
    }
    Err(e) => fail("decode failed: \(e)")
  }
}
```
（注：`conversation.some` 以 lux 实际 API 为准；本测试目标是"无静默占位"，具体断言在实现时用 IR 构造器生成输入并核对 `LucentMultimedia` 或诊断。）
- [ ] **Step 2: 确认测试失败**（预期 FAIL：当前静默文本占位无诊断）
- [ ] **Step 3: 实现**：解码优先 `LucentMultimedia`；无法精确映射则 `Degraded` 诊断。
- [ ] **Step 4: 确认测试通过**（预期 PASS）
- [ ] **Step 5: 全量验证** `moon fmt --check && moon check --warn-list +73 && moon test`

---

## Task 9: 契约测试矩阵（跨协议断言 value + diagnostics）

**文件：**
- Modify: `sdk/cross_protocol_test.mbt`
- 新增 fixture 辅助（可放同文件）

**目标：** 把 `cross_protocol_test.mbt` 中"放宽断言"（如 Chat 不保留 tool_choice、Anthropic 只断言长度 ≥）转换为显式 `Degraded`/`Unsupported` 预期 + 诊断断言。

#### Step 1: 写会失败的测试（cross_protocol_test.mbt 追加）
```moonbit
///|
test "fidelity - openai_chat tool_choice loss is reported as diagnostic" {
  // 构造带 tool_choice 的 canonical 请求（IR 构造器）
  let req = LucentRequest::new(
    "test-model", None,
    [LucentConversationItem::message(LucentMessage::new(User, [LucentContent::text("Hi")]))],
    None, Some(LucentToolChoice::Auto), LucentOptions::default(), None, None, None, None,
  )
  match @openai_chat.lux_request_to_openai_chat(req) {
    Ok(cr) => {
      // 若工具未定义则 tool_choice 被舍弃——必须携带诊断
      assert_true(cr.diagnostics().length() > 0 or req.tools is Some(_))
    }
    Err(e) => fail("encode failed: \(e)")
  }
}
```
（注：以实际 `openai_chat` 编码行为为准；若 tool_choice 在无 tools 时被保留，则改用 audit 列出的真实损失点构造 fixture。）
- [ ] **Step 2: 确认测试失败**（预期 FAIL：当前无诊断通道）
- [ ] **Step 3: 实现**：本任务主要是测试增强——为每个基础 provider 建立 canonical fixture（文本/图片/工具/推理/拒绝/未知内容/畸形 SSE），断言 value **和** diagnostics；修复测试暴露出的真实损失点（回到 Task 5-8 对应适配器补诊断）。
- [ ] **Step 4: 确认测试通过**（预期 PASS）
- [ ] **Step 5: 全量验证** `moon fmt --check && moon check --warn-list +73 && moon test`

---

## 依赖顺序

```
Task 1（信封 JSON） → Task 2（六函数契约切换）
                        ├→ Task 3（SDK/WASM 信封接入，与 Task 2 同批提交）
                        ├→ Task 4（流式累加器，独立于适配器）
                        ├→ Task 5/6/7/8（各适配器诊断，可并行）
                        └→ Task 9（契约矩阵，依赖 5-8）
```

## 验证命令汇总

| 阶段 | 命令 | 预期 |
|------|------|------|
| 单任务 | `moon test -f "<test_name>"` | FAIL → PASS |
| 全量 | `moon fmt --check && moon check --warn-list +73 && moon test` | 0 errors，全绿 |
| 接口收尾 | `moon info && moon fmt` | `.mbti` 按预期更新（六函数签名、信封 API） |

## 收尾（全任务完成后）

- [ ] `moon info && moon fmt`，核对 `.mbti` diff：六函数签名切换、`conversion_json.mbt` 新导出、`AccumulatedResponse`。
- [ ] 更新 `docs/requirements.md`：标记保真度契约 ✅。
- [ ] 更新 `.moonbit-pipeline.json`：`phase=implement`，plan_file 指向本文件。

## 未来演进（不在本计划内）

- HTTP / UDS / WebSocket 服务形态（Phase 3，复用 `convert_*`）
- `store`/`extras` 连通（Phase 2）
- 旧 `lucent_stream_events_to_response` 去留评估（refactor）
