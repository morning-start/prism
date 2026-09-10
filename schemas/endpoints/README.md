# Endpoint Official Schemas

> 目录用途：存放各端点官方（或官方来源）的机器可读 API schema，供
> conformance 交叉验证与 drift 脚本字段集替换使用（design 文档 G6 ↔ TD-FV-1/3）。
> 维护规则：每份 schema 必须记录来源、license 与获取日期；未获取的端点
> 在下方显式登记（不静默跳过）。

## 已获取

| 端点 | 文件 | 来源 | License | 获取日期 | 说明 |
|---|---|---|---|---|---|
| OpenAI Chat + Responses | `openai-openapi.yaml` | [openai/openai-openapi](https://github.com/openai/openai-openapi)（官方仓库，OpenAPI 3.1，version 2.3.0） | MIT（spec 头部 `license: MIT`） | 2026-09-09 | 包含 `/chat/completions`（1984 行起）与 `/responses`（17279 行起）完整 request/response schema |

## 未获取（登记 TD-FV-1）

| 端点 | 状态 | 原因 | License 备注 |
|---|---|---|---|
| Anthropic Messages | ⚠️ 无官方机器可读文件 | 官方未发布独立 OpenAPI/JSON Schema 仓库；schema 内嵌于官方 docs 页面（platform.claude.com）逐字段展示；第三方仓库（api-evangelist/anthropic）有 OpenAPI 但**非官方**，不落盘 | 官方文档无明确 license；第三方 spec license 未确认 |
| Google Gemini | ⚠️ 官方页面内嵌 schema | ai.google.dev API 参考页内嵌 JSON Schema（draft 2020-12 格式，含 GenerateContentRequest 等），非独立文件；Google Discovery 文档可转换但需额外处理 | Google API 服务条款 |

## 用法

- OpenAI spec：可直接用于 adapter 输出 conformance 交叉验证（提取
  `CreateChatCompletionRequest` / `CreateResponseRequest` 字段集对比
  `src/provider/openai|responses/request_encode.mbt` 输出）。
- Anthropic / Gemini：待官方发布机器可读 schema 或确认第三方 license 后补充；
  期间维持 `scripts/check_schema_drift.ps1` 的手工字段集（TD-FV-3）。
