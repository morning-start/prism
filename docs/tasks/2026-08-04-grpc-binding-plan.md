# gRPC binding 实现计划（2026-08-04）

> 来源：`transport/ARCHITECTURE.md` §5.4（protobuf 草案）+ §9 Phase 4（gRPC binding，可选）。
> 前置：Phase 0-3 + phase3b（HTTP/UDS/WS 三传输 daemon + clients/go、clients/python）+ Phase 4 质量收口。
> 目标：为 daemon 增加 gRPC binding（强类型场景，微服务架构），复用 `Backend` 接口与 D5 信封，零新增转换逻辑；`clients/go` 增加 `GRPCTransport` 保持传输可插拔契约。

## 调研结论（2026-08-04 实测）

| # | 事项 | 现状 | 处置 |
|---|------|------|------|
| A | §5.4 已有 protobuf 草案 | `service Prism`：EncodeRequest/DecodeResponse/DecodeSSE/EncodeStream(stream)/Convert/ListProviders/Capability/Ping | **Task 0**：按草案落地 proto 文件（补 ConvertStream、对齐 D5 信封字段） |
| B | Backend 接口可复用 | `transport/daemon/runtime.go` `type Backend interface`（9 方法）与 HTTP/UDS/WS 完全解耦 | gRPC handler 直接调 Backend，零新增转换逻辑 |
| C | D5 信封需在 proto 表达 | HTTP/UDS/WS 均返回 `{value, diagnostics}` 信封；proto message 需定义 `Envelope { value, diagnostics[] }` | **Task 0**：proto 定义 Envelope/Diagnostic/Event，与 §6.1 契约对齐 |
| D | protoc 工具链未安装 | `protoc` / `protoc-gen-go` / `protoc-gen-go-grpc` 均不在 PATH | **Task 0**：`go install google.golang.org/protobuf/cmd/protoc-gen-go@latest` + `google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest`；protoc 本体用 winget/choco 或下载 release 二进制 |
| E | grpc-go 依赖未引入 | daemon go.mod 目前仅 coder/websocket + wrappers/go + wazero | **Task 1**：`go get google.golang.org/grpc` |
| F | 传输可插拔契约已有测试基建 | `clients/go/transport_test.go` 的 `testWithTransports` 已跑 HTTP/UDS/WS 三传输 | **Task 3**：gRPC 加入同一套断言，验证可插拔契约扩展性 |

**范围界定（本轮 Task 0-3）**：protobuf 定义 + 生成代码、gRPC 服务端（同步 + EncodeStream 服务端流式）、`clients/go` GRPCTransport + 可插拔契约测试。
**不在本轮**：客户端 SDK 生成 pipeline（§9 Phase 5）、Daemon MoonBit 原生化（§9 Phase 6）、gRPC 双向流（Prism 语义不需要，流式只有 server→client 方向）。

## 文件结构规划

```
transport/daemon/
├── proto/
│   └── prism.proto           # Create: service Prism + Envelope/Diagnostic/Event messages（§5.4 草案落地）
├── prismpb/                  # Create: protoc 生成代码（protoc-gen-go + protoc-gen-go-grpc）
│   ├── prism.pb.go
│   └── prism_grpc.pb.go
├── grpc.go                   # Create: GRPCServer —— 实现 prismpb.PrismServer，调 Backend
├── grpc_test.go              # Create: 同步 RPC + EncodeStream 流式测试
├── go.mod                    # Modify: + grpc + protobuf 依赖
clients/go/
├── grpc.go                   # Create: GRPCTransport（实现 Transport 接口，Call/Stream）
├── grpc_test.go              # Create: 或并入 transport_test.go 的 testWithTransports
├── go.mod                    # Modify: + grpc 依赖（客户端）
transport/ARCHITECTURE.md     # Modify: §5.4 从「未来」改为「已交付」、§9 Phase 4 标记完成
```

**测试数据原则**（项目约定）：所有进入 `from_json` 的 JSON 由 IR 构造器 `to_json().stringify()` 或适配器编码产生，不手写；daemon 测试沿用「先 `moon build --target wasm` 刷新产物，`go test -count=1`」的新鲜度门禁。

---

## Task 0: proto 定义 + 工具链 + 生成代码

**文件：**
- Create: `transport/daemon/proto/prism.proto`
- Create: `transport/daemon/prismpb/`（生成代码）

**理由：** ARCHITECTURE §5.4 草案是服务骨架，需落地为完整 proto（补 ConvertStream、D5 信封消息、Event 类型，与 §6.1 客户端契约对齐）。

#### Step 1: 写 proto（prism.proto）

```proto
syntax = "proto3";
package prism.transport.v1;

service Prism {
  rpc EncodeRequest(EncodeRequestReq) returns (Envelope);
  rpc DecodeResponse(DecodeResponseReq) returns (Envelope);
  rpc DecodeSSE(DecodeSSEReq) returns (Envelope);
  rpc EncodeStream(EncodeStreamReq) returns (stream Envelope);   // 服务端流式
  rpc Convert(ConvertReq) returns (Envelope);
  rpc ConvertStream(ConvertStreamReq) returns (stream Envelope); // 服务端流式
  rpc ListProviders(Empty) returns (ProviderList);
  rpc Capability(CapabilityReq) returns (Envelope);
  rpc Ping(Empty) returns (Pong);
}

message Envelope { string value = 1; repeated Diagnostic diagnostics = 2; }
message Diagnostic { string field = 1; string status = 2; string detail = 3; }
// 请求/响应 message：与 §6.1 客户端契约字段一一对应
message EncodeRequestReq { string provider = 1; string text = 2; }
message DecodeResponseReq { string provider = 1; string json = 2; }
message DecodeSSEReq { string provider = 1; string sse = 2; }
message EncodeStreamReq { string provider = 1; string text = 2; }
message ConvertReq { string from_provider = 1; string to_provider = 2; string direction = 3; string payload = 4; }
message ConvertStreamReq { string from_provider = 1; string to_provider = 2; string sse = 3; }
message CapabilityReq { string provider = 1; }
message Empty {}
message ProviderList { repeated string providers = 1; }
message Pong { string message = 1; }
```

- [ ] **Step 2: 安装工具链**
  - `go install google.golang.org/protobuf/cmd/protoc-gen-go@latest google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest`
  - protoc 本体：winget/choco 安装或官方 release 二进制（PATH 加入）
- [ ] **Step 3: 生成代码**
  - `protoc -I proto --go_out=. --go_opt=paths=source_relative --go-grpc_out=. --go-grpc_opt=paths=source_relative proto/prism.proto`
- [ ] **Step 4: 确认生成**：`prismpb/prism.pb.go` + `prismpb/prism_grpc.pb.go` 存在且 `go build ./prismpb` 通过
- [ ] **Step 5: 全量验证** `moon fmt --check && moon check && moon test`（WASM 侧零改动）

## Task 1: gRPC 服务端（同步 RPC）

**文件：**
- Create: `transport/daemon/grpc.go`、`transport/daemon/grpc_test.go`
- Modify: `transport/daemon/go.mod`（`go get google.golang.org/grpc`）

**理由：** 复用 `Backend` 接口，每个 gRPC 方法 = Backend 调用 + D5 信封封装；与 HTTP/UDS/WS handler 同构。

#### Step 1: 写会失败的测试（grpc_test.go）

```go
// 启动 in-process gRPC server（bufconn 或真实端口）
// 客户端调 EncodeRequest → 断言 Envelope.value 为合法 provider JSON
// 客户端调 Ping → 断言 pong
// 客户端调 Convert → 断言 diagnostics 存在
// 未知 provider → 断言 error
```

- [ ] **Step 2: 确认测试失败**（预期 FAIL：`prismpb.PrismServer` 未实现）
- [ ] **Step 3: 实现**
  - `grpc.go`：`type GRPCServer struct { prismpb.UnimplementedPrismServer; backend Backend }`，各方法调 backend 并封装 `Envelope{Value, Diagnostics}`
  - 同步方法（EncodeRequest/DecodeResponse/DecodeSSE/EncodeStream/Convert/ListProviders/Capability/Ping）：`backend.Xxx(...)` → `&prismpb.Envelope{...}`
  - 错误映射：backend err → `status.Error(codes.InvalidArgument, err.Error())`
- [ ] **Step 4: 确认测试通过**
- [ ] **Step 5: 全量验证** `moon build --target wasm && cd transport/daemon && go test -count=1 -run GRPC ./`

## Task 2: gRPC 服务端流式（EncodeStream / ConvertStream）

**文件：**
- Modify: `transport/daemon/grpc.go`、`transport/daemon/grpc_test.go`

**理由：** ARCHITECTURE §5.4 草案 EncodeStream 为 server-streaming；Prism 流式语义（decode_sse/convert_stream）在 gRPC 上用 `stream Envelope` 表达，与 HTTP SSE / UDS JSON-lines / WS 多帧语义一致。

#### Step 1: 写会失败的测试

```go
// EncodeStream：调用 → 收到多个 Envelope 帧（逐事件）→ 最后一个为 done
// ConvertStream：同
// 门禁：gRPC 流式事件序列 == HTTP 同步整段解码（复用 buildSSEFixture + decodeWhole）
```

- [ ] **Step 2: 确认测试失败**
- [ ] **Step 3: 实现**
  - `EncodeStream(req, stream prismpb.Prism_EncodeStreamServer)`：调 `backend.EncodeStream` → 解析信封 value（流式请求 JSON 或事件序列）→ 逐帧 `stream.Send`
  - `ConvertStream`：同构；复用现有「整段解码后逐帧写出」策略（与 HTTP/UDS/WS 一致）
- [ ] **Step 4: 确认测试通过**
- [ ] **Step 5: 全量验证** 同上 + `moon test`（WASM 侧零改动）

## Task 3: clients/go GRPCTransport（可插拔契约）

**文件：**
- Create: `clients/go/grpc.go`、`clients/go/grpc_test.go`
- Modify: `clients/go/transport_test.go`（`testWithTransports` 加入 gRPC）

**理由：** ARCHITECTURE §6.1 传输可插拔契约——gRPC 作为第四种 Transport，同一套断言（ping/encode_request/convert/stream/unknown）必须全部通过，验证契约扩展性。

#### Step 1: 写会失败的测试（grpc_test.go）

```go
// startTestDaemon 增加 gRPC listener（bufconn 或 127.0.0.1:0）
// testWithTransports 增加 "grpc": NewGRPCTransport(grpcAddr)
// 现有断言（ping/encode_request/convert/stream_decode_sse/unknown_method）对 gRPC 全跑
```

- [ ] **Step 2: 确认测试失败**（预期 FAIL：`NewGRPCTransport` 未定义）
- [ ] **Step 3: 实现**
  - `clients/go/grpc.go`：`GRPCTransport` 实现 `Transport` 接口（`Call` → 同步 RPC；`Stream` → 服务端流式收集帧）；`Envelope` 从 `prismpb.Envelope` 转换
  - `go.mod`：+ `google.golang.org/grpc` + `google.golang.org/protobuf`（依赖 daemon 的 `prismpb` 或复制 pb 到 clients/go——**决策**：复制生成代码到 `clients/go/prismpb` 避免跨模块 import，与 `wrappers/go` 模式一致）
- [ ] **Step 4: 确认测试通过**（三传输断言 + gRPC 全绿）
- [ ] **Step 5: 全量验证** `cd clients/go && go test -count=1 ./...`

## 依赖顺序

```
Task 0（proto + 工具链 + 生成）→ 必须最先；Task 1/2/3 依赖 pb 代码
    ↓
Task 1（gRPC 服务端同步）→ 依赖 Task 0 的 prismpb
    ↓
Task 2（gRPC 流式）→ 依赖 Task 1 的服务端骨架
    ↓
Task 3（clients/go GRPCTransport）→ 依赖 Task 1/2 的服务端
```

**文件冲突提示：** Task 1 与 Task 2 都改 `grpc.go`/`grpc_test.go`；Task 3 独立于 daemon（clients/go 下）。严格串行执行，一 Task 一 commit。

## 验证命令汇总

| 阶段 | 命令 | 预期 |
|------|------|------|
| 生成代码 | `protoc -I proto ... && go build ./prismpb` | 无错误 |
| 单任务（Go） | `moon build --target wasm && cd transport/daemon && go test -count=1 -run GRPC ./` | FAIL → PASS |
| 客户端 | `cd clients/go && go test -count=1 ./...` | 四传输全绿 |
| 全量（MoonBit） | `moon fmt --check && moon check --warn-list +73 --deny-warn && moon test` | 0 errors，全绿（WASM 侧零改动） |
| 跨语言 | `cd transport/daemon && go test -count=1 ./...` | 全绿 |

## 收尾（全任务完成后）

- [ ] `transport/ARCHITECTURE.md` §5.4 从「gRPC（未来）」改为「已交付」；§9 Phase 4 标记 ✅ 已完成
- [ ] 方法集核对：gRPC 方法 == daemon RPC 方法集 == §6.1 契约（gRPC 是新传输，方法集不变）
- [ ] 更新 `.moonbit-pipeline.json`：`phase_name: grpc-binding`，`next` 指向后续
- [ ] README / docs/sdk-usage.md 补 gRPC 传输示例（如适用）

## 未来演进（不在本轮）

- 客户端 SDK 生成 pipeline（§9 Phase 5：从 api.json 半自动生成 Node/Rust/Java SDK）
- Daemon MoonBit 原生化（§9 Phase 6：MoonBit 网络栈成熟时移除 WASM 间接层）
- gRPC 双向流（当前无需求——Prism 流式只有 server→client 方向）
