# 命名规则（Naming Conventions）

> 适用范围：Prism 全仓 MoonBit 代码。目标：任何新增/重构的代码，文件名、
> 函数名、类型名、测试名都遵循同一套规则，让目录"一眼可读"。
> 依据：iteration-006/007 全仓盘点（差异清单见
> `.agent-workplace/docs/task/iteration-006-naming.md` 与
> `.agent-workplace/docs/task/iteration-007-architecture-review.md`）。

---

## 1. 源码文件命名

### 1.1 包内文件不重复包名前缀

包路径已提供命名空间（`@lux` / `@sdk` / `@internal`），文件名**不得**再
重复包名。按职责命名：

| 包 | 现状（✅ 合规） | 违规待改 |
|---|---|---|
| lux | `types.mbt`、`stream.mbt`、`diagnostics_json.mbt`、`builders.mbt`、`helpers.mbt` | —（已统一，iteration-006） |
| internal | `json.mbt`、`extras.mbt`、`usage.mbt`、`sse.mbt` | — |
| sdk | `prism.mbt`、`context.mbt`、`convert.mbt`、`pipeline.mbt` 等 | — |
| provider/* | `capability.mbt`、`request_decode.mbt` 等六文件 | — |
| wasm | `convert.mbt`、`memory.mbt` | —（已统一，iteration-006；导出函数仍保留 `wasm_` 前缀，见 §3.1） |

### 1.2 编解码文件用功能前缀

成对出现的编解码文件，用 `serialize_*` / `deserialize_*` 功能前缀，且
两侧文件一一对应：

- `serialize_meta.mbt` ↔ `deserialize_meta.mbt`
- `serialize_primitives.mbt` ↔ `deserialize_primitives.mbt`
- `serialize_request.mbt` ↔ `deserialize_request.mbt`
- `serialize_response.mbt` ↔ `deserialize_response.mbt`
- `serialize_stream.mbt` ↔ `deserialize_stream.mbt`

反序列化大文件按职责进一步拆分（`deserialize_helpers/content/tools/options`
已合规）。

### 1.3 顶层类型文件

包内类型定义的"中枢文件"用 `types.mbt`（lux 已合规）。流事件类型独立为
`stream.mbt`。

## 2. 测试文件命名

### 2.1 后缀规则

- Whitebox（可达包内私有成员）：`*_wbtest.mbt`，**必须**留在被测包目录
- Blackbox（仅公开 API）：`*_test.mbt`，位于各包 `test/` 子包

### 2.2 前缀规则

测试文件名 = 被测模块名，与源码文件名一致：

| 源码 | 测试 |
|---|---|
| `types.mbt` / `builders.mbt` / `helpers.mbt` | `types_wbtest.mbt` / `builders_wbtest.mbt` / `helpers_wbtest.mbt` |
| `serialize_primitives.mbt` | `serialize_primitives_wbtest.mbt`（或合并的 `serialize_wbtest.mbt`） |
| `diagnostics_json.mbt` | `diagnostics_json_wbtest.mbt` |

历史违规已清零（iteration-006 修复：`conversion_json_wbtest.mbt` 已随源码
改名 `diagnostics_json_wbtest.mbt`；`lux_wbtest` 作为包级综合白盒测试保留）。

## 3. 函数命名

### 3.1 导出/ABI 函数

- provider 六函数契约（**固定不可改**，外部依赖）：
  `<proto>_to_lux_request` / `lux_request_to_<proto>` /
  `<proto>_to_lux_response` / `lux_response_to_<proto>` /
  `<proto>_sse_to_events` / `lux_events_to_<proto>_sse`
- wasm ABI 导出统一 `wasm_` 前缀（`wasm_to_lux_request`、
  `wasm_sdk_encode_request`、`wasm_convert_request`…）——导出符号
  前缀是契约的一部分，**保留**（即使源码文件名去掉 `wasm_` 前缀）

### 3.2 包内 pub/私有函数

- 动词开头（`parse_*` / `get_*` / `to_json` / `from_json` / `merge_*` /
  `extract_*`），小写下划线
- 序列化统一 `Type::to_json` / `Type::from_json` 方法形态（lux 已全部合规）
- 字符串映射统一 `Type::to_string` / `Type::from_string`（lux 已合规，
  如 `LucentFinishReason::to_string` / `LucentReasoningEffort::to_string`）

## 4. 类型命名

| 前缀 | 用途 | 示例 |
|---|---|---|
| `Lucent*` | Lux IR 核心类型 | `LucentRequest` / `LucentContent` / `LucentStreamEvent` |
| `Conversion*` | 诊断/转换结果 | `ConversionDiagnostic` / `ConversionResult` / `ConversionStatus` |
| `Sdk*` | SDK 层类型 | `SdkMessage` / `SdkTool` |
| `ProviderCapability` | 能力声明 | `ProviderCapability` |

已知不一致（**涉及 pub API，本轮不改**，记录为技术债）：
- sdk `ConvertMetaResult` / `ConversionMeta` vs lux `ConversionResult`——
  `Convert`/`Conversion` 前缀不统一，改名破坏 SDK 公开 API，留待大版本

## 5. 文件夹命名

### 5.1 目录 = 包边界

每个目录是一个 MoonBit 包，含 `moon.pkg`。目录名即包名，用**单数小写名词**
（`lux` / `sdk` / `internal` / `provider` / `wasm`）。

### 5.2 测试子目录

- blackbox 测试目录统一 `test/`（各包既有先例，无前缀）
- 禁止命名 `tests/` / `test_xxx/` / `unit/` 等变体

正例：`src/lux/test/`、`src/provider/openai/test/`
反例：`src/lux/tests/`、`src/lux/unit/`、`src/lux/test_helpers/`

### 5.3 目录内文件分组用前缀，不建多余子目录

MoonBit 目录 = 包，**包内不再建子目录**（同包平铺编译）。文件分组靠
**文件名前缀**表达职责族：

| 职责族 | 前缀 | 示例 |
|---|---|---|
| 序列化 | `serialize_` | `serialize_request.mbt` / `serialize_stream.mbt` |
| 反序列化 | `deserialize_` | `deserialize_content.mbt` / `deserialize_tools.mbt` |
| 适配器布局 | 无前缀六文件 | `capability.mbt` / `request_decode.mbt` … |

正例：`serialize_request.mbt` + `deserialize_request.mbt` 成对
反例：`src/lux/serialize/request.mbt`（错误地建子目录，违反"目录=包"）

## 6. 模块命名

### 6.1 包内模块 = 文件，命名 = 职责名词

包内每个 `.mbt` 文件是一个模块单元，文件名用**职责名词**（非动词、非泛词）：

| 职责 | 正例 | 反例 |
|---|---|---|
| 类型定义 | `types.mbt` | `main.mbt` / `defs.mbt` / `index.mbt` |
| 构造器 | `builders.mbt` | `create.mbt` / `new.mbt` |
| 辅助 | `helpers.mbt` | `utils.mbt` / `util.mbt` / `common.mbt` |
| 流事件 | `stream.mbt` | `events_all.mbt` |
| 转换编排 | `pipeline.mbt` | `convert_pipeline.mbt`（与 pipeline 语义重叠，sdk 待改） |

### 6.2 禁用词

- `utils` / `util` / `common` / `misc` / `others` —— 泛化收容所，掩盖职责
- `all` / `everything` / `anything` —— 无意义
- 与包内其他文件语义重叠的名字（如 `convert_pipeline.mbt` 与 `pipeline.mbt` 并存）

## 7. 变量命名

### 7.1 基本规则

- 局部变量：小写下划线（`result` / `cparts` / `item_id`）
- 缩写词按单词处理：`json_str`（非 `jsonStr`）、`sse`（非 `SSE`）
- 计数器：`i` / `j` / `k`（循环内短名可接受）；有语义时用全名（`block_index`）

### 7.2 正反示例

| 场景 | 正例 | 反例 |
|---|---|---|
| 反序列化结果 | `let parsed = @json.parse(s)` | `let data = ...` / `let x = ...` |
| 会话项数组 | `let items : Array[...]` | `let arr` / `let list` |
| 工具参数增量 | `let acc = acc + s` | `let temp` / `let tmp` |
| 布尔开关 | `let has_usage = true` | `let flag` / `let u` |

### 7.3 枚举变体与常量

- 枚举变体：帕斯卡命名（`Stop` / `ToolCalls` / `RateLimit`），随类型前缀
  （`LucentErrorKind::RateLimit`）
- 字符串常量映射：集中为 `Type::to_string` / `Type::from_string` 方法，
  禁止散落的字符串字面量 match（如 effort 档位映射已在
  `LucentReasoningEffort::to_string` 收敛）

## 8. 文档引用同步

改名源码文件时，同步更新以下文档中的路径引用：
- `docs/lux-ir-design.md`（类型定义引用）
- `docs/status.md`（测试清单与文件布局）
- `docs/architecture.md`（Current decisions / adapter 布局）
- `AGENTS.md` / `CLAUDE.md`（如涉及结构描述）

## 9. 验收

- 全仓 `ls */**.mbt`（排除 wbtest）无 `lux_`/`wasm_` 等包名前缀文件
- 编解码文件 `serialize_*`/`deserialize_*` 两侧对称
- 测试文件名与源码文件名一致（无"源码已改名、测试未跟随"）
- `moon fmt --check` / `moon check --warn-list +73 --deny-warn` /
  `moon test`（native + wasm-gc）全绿；`.mbti` 无意外 diff
