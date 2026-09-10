# Provider 元数据唯一源设计

## 1. 背景

当前 Prism 的 provider 元数据分散在三处：

- `src/provider/<name>/capability.mbt`：provider 名称、模型 pattern、能力声明。
- `src/sdk/registry.mbt`：名称、alias、模型 pattern、能力和 6 个 codec 函数的注册组合。
- `src/sdk/schema.mbt`：按 provider 名再次分发请求/响应校验 schema。

这会导致新增或修改 provider 时产生散弹式修改，且 alias、model pattern、capability 与 schema 可能漂移。

本设计不改变 Lucent IR，不拆分 `lux`/`sdk`，也不引入动态插件系统。

## 2. 目标与非目标

### 目标

1. 每个 provider 对自身身份、别名、模型匹配、能力和校验规则拥有唯一描述入口。
2. SDK registry 只负责声明当前构建启用哪些 provider，并接线 codec。
3. 保持现有 provider 公共 codec 函数和 `ProviderSchema` API 兼容。
4. 让新增 provider 不需要修改中心 `sdk/schema.mbt` provider-name switch。
5. 通过测试阻止 metadata、registry、schema 三者漂移。

### 非目标

- 不修改 `ProviderCapability` 的 Lucent IR 字段。
- 不引入运行时包扫描、动态加载或外部 manifest 代码生成。
- 不把 provider-specific schema 下沉到 `lux`。
- 不引入 `trait Codec`。
- 不在本次设计中处理流式增量接口。

## 3. 核心所有权模型

```text
Lucent IR contract
  └── lux + docs/lux-ir-design.md + schemas/lux-ir-v1.json

Provider-owned metadata
  └── src/provider/<name>/meta.mbt

SDK composition list
  └── src/sdk/registry.mbt

Compatibility facade
  └── src/sdk/schema.mbt
```

“唯一源”分为三类，不强行收敛成单个文件：

- IR 契约的唯一源：`lux` 类型与 IR 规范。
- provider 元数据的唯一源：各 provider 的 `meta.mbt`。
- 当前 SDK 构建启用 provider 的唯一源：`sdk/registry.mbt`。

## 4. 新增公共 descriptor 包

新增 `src/provider/meta/` 包：

```text
src/provider/meta/
  moon.pkg
  types.mbt
```

该包只依赖 `morning-start/prism/lux`，不依赖任何具体 provider 或 sdk。

`ProviderMeta` 至少包含：

```text
ProviderMeta
├── name
├── aliases
├── model_pattern
├── capability
└── schema
```

其中 `schema` 是 `src/provider/meta` 定义的通用 schema descriptor，包含：

```text
ProviderSchema
├── provider_name
├── temperature / top_p / top_k / max_output_tokens constraints
├── resp_min_choices
├── supports_tools
├── supports_system_instruction
├── supported_reasoning_efforts
└── optional custom validation functions
```

`src/provider/meta` 同时提供 `ProviderSchema::validate_request/validate_response` 的通用实现。具体 provider 的 `meta.mbt` 只填充自己的约束数据，必要时提供 provider-local 的 custom validation function。

这样 `ProviderMeta` 不需要保存两个脱离 schema 的 validator 函数，也不会丢失现有 `FieldConstraint` 等结构。`src/provider/meta` 只依赖 `lux`；它不依赖具体 provider 或 sdk。

现有 `sdk.ProviderSchema` 在迁移期保留为兼容 facade。若 MoonBit 不支持跨包 type alias，则 facade 持有/转换 `@provider_meta.ProviderSchema`，而不是复制约束数据。新 provider 不得再向 `sdk/schema.mbt` 添加 schema 数据。

## 5. Provider 目录结构

每个 provider 新增一个公开描述入口：

```moonbit
pub fn metadata() -> @meta.ProviderMeta
```

推荐结构：

```text
src/provider/openai/
  meta.mbt
  schema.mbt          # 仅当校验逻辑需要独立文件时存在
  capability.mbt      # 迁移期 facade；最终只委托 metadata()
  request_decode.mbt
  request_encode.mbt
  response.mbt
  stream_decode.mbt
  stream_encode.mbt
```

`meta.mbt` 是 provider 元数据的唯一组合入口。`schema.mbt` 只能放校验实现，不能再拥有独立的 provider identity、alias、model pattern 或 capability 数据。

迁移后，`meta.mbt` 直接构造唯一的 `ProviderCapability` 值；现有 `capability()` 函数保留为兼容 facade，只返回 `metadata().capability()`，不得反向让 `metadata()` 调用 `capability()`，避免循环和第二真源。

复杂 provider 可以将 validator 定义在 `schema.mbt`，简单 provider 可以直接在 `meta.mbt` 内定义；SDK 不应感知两者差异。
  request_encode.mbt
  response.mbt
  stream_decode.mbt
  stream_encode.mbt
```

`meta.mbt` 是 provider 元数据的唯一组合入口。`schema.mbt` 只能放校验实现，不能再拥有独立的 provider identity、alias 或 model pattern。

复杂 provider 可以将 validator 定义在 `schema.mbt`，简单 provider 可以直接在 `meta.mbt` 内定义；SDK 不应感知两者差异。

## 6. SDK Registry 组合边界

保留 `src/sdk/registry.mbt`，因为 MoonBit 没有可靠的运行时包扫描；静态 WASM 构建必须明确包含哪些 provider。

扩展 `ProviderRegistration`，增加从 metadata 构造的入口：

```text
ProviderRegistration::from_metadata(
  metadata,
  request_decode,
  request_encode,
  response_decode,
  response_encode,
  events_decode,
  events_encode,
)
```

构造后，`ProviderRegistration` 的 name、aliases、model pattern、capability、validator 均来自 metadata；registry 不再重复这些值。

`build_providers()` 只保留 provider 清单和 codec 接线：

```text
metadata + six codec functions -> ProviderRegistration
```

保留静态注册顺序和现有 model matching 语义。registry 仍是“启用集合”的唯一源，但不是 provider 元数据的来源。

## 7. Schema 兼容层

`src/sdk/schema.mbt` 删除 `schema_for_provider_name()` 中的 provider-name switch。

`get_schema(name)` 的流程改为：

```text
name/alias/model
  -> match_provider_name
  -> registration metadata validator/schema
```

现有公共 API 保持兼容：

- `ProviderSchema::openai()`
- `ProviderSchema::anthropic()`
- `ProviderSchema::gemini()`
- `ProviderSchema::azure()`
- `ProviderSchema::validate_request/validate_response`

这些入口在迁移期作为 facade 保留，不再作为 provider schema 的真源。新 provider 不需要新增 `ProviderSchema::<name>()`，而是通过 metadata 接入。

若现有 `ProviderSchema` 的完整字段结构无法直接复用，先保留兼容 facade，再让 `ProviderMeta` 持有 validator 函数；不要为了抽象统一而修改 Lucent IR 或扩大 SDK 公共 API。

## 8. 迁移步骤

1. 新增 `src/provider/meta` 和 `ProviderMeta`，不改现有行为。
2. 为四个 provider 新增 `meta.mbt`，把现有 capability、name、pattern、aliases 和 schema validator 收拢进去。
3. 为 `ProviderRegistration` 增加 `from_metadata()`。
4. 修改 `build_providers()`，改为消费各 provider 的 `metadata()`。
5. 将 SDK 内部校验路径改为消费 registration metadata。
6. 删除 `sdk/schema.mbt` 的 provider-name switch。
7. 保留现有 `ProviderSchema::*` 兼容入口并补充等价性测试。
8. 在所有测试通过、`.mbti` 变化审查完成后，删除旧 `capability.mbt` 或将其降为仅内部实现。
9. 更新 `docs/provider-guide.md`，把新增 provider 的步骤改为先实现 `meta.mbt`。

## 9. 验收标准

### 结构

- 每个 provider 只有一个公开 metadata 入口。
- `sdk/registry.mbt` 不重复写 provider name、aliases、model pattern、capability。
- `sdk/schema.mbt` 不包含 provider-name switch。
- `lux` 不依赖 `provider/meta`、具体 provider 或 sdk。
- provider 之间保持互不依赖。

### 行为

- 现有 provider 名称、alias 和 model matching 结果不变。
- 现有 codec 输出和诊断不变。
- `get_schema(canonical_name)`、`get_schema(alias)`、`get_schema(model)` 仍返回等价校验行为。
- `ProviderSchema::*` 兼容 API 的既有测试保持通过。
- provider metadata 与 registration 的字段一致性测试通过。

### 接口

- 检查所有受影响包的 `pkg.generated.mbti`。
- 若不需要新增公共 API，`.mbti` 只允许出现预期的 descriptor/constructor 变化。
- WASM export 列表和 wrapper ABI 不变。

## 10. 风险与回滚

主要风险是 `ProviderMeta` 引入后扩大 provider 或 SDK 的公共 API。缓解方式：

- descriptor 的字段保持 package-private，只通过构造器和只读方法暴露必要能力。
- 先在 SDK 内部消费 metadata，再决定哪些 descriptor API 需要公开。
- 每一步单独运行 `moon info`，用 `.mbti` diff 作为兼容性门禁。
- 保留旧 schema facade，出现兼容问题时可回退 registry 接线而不回退 provider codec。

回滚边界：若 provider metadata 迁移导致公共 API 或编译时间明显恶化，可保留 `src/provider/meta` 类型和各 provider 的 metadata 实现，仅将 SDK registry 临时恢复为旧构造方式；provider codec 不受影响。
