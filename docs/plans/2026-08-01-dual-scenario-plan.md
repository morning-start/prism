# 双场景实现计划（2026-08-01）

> 来源：`docs/requirements.md` 双场景设计章节（2026-08-01 用户确认）
> 架构：A. IR 中心辐射式 —— convert_* 组合入口 + WASM 先行 + SDK 高层 API

## 目标

1. **场景 2（中转站）**：新增 `convert_*` 组合入口（source 解码 + target 编码，零新增转换逻辑），并导出 `wasm_convert_*`。
2. **场景 1（开发者 SDK）**：补齐 `Context.add_tool_result`（Agent 循环工具结果注入）+ `Prism.complete` / `Prism.stream` 便捷 API（HTTP 由 Host 注入 transport 函数）。

## 文件结构

```
sdk/
├── convert.mbt            # Create: convert_request/response/stream 组合入口
├── convert_test.mbt       # Create: 组合入口黑盒测试
├── context.mbt            # Modify: 新增 Context::add_tool_result
├── prism.mbt              # Modify: 新增 Prism::complete / Prism::stream
└── sdk_test.mbt           # Modify: complete/stream 便捷 API 测试
wasm/
├── wasm.mbt               # Modify: 新增 wasm_convert_request/response/stream
└── wasm_test.mbt          # Modify: WASM 中转导出黑盒测试
```

**依赖**：`sdk/moon.pkg` 已 import 全部 7 个 provider 与 lux；`wasm/moon.pkg` 已 import sdk。无需改 moon.pkg。

**测试数据原则**（沿用项目 memory 约定）：所有进入 `from_json` 的 JSON 必须由 IR 类型构造器 `to_json().stringify()` 或适配器 `lux_request_to_*` 编码产生，不手写 JSON 字符串。

---

## Task 1: convert_* 组合入口（sdk/convert.mbt）

**文件：**
- Create: `sdk/convert.mbt`
- Test: `sdk/convert_test.mbt`

**接口：**
- 消费: `@sdk.match_provider_name`（`sdk/provider_capability.mbt` 已存在）
- 产出:
  ```moonbit
  pub fn convert_request(source : String, json_str : String, target : String) -> Result[String, String]
  pub fn convert_response(source : String, json_str : String, target : String) -> Result[String, String]
  pub fn convert_stream(source : String, sse_str : String, target : String) -> Result[String, String]
  ```

**实现语义：**
- `convert_request` = `match_provider_name(source)` 的 `request_decode(json_str)` → `LucentRequest` → `match_provider_name(target)` 的 `request_encode(req)`
- `convert_response` 同理走 `response_decode` / `response_encode`
- `convert_stream` 走 `events_decode` / `events_encode`
- source/target 任一未知 → `Err("unknown provider: ...")`

#### Step 1: 写会失败的测试

```moonbit
///|
/// 标准对话经 IR 构造器生成，再经 source 适配器编码为 source JSON
fn openai_chat_req_json() -> String {
  let req = @lux.LucentRequest::new(
    "gpt-4o",
    Some([@lux.LucentContent::text("You are helpful")]),
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(@lux.User, [@lux.LucentContent::text("Hi")]),
      ),
    ],
    None,
    None,
    @lux.LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
  match @openai_chat.lux_request_to_openai_chat(req) {
    Ok(json) => json
    Err(e) => fail("encode source failed: \(e)")
  }
}

///|
test "convert_request - openai-chat to anthropic" {
  let json = openai_chat_req_json()
  match convert_request("openai-chat", json, "anthropic") {
    Ok(target_json) => {
      // 目标 JSON 必须能被 anthropic 适配器解码回 IR
      match @anthropic.anthropic_to_lux_request(target_json) {
        Ok(req) => {
          assert_eq(req.model, "gpt-4o")
          assert_eq(req.conversation.length(), 1)
        }
        Err(e) => fail("target decode failed: \(e)")
      }
    }
    Err(e) => fail("convert_request failed: \(e)")
  }
}

///|
test "convert_request - unknown source returns error" {
  match convert_request("no-such-provider", "{}", "anthropic") {
    Err(e) => assert_true(e.contains("unknown provider"))
    Ok(_) => fail("expected error")
  }
}

///|
test "convert_request - unknown target returns error" {
  let json = openai_chat_req_json()
  match convert_request("openai-chat", json, "no-such-provider") {
    Err(e) => assert_true(e.contains("unknown provider"))
    Ok(_) => fail("expected error")
  }
}
```

- [ ] **Step 2: 确认测试失败**
  Run: `moon test -f "convert_request"`（预期: FAIL，函数未定义）

- [ ] **Step 3: 写最小实现**
  ```moonbit
  ///|
  fn decode_encode_request(json_str : String, decode : (String) -> Result[@lux.LucentRequest, String], encode : (@lux.LucentRequest) -> Result[String, String]) -> Result[String, String] {
    match decode(json_str) {
      Ok(req) => encode(req)
      Err(e) => Err(e)
    }
  }

  ///|
  pub fn convert_request(source : String, json_str : String, target : String) -> Result[String, String] {
    match match_provider_name(source) {
      Some(src) =>
        match match_provider_name(target) {
          Some(dst) => decode_encode_request(json_str, src.request_decode, dst.request_encode)
          None => Err("unknown provider: " + target)
        }
      None => Err("unknown provider: " + source)
    }
  }
  ```
  `convert_response` / `convert_stream` 同构（response 用 `response_decode`/`response_encode`，stream 用 `events_decode`/`events_encode`）。

- [ ] **Step 4: 确认测试通过**
  Run: `moon test -f "convert_request"`（预期: PASS）

- [ ] **Step 5: 全量验证**
  Run: `moon fmt --check && moon check && moon test`

---

## Task 2: wasm_convert_* 导出（wasm/wasm.mbt）

**文件：**
- Modify: `wasm/wasm.mbt`
- Test: `wasm/wasm_test.mbt`

**接口：**
- 消费: Task 1 的 `@sdk.convert_request/response/stream`
- 产出:
  ```moonbit
  pub fn wasm_convert_request(source : String, json_str : String, target : String) -> String
  pub fn wasm_convert_response(source : String, json_str : String, target : String) -> String
  pub fn wasm_convert_stream(source : String, sse_str : String, target : String) -> String
  ```
  复用现有 `to_error(e)`：错误返回 `{"error": "..."}`。

#### Step 1: 写会失败的测试（追加到 wasm_test.mbt）

```moonbit
///|
test "wasm_convert_request - openai-chat to anthropic" {
  // 经 IR 构造器 → openai_chat 编码得到 source JSON
  let req = @lux.LucentRequest::from_messages(
    "gpt-4o",
    None,
    [@lux.LucentMessage::new(@lux.User, [@lux.LucentContent::text("Hi")])],
    None,
    None,
    @lux.LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
  let json = match @openai_chat.lux_request_to_openai_chat(req) {
    Ok(j) => j
    Err(e) => fail("encode: \(e)")
  }
  let result = wasm_convert_request("openai-chat", json, "anthropic")
  // 成功时结果可被 anthropic 适配器解码
  assert_true(result.contains("model"))
  match @anthropic.anthropic_to_lux_request(result) {
    Ok(r) => assert_eq(r.model, "gpt-4o")
    Err(e) => fail("target decode: \(e)")
  }
}

///|
test "wasm_convert_request - unknown provider returns error json" {
  let result = wasm_convert_request("nope", "{}", "anthropic")
  assert_true(result.contains("error"))
  assert_true(result.contains("unknown provider"))
}
```

- [ ] **Step 2: 确认测试失败**
  Run: `moon test -f "wasm_convert_request"`（预期: FAIL）

- [ ] **Step 3: 写最小实现**
  ```moonbit
  ///|
  /// 中转站：请求协议 A → 请求协议 B（String 进出）
  pub fn wasm_convert_request(source : String, json_str : String, target : String) -> String {
    match @sdk.convert_request(source, json_str, target) {
      Ok(v) => v
      Err(e) => to_error(e)
    }
  }
  ```
  `wasm_convert_response` / `wasm_convert_stream` 同构。

- [ ] **Step 4: 确认测试通过**
  Run: `moon test -f "wasm_convert_request"`（预期: PASS）

- [ ] **Step 5: 全量验证**
  Run: `moon fmt --check && moon check && moon test`

---

## Task 3: Context.add_tool_result（sdk/context.mbt）

**文件：**
- Modify: `sdk/context.mbt`
- Test: `sdk/sdk_test.mbt`

**接口：**
- 消费: `@lux.LucentToolResult::ok` / `@lux.LucentToolResult::new`、`@lux.LucentConversationItem::tool_result`
- 产出:
  ```moonbit
  pub fn Context::add_tool_result(self : Context, tool_use_id : String, content : String, is_error : Bool) -> Context
  ```

**实现语义：** 追加 `Item::ToolResult` 到 Context 消息队列（与 `add_user`/`add_assistant` 相同的不可变追加风格），供 Agent 循环注入工具结果后继续对话。

#### Step 1: 写会失败的测试

```moonbit
///|
test "context - add_tool_result appends tool result item" {
  let ctx = Context::new().add_user("use weather tool").add_tool_result(
    "tu_1",
    "sunny",
    false,
  )
  let req = context_to_lux_request(ctx, "gpt-4o", PrismOptions::default())
  assert_eq(req.conversation.length(), 2)
  match req.conversation[1] {
    @lux.ToolResult(tr) => {
      assert_eq(tr.tool_use_id, "tu_1")
      assert_eq(tr.is_error, false)
    }
    _ => fail("expected ToolResult item")
  }
}

///|
test "context - add_tool_result marks error" {
  let ctx = Context::new().add_tool_result("tu_2", "boom", true)
  let req = context_to_lux_request(ctx, "gpt-4o", PrismOptions::default())
  match req.conversation[0] {
    @lux.ToolResult(tr) => assert_eq(tr.is_error, true)
    _ => fail("expected ToolResult item")
  }
}
```

- [ ] **Step 2: 确认测试失败**
  Run: `moon test -f "add_tool_result"`（预期: FAIL）

- [ ] **Step 3: 写最小实现**
  ```moonbit
  ///|
  /// 注入工具执行结果（Agent 循环：执行工具后继续对话）
  pub fn Context::add_tool_result(
    self : Context,
    tool_use_id : String,
    content : String,
    is_error : Bool,
  ) -> Context {
    let new_msgs = self.messages.map(fn(msg) { msg })
    new_msgs.push({ role: "tool", content: content })
    { ..self, messages: new_msgs }
  }
  ```
  并在 `context_to_lux_request` 的循环中加入 `"tool"` 角色 → `Item::ToolResult` 的映射：
  ```moonbit
  "tool" => {
    // role 为 tool 的消息映射为 ToolResult item
    let tr = if is_error_flag { ... } else { ... }
  }
  ```
  （具体以 `@lux.LucentToolResult::ok/err` 实际签名实现；见 lux.mbt 构造器。）

- [ ] **Step 4: 确认测试通过**
  Run: `moon test -f "add_tool_result"`（预期: PASS）

- [ ] **Step 5: 全量验证**
  Run: `moon fmt --check && moon check && moon test`

---

## Task 4: Prism.complete / Prism.stream（sdk/prism.mbt）

**文件：**
- Modify: `sdk/prism.mbt`
- Test: `sdk/sdk_test.mbt`

**接口：**
- 消费: 现有 `encode_request` / `decode_response` / `encode_stream_request` / `decode_sse`、Task 3 的 `Context`
- 产出（HTTP transport 由 Host 注入，保持纯编解码 façade 边界）:
  ```moonbit
  pub fn Prism::complete(
    self : Prism,
    text : String,
    opts : PrismOptions,
    send : (String) -> Result[String, String],  // Host 注入的 HTTP 发送函数
  ) -> Result[String, String]

  pub fn Prism::stream(
    self : Prism,
    ctx : Context,
    send : (String) -> Result[String, String],  // Host 注入的 HTTP 发送函数
  ) -> Result[Array[PrismEvent], String]
  ```

**实现语义：**
- `complete` = `encode_request(text, opts)` → `send(json)` → `decode_response(resp_json)`
- `stream` = `context_to_lux_request(ctx, model, default)` + `with_stream(true)` → `send(json)` → `decode_sse(sse)` → `Array[PrismEvent]`

#### Step 1: 写会失败的测试（用假 send 函数）

```moonbit
///|
test "complete - text in text out via mock transport" {
  let prism = Prism::new().with_provider("openai-chat")
  // 假 transport：直接把请求 JSON 回显为响应
  let mock_send : (String) -> Result[String, String] = fn(req_json) {
    // 用 openai_chat 适配器编码一个响应
    let resp = @lux.LucentResponse::new(
      "resp-1",
      "gpt-4o",
      [@lux.LucentChoice::new(@lux.LucentMessage::new(@lux.Assistant, [@lux.LucentContent::text("Hello back")]), @lux.Stop, None)],
      @lux.LucentUsage::default(),
    )
    match @openai_chat.lux_response_to_openai_chat(resp) {
      Ok(j) => Ok(j)
      Err(e) => Err(e)
    }
  }
  match prism.complete("Hi", PrismOptions::default(), mock_send) {
    Ok(text) => assert_eq(text, "Hello back")
    Err(e) => fail("complete failed: \(e)")
  }
}
```
（`LucentResponse`/`LucentChoice`/`LucentUsage` 具体构造器参数以 `lux/lux.mbt` 实际签名为准。）

- [ ] **Step 2: 确认测试失败**
  Run: `moon test -f "complete - text in text out"`（预期: FAIL）

- [ ] **Step 3: 写最小实现**
  ```moonbit
  ///|
  /// L1 零配置：文本进、文本出（HTTP 由 Host 注入 send）
  pub fn Prism::complete(
    self : Prism,
    text : String,
    opts : PrismOptions,
    send : (String) -> Result[String, String],
  ) -> Result[String, String] {
    match self.encode_request(text, opts) {
      Ok(json) =>
        match send(json) {
          Ok(resp_json) => self.decode_response(resp_json)
          Err(e) => Err(e)
        }
      Err(e) => Err(e)
    }
  }

  ///|
  /// L2 Agent 循环：流式请求 + 5 事件解码（HTTP 由 Host 注入 send）
  pub fn Prism::stream(
    self : Prism,
    ctx : Context,
    send : (String) -> Result[String, String],
  ) -> Result[Array[PrismEvent], String] {
    match self.encode_stream_request(ctx, PrismOptions::default()) {
      Ok(json) =>
        match send(json) {
          Ok(sse) => self.decode_sse(sse)
          Err(e) => Err(e)
        }
      Err(e) => Err(e)
    }
  }
  ```

- [ ] **Step 4: 确认测试通过**
  Run: `moon test -f "complete - text in text out"`（预期: PASS）

- [ ] **Step 5: 全量验证**
  Run: `moon fmt --check && moon check && moon test`

---

## 收尾（全任务完成后）

- [ ] **Run:** `moon info && moon fmt`（更新 `.mbti` 接口文件并格式化）
- [ ] **检查 .mbti diff**：`sdk/pkg.generated.mbti` 新增 `convert_request/response/stream`、`Context::add_tool_result`、`Prism::complete/stream`；`wasm/pkg.generated.mbti` 新增 `wasm_convert_*`；确认无意外导出。
- [ ] **Run:** `moon test`（645 + 新增用例全绿）
- [ ] **更新需求文档状态表**：`docs/requirements.md` 标记 convert_* 与 wasm_convert_* 为 ✅。

## 验证命令汇总

| 阶段 | 命令 | 预期 |
|------|------|------|
| 单任务 | `moon test -f "<test_name>"` | FAIL → PASS |
| 全量 | `moon fmt --check && moon check && moon test` | 0 错误，全绿 |
| 接口收尾 | `moon info && moon fmt` | .mbti 按预期更新 |

## 未来演进（不在本计划内）

- HTTP 服务请求方式：复用 `convert_*` 于 `transport/daemon`（Go + wazero）
- 本地进程间通信：UDS / stdio / WebSocket 选型未定，仅加入口层
