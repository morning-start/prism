# src/sdk — SDK 组合根（导航索引）

> MoonBit 目录 = 包：本目录是一个包，**不能**再建子文件夹（子文件夹 = 子包，
> 会破坏 inherent methods 与包环约束，见 `docs/report/sdk-split-feasibility.md`）。
> 包内组织靠**功能组分区注释 + 本导航文件**。

## 功能组文件地图

### 1. facade（对外入口，先读这里）

| 文件 | 内容 |
|---|---|
| `prism.mbt` | Prism 门面类型 + PrismOptions/ConversionMeta/DecodedResponse + SdkProviderEndpoint |
| `context.mbt` | Context/SdkMessage/SdkTool 构建 + context_to_lux_request |

### 2. registry+match（注册与路由）

| 文件 | 内容 |
|---|---|
| `registry.mbt` | ProviderRegistration 定义 + providers_cache + 动态注册表（register/unregister/with_overrides，T6） |
| `match.mbt` | 路由匹配（match_provider_name / match_by_model）——**唯一路由入口**（静态表优先，动态表兜底） |

### 3. pipeline（编码解码编排）

| 文件 | 内容 |
|---|---|
| `pipeline.mbt` | Prism 门面内部方法（encode/decode 样板，从自身 provider 出发） |
| `codec_pipeline.mbt` | 通用 decode→IR→encode 管线（任意 source→target，无状态） |

### 3.5 stream session（增量解码会话，首字实时）

| 文件 | 内容 |
|---|---|
| `event_stream.mbt` | `Prism::stream_session` 拉式会话（feed/finish）+ `EventNormalizer` 跨帧规整器（与 StreamConverter 共享）+ `PrismEventBuffer` 工具参数跨帧累积 |

### 4. convert（跨协议中转）

| 文件 | 内容 |
|---|---|
| `convert.mbt` | convert_request/response/stream 组合入口（场景 2）+ StreamConverter 增量会话（T5）+ 类型化入口（T7） |

### 5. hooks（IR 策略层，T4）

| 文件 | 内容 |
|---|---|
| `hooks.mbt` | SdkRequestHook/SdkResponseHook/SdkStreamHook + convert_*_with_hooks + 内置钩子 |

### 6. snapshot（会话快照，T8）

| 文件 | 内容 |
|---|---|
| `snapshot.mbt` | ConversationStore + restore_request_from_snapshot + convert_request_with_store |

### 7. error + diagnostics（类型化错误与诊断运维，T7/T10）

| 文件 | 内容 |
|---|---|
| `error.mbt` | PrismError（LucentErrorKind 上翻）+ 保守分类器 + is_retryable |
| `diagnostics.mbt` | DiagnosticPolicy + enforce_policy + DiagnosticCollector |

### 8. schema+event（元数据，零内部依赖）

| 文件 | 内容 |
|---|---|
| `schema.mbt` | ProviderSchema/FieldConstraint |
| `event.mbt` | PrismToolCall/PrismToolResult/PrismThinking |

### 9. 测试

- `*_wbtest.mbt`：白盒测试（留包内，MoonBit 约束）
- `test/`：黑盒测试子包（cross_protocol / convert_matrix / sdk_test /
  context_toolcall / events_to_context / options_ext / hooks /
  stream_converter / snapshot_store / error_typed / diagnostics_policy 等）

## 依赖方向（禁止反向）

```
facade (prism/context) ──► match ◄── pipeline
                              │
                         registry（providers_cache + dynamic_providers）
                              ▲
                         convert ◄─► codec_pipeline
                              ▲
        hooks / snapshot / error / diagnostics（只消费 IR 与注册表；
        禁止反向依赖 provider——单向依赖图护栏）
```

- `match.mbt` 是唯一读取注册表的文件
- `schema.mbt` / `event.mbt` 零内部依赖（只定义数据）
- 禁止 registry/match 反向引用 facade/convert
- T5 起 sdk 直接依赖 `internal`（SseFrameSplitter；internal 是叶子包，不成环）

## 约定

- 新增门面 API → `prism.mbt`；新增状态构建 → `context.mbt`
- 新增路由逻辑 → `match.mbt`；新增跨协议组合 → `convert.mbt` + `codec_pipeline.mbt`
- 遵循 `docs/rules/naming-conventions.md`
