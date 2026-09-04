# SDK 拆包可行性测量报告

> 日期：2026-09-04
> 目的：测量将 `src/sdk` 单包拆分为子包（registry / match / convert / pipeline）
> 的公开 API 影响与工作量，为 iteration-005 的拆包决策提供数据。
> 背景：architecture.md 记载「SDK remains the static provider composition root
> for now. A dedicated registry package requires a compatibility plan for the
> public ProviderRegistration type.」——本文档完成该计划的可行性测量。

---

## 1. 现状基线

- sdk 包源码 13 个文件（其中 4 个 wbtest）、约 1300 行
- pub 声明 62 个；inherent methods **36 个**，分布于 11 个类型：

| 类型 | 方法数 | 所在文件 |
|------|--------|---------|
| Prism | 12 | prism.mbt（facade） |
| ProviderSchema | 6 | schema.mbt |
| Context | 6 | context.mbt |
| ConvertMetaResult | 3 | convert.mbt |
| SdkMessage | 2 | prism.mbt |
| PrismOptions | 2 | prism.mbt |
| SdkTool / ProviderRegistration / FieldConstraint / DecodedResponse / ConversionMeta | 各 1 | 散落 |

- 外部调用面：wasm 15 处、examples 31 处、cmd 1 处（共 47 处 `@sdk.`）
- sdk 依赖 lux + 4 provider + json（单向，无环）

## 2. 决定性约束（与 lux 完全同构）

### 2.1 inherent methods 必须与类型同包

sdk 的 36 个方法全部是 `Type::method` 形态（`Prism::new` / `Prism::with_provider` /
`ProviderSchema::register` / `Context::set_*` …）。MoonBit 要求 inherent methods
定义在**类型所在的包**内。拆 registry/match/convert 子包后：

- `Prism` 类型若留在 sdk 主包，其 12 个方法也必须在主包——方法体引用的
  registry/match/convert 逻辑形成**主包 → 子包**依赖，而子包若要构造/访问
  Prism 又形成**子包 → 主包**依赖 → 包环
- 打破包环只能：把类型与方法整体下沉到子包（facade 拆没）、或把方法改为
  trait/顶层函数（36 个方法全改，47 处外部调用点全改）

### 2.2 struct 字段非 pub

`pub struct Prism { provider : String }`、`ProviderSchema`、`Context` 等
字段均无 pub 前缀。子包访问父包字段需要 pub 化或 getter——同 lux 情形。

### 2.3 子包候选文件间强交叉引用

registry / match / pipeline / convert 四个文件互相引用
`ProviderRegistration`（registry 11 处、pipeline 2 处、match 3 处、
convert 3 处）与 `PrismOptions`——拆包后这些裸符号全部要加包前缀，
且任一子包都需要 `ProviderRegistration` 类型，把它放哪都会引发
「类型 vs 逻辑」的归属分歧。

## 3. 结论

**本轮不拆 sdk 包**，维持单包平铺。理由：

1. 与 lux 同因：36 个 inherent methods 是语言硬约束，拆包必须 trait/
   顶层函数化，47 处外部调用点全改，风险远超收益
2. struct 字段非 pub 是保护性设计，拆包强制扩大公开 API 面
3. 四个文件间的强交叉引用使子包边界本身就不清晰（registry 被 4 个
   文件共用），拆了也是「类型包 + 逻辑包」双向紧绑定，收益低
4. 现状单包 1300 行、62 个 pub，规模远小于 lux（4484 行 / 232 pub），
   尚无独立复用需求

## 4. 附：与 lux 测量的一致性

- lux 测量（docs/report/lux-split-feasibility.md）：70 个 inherent methods
  → 不拆
- sdk 测量（本文档）：36 个 inherent methods，同因 → 不拆
- 结论写入 docs/architecture.md Current decisions，两条决策一致：
  「类型定义与其方法（含序列化/注册逻辑）在 MoonBit 中构成不可拆单元，
  文件级拆分即结构边界」
