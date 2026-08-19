# CR-001 变更申请单 — Provider 适配器「去样板化」重构（定稿）

- **change_id**: CR-001
- **提出时间**: 2026-08-19
- **提出人**: 用户（对话渠道）
- **状态**: 已归档（已确认，待实施）
- **分级**: 中度
- **范围**: A 组（样板函数抽取）
- **决策**: accepted
- **approved_by**: user
- **排期**: 本轮立即实施

---

## 1. 需求原文（逐字记录）

> 「架构还有能优化的么?有什么可以抽象为函数的?」（用户 2026-08-19，对话渠道）
> 后续指令：「fst进行」（要求按 flowstate 流程推进）

Agent 上一轮架构审查确认的具体需求：

对四个 provider 适配器（anthropic 1312 行 / chat 1294 行 / gemini 1217 行 / responses 1394 行，均为单文件）做「去样板化」重构。

## 2. 变更分级（已确认：中度）

| 选项 | 结论 |
|------|------|
| 中度（仅 A 组） | ✅ 已确认，本轮立即实施 |
| 重大（A + B 组） | ❌ 暂不实施，B 组（跨 provider 收敛）留待后续评估 |
| 含 C 组（全量） | ❌ 暂不实施，C 组（拆文件 / Json builder / SDK kind）另行立项 |

## 3. 实施范围（已确认：A 组 — 样板函数抽取）

- [x] `parse_protocol_json`：统一 8+ 处 `@json.parse catch` 样板
- [x] `ConversionResult::with_diagnostics(value, diagnostics)` 批量构造器（~10 处装配样板）
- [x] `unsupported(field, msg)` / `degraded(field, msg)` 诊断辅助（30+ 处重复）
- [x] 统一删除各 provider 自己的 `json_escape` / `escape_json` 包装，直接用 `@internal.json_escape`

## 4. 影响评估

| 维度 | 评估 |
|------|------|
| 是否改库（IR 字段/枚举） | 否 —— 不涉及 `lucent-ir-evolution.md` 治理 |
| 是否重构 | 是 —— 去样板化，行为不变为硬门槛 |
| 是否影响旧功能 | 否 —— 纯重构，全量测试回归为验收门槛 |
| `.mbti` 变化 | 新增 pub 辅助会更新 `.mbti`；需 `moon info` 检查 diff 是否预期 |
| 影响点清单 | `provider/anthropic`、`provider/gemini`、`provider/openai_chat`、`provider/openai_responses`、`lux`（诊断辅助） |
| 变更针对性测试 | 四个适配器请求/响应/流式转换测试全量回归；新增辅助的单元测试 |

## 5. 实施记录

- **分支**: `feature/cr-001-provider-deboilerplate`
- **提交**: 待填（功能分支提交后回填）
- **验证**: `moon fmt --check` ✅ / `moon check` ✅ / `moon test` 796/796 ✅
- **`.mbti` 变化**: 新增 4 个 pub 辅助（`parse_protocol_json`、`ConversionResult::with_diagnostics`、`ConversionDiagnostic::unsupported`、`ConversionDiagnostic::degraded`），符合预期
- **归档日期**: 2026-08-19
