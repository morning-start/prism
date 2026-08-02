# Phase 3 Transport 扩展实现计划（2026-08-02）

> 来源：`docs/plans/2026-08-01-project-roadmap.md` Phase 3 + `transport/ARCHITECTURE.md` §4/§5/§9。
> 本轮范围（已确认）：**Task 0-3**，即「修复传输层保真度断裂 + HTTP 流式通路」。
> UDS / Named Pipe / WebSocket / `clients/go` / `clients/python` **不在本轮**，另开一阶段。
> 决策：D5 = JSON-RPC `result` 改为 `{value, diagnostics}` 信封（clean cutover，沿用 D1 精神）。

## 调研结论（2026-08-02 实测）

| # | 问题 | 证据 | 处置 |
|---|------|------|------|
| A | **`convert` RPC 在最新构建下直接失败** | 刷新 `_build/wasm/debug/build/cmd/main/main.wasm` 后 `go test -run TestServeConvert` → `-32000 prism: missing required field schema_version`（`daemon_test.go:105`） | Task 1 |
| B | 根因：`wrappers/go/prism.go:90` `Convert` 手工两步，把 `ToLuxRequest` 返回的 `{"value":…,"diagnostics":[]}` 信封原样喂给 `LuxRequestToProvider`，后者 `LucentRequest::from_json` 找不到 `schema_version` | `wasm/wasm.mbt:40` 已改为 `cr.envelope_json(...)`（Phase 1）；Go 侧未同步 | Task 1 |
| C | **三个 wrapper 均不解析信封** | 全仓 grep `diagnostics\|"value"\|'value'` 在 `wrappers/` 下 **零命中**（go / py / ts） | Task 1 |
| D | **link 导出清单缺 3 个 `wasm_convert_*`** | `cmd/main/moon.pkg:11-23` 仅 11 项；`cmd/main/main.mbt` 只有 11 个 shim；`wasm/pkg.generated.mbti` 有 14 个 `pub fn`。故 Phase 3「复用 `wasm_convert_*`」的函数在链接产物中不存在 —— 这正是 Go 侧当初手工两步的原因 | Task 0 |
| E | **Go 测试跑 stale 产物 → 假绿** | 产物原时间戳 `2026-08-01 13:42`，早于 Phase 1 后半（`606402f` 等）与全部 Phase 2 提交（08-02）。`daemon_test.go:18` 读的正是该文件，`moon build --target wasm` 前 7/7 PASS，刷新后 1 FAIL | Task 0 |
| F | `list_providers` RPC 返回硬编码 7 名 | `wrappers/go/prism.go:106-116` 硬编码数组，而注册表真值是 `@sdk.list_provider_names()`（`sdk/pkg.generated.mbti:21`）。新增 provider 会被静默漏报 | Task 1 |
| G | `wasm_sdk_*`（5 个）无诊断 | `wasm/wasm.mbt:159-274` 返回裸值或 `{"error":…}`；但 SDK 已有 `encode_request_with_diagnostics` / `decode_response_with_diagnostics`（`sdk/pkg.generated.mbti:56,59`）可用 | Task 2 |
| H | ARCHITECTURE.md 自相矛盾 | §3.4 与 §4.2.2 说 `encode_stream` 返回「流式请求 JSON」（当前实现如此），§4.5 的 SSE 示例却让它返回 `text_delta` 事件流 | Task 3 文档修正 |

**术语澄清（影响 Task 3 设计）**：当前 `encode_stream` 是**同步**方法（文本 → 带 `stream:true` 的请求 JSON），本身不产生事件流。真正需要流式传输的是**解码方向**：`decode_sse` / `convert_stream`。

## 决策记录

| # | 决策 | 结论 |
|---|------|------|
| D5 | JSON-RPC `result` 是否携带诊断 | **改为信封** `{"value":…,"diagnostics":[…]}`，与 WASM 边界同形。项目未上线，不留兼容层；`ARCHITECTURE.md` §4.3/§4.5 全部示例同步改写 |
| D6 | 新增导出命名 | 沿用 `cmd/main/main.mbt` 现有缩写惯例：`wasm_convert_req` / `wasm_convert_resp` / `wasm_convert_stream` / `wasm_list_providers` |
| D7 | `decode_sse_stream` 会话模型是否本轮实现 | **不实现**。ARCHITECTURE.md §4.5 的 session + notification 模型依赖全双工，属 UDS/WS 形态；HTTP 单请求单响应下用「一次 POST + SSE 响应」表达流式即可。文档中标注该方法为 UDS/WS 阶段交付 |

## 文件结构规划

```
cmd/main/
├── main.mbt                    # Modify: 补 wasm_convert_req/resp/stream + wasm_list_providers shim
├── moon.pkg                    # Modify: link exports 11 → 15
wasm/
├── wasm.mbt                    # Modify: wasm_sdk_* 改为信封输出（用 *_with_diagnostics）+ 新增 wasm_list_providers
├── wasm_test.mbt               # Test: 信封形状断言
wrappers/go/
├── envelope.go                 # New: Envelope/Diagnostic 类型 + 解析
├── prism.go                    # Modify: Convert 走单次 wasm_convert_*；ListProviders 走导出；各方法返回诊断
├── wasm.go                     # Modify: 导出映射补 4 项；删除恒等映射冗余层
├── prism_test.go               # Test: 信封解析 + Convert 单调用 + 诊断透出
transport/daemon/
├── types.go                    # Modify: Result 信封类型
├── dispatcher.go               # Modify: 各 handler 返回信封；新增 convert_stream 分发
├── http.go                     # Modify: Accept: text/event-stream → SSE 流式响应
├── stream.go                   # New: SSE 帧切分 + 逐帧解码 + 流式写出
├── daemon_test.go              # Test: 信封断言、SSE 流式、逐帧/全量等价性
├── freshness_test.go           # New: 构建产物新鲜度门禁
transport/ARCHITECTURE.md       # Modify: §4.3/§4.5 信封化、§3.4/§4.2.2 encode_stream 语义统一、§9 阶段状态
wrappers/py/, wrappers/ts/      # Modify: 同步信封解析（与 Go 对齐）
```

**测试数据原则**（项目约定）：进入 `from_json` 的 JSON 由 IR 构造器 `to_json().stringify()` 或适配器编码产生，不手写。SSE fixture 由 `wasm_events_to_sse` 产出。

---

## Task 0: 导出清单对齐 + 构建新鲜度门禁

**为什么最先做**：缺口 D 使 Task 1 无法实现（要调的函数不存在），缺口 E 使一切验证不可信。这两项不修，后续所有绿灯都是假的。

**文件：**
- Modify: `cmd/main/main.mbt`（补 4 个 shim）、`cmd/main/moon.pkg`（exports 11 → 15）
- Modify: `wasm/wasm.mbt`（新增 `wasm_list_providers`）
- New: `transport/daemon/freshness_test.go`
- Modify: `transport/daemon/daemon_test.go:16-28` `loadBackend`（跳过改为失败）

#### Step 1: 写会失败的测试

```go
// freshness_test.go — 产物必须比所有 MoonBit 源文件新
func TestWASMArtifactFresherThanSources(t *testing.T) {
    art, err := os.Stat(wasmArtifactPath)
    if err != nil {
        t.Fatalf("wasm artifact missing, run: moon build --target wasm (%v)", err)
    }
    var newest time.Time
    var newestPath string
    filepath.WalkDir("../..", func(p string, d fs.DirEntry, err error) error {
        // 跳过 _build/ 与 .git/；只看 *.mbt / moon.pkg / moon.mod
        ...
    })
    if newest.After(art.ModTime()) {
        t.Fatalf("stale wasm artifact: %s modified %v after build %v — run: moon build --target wasm",
            newestPath, newest, art.ModTime())
    }
}

// 导出面必须包含 15 个函数（含 3 个 convert + list_providers）
func TestAllExportsPresent(t *testing.T) {
    backend := loadBackend(t)
    for _, name := range []string{
        "wasm_to_lux_req", "wasm_lux_req_to_provider",
        "wasm_to_lux_resp", "wasm_lux_resp_to_provider",
        "wasm_sse_to_events", "wasm_events_to_sse",
        "wasm_sdk_encode_req", "wasm_sdk_decode_resp",
        "wasm_sdk_encode_stream", "wasm_sdk_decode_sse", "wasm_sdk_capability",
        "wasm_convert_req", "wasm_convert_resp", "wasm_convert_stream",
        "wasm_list_providers",
    } {
        if backend.HasExport(name) == false {
            t.Errorf("missing export: %s", name)
        }
    }
}
```

- [ ] **Step 2: 确认测试失败**（预期 FAIL：4 个导出缺失；新鲜度测试视工作区状态）
- [ ] **Step 3: 实现**
  - `wasm/wasm.mbt` 新增 `pub fn wasm_list_providers() -> String`：`@sdk.list_provider_names()` → JSON 数组字符串（**注意**：`Json::array` + `stringify`，不手工拼字符串）。
  - `cmd/main/main.mbt` 新增 4 个 shim，委托 `@wasm.wasm_convert_request/response/stream` 与 `@wasm.wasm_list_providers`；更新首部注释「6 + 5」→「6 + 3 中转 + 6 SDK/查询」。
  - `cmd/main/moon.pkg` exports 数组补 4 项。
  - `wrappers/go/wasm.go` 的 `wasmExportMap` 补 4 项；顺手删掉「Go 名 → WASM 名」的恒等映射与 `reversedMap`（`wasm.go:21-43` 全为同名，`reversedMap` 无任何调用方），`Call` 直接用名字。
  - `loadBackend` 的 `t.Skipf` 改 `t.Fatalf`：产物缺失必须是硬失败，不能静默跳过（缺口 E 的成因）。
  - `WASMBackend` 加 `HasExport(name string) bool`（`mod.ExportedFunction(name) != nil`）。
- [ ] **Step 4: 确认测试通过**（`moon build --target wasm` 后 PASS）
- [ ] **Step 5: 全量验证** `moon fmt --check && moon check --warn-list +73 && moon test && moon build --target wasm && (cd transport/daemon && go test -count=1 ./...)`
  - 预期：`TestServeConvert` 此时**仍 FAIL**（缺口 A/B 未修）→ 由 Task 1 转绿。记录该失败为 Task 1 的起点。

---

## Task 1: wrapper 信封解析 + `Convert` 走 `wasm_convert_*`

**文件：**
- New: `wrappers/go/envelope.go`
- Modify: `wrappers/go/prism.go`（`Convert`、`ListProviders`、6 个 IR 方法签名）
- Test: `wrappers/go/prism_test.go`
- Modify: `wrappers/py/*`、`wrappers/ts/*`（同步，与 Go 契约一致）

**产出接口：**

```go
// Diagnostic 对应 lux.ConversionDiagnostic：
//   {"field":"options.store","status":"unsupported","detail":"..."}
// status ∈ exact | degraded | unsupported | invalid（lux/conversion_json.mbt:15-22）
type Diagnostic struct {
    Field  string `json:"field"`
    Status string `json:"status"`
    Detail string `json:"detail,omitempty"`
}

// Envelope 对应 lux.ConversionResult::envelope_json（lux/conversion_json.mbt:137-147）。
// Value 是 json.RawMessage：IR 方向为对象，provider 方向为 JSON 字符串。
type Envelope struct {
    Value       json.RawMessage `json:"value"`
    Diagnostics []Diagnostic    `json:"diagnostics"`
}

func parseEnvelope(raw string) (*Envelope, error)
func (e *Envelope) ValueString() (string, error)  // Value 为 JSON string 时取出裸串
```

#### Step 1: 写会失败的测试

```go
// Convert 必须单次 WASM 调用，且返回可直接发给厂商的 JSON（非信封）
func TestConvertRequestSingleCall(t *testing.T) {
    c := loadClient(t)
    payload := `{"model":"gpt-4o","input":[{"type":"message","role":"user",` +
        `"content":[{"type":"input_text","text":"Hi"}]}]}`
    env, err := c.ConvertRequest("openai", "anthropic", payload)
    if err != nil {
        t.Fatal(err)
    }
    out, err := env.ValueString()
    if err != nil || !strings.Contains(out, `"messages"`) {
        t.Errorf("expected anthropic request, got %q (%v)", out, err)
    }
    if strings.Contains(out, `"diagnostics"`) {
        t.Error("value must not be an envelope — envelope was double-wrapped")
    }
}

// 诊断必须透出到 Go 侧（Phase 1 契约不得止步于 WASM 边界）
func TestDiagnosticsSurfaced(t *testing.T) {
    c := loadClient(t)
    // Anthropic 无 store 字段 → Phase 2 已产 Unsupported 诊断
    luxReq := buildLuxRequestWithStore(t)  // 由 IR 构造器产出，不手写
    env, err := c.LuxRequestToProvider("anthropic", luxReq)
    if err != nil {
        t.Fatal(err)
    }
    if len(env.Diagnostics) == 0 {
        t.Fatal("expected unsupported diagnostic for options.store")
    }
    if env.Diagnostics[0].Status != "unsupported" {
        t.Errorf("status = %q, want unsupported", env.Diagnostics[0].Status)
    }
}

// 注册表真值，而非硬编码
func TestListProvidersFromRegistry(t *testing.T) {
    c := loadClient(t)
    got, err := c.ListProviders()
    if err != nil {
        t.Fatal(err)
    }
    if len(got) < 7 {
        t.Errorf("got %d providers, want >= 7 from registry", len(got))
    }
}
```

- [ ] **Step 2: 确认测试失败**（预期 FAIL：无 `ConvertRequest`/`Envelope` 类型，`ListProviders` 无 error 返回）
- [ ] **Step 3: 实现**
  - 6 个 IR 方法与 3 个 convert 方法返回 `(*Envelope, error)`；`wasm.go` 的 `{"error":` 前缀分支保留（错误信封 `wasm/wasm.mbt:20-22` 仍以此开头，行为不变）。
  - `Convert(from, to, direction, payload)` 改为按 direction 分发到 `wasm_convert_req` / `wasm_convert_resp` **单次调用**，删除手工两步（`prism.go:90-103`）。补 `ConvertStream`。
  - `ListProviders() ([]string, error)` 走 `wasm_list_providers`，删除硬编码数组。
  - `wasm_sdk_*` 的信封化留给 Task 2（避免与 daemon 改动交叉）。
  - `wrappers/py`、`wrappers/ts` 同步：等价 `Envelope` 结构 + `convert_*` 单调用 + `list_providers` 走导出。
- [ ] **Step 4: 确认测试通过**（含 Task 0 遗留的 `TestServeConvert` 转绿）
- [ ] **Step 5: 全量验证** 同 Task 0 Step 5，此时 daemon 全绿

---

## Task 2: JSON-RPC `result` 信封化（D5）

**文件：**
- Modify: `wasm/wasm.mbt`（5 个 `wasm_sdk_*` 改信封输出）
- Modify: `transport/daemon/types.go`、`dispatcher.go`
- Test: `wasm/wasm_test.mbt`、`transport/daemon/daemon_test.go`
- Modify: `transport/ARCHITECTURE.md` §4.3、§4.5

**线上格式变更（before → after）：**

```jsonc
// before
{"jsonrpc":"2.0","id":2,"result":"Hi"}
// after
{"jsonrpc":"2.0","id":2,"result":{"value":"Hi","diagnostics":[]}}

// 诊断非空时（Anthropic 收到 store）
{"jsonrpc":"2.0","id":4,"result":{"value":"{\"messages\":[...]}",
 "diagnostics":[{"field":"options.store","status":"unsupported",
                 "detail":"provider has no store field"}]}}
```

错误响应形状不变（JSON-RPC `error` 对象）。

#### Step 1: 写会失败的测试

```go
func TestResultIsEnvelope(t *testing.T) {
    handler := NewHTTPHandler(loadBackend(t), "test")
    resp := rpcPost(t, handler, `{"jsonrpc":"2.0","id":1,"method":"encode_request",`+
        `"params":{"provider":"openai","text":"Hello"}}`)
    if resp.Error != nil {
        t.Fatalf("unexpected error: %+v", resp.Error)
    }
    m, ok := resp.Result.(map[string]any)
    if !ok {
        t.Fatalf("result must be an envelope object, got %T", resp.Result)
    }
    if _, ok := m["value"]; !ok {
        t.Error("missing value")
    }
    if _, ok := m["diagnostics"]; !ok {
        t.Error("missing diagnostics")  // 空也必须在场，客户端才能无条件读
    }
}
```

- [ ] **Step 2: 确认测试失败**（预期 FAIL：`result` 当前是裸 string）
- [ ] **Step 3: 实现**
  - `wasm/wasm.mbt`：`wasm_sdk_encode_request` / `wasm_sdk_decode_response` 改走 `Prism::encode_request_with_diagnostics` / `decode_response_with_diagnostics`（`sdk/pkg.generated.mbti:56,59`）并 `envelope_json` 输出；`wasm_sdk_encode_stream`、`wasm_sdk_decode_sse`、`wasm_sdk_capability` 无诊断源 → 输出 `diagnostics: []` 保持形状一致（`to_error` 统一换成 `wasm_envelope_err`，消除两套错误形状）。
  - `dispatcher.go`：各 handler 解析 backend 返回的信封并原样放入 `result`；`list_providers` / `ping` 同样包信封（形状统一优先于省字节）。
  - 新增 `convert_stream` 方法分发（`wasm_convert_stream`），补齐 ARCHITECTURE §4.2 的中转三通路。
  - `ARCHITECTURE.md` §4.3 全部示例改信封；§4.4 错误码表不变；§4.2 方法目录补 `convert_stream`。
- [ ] **Step 4: 确认测试通过**
- [ ] **Step 5: 全量验证** 同上

---

## Task 3: HTTP SSE 流式通路

**文件：**
- New: `transport/daemon/stream.go`
- Modify: `transport/daemon/http.go`（`Accept: text/event-stream` 分支）
- Test: `transport/daemon/daemon_test.go`
- Modify: `transport/ARCHITECTURE.md` §3.4/§4.2.2/§4.5/§9

**设计（D7）：** HTTP 下不做 session。客户端一次 POST 带完整或分块 SSE 文本，`Accept: text/event-stream` 时 daemon 按 `\n\n` 切帧、逐帧解码、逐帧写出，边解边发。适用方法：`decode_sse`、`convert_stream`。

```
POST /v1   Accept: text/event-stream
{"jsonrpc":"2.0","id":1,"method":"decode_sse","params":{"provider":"anthropic","sse":"..."}}

HTTP/1.1 200 OK
Content-Type: text/event-stream

event: data
data: {"jsonrpc":"2.0","id":1,"result":{"value":{"type":"text_delta","text":"你"},"diagnostics":[]}}

event: data
data: {"jsonrpc":"2.0","id":1,"result":{"value":{"type":"finish","reason":"stop"},"diagnostics":[]}}

event: done
data: {"jsonrpc":"2.0","id":1,"result":{"value":{"type":"done"},"diagnostics":[]}}
```

**核心风险与门禁：** 逐帧解码是否与全量解码等价？跨帧状态（块索引、工具参数增量拼接）若被帧边界打断，会破坏「流式事件语义不被破坏」的验收门槛。**该等价性必须成为测试，不是假设。** 若某 provider 不等价，则退化为「全量解码后再流式写出」（正确性优先于首字节延迟），并记录诊断。

#### Step 1: 写会失败的测试

```go
// 门禁：逐帧解码 == 全量解码（4 个基础 provider 全覆盖）
func TestFrameByFrameEqualsWholeText(t *testing.T) {
    backend := loadBackend(t)
    for _, p := range []string{"openai", "openai-chat", "anthropic", "gemini"} {
        t.Run(p, func(t *testing.T) {
            sse := buildSSEFixture(t, backend, p)  // 经 wasm_events_to_sse 产出，不手写
            whole := decodeWhole(t, backend, p, sse)
            framed := decodeFrameByFrame(t, backend, p, sse)
            if !reflect.DeepEqual(whole, framed) {
                t.Errorf("frame-by-frame diverges from whole-text decode:\n whole  = %v\n framed = %v",
                    whole, framed)
            }
        })
    }
}

func TestSSEStreamingResponse(t *testing.T) {
    handler := NewHTTPHandler(loadBackend(t), "test")
    req := httptest.NewRequest(http.MethodPost, "/v1", body)
    req.Header.Set("Accept", "text/event-stream")
    rec := httptest.NewRecorder()
    handler.ServeHTTP(rec, req)
    if ct := rec.Header().Get("Content-Type"); !strings.HasPrefix(ct, "text/event-stream") {
        t.Fatalf("Content-Type = %q", ct)
    }
    frames := parseSSEFrames(rec.Body.String())
    if len(frames) < 2 {
        t.Fatalf("expected multiple frames, got %d", len(frames))
    }
    if frames[len(frames)-1].Event != "done" {
        t.Errorf("last frame event = %q, want done", frames[len(frames)-1].Event)
    }
}

// 同一请求不带 Accept 头 → 仍走同步 JSON，形状为信封
func TestSyncPathUnaffectedByStreaming(t *testing.T) { ... }
```

- [ ] **Step 2: 确认测试失败**（预期 FAIL：无 SSE 分支，`Content-Type` 为 `application/json`）
- [ ] **Step 3: 实现**
  - `stream.go`：`splitSSEFrames(text string) []string`（按 `\n\n`，保留尾部不完整帧）、`writeSSEFrame(w, event, payload)`（每帧后 `Flusher.Flush()`，否则 Go 默认缓冲会让「流式」退化成一次性响应）。
  - `http.go`：`serveRPC` 前判 `Accept` 含 `text/event-stream` 且 method ∈ {`decode_sse`, `convert_stream`} → 走流式；否则同步路径不变。
  - 客户端断连处理：`r.Context().Done()` 即停止写出，不泄漏 goroutine。
  - 流中途出错：写 `event: error` 帧后收尾（HTTP 头已发出，无法再改状态码——这点需在 ARCHITECTURE §4.5 明确写出）。
  - `ARCHITECTURE.md`：§3.4 与 §4.2.2 统一 `encode_stream` 语义为「返回流式请求 JSON，非事件流」（缺口 H）；§4.5 改为本节实际形状，并标注 `decode_sse_stream` session 模型为 UDS/WS 阶段交付；§9 更新阶段状态。
- [ ] **Step 4: 确认测试通过**
- [ ] **Step 5: 全量验证** 同上

---

## 依赖顺序

```
Task 0（导出对齐 + 新鲜度门禁）  → 必须最先；缺口 D 阻塞 Task 1，缺口 E 让验证不可信
      ↓
Task 1（wrapper 信封 + Convert） → 修复缺口 A/B/C/F；TestServeConvert 在此转绿
      ↓
Task 2（JSON-RPC 信封化 D5）     → 依赖 Task 1 的 Envelope 类型
      ↓
Task 3（HTTP SSE 流式）          → 依赖 Task 2 的 result 形状（流式帧内也是信封）
```

**文件冲突提示：** Task 0 与 Task 2 都改 `wasm/wasm.mbt`；Task 1 与 Task 2 都改 `wrappers/go/prism.go`；Task 2 与 Task 3 都改 `transport/ARCHITECTURE.md`。严格串行执行，一 Task 一 commit。

## 验证命令汇总

| 阶段 | 命令 | 预期 |
|------|------|------|
| 单任务（MoonBit） | `moon test -f "<test_name>"` | FAIL → PASS |
| 单任务（Go） | `moon build --target wasm; cd transport/daemon; go test -count=1 -run <Test> ./` | FAIL → PASS |
| 全量 | `moon fmt --check && moon check --warn-list +73 && moon test && moon build --target wasm` | 0 errors，全绿 |
| 跨语言 | `cd transport/daemon && go test -count=1 ./...`；`cd wrappers/go && go test -count=1 ./...` | 全绿，**无 skip** |
| 接口收尾 | `moon info && moon fmt` | `.mbti` 按预期更新（`wasm` +1 导出、`cmd/main` +4） |

**`-count=1` 不可省**：Go 会缓存测试结果，缓存命中时不会重新加载 WASM 产物 —— 这是缺口 E 能潜伏至今的第二个原因。

## 收尾（全任务完成后）

- [ ] `moon info && moon fmt`，核对 `.mbti` diff。
- [ ] 导出数唯一真值核对：`cmd/main/moon.pkg` exports 项数 == `cmd/main/main.mbt` 的 `pub fn` 数 == `wrappers/go/wasm.go` 映射项数 == 15。README / 路线图中「14 个导出」等表述一并更正（路线图 Phase 4「统一导出数清单」的一部分）。
- [ ] `docs/rules/audit-gaps.md` 记录：`wasm_sdk_decode_sse` / `capability` 无诊断源（形状对齐但恒为空数组），待 SDK 补 `*_with_diagnostics`。
- [ ] `transport/ARCHITECTURE.md` §6 客户端契约同步信封（`clients/*` 未实现，仅改契约描述）。
- [ ] 更新 `.moonbit-pipeline.json`：`phase_name: phase3-transport-http`，`next: plan:phase3b-ipc-ws-clients`。

## 未来演进（不在本轮）

- UDS（Unix）+ Named Pipe（Windows）JSON lines binding，含 `decode_sse_stream` session 模型（D4）
- WebSocket binding
- `clients/go`、`clients/python` 客户端 SDK（ARCHITECTURE §6）
- gRPC binding（ARCHITECTURE §5.4）
- `TransportConfig` 承载 api_key/base_url（Phase 2 计划移出的死字段归宿）

---
