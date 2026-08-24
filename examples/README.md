# Prism Examples

本目录包含 Prism SDK 的使用示例，展示如何进行协议转换测试。

---

## 目录结构

```
src/examples/           # MoonBit 示例（源码根 src/ 下）
├── sdk-basic/          # MoonBit SDK 示例
│   ├── moon.pkg        # 包配置
│   ├── main.mbt        # 主程序
│   └── main_wbtest.mbt # 测试文件
│
examples/               # 其余示例
├── ts-wasm/            # TypeScript WASM 示例（真实 API）
│   ├── package.json    # 项目配置
│   ├── .env            # 环境变量（API Key）
│   ├── .env.example    # 环境变量示例
│   └── src/
│       ├── main.ts     # 主程序（真实 API 测试）
│       ├── test-e2e.ts     # 端到端真实测试
│       ├── test-wasm.ts    # WASM 功能测试
│       └── test-env.ts     # 环境变量测试
│
└── README.md           # 本文件
```

---

## 快速开始

### 1. MoonBit SDK 示例

**运行示例：**
```bash
# 在项目根目录
moon run src/examples/sdk-basic
```

**运行测试：**
```bash
moon test -p morning-start/prism/examples/sdk-basic
```

**示例内容：**
- 支持的 Provider 列表
- OpenAI Chat 能力查询
- 编码请求 (文本 → JSON)
- 解码响应 (JSON → 文本)
- SSE 流式解码
- 协议转换 (OpenAI Chat → Anthropic/Gemini)

---

### 2. TypeScript WASM 示例（真实 API）

**安装依赖：**
```bash
cd examples/ts-wasm
bun install
```

**配置环境变量：**

编辑 `.env` 文件：
```bash
BASE_URL=https://apihub.agnes-ai.com/v1
API_KEY=sk-your-api-key-here
MODEL_ID=agnes-2.5-flash
```

**运行端到端真实测试（推荐）：**
```bash
bun run test:e2e
```

**运行主程序：**
```bash
bun run src/main.ts
```

**运行 WASM 功能测试（不需要 API）：**
```bash
bun run test
```

**运行环境变量测试：**
```bash
bun run test:env
```

**运行所有测试：**
```bash
bun run test:all
```

---

## 测试内容

### MoonBit SDK 测试

| 测试项 | 说明 |
|--------|------|
| 编码请求 | 文本 → OpenAI Chat JSON |
| 解码响应 | OpenAI Chat JSON → 文本 |
| SSE 流式解码 | SSE 事件流 → 事件数组 |
| 协议转换 | OpenAI Chat → Anthropic/Gemini |
| 能力查询 | 查询 Provider 支持的能力 |

### TypeScript WASM 测试

| 测试项 | 说明 |
|--------|------|
| 端到端真实测试 | 编码 → 发送 → 接收 → 解码 完整流程 |
| 请求转换 | OpenAI Chat → Anthropic/Gemini |
| 响应转换 | OpenAI Chat → Anthropic 响应 |
| 流式响应 | SSE 流式数据处理 |
| 真实 API 调用 | 发送请求到真实 API |

---

## 协议转换示例

### OpenAI Chat → Anthropic

**输入 (OpenAI Chat):**
```json
{
  "model": "gpt-4o",
  "messages": [
    {"role": "user", "content": "Hello"}
  ]
}
```

**输出 (Anthropic):**
```json
{
  "model": "gpt-4o",
  "messages": [
    {
      "role": "user",
      "content": [{"type": "text", "text": "Hello"}]
    }
  ]
}
```

### OpenAI Chat → Gemini

**输入 (OpenAI Chat):**
```json
{
  "model": "gpt-4o",
  "messages": [
    {"role": "user", "content": "Hello"}
  ]
}
```

**输出 (Gemini):**
```json
{
  "model": "gpt-4o",
  "contents": [
    {
      "role": "user",
      "parts": [{"text": "Hello"}]
    }
  ]
}
```

---

## 注意事项

1. **MoonBit SDK 是纯函数库**：不包含 HTTP 客户端，真实 API 调用需要通过宿主语言（TypeScript/Go/Python）完成。

2. **WASM 模块**：编译自 MoonBit 代码，提供协议转换功能，可通过 TypeScript/Go/Python 调用。

3. **API Key 安全**：请勿将 `.env` 文件提交到版本控制系统。

4. **vLLM/DeepSeek 适配器**：如果 API 返回 `reasoning_content` 字段，请使用 `openai-vllm` 适配器。

---

## 相关文档

- [Prism 架构设计](../docs/architecture.md)
- [SDK 使用指南](../docs/sdk-usage.md)
- [Lucent IR 设计](../docs/lux-ir-design.md)

---

## 开源协议

[MIT License](../LICENSE)
