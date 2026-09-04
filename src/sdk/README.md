# src/sdk — SDK 组合根（导航索引）

> MoonBit 目录 = 包：本目录是一个包，**不能**再建子文件夹（子文件夹 = 子包，
> 会破坏 inherent methods 与包环约束，见 `docs/report/sdk-split-feasibility.md`）。
> 包内组织靠**功能组分区注释 + 本导航文件**。

## 功能组文件地图

### 1. facade（对外入口，先读这里）

| 文件 | 内容 |
|---|---|
| `prism.mbt` | Prism 门面类型 + PrismOptions/ConversionMeta/DecodedResponse |
| `context.mbt` | Context/SdkMessage/SdkTool 构建 + context_to_lux_request |

### 2. registry+match（注册与路由）

| 文件 | 内容 |
|---|---|
| `registry.mbt` | ProviderRegistration 定义 + providers_cache（注册表） |
| `match.mbt` | 路由匹配（match_provider_name / match_by_model）——**唯一路由入口** |

### 3. pipeline（编码解码编排）

| 文件 | 内容 |
|---|---|
| `pipeline.mbt` | Prism 门面内部方法（encode/decode 样板，从自身 provider 出发） |
| `codec_pipeline.mbt` | 通用 decode→IR→encode 管线（任意 source→target，无状态） |

### 4. convert（跨协议中转）

| 文件 | 内容 |
|---|---|
| `convert.mbt` | convert_request/response/stream 组合入口（场景 2） |

### 5. schema+event（元数据，零内部依赖）

| 文件 | 内容 |
|---|---|
| `schema.mbt` | ProviderSchema/FieldConstraint |
| `event.mbt` | PrismToolCall/PrismToolResult/PrismThinking |

### 6. 测试

- `*_wbtest.mbt`：白盒测试（留包内，MoonBit 约束）
- `test/`：黑盒测试子包（cross_protocol / convert_matrix / sdk_test 等）

## 依赖方向（禁止反向）

```
facade (prism/context) ──► match ◄── pipeline
                              │
                         registry（providers_cache）
                              ▲
                         convert ◄─► codec_pipeline
```

- `match.mbt` 是唯一读取 `providers_cache` 的文件
- `schema.mbt` / `event.mbt` 零内部依赖（只定义数据）
- 禁止 registry/match 反向引用 facade/convert

## 约定

- 新增门面 API → `prism.mbt`；新增状态构建 → `context.mbt`
- 新增路由逻辑 → `match.mbt`；新增跨协议组合 → `convert.mbt` + `codec_pipeline.mbt`
- 遵循 `docs/rules/naming-conventions.md`
