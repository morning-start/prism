# Provider 元数据唯一源实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 provider 的身份、alias、model pattern、capability 与 schema 约束收敛到各 provider 自己的 `meta.mbt`，让 SDK registry 只负责静态组合和 codec 接线。

**Architecture:** 新增不依赖具体 provider/sdk 的 `src/provider/meta` 公共叶子包，定义通用 `ProviderMeta` 与 `ProviderSchema` descriptor/校验实现。每个 provider 的 `meta.mbt` 成为自身元数据唯一入口；`src/sdk/registry.mbt` 仍保留，但只列出启用的 provider 和六个 codec 函数。现有 `sdk.ProviderSchema` API 保留为兼容 facade，不再保存 provider-specific schema 真源。

**Tech Stack:** MoonBit 0.10.x、MoonBit package manifests、Lucent IR v1、`moon test`、`moon info`、生成的 `pkg.generated.mbti`。

## Global Constraints

- 不修改 `ProviderCapability` 的 Lucent IR 字段。
- 不引入运行时包扫描、动态加载或外部 manifest 代码生成。
- 不把 provider-specific schema 下沉到 `lux`。
- 不引入 `trait Codec`。
- 不处理流式增量接口。
- 保持现有 provider 公共 codec 函数和 WASM export ABI 不变。
- 每个 provider 只有一个公开 metadata 入口：`pub fn metadata() -> @meta.ProviderMeta`。
- `sdk/registry.mbt` 是当前构建启用 provider 的唯一清单，但不重复 provider 元数据字段。
- Extension 字段继续保持 optional；本任务不新增 IR extension。
- 每个任务先写行为测试，再写实现；每个任务独立运行针对性验证。

---

### Task 1: 建立公共 ProviderMeta descriptor 包

**Files:**
- Create: `src/provider/meta/moon.pkg`
- Create: `src/provider/meta/types.mbt`
- Create: `src/provider/meta/pkg.generated.mbti` via `moon info`
- Test: `src/provider/meta/test/moon.pkg`
- Test: `src/provider/meta/test/types_test.mbt`

**Interfaces:**
- Produces `@meta.ProviderMeta`。
- Produces `@meta.ProviderSchema`、`@meta.FieldConstraint`。
- `ProviderMeta` 至少提供 `name`、`aliases`、`model_pattern`、`capability`、`schema` 的构造和只读访问入口。
- `ProviderSchema` 提供与现有 SDK schema 等价的 request/response validation 行为。

- [ ] **Step 1: Write the failing test**

在 `types_test.mbt` 编写黑盒测试，构造一个包含 temperature 限制和 response choice 限制的 schema，验证：

```moonbit
let schema = @meta.ProviderSchema::new(
  "test",
  @meta.FieldConstraint::range(0.0, 1.0),
  @meta.FieldConstraint::any(),
  @meta.FieldConstraint::any(),
  @meta.FieldConstraint::min(1.0),
  1,
  true,
  true,
  None,
  None,
)
let meta = @meta.ProviderMeta::new(
  "test",
  ["t"],
  "test-*",
  capability,
  schema,
)
assert_eq(meta.name(), "test")
assert_eq(meta.aliases(), ["t"])
assert_eq(meta.model_pattern(), "test-*")
assert_eq(meta.schema().provider_name(), "test")
```

并验证 schema 的 request/response 校验能返回错误，而不是只测试字段 getter。

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
moon test --target native src/provider/meta/test
```

Expected: 编译失败，因为 `src/provider/meta`、`ProviderMeta` 和 `ProviderSchema` 尚不存在。

- [ ] **Step 3: Write minimal implementation**

`src/provider/meta/moon.pkg` 只声明：

```text
import {
  "morning-start/prism/lux",
}
```

`types.mbt` 实现：

- package-private 字段。
- `FieldConstraint::any/range/min` 构造器。
- `ProviderSchema::new`，字段顺序与当前 `sdk.ProviderSchema` 对齐。
- `ProviderSchema::validate_request`：复用 `req.validate()`，检查 temperature、top_p、top_k、max_output_tokens 和 tools/system/reasoning 约束。
- `ProviderSchema::validate_response`：复用 `resp.validate()`，检查最少 choices。
- `ProviderMeta::new` 和只读方法。
- 不导出 codec 函数字段；codec 仍由 SDK registry 组合。

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
moon test --target native src/provider/meta/test
```

Expected: 新 descriptor 测试通过。

- [ ] **Step 5: Run interface review**

Run：

```bash
moon info --target native
```

检查新增 `pkg.generated.mbti` 只暴露预期 descriptor 构造器、访问器和校验方法。

- [ ] **Step 6: Commit**

```bash
rtk git add src/provider/meta
rtk git commit -m "feat: add provider metadata descriptors"
```

---

### Task 2: 将 OpenAI 与 Responses schema 收拢到 provider metadata

**Files:**
- Create: `src/provider/openai/meta.mbt`
- Create: `src/provider/responses/meta.mbt`
- Modify: `src/provider/openai/capability.mbt`
- Modify: `src/provider/responses/capability.mbt`
- Modify: `src/provider/openai/moon.pkg`
- Modify: `src/provider/responses/moon.pkg`
- Test: `src/provider/openai/test/openai_test.mbt`
- Test: `src/provider/responses/test/responses_test.mbt`

**Interfaces:**
- Produces `@openai.metadata() -> @meta.ProviderMeta`。
- Produces `@responses.metadata() -> @meta.ProviderMeta`。
- Metadata values must preserve current canonical names, aliases, patterns and capabilities.
- Existing `capability()` functions remain behaviorally identical during migration.

- [ ] **Step 1: Write failing metadata consistency tests**

Add blackbox tests that assert:

```moonbit
let meta = @openai.metadata()
assert_eq(meta.name(), "openai")
assert_eq(meta.model_pattern(), "gpt-*,o*")
assert_eq(meta.aliases(), ["chat"])
assert_eq(meta.capability(), @openai.capability())
```

For Responses, assert canonical name `responses`, alias `openai-responses`, pattern `gpt-*,o*`, and capability equivalence.

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
moon test --target native src/provider/openai/test
moon test --target native src/provider/responses/test
```

Expected: compile failure because `metadata()` is not defined.

- [ ] **Step 3: Implement provider metadata**

Add `meta.mbt` in each provider. During this task, use the existing `capability()` result to avoid behavior changes, but put canonical name, aliases, model pattern and schema data in `metadata()`.

The metadata schema must contain the same constraints currently encoded in `src/sdk/schema.mbt::ProviderSchema::openai()`.

Add `morning-start/prism/provider/meta` to each provider `moon.pkg`.

- [ ] **Step 4: Run tests to verify metadata behavior**

Run the two targeted test commands again. Expected: PASS, with current codec tests unchanged.

- [ ] **Step 5: Commit**

```bash
rtk git add src/provider/openai src/provider/responses
rtk git commit -m "feat: add OpenAI provider metadata"
```

---

### Task 3: 将 Messages 与 Gemini schema 收拢到 provider metadata

**Files:**
- Create: `src/provider/messages/meta.mbt`
- Create: `src/provider/gemini/meta.mbt`
- Modify: `src/provider/messages/capability.mbt`
- Modify: `src/provider/gemini/capability.mbt`
- Modify: `src/provider/messages/moon.pkg`
- Modify: `src/provider/gemini/moon.pkg`
- Test: `src/provider/messages/test/messages_test.mbt`
- Test: `src/provider/gemini/test/gemini_test.mbt`

**Interfaces:**
- Produces `@messages.metadata() -> @meta.ProviderMeta`。
- Produces `@gemini.metadata() -> @meta.ProviderMeta`。
- Metadata preserves current canonical names, aliases, model patterns, capabilities and validation behavior.

- [ ] **Step 1: Write failing metadata consistency tests**

Messages assertions：

```moonbit
let meta = @messages.metadata()
assert_eq(meta.name(), "messages")
assert_eq(meta.model_pattern(), "claude-*")
assert_eq(meta.aliases(), ["claude-messages", "anthropic"])
```

Gemini assertions：

```moonbit
let meta = @gemini.metadata()
assert_eq(meta.name(), "gemini")
assert_eq(meta.model_pattern(), "gemini-*")
assert_eq(meta.aliases(), ["google"])
```

Also compare `meta.capability()` with the existing provider capability implementation.

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
moon test --target native src/provider/messages/test
moon test --target native src/provider/gemini/test
```

Expected: compile failure because `metadata()` is not defined.

- [ ] **Step 3: Implement metadata**

Add `meta.mbt` and import the public descriptor package. Copy only the current provider-specific constraints from `sdk/schema.mbt`; do not add new validation semantics.

- [ ] **Step 4: Run tests to verify they pass**

Run the two targeted commands again. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
rtk git add src/provider/messages src/provider/gemini
rtk git commit -m "feat: add Anthropic and Gemini provider metadata"
```

---

### Task 4: Make SDK registry consume metadata

**Files:**
- Modify: `src/sdk/moon.pkg`
- Modify: `src/sdk/registry.mbt`
- Modify: `src/sdk/pkg.generated.mbti` via `moon info`
- Test: `src/sdk/provider_registry_wbtest.mbt`
- Test: `src/sdk/test/schema_test.mbt`

**Interfaces:**
- Consumes `@openai.metadata()`, `@responses.metadata()`, `@messages.metadata()`, `@gemini.metadata()`.
- Adds `ProviderRegistration::from_metadata(metadata, six codec functions)`.
- `build_providers()` no longer repeats provider name, aliases, model pattern or capability literals.
- Existing `ProviderRegistration` consumers remain source-compatible unless `.mbti` review proves otherwise.

- [ ] **Step 1: Write failing registry consistency tests**

Add tests asserting for every registered provider:

```moonbit
match @sdk.match_provider_name("chat") {
  Some(reg) => {
    assert_eq(reg.name, @openai.metadata().name())
    assert_eq(reg.model_pattern, @openai.metadata().model_pattern())
    assert_eq(reg.capability, @openai.metadata().capability())
  }
  None => fail("openai alias must resolve")
}
```

Add equivalent checks for canonical names, aliases and model fallback.

- [ ] **Step 2: Run tests to verify the new constructor is absent**

Run:

```bash
moon test --target native src/sdk/test
```

Expected: compile failure until `from_metadata()` and registry migration are implemented.

- [ ] **Step 3: Implement `from_metadata()`**

Construct the existing `ProviderRegistration` fields from `ProviderMeta` accessors. Keep the existing six function field types unchanged. Do not add validator behavior in this task beyond storing metadata schema or schema access required by the next task.

- [ ] **Step 4: Rewrite `build_providers()`**

Each registration should follow this shape:

```moonbit
ProviderRegistration::from_metadata(
  @openai.metadata(),
  @openai.openai_to_lux_request,
  @openai.lux_request_to_openai,
  @openai.openai_to_lux_response,
  @openai.lux_response_to_openai,
  @openai.openai_sse_to_events,
  @openai.lux_events_to_openai_sse,
)
```

Preserve registration order.

- [ ] **Step 5: Run registry and cross-protocol tests**

Run:

```bash
moon test --target native src/sdk/test
```

Expected: existing registry, schema and cross-protocol behavior remains green.

- [ ] **Step 6: Review generated interfaces**

Run:

```bash
moon info --target native
```

Review all changed `.mbti`; reject accidental new public fields or changed WASM-facing signatures.

- [ ] **Step 7: Commit**

```bash
rtk git add src/sdk src/*/pkg.generated.mbti
rtk git commit -m "refactor: compose provider registry from metadata"
```

---

### Task 5: Remove central provider schema switch and preserve compatibility facade

**Files:**
- Modify: `src/sdk/schema.mbt`
- Modify: `src/sdk/prism.mbt`
- Modify: `src/sdk/test/schema_test.mbt`
- Modify: `src/sdk/pkg.generated.mbti` via `moon info`

**Interfaces:**
- `get_schema(String) -> ProviderSchema?` remains available.
- `ProviderSchema::openai/anthropic/gemini/azure` remain available for existing callers.
- `get_schema` resolves canonical names, aliases and model names through registry metadata, without a provider-name switch.

- [ ] **Step 1: Add failing alias/model equivalence tests**

For each provider, compare validation results from canonical name, alias and model pattern. Example:

```moonbit
let canonical = @sdk.get_schema("openai").unwrap()
let alias = @sdk.get_schema("chat").unwrap()
let model = @sdk.get_schema("gpt-4o").unwrap()
assert_eq(canonical.validate_request(ok_req()), alias.validate_request(ok_req()))
assert_eq(canonical.validate_request(ok_req()), model.validate_request(ok_req()))
```

Add the same request/response equivalence for Messages and Gemini.

- [ ] **Step 2: Run tests to verify the desired path is not yet wired**

Run:

```bash
moon test --target native src/sdk/test
```

Expected: at least one new equivalence test fails while the old switch remains authoritative or metadata schema is not exposed through registration.

- [ ] **Step 3: Remove provider-name switch from `sdk/schema.mbt`**

Replace `schema_for_provider_name()` lookup with registry resolution and metadata schema retrieval. Keep compatibility constructors as facades over the corresponding provider metadata schema; they must not contain duplicated constraint literals.

- [ ] **Step 4: Run schema and SDK tests**

Run:

```bash
moon test --target native src/sdk/test
```

Expected: all old schema tests and new equivalence tests pass.

- [ ] **Step 5: Review API surface**

Run:

```bash
moon info --target native
git diff -- '**/pkg.generated.mbti'
```

Expected: no WASM export changes; only intended descriptor/facade API changes.

- [ ] **Step 6: Commit**

```bash
rtk git add src/sdk
rtk git commit -m "refactor: resolve schemas through provider metadata"
```

---

### Task 6: Add metadata invariants and update provider documentation

**Files:**
- Modify: `src/sdk/provider_registry_wbtest.mbt`
- Modify: `src/sdk/test/schema_test.mbt`
- Modify: `docs/provider-guide.md`
- Modify: `src/sdk/README.md`
- Modify: `docs/architecture.md`
- Modify: `docs/architecture-packages.md`

**Interfaces:**
- Documentation describes `meta.mbt` as the provider-owned metadata source.
- Tests enforce metadata/registry/schema consistency.

- [ ] **Step 1: Add invariant tests**

Cover:

- every registration name equals metadata name;
- every registration model pattern equals metadata model pattern;
- capability equality;
- canonical, alias and model lookup return equivalent schemas;
- unknown provider still returns `None` or the existing error behavior;
- provider list remains unchanged.

- [ ] **Step 2: Run invariant tests**

Run:

```bash
moon test --target native src/sdk/test
```

Expected: PASS.

- [ ] **Step 3: Update provider guide**

Replace the obsolete `src/sdk/provider_capability.mbt` reference with:

```text
src/provider/<name>/meta.mbt
src/sdk/registry.mbt  # add provider to the static enabled set
```

Explicitly state that name, aliases, model pattern, capability and schema belong in `meta.mbt`, while registry only wires codecs.

- [ ] **Step 4: Update package architecture docs**

Document the three distinct unique-source categories:

```text
IR contract          -> lux + formal schema docs
provider metadata    -> provider/<name>/meta.mbt
enabled set          -> sdk/registry.mbt
```

- [ ] **Step 5: Commit**

```bash
rtk git add docs/provider-guide.md src/sdk/README.md docs/architecture.md docs/architecture-packages.md src/sdk/*test.mbt
rtk git commit -m "docs: define provider metadata ownership"
```

---

### Task 7: Full verification and interface drift gate

**Files:**
- Modify only generated `.mbti` files if `moon info` produces intentional changes.

- [ ] **Step 1: Run formatting**

```bash
moon fmt --check
```

Expected: exit 0.

- [ ] **Step 2: Run type checking**

```bash
moon check --warn-list +73 --deny-warn
```

Expected: exit 0 with no warnings.

- [ ] **Step 3: Run native and wasm tests**

```bash
moon test --target native
moon test --target wasm-gc
```

Expected: all tests pass.

- [ ] **Step 4: Regenerate and inspect interfaces**

```bash
moon info --target native
moon info --target wasm-gc
```

Confirm no unexpected public API or WASM export changes.

- [ ] **Step 5: Run schema drift validation**

```powershell
./scripts/check_schema_drift.ps1 -Strict
```

Expected: exit 0.

- [ ] **Step 6: Inspect final diff**

```bash
rtk git diff --check
rtk git status --short
```

Expected: no whitespace errors; only intended files remain.

- [ ] **Step 7: Commit final generated interfaces if needed**

```bash
rtk git add src/**/pkg.generated.mbti
rtk git commit -m "chore: refresh package interfaces"
```

