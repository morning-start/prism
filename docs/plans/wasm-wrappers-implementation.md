# Prism WASM Wrapper 包实现计划

> TypeScript (Bun) + Python (UV)  
> 日期：2026-07-30

---

## 一、项目结构

在 Prism 单仓库内新增 `wrappers/` 目录：

```
prism/
├── moon.mod                      ← MoonBit 核心（不变）
├── wasm/wasm.mbt                 ← 11 个 WASM 导出函数（不变）
│
├── wrappers/                     ← ← 新增：各语言 wrapper 包
│   ├── ts/                       ← TypeScript (Bun)
│   │   ├── package.json
│   │   ├── tsconfig.json
│   │   ├── src/
│   │   │   ├── index.ts          ← 主入口，导出 PrismClient
│   │   │   ├── client.ts         ← PrismClient 类（~80 行）
│   │   │   ├── types.ts          ← 类型定义（Event, Options 等）
│   │   │   └── wasm.ts           ← WASM 加载 + 底层调用
│   │   ├── test/
│   │   │   └── client.test.ts
│   │   └── prism.wasm            ← CI 编译产物（gitignore 中保留目录）
│   │
│   └── py/                       ← Python (UV)
│       ├── pyproject.toml
│       ├── uv.lock
│       ├── src/
│       │   └── prism_wasm/
│       │       ├── __init__.py   ← 导出 PrismClient
│       │       ├── client.py     ← PrismClient 类
│       │       ├── types.py      ← 类型定义（dataclass + Enum）
│       │       └── wasm.py       ← wasmtime 加载 + 底层调用
│       ├── tests/
│       │   └── test_client.py
│       └── prism.wasm            ← CI 编译产物
│
└── .github/workflows/
    └── release-wrappers.yml      ← ↑ 新增：一键编译 WASM + 发布所有语言包
```

---

## 二、WASM 编译流程

### 2.1 当前状态

```
moon build --target wasm-gc     # 编译到 WASM-GC（MoonBit 首选目标，生态受限）
moon build --target wasm        # 编译到标准 WASM（兼容性好，无 GC 扩展）
```

两种 target 都成功编译（425 测试全通过）。

### 2.2 策略

| 语言 | WASM Runtime | WASM-GC | 标准 WASM | 选择 |
|------|-------------|---------|----------|------|
| **TypeScript (Bun)** | Bun 内置 WebAssembly | V8 ≥119 ✅ | ✅ | **标准 WASM**（兼容最广） |
| **Python** | wasmtime-py | ✅ 实验性 | ✅ | **标准 WASM**（兼容最广） |

**结论**：优先使用 `moon build --target wasm --release` 编译标准 WASM，确保最大兼容性。等 WASM-GC 生态成熟后再切换。

### 2.3 编译脚本

```bash
# 编译标准 WASM（release）
moon build --target wasm --release

# 产物位置需要确认（_build/wasm/release/build/ 下）
# 然后复制到各 wrapper 目录
cp _build/wasm/release/build/prism.wasm wrappers/ts/
cp _build/wasm/release/build/prism.wasm wrappers/py/
```

> ⚠️ 需要先跑一次 `moon build --target wasm --release` 确认产物路径，确保 CI 脚本路径正确。

### 2.4 WASM 导出的 11 个函数签名

```typescript
// 所有函数 String → String，JSON 进 JSON 出
wasm_to_lux_request(provider: string, json_str: string): string
wasm_lux_request_to_provider(provider: string, json_str: string): string
wasm_to_lux_response(provider: string, json_str: string): string
wasm_lux_response_to_provider(provider: string, json_str: string): string
wasm_sse_to_events(provider: string, sse_str: string): string
wasm_events_to_sse(provider: string, json_str: string): string

wasm_sdk_encode_request(provider: string, text: string): string
wasm_sdk_decode_response(provider: string, resp_json: string): string
wasm_sdk_encode_stream(provider: string, text: string): string
wasm_sdk_decode_sse(provider: string, sse_str: string): string
wasm_sdk_capability(provider: string): string
```

---

## 三、Python (UV) Wrapper 详细设计

### 3.1 技术选型

| 项 | 选择 | 理由 |
|---|------|------|
| 包管理器 | **UV** | 用户指定，极速，`pyproject.toml` 原生 |
| WASM runtime | **wasmtime** | 最成熟的 Python WASM 运行时，跨平台 |
| Python 版本 | ≥3.10 | dataclass + Union types |
| 异步 | **同步+异步双模式** | httpx 风格 |
| 测试 | **pytest** | 标准选择 |

### 3.2 包结构

```
wrappers/py/
├── pyproject.toml          ← UV 配置
├── uv.lock                 ← 锁文件
├── README.md
├── src/
│   └── prism_wasm/
│       ├── __init__.py     ← 公开 API
│       ├── client.py       ← PrismClient (sync) + AsyncPrismClient
│       ├── types.py        ← Event, Options, FinishReason dataclass
│       ├── wasm.py         ← wasmtime 加载 + 11 个底层函数
│       └── errors.py       ← PrismError 异常类
├── tests/
│   └── test_client.py
└── prism.wasm             ← CI 复制进来
```

### 3.3 核心 API 设计

```python
# __init__.py
from prism_wasm.client import PrismClient, AsyncPrismClient
from prism_wasm.types import Event, Options, FinishReason

__all__ = ["PrismClient", "AsyncPrismClient", "Event", "Options", "FinishReason"]
```

```python
# types.py
from dataclasses import dataclass, field
from enum import Enum
from typing import Optional

class FinishReason(str, Enum):
    stop = "stop"
    length = "length"
    tool_calls = "tool_calls"
    content_filter = "content_filter"
    error = "error"

@dataclass
class Options:
    model: Optional[str] = None
    temperature: Optional[float] = None
    max_tokens: Optional[int] = None

@dataclass
class Event:
    type: str  # "text_delta" | "tool_call" | "tool_result" | "thinking" | "finish"
    text: Optional[str] = None
    ...
```

```python
# wasm.py — 底层 WASM 调用封装
import wasmtime
from pathlib import Path

class WasmRuntime:
    """封装 wasmtime 加载 + 11 个底层函数调用"""
    
    _instance = None  # 单例，避免重复加载
    
    @classmethod
    def load(cls, wasm_path: str | Path | bytes) -> "WasmRuntime":
        """加载 WASM 模块（只加载一次）"""
        ...
    
    def call(self, func_name: str, *args: str) -> str:
        """调用 WASM 导出函数"""
        ...

# 11 个底层函数（每个 ~3 行）
def wasm_to_lux_request(provider: str, json_str: str) -> str: ...
def wasm_sdk_encode_request(provider: str, text: str) -> str: ...
# ... 以此类推
```

```python
# client.py — 高层 API
from prism_wasm.types import Event, Options, FinishReason
from prism_wasm.wasm import WasmRuntime

class PrismClient:
    def __init__(self, wasm_bytes: bytes):
        self._wasm = WasmRuntime.load(wasm_bytes)
    
    def encode_request(self, provider: str, text: str, opts: Optional[Options] = None) -> str:
        """文本 → 厂商请求 JSON"""
        # 构造 opts JSON
        opts_json = json.dumps(opts.to_dict()) if opts else "{}"
        # 调用底层 WASM 函数（需要确认 SDK 函数是否接受 opts）
        result = self._wasm.call("wasm_sdk_encode_request", provider, text)
        ...
    
    def decode_response(self, provider: str, json_str: str) -> str:
        """厂商响应 JSON → 文本"""
        ...
    
    def decode_sse(self, provider: str, sse_str: str) -> list[Event]:
        """厂商 SSE → Event 列表"""
        ...
    
    def list_providers(self) -> list[str]:
        """列出所有可用 provider"""
        ...

class AsyncPrismClient:
    """异步版本，API 签名与 PrismClient 一致"""
    ...

# 使用示例
client = PrismClient(Path("prism.wasm").read_bytes())
req = client.encode_request("openai", "你好")
# 一行切换 provider
req = client.encode_request("anthropic", "写一首诗")
```

### 3.4 测试策略

```python
# tests/test_client.py
import pytest
from prism_wasm import PrismClient, Event, FinishReason

WASM_PATH = Path(__file__).parent.parent / "prism.wasm"

@pytest.fixture
def client():
    return PrismClient(WASM_PATH.read_bytes())

def test_encode_request_openai(client):
    result = client.encode_request("openai", "你好")
    assert '"model"' in result
    assert '"messages"' in result
    assert '"user"' in result

def test_encode_request_anthropic(client):
    result = client.encode_request("anthropic", "你好")
    assert '"model"' in result
    assert '"messages"' in result

def test_decode_response_openai(client):
    resp = '{"choices":[{"message":{"content":"你好！"}}]}'
    text = client.decode_response("openai", resp)
    assert text == "你好！"
```

### 3.5 发布配置

```toml
# pyproject.toml
[project]
name = "prism-wasm"
version = "0.1.0"
description = "Prism LLM protocol converter - universal WASM wrapper"
requires-python = ">=3.10"
dependencies = ["wasmtime>=20.0.0"]

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[tool.uv]
dev-dependencies = ["pytest>=8.0"]
```

---

## 四、TypeScript (Bun) Wrapper 详细设计

### 4.1 技术选型

| 项 | 选择 | 理由 |
|---|------|------|
| 运行时 | **Bun** | 用户指定，内置 WebAssembly + TS 原生 |
| WASM API | 内置 `WebAssembly` | 无需额外依赖 |
| 包管理器 | **Bun** | `bun add` / `bun publish` |
| 测试 | **Bun test** | 内置，零配置 |
| 发布 | **npm** | `bun publish` 直接发 npm |

### 4.2 包结构

```
wrappers/ts/
├── package.json
├── tsconfig.json
├── README.md
├── src/
│   ├── index.ts          ← 公开 API
│   ├── client.ts         ← PrismClient 类
│   ├── types.ts          ← 类型定义
│   └── wasm.ts           ← WASM 加载 + 底层调用
├── test/
│   └── client.test.ts
└── prism.wasm            ← CI 复制进来
```

### 4.3 核心 API 设计

```typescript
// types.ts
export interface PrismOptions {
  model?: string;
  temperature?: number;
  max_tokens?: number;
}

export type FinishReason = "stop" | "length" | "tool_calls" | "content_filter" | "error";

export interface TextDeltaEvent {
  type: "text_delta";
  text: string;
}

export interface FinishEvent {
  type: "finish";
  reason: FinishReason;
}

export type PrismEvent = TextDeltaEvent | FinishEvent | ToolCallEvent | ToolResultEvent | ThinkingEvent;
```

```typescript
// wasm.ts — 底层 WASM 调用封装
import { readFileSync } from "fs";

let _instance: WebAssembly.Instance | null = null;

export function loadWasm(wasmBytes: BufferSource): WebAssembly.Instance {
  if (_instance) return _instance;
  // Bun 使用 V8 内置 WebAssembly API
  const module = new WebAssembly.Module(wasmBytes);
  _instance = new WebAssembly.Instance(module);
  return _instance;
}

export function callWasm(funcName: string, ...args: string[]): string {
  const inst = _instance!;
  const fn = inst.exports[funcName as keyof WebAssembly.Exports] as CallFunction;
  return fn(...args) as string;
}
```

```typescript
// client.ts — 高层 API
import { loadWasm, callWasm } from "./wasm.js";
import type { PrismOptions, PrismEvent } from "./types.js";

export class PrismClient {
  private loaded: boolean = false;

  constructor(wasmBytes: BufferSource) {
    loadWasm(wasmBytes);
    this.loaded = true;
  }

  /** 文本 → 厂商请求 JSON */
  encodeRequest(provider: string, text: string, opts?: PrismOptions): string {
    // TODO: 处理 opts 参数（当前 WASM SDK 层用默认值）
    return callWasm("wasm_sdk_encode_request", provider, text);
  }

  /** 厂商响应 JSON → 文本 */
  decodeResponse(provider: string, jsonStr: string): string {
    return callWasm("wasm_sdk_decode_response", provider, jsonStr);
  }

  /** 厂商 SSE → PrismEvent 数组 */
  decodeSSE(provider: string, sseStr: string): PrismEvent[] {
    const result = callWasm("wasm_sdk_decode_sse", provider, sseStr);
    return JSON.parse(result);
  }

  /** 列出所有 provider */
  listProviders(): string[] {
    // 通过 wasm_sdk_capability + 内部注册表获取
    // 或用 wasm_to_lux_request 测试各 provider
    return ["openai", "openai-chat", "anthropic", "gemini", "azure-openai"];
  }
}

// 使用示例
import { PrismClient } from "@morning-start/prism-wasm";
import { readFileSync } from "fs";

const client = new PrismClient(readFileSync("prism.wasm"));
const req = client.encodeRequest("openai", "你好");
console.log(req);
```

### 4.4 测试策略

```typescript
// test/client.test.ts
import { describe, expect, test } from "bun:test";
import { PrismClient } from "../src/index.ts";
import { readFileSync } from "fs";

const wasmBytes = readFileSync(import.meta.dir + "/../prism.wasm");

describe("PrismClient", () => {
  test("encode_request openai", () => {
    const client = new PrismClient(wasmBytes);
    const result = client.encodeRequest("openai", "你好");
    expect(result).toContain("model");
    expect(result).toContain("messages");
  });

  test("decode_response openai", () => {
    const client = new PrismClient(wasmBytes);
    const resp = JSON.stringify({
      choices: [{ message: { content: "你好！" }, finish_reason: "stop" }]
    });
    const text = client.decodeResponse("openai", resp);
    expect(text).toBe("你好！");
  });

  test("decode_sse anthropic", () => {
    const client = new PrismClient(wasmBytes);
    const sse = 'data: {"type":"content_block_delta","delta":{"text":"你好"}}\n\ndata: [DONE]';
    const events = client.decodeSSE("anthropic", sse);
    expect(events.length).toBeGreaterThan(0);
  });
});
```

### 4.5 发布配置

```json
{
  "name": "@morning-start/prism-wasm",
  "version": "0.1.0",
  "type": "module",
  "main": "dist/index.js",
  "types": "dist/index.d.ts",
  "files": ["dist/", "prism.wasm"],
  "scripts": {
    "build": "bun build ./src/index.ts --outdir=dist --target=bun",
    "test": "bun test",
    "prepublish": "bun run build && bun run test"
  },
  "devDependencies": {
    "@types/bun": "latest"
  }
}
```

---

## 五、实现步骤（任务分解）

### Step 1：确认 WASM 编译产物路径

```bash
moon build --target wasm --release
# 找到 .wasm 产物位置，确认导出的 11 个函数名正确
```

**产出**：CI 脚本中正确的 WASM 产物复制路径

---

### Step 2：实现 Python wrapper

| 子任务 | 文件 | 代码量 | 依赖 |
|-------|------|:------:|------|
| 2.1 初始化项目 | `pyproject.toml`, `uv.lock` | 配置 | UV |
| 2.2 类型定义 | `src/prism_wasm/types.py` | ~40 行 | 无 |
| 2.3 WASM 加载层 | `src/prism_wasm/wasm.py` | ~60 行 | wasmtime |
| 2.4 PrismClient（同步） | `src/prism_wasm/client.py` | ~80 行 | 无 |
| 2.5 AsyncPrismClient | `src/prism_wasm/client.py`（追加） | ~30 行 | 无 |
| 2.6 异常定义 | `src/prism_wasm/errors.py` | ~15 行 | 无 |
| 2.7 公开 API | `src/prism_wasm/__init__.py` | ~10 行 | 无 |
| 2.8 测试 | `tests/test_client.py` | ~60 行 | pytest |
| 2.9 文档 | `README.md` | ~30 行 | 无 |

**合计**：**~9 文件，~325 行**

---

### Step 3：实现 TypeScript wrapper

| 子任务 | 文件 | 代码量 | 依赖 |
|-------|------|:------:|------|
| 3.1 初始化项目 | `package.json`, `tsconfig.json` | 配置 | Bun |
| 3.2 类型定义 | `src/types.ts` | ~50 行 | 无 |
| 3.3 WASM 加载层 | `src/wasm.ts` | ~30 行 | 无 |
| 3.4 PrismClient | `src/client.ts` | ~80 行 | 无 |
| 3.5 公开 API | `src/index.ts` | ~10 行 | 无 |
| 3.6 测试 | `test/client.test.ts` | ~50 行 | Bun test |
| 3.7 构建脚本 | `bunfig.toml`（可选） | 配置 | Bun |
| 3.8 文档 | `README.md` | ~30 行 | 无 |

**合计**：**~8 文件，~250 行**

---

### Step 4：CI/CD 流水线

| 子任务 | 文件 | 说明 |
|-------|------|------|
| 4.1 WASM 编译 + 复制 | `.github/workflows/release-wrappers.yml` | `moon build → cp` |
| 4.2 Python 测试 + 发布 | 同上 | `uv run pytest → uv publish` |
| 4.3 TS 测试 + 发布 | 同上 | `bun test → bun publish` |

---

## 六、各层 API 对照

为了保证跨语言一致性，三种语言的 API 签名保持一致：

| 功能 | MoonBit (原生) | Python | TypeScript |
|------|--------------|--------|------------|
| 创建实例 | `Prism::new().with_provider("openai")` | `PrismClient(wasm_bytes)` | `new PrismClient(wasm_bytes)` |
| 编码请求 | `.encode_request(text, opts)` | `.encode_request(provider, text, opts?)` | `.encodeRequest(provider, text, opts?)` |
| 解码响应 | `.decode_response(json_str)` | `.decode_response(provider, json_str)` | `.decodeResponse(provider, jsonStr)` |
| 解码 SSE | `.decode_sse(sse_str)` | `.decode_sse(provider, sse_str)` | `.decodeSSE(provider, sseStr)` |
| 编码流 | `.encode_stream_request(text, opts)` | `.encode_stream(provider, text, opts?)` | `.encodeStream(provider, text, opts?)` |
| 能力查询 | `.capability(provider_name)` | `.capability(provider)` | `.capability(provider)` |
| 列表 provider | — | `.list_providers()` | `.listProviders()` |

---

## 七、关键决策点

### 7.1 WASM SDK 函数当前缺少 opts 参数

当前 `wasm_sdk_encode_request` 的签名是：

```moonbit
pub fn wasm_sdk_encode_request(provider : String, text : String) -> String {
  let prism = @sdk.Prism::new().with_provider(provider)
  match prism.encode_request(text, @sdk.PrismOptions::default()) {
```

它**硬编码了 `PrismOptions::default()`**，不接受 opts 参数。需要先改造 WASM 层，让 opts 也能传入：

```moonbit
// 改造后
pub fn wasm_sdk_encode_request(provider : String, text : String, opts_json : String) -> String
```

**是否改造**：可以先不改，第一版用默认参数。后续再支持 opts 透传。

### 7.2 WASM 文件大小

当前 WASM 文件大小需确认。如果太大（>1MB），可以考虑：
- 编译时 `--release` 减少体积
- 分拆为 slim 版本（仅核心转换，不含 SDK 层）

### 7.3 错误处理策略

WASM 导出函数在错误时返回 `{"error": "message"}` 格式。wrapper 层需要：
1. 检查返回字符串是否以 `{"error"` 开头
2. 如果是，解析出错误消息并抛出语言原生异常（Python `PrismError` / TS `PrismError`）

---

## 八、时间估算

| 步骤 | 内容 | 预估 |
|:----:|------|:----:|
| 1 | 确认 WASM 产物路径 | 0.5h |
| 2 | Python wrapper 全量实现 | **4h** |
| 3 | TypeScript wrapper 全量实现 | **3h** |
| 4 | CI/CD 配置 | **1h** |
| 5 | 测试 + 修复 | **2h** |
| | **总计** | **~2 天（10.5h）** |

---

## 九、MoonBit WASM 导出限制

### 9.1 已知问题

**MoonBit 0.1.20260713（当前版本）不支持将 `pub fn` 暴露为 WASM exports。**

| 构建方式 | 结果 |
|---------|------|
| `moon build --target wasm-gc` (library) | 产生 `.core`/`.mi` 中间文件，无 `.wasm` |
| `moon build --target wasm-gc` (executable) | 产生 `.wasm`，但仅导出 `_start` |
| `moon test --target wasm-gc` | 按需生成 `.wasm`，函数编译在内但无 export section |

**影响**：两个 wrapper 包的 WASM 加载层代码已编写完成且语法正确，但实际的 `wasm_*` 函数调用无法通过 WASM export 访问。一旦 MoonBit 工具链添加 WASM exports 支持，wrapper 包即可直接工作，无需修改代码。

### 9.2 临时替代方案

在 MoonBit 支持 WASM exports 之前，有以下替代方案：

1. **MoonBit JS 目标**：使用 `moon build --target js` 编译为 JavaScript，通过 JS 桥接层在各语言中调用
2. **Go wazero 中间层**：编写一个极薄的 Go 程序，用 wazero 加载 MoonBit WASM 并通过 Go 的 C ABI 或 HTTP 暴露函数
3. **直接集成**：在 Go 项目中直接使用 MoonBit 的 Go SDK（`import prism` 的方式）

## 十、构建与测试

### Python (UV) wrapper

```bash
# 安装依赖
cd wrappers/py
uv sync

# 运行测试
uv run pytest -v
```

### TypeScript (Bun) wrapper

```bash
# 安装依赖
cd wrappers/ts
bun install

# 运行测试
bun test
```

### 编译 WASM 并更新 wrapper

```bash
# 编译 WASM-GC 目标
moon build --target wasm-gc

# 复制 WASM 文件到 wrapper 目录
cp _build/wasm-gc/debug/build/cmd/main/main.wasm wrappers/py/prism.wasm
cp _build/wasm-gc/debug/build/cmd/main/main.wasm wrappers/ts/prism.wasm
```

## 十一、注意事项

1. **WASM 文件不 gitignore** — wrapper 包需要包含 `prism.wasm` 文件才能独立安装使用。可以在 CI 中编译后自动更新。
2. **版本对齐** — wrapper 包版本与 Prism 主版本保持一致，用 `0.1.x` 系列。
3. **开发流程** — 修改 MoonBit 核心后 → `moon build` → 覆盖 `wrappers/*/prism.wasm` → 在 wrapper 目录运行测试。
4. **Bun 的 WebAssembly** — Bun 使用 V8 引擎，对标准 WASM 支持良好。
5. **UV 的 wasmtime** — `wasmtime-py` 支持标准 WASM，跨平台（Win/Mac/Linux），不需额外二进制。
