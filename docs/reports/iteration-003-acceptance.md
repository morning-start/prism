# Iteration-003 验收记录（DoD 定稿 + 测试报告定稿）

> 日期：2026-09-09　状态：final（正式文档，随 git 提交）
> 迭代：iteration-003　方略：spec　主题：协议转换形式化验证 P0（L3 属性测试 + schema conformance）
> 关联：`docs/lux-ir-design.md`、`docs/api-protocol-converter.md`、
> `.agent-workplace/docs/design/formal-verification-design.md`（设计决策，过程态）
> 过程态草稿：`.agent-workplace/iterations/iteration-003/release/`（test-report.md、dod-checklist.md、gray-release.md）

## 1. DoD 核销（fst-review checklist）

| # | 核销项 | 必须 | 结果 | 证据 |
|---|---|---|---|---|
| 1 | 功能完成（含骨架冒烟通过） | ✅ | ✅ | 7/7 批次完成；无未确认需求骨架 |
| 2 | 变更针对性测试通过 | ✅ | ✅ | 8 个改动点逐一验证（§3） |
| 3 | 核心主干回归通过 | ✅ | ✅ | native 844/844 + wasm-gc 844/844 + fmt/check + drift 双 PASS（§4） |
| 4 | 文档同步（设计/任务文档） | ✅ | ✅ | design/plan/task/iteration-info/checkpoint 已更新 |
| 5 | 变更记录归档 | ✅ | ✅ | 6 提交 + 1 合并（8ec9815）至 master |
| 6 | 待定需求不纳入交付验收 | — | ✅ | P1/P2 预留后续迭代 |

**`all_passed = true`**，放量决策：**全量放行**（用户确认，2026-09-09）。

## 2. 本轮交付

| 批次 | 交付 |
|---|---|
| 1.1 | @qc 生成器扩展（`gen_text_resp` / `gen_extended_req`，构造器驱动） |
| 1.2 | G4 诊断完备性属性测试（4 adapter × 100 轮）→ 修复 4 处静默丢弃 |
| 1.3 | G5 跨协议差分属性测试（request+response × 100 轮）→ 修复 gemini 响应丢 id/model |
| 2.1 | drift 脚本扩展 adapter 输出侧（输出字段 ⊆ 协议字段集） |
| 2.2 | 属性级 conformance（4 adapter × request/response × 100 轮） |
| 3.1 | CI conformance job（drift -Strict + 属性测试） |
| 3.2 | 技术债 5 项 + 回顾报告 |

测试规模：833 → **844**（+11，8 个新属性测试）。

## 3. 变更针对性测试（改动点 + 关联影响点）

| 改动点 | 变更内容 | 针对性验证 | 结果 |
|---|---|---|---|
| `src/provider/openai/request_encode.mbt` | Thinking → Unsupported 诊断；annotations → Degraded | G4 openai 100 轮 + openai wbtest + convert_matrix | ✅ |
| `src/provider/messages/request_encode.mbt` | annotations → Degraded | G4 messages 100 轮 + wbtest | ✅ |
| `src/provider/responses/request_encode.mbt` | annotations → Degraded；Audio/Native → Unsupported | G4 responses 100 轮 + wbtest | ✅ |
| `src/provider/gemini/request_encode.mbt` | annotations → Degraded；Image/Audio/Native → Unsupported | G4 gemini 100 轮 + wbtest | ✅ |
| `src/provider/gemini/response.mbt` | 补 model/modelVersion，id/model 保真 | G5 response 100 轮 + wbtest | ✅ |
| `scripts/check_schema_drift.ps1` | adapter 输出字段 ⊆ 协议字段集 | SelfTest + report/strict 实跑 | ✅ |
| `src/sdk/test/*`（4 新属性文件） | G4/G5/conformance/生成器 | 各 100/100 轮 | ✅ |
| `.github/workflows/ci.yml` | conformance job | yaml 校验 + 本地等价命令 | ✅ |

## 4. 核心回归

| 回归面 | 结果 |
|---|---|
| `moon test --target native` | 844/844 ✅ |
| `moon test --target wasm-gc` | 844/844 ✅ |
| `moon fmt --check` / `moon check` | ✅ |
| `check_schema_drift.ps1 -SelfTest` | PASS（version/required/enum/stream_event/adapter_field）✅ |
| `check_schema_drift.ps1 -Strict` | PASS，零漂移 ✅ |
| `moon info`（.mbti） | 无意外变化 ✅ |

## 5. 缺陷清单（属性测试暴露并修复）

| # | 缺陷 | 来源 | 处置 |
|---|---|---|---|
| BUG-003-1 | openai-chat 静默丢弃 thinking 块 | G4 | 已修复（Unsupported 诊断） |
| BUG-003-2 | 4 adapter 静默丢弃 text annotations | G4 | 已修复（Degraded 诊断） |
| BUG-003-3 | responses/gemini 兜底丢弃 audio/native/image | G4 | 已修复（Unsupported 诊断） |
| BUG-003-4 | gemini 响应编码丢失 id/model | G5 | 已修复（model/modelVersion） |

## 6. 灰度与放量

- 变更性质：库（MoonBit package），无独立服务流量；灰度观察期 = 合入后一个 CI 周期 + 下游首个升级周期。
- 指标：通过率 100%（≥99% ✅）、错误率 0（<0.5% ✅）、无 P0 ✅、零漂移 ✅、.mbti 无意外 ✅。
- 回滚预案：`git revert 8ec9815`（单提交回滚）；新增诊断仅追加 `ConversionResult.diagnostics`，`value` 结构不变，对按 value 消费的下游无破坏。
- 决策：**全量放行**（用户确认）。灰度期新问题 → 需求池 / fst-change。

## 7. 技术债（不影响放行）

TD-FV-1..5：官方端点 schema 未获取；生成器未覆盖全部扩展变体（AgentAction 等）；drift 字段集手工维护；G5 生成域收窄；L2（moon prove）**已暂缓**（2026-09-09 决策：工具链缺失 + L3 已验证主体路径；重启条件见 design 文档 §9）。
