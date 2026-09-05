<div align="center">
  <img src="./assets/readme/hero.svg" width="100%" alt="Prism — LLM 统一协议中间件" />
</div>

<h3 align="center">一套中立 IR，互通所有 LLM 协议</h3>

<p align="center">
  Prism 是一个用 MoonBit 编写的 <strong>LLM 协议转换引擎</strong>：
  通过中立中间表示 <strong>Lucent IR</strong>，在 OpenAI · Anthropic · Gemini 等协议之间自由互转，
  请求 / 响应 / 流式（SSE）全覆盖，原生与 WASM 双形态交付。
</p>

<p align="center">
  <a href="https://www.moonbitlang.com"><img src="https://img.shields.io/badge/MoonBit-0.1.x-blue" alt="MoonBit" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green" alt="MIT License" /></a>
  <a href="https://github.com/morning-start/prism/actions"><img src="https://img.shields.io/github/actions/workflow/status/morning-start/prism/ci.yml?branch=master" alt="CI" /></a>
</p>

---

## 它解决什么问题

写 LLM 应用最繁琐的部分往往不是模型，而是**协议碎片化**：
OpenAI Chat Completions、OpenAI Responses、Anthropic Messages、Google Gemini
各有各的 JSON 结构与 SSE 事件流，客户端换一家厂商就要重写一遍。

Prism 用一层**中立中间表示（Lucent IR）**统一它们：

- **一次适配，全协议互通** —— 每家厂商只需实现 6 个纯函数
  （request / response / stream × decode / encode），接入成本与协议数量成 **O(N)**，而非两两互转的 O(N²)；
- **任何格式先归一、再编码** —— 代码可以在 IR 层“插一手”，做审计、改写、路由、过滤；
- **流式同等待遇** —— SSE 被归一为统一事件流，消费端只写一次事件处理逻辑；
- **不静默丢数据** —— 承载不了的能力显式失败或打上诊断，转换结果可检查保真度。

```
OpenAI JSON  ──[decode]──►  Lucent IR  ──[encode]──►  Anthropic JSON
Gemini JSON  ◄──[encode]──  Lucent IR  ◄──[decode]──  OpenAI JSON
                                │
                  你的代码在这里（审计 / 改写 / 路由 / 过滤）
```

## 快速开始

```bash
moon add morning-start/prism
```

**MoonBit SDK —— 一行创建，文本进、文本出：**

```moonbit
fn main {
  // 想用哪家就写哪家：openai / responses / anthropic / gemini
  let prism = Prism::new().with_provider("openai")

  // 编码请求：文本 → OpenAI JSON
  let req_json = prism.encode_request("你好", PrismOptions::default())

  // 解码响应：OpenAI JSON → 文本
  let text = prism.decode_response(resp_json)
}
```

切换厂商只需改一个 provider 名；直接传**模型名**也能自动路由
（`claude-*` → Anthropic、`gemini-*` → Google、`gpt-*` / `o*` → OpenAI）。

> 完整端到端场景见 [USAGE.md](USAGE.md)：
> 嵌入 SDK（应用内转换）、网关模式（OpenAI 客户端接 Claude 后端）、流式转码、企业审计网关。

## 支持的协议

| 注册名      | 别名                            | 协议                                           | 状态 |
| ----------- | ------------------------------- | ---------------------------------------------- | ---- |
| `openai`    | `chat`                          | OpenAI Chat Completions                        | ✅   |
| `responses` | `openai-responses`              | OpenAI Responses API                           | ✅   |
| `messages`  | `anthropic` · `claude-messages` | Anthropic Messages API（含 extended thinking） | ✅   |
| `gemini`    | `google`                        | Google Gemini API                              | ✅   |

每个适配器实现同一套 **6 函数接口**（请求 / 响应 / 流 × 解码 / 编码），
新增协议只需在 `src/sdk/registry.mbt` 追加一个注册条目。

## 流式与事件

SSE 是各家协议最容易分叉的地方。Prism 把 provider 的 SSE 文本归一成统一事件
（文本增量、工具调用、思考过程、结束原因……），客户端只需写一次：

```moonbit
match prism.decode_sse(sse_text) {
  Ok(events) => for event in events {
    match event {
      TextDelta(s) => ui.append(s)        // 流式文本
      ToolCall(tc) => execute_tool(tc)    // 工具调用
      Thinking(t) => ui.show_thinking(t)  // 推理过程
      Finish(_) => break                  // 结束
    }
  }
}
```

## 诊断与保真

转换不是“尽力而为”。Lucent IR 对字段分类为**标准 / 扩展**：
扩展能力（如 Anthropic extended thinking、各家的并行工具调用开关）以可选字段承载，
无法映射时**显式降级并携带诊断**（Degraded / Unsupported），而不是悄悄丢弃数据。
解码结果可携带元信息与诊断列表（`decode_response_with_meta` / `decode_response_with_diagnostics`），
让上层判断这次转换的保真程度。字段演进规则见 [docs/rules/lucent-ir-evolution.md](docs/rules/lucent-ir-evolution.md)。

## 代码架构

<div align="center">
  <img src="./assets/readme/flow.svg" width="100%" alt="Prism 代码架构：Lucent IR 核心 → 协议适配器 → SDK 注册表 → WASM 导出" />
</div>

- `src/lux` —— Lucent IR：类型、序列化、诊断、流事件（无 IO、无厂商绑定）
- `src/provider/*` —— 协议适配器：`openai` / `responses` / `messages` / `gemini`
- `src/sdk` —— `Prism` 门面 + 注册表 + 路由 + Context 构建（唯一收敛点）
- `src/internal` —— JSON 字段访问、SSE 帧解析、extras 合并等共享基元
- `src/wasm` + `src/cmd/main` —— WASM 字符串 ABI 导出（进出皆 String，零 provider 耦合）
- `src/conformance` —— 8 个 `check_*` 协议符合性验证器（测试工具包）

## 测试与质量

- **双形态测试**：`moon test` 同时跑 native 与 wasm-gc
- **800+ 条用例**：黑盒（`test/` 子包，只走公共 API）+ 白盒（`*_wbtest` 留在包内）
- **质量门禁**：`moon fmt --check`、`moon check --deny-warn`、`moon test`

## 文档

- [USAGE.md](USAGE.md) —— 四种场景的完整上手指南
- [docs/architecture.md](docs/architecture.md) · [docs/status.md](docs/status.md) —— 设计决策与项目状态
- [docs/lux-ir-design.md](docs/lux-ir-design.md) · [schemas/lux-ir-v1.json](schemas/lux-ir-v1.json) —— Lucent IR 规范与 JSON Schema
- [docs/api-protocol-converter.md](docs/api-protocol-converter.md) —— 三端点协议转换契约
- `src/lux/README.md` · `src/sdk/README.md` —— 包内导航

## License

[MIT](LICENSE)

## 友情链接

- [LINUX DO](https://linux.do)
- [Moonbit 官方](https://www.moonbitlang.cn/)
- <p>本项目的 AI API 支持由 <a href="https://tokeness.io">Tokeness.io</a>赞助提供。</p>

## 赞助感谢

- [Akanyi](https://linux.do/u/akanyi) 佬赞助的公益API
- [atomcode](https://atomgit.com/atomgit_atomcode/atomcode) 的dpv4的额度
