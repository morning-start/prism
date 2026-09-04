# Lux 拆包可行性测量报告

> 日期：2026-09-04
> 目的：测量将 `src/lux` 单包拆分为子包（lux 核心 + serialize/deserialize/stream）的
> 公开 API 影响与工作量，为 iteration-004 的拆包决策提供数据。
> 背景：architecture.md 记载「lux 拆包被延后，until public API and package-cycle impact are measured」。

---

## 1. 现状基线

- lux 包源码 15 个文件、约 4484 行（另有 8 个测试文件约 4755 行已迁入 `lux/test/`）
- pub 声明 232 个；`pub(all)` 类型 15 个（LucentRole/LucentModality/LucentMediaSource/
  LucentAnnotationKind/LucentContent/LucentConversationItem/LucentToolKind/
  LucentToolChoice 等 enum）
- 依赖方向：lux → internal + core；provider/sdk/wasm → lux（单向，健康）

## 2. 决定性约束：inherent methods 与字段可见性

### 2.1 70 个 `Type::method` 形态的 inherent methods

serialize/deserialize 文件中定义的全部是 inherent methods：

- 方法形态（`::`）：**70 个**（`LucentContent::to_json` / `LucentRequest::from_json` / …）
- 顶层函数：仅 1 个

MoonBit 规则：inherent methods 只能定义在**类型所在的包**内，不能跨包为类型
添加 `Type::method`。因此把 serialize/deserialize 拆到子包后，这 70 个方法
**必须**改写为以下之一，否则编译失败：

- trait（`trait LuxJson { fn to_json(...) }` + 各类型 impl）→ 所有调用点
  `@lux.X.to_json()` 需改为 trait 方法调用，波及 800+ 处外部调用
- 顶层函数（`fn x_to_json(x : X) -> String`）→ 同上全量改调用点

### 2.2 struct 字段非 pub

lux.mbt 中 `pub struct LucentRequest { schema_version : String ... }` 等字段
**均无 pub 前缀**（包内可见）。serialize/deserialize 大量通过 `self.<field>`
直接读字段（self.conversation / self.extra / self.choices / …约 30+ 字段）。

拆包后 serialize 子包访问这些字段需要：
- 全部字段加 pub（扩大公开 API 面，.mbti 大幅膨胀），或
- struct 整体 `pub(all)`（15 个 struct 全部），或
- 提供 getter（新增 30+ getter + 改 serialize 内部）

### 2.3 外部调用面

provider/sdk/wasm 对 `@lux.` 的方法调用高度集中于：

| 类型 | 外部调用次数 |
|------|-------------|
| LucentContent | 205 |
| LucentMessage | 144 |
| LucentRequest | 95 |
| LucentOptions | 92 |
| LucentConversationItem | 86 |
| 其余 20 类 | ≤45 |

这些调用点的形态（`::new` / `::to_json` / `::from_json` / 顶层函数）任何改变
都会产生全仓连锁修改，且 `.mbti` 全部重写。

## 3. 拆包方案对比

### 方案 A：lux → lux(core) + lux/codec（serialize+deserialize）

- 需要：70 个 inherent method → trait/顶层函数；30+ 字段 pub 化
- 影响：`@lux.` 800+ 调用点改造；.mbti 大规模重写；公开 API 面显著扩大
- 收益：包边界更清晰；**但** codec 与类型强耦合（方法/字段依赖），拆包后
  仍是「类型包 + codec 包」双向紧绑定，实质收益低
- 结论：**不推荐**（收益 << 成本，且违反"公开 API 稳定"治理）

### 方案 B：lux → lux(core) + lux/stream + lux/diagnostics

- stream.mbt（607 行）与 conversion_json.mbt（147 行）对类型的依赖以
  构造器/方法调用为主，拆包时**不需要**字段 pub 化（只调 pub 方法）
- diagnostics（ConversionDiagnostic/ConversionResult）独立性强，可先拆
- 影响：少量 import 路径调整；.mbti 仅新增子包文件、主包 pub 面不变
- 收益：中等；风险：低
- 结论：**可试点**，但仍需先确认 stream 内部对私有符号的引用

### 方案 C：不拆包，保持单包平铺（现状）

- architecture.md 既有决策延续；文件级拆分已做（serialize_meta/primitives/
  request/response/stream 等），单文件职责已清晰
- 结论：维持，直到有具体痛点（如编译时间、独立复用需求）

## 4. 决策建议

**本轮不拆 lux 包**。理由：

1. 70 个 inherent methods 是 MoonBit 语言层面的硬约束——拆 codec 必须
   trait/顶层函数化，改动面 800+ 调用点，风险远超收益
2. struct 字段非 pub 是保护性设计；拆包会强制扩大公开 API 面，与
   「扩展字段必须可选、公开 API 稳定」治理相悖
3. 现状单包内文件职责已拆分清晰，无实际维护痛点

**可选的低风险增强**（不拆包、纯文件内重组，若后续需要）：
- 将 ConversionDiagnostic/ConversionResult 等诊断类型集中到
  `lux/diagnostics.mbt` 单一文件（当前在 lux.mbt 内散落）
- 保持 serialize_*/deserialize_* 命名对称，已在 iteration-001 完成

## 5. 附：数据来源

- `grep -h "^pub fn [A-Z].*::" serialize_*.mbt deserialize_*.mbt` → 70 方法
- `grep -rhoE "@lux\.[A-Za-z_]+::" provider/ sdk/ wasm/` → 外部调用分布
- `grep -hoE "self\.[a-z_]+" serialize_*.mbt deserialize_*.mbt` → 字段访问面
- MoonBit 语言规则：inherent method 必须与类型同包（同包多文件编译，跨包不适用）
