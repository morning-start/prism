# SDK 转换来源元信息（ConversionMeta）实现计划（2026-08-02）

> 来源：`docs/requirements.md`（双场景设计）+ 2026-08-02 设计讨论（用户确认「SDK 层实现，不动 IR」）。
> 决策：D8 = 转换来源（source_provider）作为**解码操作的元信息**，放在 SDK 层 `ConversionMeta` 信封，**不进 IR 结构体**。
> 目标：多协议混流场景下，SDK 开发者能通过 `meta.source_provider` 分辨 LUX 值来源，并对特殊协议字段做按需特判处理；主路径代码仍只写一次。

## 背景与问题

| 场景 | 转换方向 | 来源可知性 | 问题 |
|------|---------|-----------|------|
| 场景 1 单协议 | LUX → provider A JSON | 开发者自己选协议，天然知道 | 无 |
| 场景 2 中转站 | provider A JSON → LUX → provider B JSON | source 只在 `convert_*` 参数里 | **多协议混流后，LUX 值不携带来源标签，开发者无法分辨** |

**现状核实（2026-08-02 实测）：**
- `LucentRequest` / `LucentResponse` 无 source 字段（`lux/lux.mbt`），只有 `extra: Map[String, Json]?` 与 `provider_payload: Json?`
- `sdk/convert.mbt` 的 `convert_request/response/stream` 中 source 仅存在于函数参数，解码结果（`ConversionResult[String]`）不带来源信息
- `sdk/prism.mbt` 已有 `decode_response_with_diagnostics`（返回完整 `LucentResponse` + 诊断），但无来源标签，payload 靠开发者自行推断

## 核心设计决策（D8）

**Source 是「解码操作的元信息」，不是「值的属性」。**

- ✅ 加在 **SDK 层**（`ConversionMeta` 信封），不动 IR 结构体、不动适配器、不加协议字段
- ❌ 不加进 `LucentRequest` / `LucentResponse` 结构体——三个硬伤：
  1. 违反 IR 中立原则（「纯数据结构、无厂商绑定」，`lux.mbt` 注释原话）
  2. 多跳转换 A→B→C 时 source 语义无法定义（链起点 vs 上一跳）
  3. 污染全项目共享的 IR 序列化/反序列化契约（需走 lucent-ir-evolution 治理，成本高）

**适用对象：** 只有使用 SDK 的开发者会遇到「多协议混流」场景（中转站消费者），故只做 SDK 层 API；适配器与 IR 零改动，无需走 IR 演进治理流程。

## 文件结构规划

```
sdk/
├── prism.mbt                      # Modify: 新增 decode_response_with_meta；ConversionMeta/DecodedResponse 结构
├── prism.mbt 或新文件 meta.mbt    # Create（若独立文件）：ConversionMeta + DecodedResponse 定义
├── sdk_test.mbt                   # Modify: 新增 meta 相关测试（来源标签/特殊字段透出/混流）
├── convert.mbt                    # Modify: 新增 convert_response_with_meta（信封透出，场景 2）
├── convert_test.mbt               # Modify: convert 带 meta 测试
├── pkg.generated.mbti             # 自动更新（moon info）
README.md / docs/sdk-usage.md      # Modify: 记录 meta 使用方式
```

**测试数据原则**（项目约定）：所有进入 `from_json` 的 JSON 由 IR 构造器 `to_json().stringify()` 或适配器编码产生，不手写。

---

## Task 1: ConversionMeta / DecodedResponse 结构 + `Prism::decode_response_with_meta`

**文件：**
- Create/Modify: `sdk/prism.mbt`（`ConversionMeta`、`DecodedResponse` 结构体 + `decode_response_with_meta` 方法）
- Test: `sdk/sdk_test.mbt`

**理由：** D8 确认 source 放 SDK 层信封；`decode_response_with_meta` 是既有 `decode_response_with_diagnostics` 的超集（多带 source_provider）。

#### Step 1: 写会失败的测试（sdk_test.mbt 追加）

```moonbit
///|
test "meta - decode_response_with_meta carries source_provider" {
  let prism = Prism::new().with_provider("openai-chat")
  let resp_json = <由 LucentResponse 构造器 to_json().stringify() 产生的 JSON>
  match prism.decode_response_with_meta(resp_json) {
    Ok(decoded) => {
      assert_eq(decoded.text, "Hello")
      assert_eq(decoded.meta.source_provider, "openai-chat")
    }
    Err(e) => fail("meta decode failed: \{e}")
  }
}

///|
test "meta - provider_payload passthrough" {
  // 构造含 content_filters / 特殊字段的响应 JSON（经适配器编码产生）
  // 断言 decoded.meta.provider_payload 可达且原样
}

///|
test "meta - anthropic source tag" {
  // with_provider("anthropic")，断言 meta.source_provider == "anthropic"
}

///|
test "meta - diagnostics attached" {
  // 含 Degraded 场景，断言 meta.diagnostics 透传
}
```

- [ ] **Step 2: 确认测试失败**（预期 FAIL：`decode_response_with_meta` / `ConversionMeta` 未定义）
- [ ] **Step 3: 实现**
  - `ConversionMeta { source_provider : String, diagnostics : Array[ConversionDiagnostic], provider_payload : Json?, extra_fields : Map[String, Json]? }`
  - `DecodedResponse { text : String, meta : ConversionMeta }`
  - `Prism::decode_response_with_meta`：调 `decode_to_lux` → 组装 `ConversionMeta`（source = `self.provider`，payload 从 `LucentResponse.provider_payload` 透出，diagnostics 从 `decode_response_with_diagnostics` 路径复用 schema 校验）
  - source_provider 经 `match_provider_name` 解析后的规范名填充（精确匹配/别名/模型正则，开发者无需硬编码）
- [ ] **Step 4: 确认测试通过**（预期 PASS）
- [ ] **Step 5: 全量验证** `moon fmt --check && moon check && moon test`

---

## Task 2: 场景 2 组合入口 `convert_response_with_meta`

**文件：**
- Modify: `sdk/convert.mbt`
- Test: `sdk/convert_test.mbt`

**理由：** 中转站消费者同样需要来源分辨；meta 作为信封字段随 result 输出，WASM/daemon 边界同形，零新增导出。

#### Step 1: 写会失败的测试（convert_test.mbt 追加）

```moonbit
///|
test "convert_response_with_meta - carries source" {
  // source="anthropic", target="openai-chat"
  // 断言 result.value() 可解析为 target JSON；诊断合并正确；meta 信封含 source_provider
}

///|
test "convert_response_with_meta - unknown provider error" {
  // source 未知 → Err("unknown provider: ...")
}
```

- [ ] **Step 2: 确认测试失败**（预期 FAIL：函数未定义）
- [ ] **Step 3: 实现**：`convert_response_with_meta(source, json_str, target) -> Result[ConversionResult[String], String]`——复用 `decode_encode_response` 逻辑，meta 以信封字段输出（`{value, diagnostics, source_provider}`，`conversion_json.mbt` 信封 helper 扩展或外层包装）
- [ ] **Step 4: 确认测试通过**
- [ ] **Step 5: 全量验证** 同上

---

## Task 3: 多协议混流集成测试 + 文档

**文件：**
- Test: `sdk/cross_protocol_test.mbt` 或 `sdk/sdk_test.mbt`
- Docs: `README.md`、`docs/sdk-usage.md`

**理由：** 核心价值验证——同一流程中混流多家响应，各自来源可分辨；文档让开发者知道「主路径写一次 + 按来源特判」的使用模式。

#### Step 1: 写会失败的测试（混流）

```moonbit
///|
test "meta - mixed-flow sources are distinguishable" {
  // 同一流程：decode openai-chat / anthropic / gemini 三家响应
  // 断言各自 meta.source_provider 分别正确，可 if 分支特判
}

///|
test "meta - special field handling via if branch" {
  // openai-responses 来源 → provider_payload 含 content_filters → 特判分支可达
  // 其他来源 → 分支不触发（_ => ()）
}
```

- [ ] **Step 2: 确认测试失败**
- [ ] **Step 3: 实现**：无新逻辑（复用 Task 1/2），如遇混流行为不一致则修正 meta 组装
- [ ] **Step 4: 确认测试通过**
- [ ] **Step 5: 文档**：README / sdk-usage 增加「来源元信息」章节，示例：

```moonbit
match prism.decode_response_with_meta(resp_json) {
  Ok(decoded) => {
    let answer = decoded.text             // 99% 代码：只用文本，跨协议一致
    match decoded.meta.source_provider {  // 1% 情况：按来源特判
      "openai-responses" => handle_openai_special(decoded.meta.provider_payload)
      "anthropic" => handle_anthropic_special(decoded.meta.extra_fields)
      _ => ()
    }
  }
  Err(e) => ...
}
```

---

## 依赖顺序

```
Task 1（结构 + Prism API）→ 先落 ConversionMeta 类型，Task 2/3 依赖
    ↓
Task 2（convert 信封透出）→ 依赖 Task 1 的 ConversionMeta
    ↓
Task 3（混流测试 + 文档）→ 依赖 Task 1/2 的完整链路
```

**文件冲突提示：** Task 1 与 Task 2 都改 `sdk/` 下文件但不同文件；Task 3 只改测试与文档。严格串行执行，一 Task 一 commit。

## 验证命令汇总

| 阶段 | 命令 | 预期 |
|------|------|------|
| 单任务（MoonBit） | `moon test -f "<test_name>"` | FAIL → PASS |
| 全量 | `moon fmt --check && moon check && moon test` | 0 errors，全绿 |
| 接口收尾 | `moon info && moon fmt` | `.mbti` 按预期更新（sdk +2~3 导出） |

## 收尾（全任务完成后）

- [ ] `moon info && moon fmt`，核对 `.mbti` diff（`sdk` 新增 `decode_response_with_meta`、`convert_response_with_meta`、结构体字段）
- [ ] 更新 `.moonbit-pipeline.json`：记录本计划完成状态，`next` 指向后续阶段
- [ ] 文档同步：README / docs/sdk-usage.md / docs/requirements.md（场景 1 SDK 能力清单）

## 未来演进（不在本轮）

- UDS / WebSocket / clients（phase3b）
- 结构化输出约束（L5，schema + 校验重试，场景 1 SDK 增强）
- 若未来确需「IR 对象自带来源」（跨进程传递 LUX JSON 后丢失解码上下文），折中方案：在 `ConversionResult` 信封加 `source_provider` 字段（信封是转换结果外包装，非 IR 本体）
