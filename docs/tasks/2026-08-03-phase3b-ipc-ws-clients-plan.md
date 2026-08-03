# Phase 3b Transport 扩展实现计划（UDS / Named Pipe / WebSocket / Clients）（2026-08-03）

> 来源：`docs/plans/2026-08-01-project-roadmap.md` Phase 3 + `transport/ARCHITECTURE.md` §4.5/§5.2/§5.3/§6/§9。
> 前置：Phase 3（Task 0-3）已完成——HTTP JSON-RPC + SSE 流式 + D5 信封。
> 决策：D4 = UDS（Linux/macOS）+ Named Pipe（Windows）；D7 = `decode_sse_stream` 会话式逐块解码在本阶段交付（依赖全双工）。
> 目标：把「HTTP 先行」演进为多传输形态（UDS/Named Pipe/WebSocket），并交付 `clients/go`、`clients/python` 客户端 SDK；复用现有 `ServeRPC`/`Backend`，零新增转换逻辑。

## 调研结论（2026-08-03 基于源码与架构文档）

| # | 事项 | 现状 | 处置 |
|---|------|------|------|
| A | daemon 分发已传输无关 | `transport/daemon/http.go` 的 `ServeHTTP` 只做「路由 + 解码 JSON-RPC → `ServeRPC(ctx, backend, req)`」；`ServeRPC`（`dispatcher.go`）已与 HTTP 解耦 | **UDS/WS 直接复用 `ServeRPC`**，只需新传输前端 |
| B | D5 信封已统一 | `envelopeResult` / `wrapEnvelope`（`dispatcher.go`）产出 `{value, diagnostics}`；流式帧用 `rpcEnvelope`（`stream.go`） | UDS/WS 流式沿用同形信封 |
| C | Backend 接口已抽象 | `runtime.go` `type Backend interface`（EncodeRequest/DecodeResponse/…），首个实现是 WASM（wrappers/go）；原生/远程后端是未来替换点 | 传输层只依赖 `Backend`，天然可插拔 |
| D | `decode_sse_stream` 未实现 | ARCHITECTURE §4.5：session + notification 模型，依赖全双工；HTTP 单请求单响应已用「一次 POST + SSE 响应」替代（D7 记录） | 本阶段在 UDS/WS 上实现 session 模型 |
| E | 客户端 SDK 未建 | `wrappers/go`（信封已解析）与 `wrappers/python` 存在但为「薄 wrapper」；ARCHITECTURE §6.1 定义了跨语言公共接口契约（`Transport` 可插拔） | 升级为正式 `clients/*`，实现 `Transport` 接口 + 统一方法集 |
| F | WebSocket 无依赖 | `go.mod` 目前仅标准库 + wazero；WS 服务端需第三方库（Go 标准库无 WS 服务端） | 引入轻量 WS 库（候选见 Task 2） |

**范围界定（本轮 Task 0-4）**：UDS（Linux/macOS）+ Named Pipe（Windows）+ WebSocket binding + `decode_sse_stream` session 模型 + `clients/go` + `clients/python`。
**不在本轮**：gRPC binding（ARCHITECTURE §5.4）、客户端 SDK 生成 pipeline（§9 Phase 5）、Daemon MoonBit 原生化（§9 Phase 6）。

## 文件结构规划

```
transport/daemon/
├── http.go                   # 现有：HTTPHandler（POST /v1 + GET /health + SSE）
├── uds.go                    # Create: UDS/Named Pipe listener（JSON lines，复用 ServeRPC）
├── uds_test.go               # Create: JSON lines 请求/响应/流式测试
├── ws.go                     # Create: WebSocket handler（每帧一个 JSON-RPC 消息）
├── ws_test.go                # Create: WS 同步/流式测试
├── session.go                # Create: decode_sse_stream session 管理（逐块解码，全双工）
├── session_test.go           # Create: session 生命周期/逐块事件测试
clients/
├── go/
│   ├── go.mod                # Create: 正式 Go SDK 模块
│   ├── transport.go          # Create: Transport 接口（HTTP/UDS/WS 三实现）
│   ├── client.go             # Create: Client 统一方法集（encode/decode/convert/…）
│   └── transport_test.go     # Create: 传输可插拔测试（同一测试跑三种 transport）
├── python/
│   ├── pyproject.toml        # Create: Python SDK 包
│   ├── prism/
│   │   ├── __init__.py
│   │   ├── transport.py      # Create: Transport 抽象（HTTP/UDS/WS）
│   │   └── client.py         # Create: PrismClient 统一接口
│   └── tests/
│       └── test_transport.py # Create: 三种传输契约测试
transport/ARCHITECTURE.md     # Modify: §9 阶段状态更新（Phase 2/3 完成）、§4.5 标记实现
```

**测试数据原则**（项目约定）：所有进入 `from_json` 的 JSON 由 IR 构造器 `to_json().stringify()` 或适配器编码产生，不手写；daemon 测试沿用「先 `moon build --target wasm` 刷新产物，`go test -count=1`」的新鲜度门禁（Phase 3 缺口 E 教训，`-count=1` 不可省）。

---

## Task 0: UDS / Named Pipe binding（JSON lines）

**文件：**
- Create: `transport/daemon/uds.go`、`transport/daemon/uds_test.go`
- Modify: `transport/daemon/cmd/prism-daemon/main.go`（新增 `--uds /tmp/prism.sock` 与 `--pipe \\.\pipe\prism` 启动参数）

**理由：** ARCHITECTURE §5.2 已定义协议（`\n` 分隔 JSON lines，同步请求即写回、流式按住连接直到流结束）；复用 `ServeRPC` 零新增转换逻辑。

#### Step 1: 写会失败的测试（uds_test.go）

```go
// 启动 UDS listener（临时 sock 路径）
// 客户端写入: {"jsonrpc":"2.0","id":1,"method":"ping","params":{}}
// 断言读回:   {"jsonrpc":"2.0","id":1,"result":{"value":"pong","diagnostics":[]}}
```

- [ ] **Step 2: 确认测试失败**（预期 FAIL：`ListenUDS` 未实现）
- [ ] **Step 3: 实现**
  - `ListenUDS(ctx, backend, sockPath, version)`：`net.Listen("unix", sockPath)` + `umask 077`（仅本用户可访问）；每个连接一个 goroutine，`bufio.Scanner` 按行读请求 → `ServeRPC` → 按行写响应
  - Named Pipe：Windows 上用 `npipe`（`github.com/Microsoft/go-winio`）监听 `\\.\pipe\prism`，协议与 UDS 相同（编译时 `//go:build windows` 分支）
  - 流式请求（`decode_sse`/`convert_stream` 带流式意图）：按住连接，逐事件写行，`done` 帧收尾
- [ ] **Step 4: 确认测试通过**
- [ ] **Step 5: 全量验证** `moon build --target wasm && cd transport/daemon && go test -count=1 -run UDS ./`

## Task 1: 复用 ServeRPC 的流式通路校验（UDS 逐事件）

**文件：**
- Modify: `transport/daemon/uds.go`（流式分支细化）
- Test: `transport/daemon/uds_test.go`

**理由：** Task 0 打通同步；本任务确保 UDS 流式与 HTTP SSE 语义一致（`TestFrameByFrameEqualsWholeText` 同款门禁移植到 UDS 路径）。

#### Step 1: 写会失败的测试

```go
// UDS 流式：decode_sse 请求 → 逐行读回事件帧，断言与整段解码结果逐帧相等
// （移植 Phase 3 Task 3 的 TestFrameByFrameEqualsWholeText 到 UDS）
```

- [ ] **Step 2: 确认测试失败**
- [ ] **Step 3: 实现**：UDS 流式分支复用 `splitSSEFrames`（`stream.go`）+ `rpcEnvelope`，逐帧写行
- [ ] **Step 4: 确认测试通过**
- [ ] **Step 5: 全量验证** 同上

## Task 2: WebSocket binding

**文件：**
- Create: `transport/daemon/ws.go`、`transport/daemon/ws_test.go`
- Modify: `transport/daemon/cmd/prism-daemon/main.go`（新增 `--ws :8765` 启动参数）
- Modify: `transport/daemon/go.mod`（新增 WS 库依赖）

**理由：** ARCHITECTURE §5.3：`ws://127.0.0.1:8765/ws`，每帧一个完整 JSON-RPC 消息，原生支持流式。Go 标准库无 WS 服务端，需第三方库。

#### Step 1: 写会失败的测试（ws_test.go）

```go
// httptest + WS 客户端（candidate 库自带或 golang.org/x/net/websocket）
// 同步: encode_request 请求帧 → result 帧
// 流式: decode_sse 请求帧 → 多帧事件 → done 帧
```

- [ ] **Step 2: 确认测试失败**（预期 FAIL：`ServeWS` 未实现）
- [ ] **Step 3: 实现**
  - 引入 WS 库：**候选** `github.com/coder/websocket`（现代、零依赖、context 友好）或 `github.com/gorilla/websocket`（最广泛）；选型依据：context 取消传播 + 测试便利
  - `ServeWS(w, r)`：标准 HTTP Upgrade → 每收到一帧 JSON-RPC 请求 → `ServeRPC` → 写回一帧；流式请求逐帧写事件帧 + `done` 帧
- [ ] **Step 4: 确认测试通过**
- [ ] **Step 5: 全量验证** 同上

## Task 3: `decode_sse_stream` session 模型（逐块解码，全双工）

**文件：**
- Create: `transport/daemon/session.go`、`transport/daemon/session_test.go`
- Modify: `transport/daemon/ws.go` / `uds.go`（全双工传输接入 session）
- Modify: `transport/ARCHITECTURE.md`（§4.5 标记实现状态，从「留待 phase3b」改为「已交付」）

**理由：** D7 明确本阶段交付。ARCHITECTURE §4.5 定义了 session + notification 模型：`decode_sse_stream(provider)` 返回 `SseSession`，客户端逐块喂 SSE、逐块收 PrismEvent——依赖全双工（UDS/WS 均满足），HTTP 不具备。

#### Step 1: 写会失败的测试（session_test.go）

```go
// 1. 创建 session → 返回 session id
// 2. 客户端分块喂 SSE（第 1 块不完整帧，第 2 块补全）
// 3. 断言服务端逐块返回事件（帧间状态：块索引/工具参数拼接不破坏）
// 4. close session → 后续请求报错
```

- [ ] **Step 2: 确认测试失败**（预期 FAIL：`decode_sse_stream` 方法不存在）
- [ ] **Step 3: 实现**
  - `session.go`：`SessionManager` 维护 `map[sessionID]*SseSession`；session 内累积 SSE 文本，逐块调 `backend.DecodeSSE` 全量解码后 diff（沿用 Phase 3 的「整段解码保证正确性」策略，或按块增量——以 `TestFrameByFrameEqualsWholeText` 门禁为准）
  - WS 帧承载：`{"jsonrpc":"2.0","id":1,"method":"decode_sse_stream","params":{"provider":...}}` → `{"session":"sse-001"}`；后续 `{"method":"sse_feed","params":{"session":"sse-001","chunk":"..."}}` 逐块；服务端 notification 帧推送事件
- [ ] **Step 4: 确认测试通过**
- [ ] **Step 5: 全量验证** 同上 + `moon test`（确认 WASM 侧零改动）

## Task 4: clients/go 正式客户端 SDK

**文件：**
- Create: `clients/go/go.mod`、`transport.go`、`client.go`、`transport_test.go`

**理由：** ARCHITECTURE §6.1/6.2：跨语言公共接口 + `Transport` 可插拔（HTTP/UDS/WS 一行切换）；现有 `wrappers/go` 是薄 wrapper，升级为正式 SDK。

#### Step 1: 写会失败的测试（transport_test.go）

```go
// 同一套断言函数分别以 HTTPTransport / UDSTransport / WSTransport 运行：
//   encode_request → 信封解析 → value 为合法 provider JSON
//   convert → 信封 + diagnostics
//   ping → "pong"
// 断言「三种传输行为一致」（可插拔契约）
```

- [ ] **Step 2: 确认测试失败**（预期 FAIL：`clients/go` 包不存在）
- [ ] **Step 3: 实现**
  - `Transport` 接口：`Call(ctx, method, params) (Envelope, error)` + `Stream(ctx, method, params) (<-chan Envelope, error)`
  - `HTTPTransport`：复用现有 JSON-RPC POST + SSE 解析；`UDSTransport`：JSON lines；`WSTransport`：帧
  - `Client`：`EncodeRequest/DecodeResponse/DecodeSSE/Convert/ConvertStream/ListProviders/Capability/Ping`，统一解析 D5 信封
- [ ] **Step 4: 确认测试通过**
- [ ] **Step 5: 全量验证** `cd clients/go && go test -count=1 ./...`（daemon 需先启动或测试内嵌起 listener）

## Task 5: clients/python 客户端 SDK

**文件：**
- Create: `clients/python/pyproject.toml`、`prism/__init__.py`、`prism/transport.py`、`prism/client.py`、`tests/test_transport.py`

**理由：** ARCHITECTURE §6.3：Python SDK 异步接口 + 传输可插拔。

#### Step 1: 写会失败的测试（test_transport.py）

```python
# 同一套断言以 HTTP / UDS 两种 transport 运行：
#   client.encode_request(...) → 信封 → value 为合法 JSON
#   client.convert(...) → diagnostics 可读
#   async stream: async for event in client.decode_sse_stream(...)
```

- [ ] **Step 2: 确认测试失败**（预期 FAIL：`prism` 包不存在）
- [ ] **Step 3: 实现**：`Transport` 抽象（HTTP 用 `httpx`，UDS 用 `socket` 原生 JSON lines，WS 用 `websockets`）；`PrismClient` 统一方法集 + 信封解析
- [ ] **Step 4: 确认测试通过**
- [ ] **Step 5: 全量验证** `cd clients/python && python -m pytest tests/`

## 依赖顺序

```
Task 0（UDS/Named Pipe 同步）→ 先落地 JSON lines 基础
    ↓
Task 1（UDS 流式）→ 依赖 Task 0 的 listener + ServeRPC 复用
    ↓
Task 2（WebSocket）→ 独立于 Task 0/1，可并行；但与 Task 3 共用流式帧形状
    ↓
Task 3（decode_sse_stream session）→ 依赖 Task 1 流式通路 + Task 2 全双工载体
    ↓
Task 4/5（clients/go、clients/python）→ 依赖 Task 0-3 的三种传输后端（可插拔契约测试需要三种 transport 齐备）
```

**并行提示：** Task 0/1/2 是 Go daemon 内部工作，Task 4/5 依赖其稳定契约；Task 0↔2 无文件冲突（uds.go vs ws.go），可并行但受 agent 单线程限制——严格串行执行，一 Task 一 commit。

## 验证命令汇总

| 阶段 | 命令 | 预期 |
|------|------|------|
| 单任务（Go） | `moon build --target wasm && cd transport/daemon && go test -count=1 -run <Test> ./` | FAIL → PASS（**`-count=1` 不可省**，避免 Go 缓存吃 stale WASM） |
| 单任务（Python） | `cd clients/python && python -m pytest tests/ -k <name>` | FAIL → PASS |
| 全量（MoonBit） | `moon fmt --check && moon check && moon test` | 0 errors，全绿（WASM 侧应零改动） |
| 跨语言 | `cd transport/daemon && go test -count=1 ./...`；`cd clients/go && go test -count=1 ./...`；`cd clients/python && python -m pytest tests/` | 全绿，无 skip |
| 接口收尾 | `moon info && moon fmt` | `.mbti` 无变化（本轮不动 MoonBit 侧） |

## 收尾（全任务完成后）

- [ ] `transport/ARCHITECTURE.md` §9 阶段状态更新：Phase 2（UDS + Python SDK）、Phase 3（WS + 流式完善 + decode_sse_stream）标记完成
- [ ] `transport/ARCHITECTURE.md` §4.5 `decode_sse_stream` 从「留待 phase3b」改为「已交付（session + notification）」
- [ ] 导出数/方法数唯一真值核对：daemon RPC 方法集 == `clients/go` Client 方法集 == `clients/python` PrismClient 方法集 == ARCHITECTURE §6.1 契约
- [ ] 更新 `.moonbit-pipeline.json`：`phase_name: phase3b-ipc-ws-clients`，`next` 指向后续
- [ ] README / docs/sdk-usage.md 补充「传输可插拔」使用示例

## 未来演进（不在本轮）

- gRPC binding（ARCHITECTURE §5.4，protobuf 强类型，与 UDS/WS 正交可并行）
- 客户端 SDK 生成 pipeline（§9 Phase 5：从 api.json 半自动生成 Node/Rust/Java SDK）
- Daemon MoonBit 原生化（§9 Phase 6：MoonBit 网络栈成熟时移除 WASM 间接层）
- `RemoteBackend` / `ProcessBackend`（§7.2：分布式部署与本地进程后端）
