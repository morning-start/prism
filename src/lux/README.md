# src/lux — Lucent IR 核心包（导航索引）

> MoonBit 目录 = 包：本目录是一个包，**不能**再建子文件夹（子文件夹 = 子包，
> 会破坏 inherent methods 与包环约束，见 `docs/report/lux-split-feasibility.md`）。
> 包内组织靠**文件名前缀 + 职责分区**，本文件为阅读导航。

## 文件地图

### 1. 类型与构造（先读这里）

| 文件 | 内容 |
|---|---|
| `types.mbt` | 全部 IR 类型定义（Lucent* struct/enum，含诊断 Conversion* 类型） |
| `builders.mbt` | 构造器（`LucentX::new/default/create` + with_* 副本方法） |
| `helpers.mbt` | 跨包辅助（lucent_* 提取函数、to_string/from_string 映射） |
| `stream.mbt` | 流事件类型（LucentStreamEvent / BlockAccumulator） |

### 2. 序列化（IR → JSON）

| 文件 | 内容 |
|---|---|
| `serialize_meta.mbt` | 元数据序列化 |
| `serialize_primitives.mbt` | 基础类型 to_json |
| `serialize_request.mbt` | LucentRequest → JSON |
| `serialize_response.mbt` | LucentResponse → JSON |
| `serialize_stream.mbt` | 流事件 → JSON |
| `diagnostics_json.mbt` | ConversionStatus/Diagnostic 的 JSON 编解码 |

### 3. 反序列化（JSON → IR）

| 文件 | 内容 |
|---|---|
| `deserialize_helpers.mbt` | get_*/parse_* 共享辅助 |
| `deserialize_primitives.mbt` | 基础类型 from_json（Modality~AgentAction） |
| `deserialize_content.mbt` | Content/Message/ConversationItem |
| `deserialize_tools.mbt` | Tool/ToolChoice/StructuredOutput |
| `deserialize_options.mbt` | Options/ReasoningConfig/Capabilities |
| `deserialize_request.mbt` / `deserialize_response.mbt` / `deserialize_stream.mbt` | 对应 to_json 的 from_json |

### 4. 测试

- `*_wbtest.mbt`：白盒测试（留包内，MoonBit 约束）
- `test/`：黑盒测试子包（public API 校验）

## 依赖方向

`types.mbt` → `builders/helpers` → `serialize_*/deserialize_*`（单向；
helpers 提供 to_string/from_string 给编解码复用）。

## 约定

- 新增类型 → `types.mbt`；新增构造器 → `builders.mbt`；新增辅助 → `helpers.mbt`
- 序列化与反序列化**成对**修改（serialize_X ↔ deserialize_X 一一对应）
- 遵循 `docs/rules/naming-conventions.md`
