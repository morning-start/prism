# Prism 项目文档梳理报告

> 产出：PM Agent · 2026-10-24
> 输入：docs/ 全量索引 + 核心 docs 节选阅读（README/status/architecture/dod/test-report/fidelity-matrix/rules×3/design/provider-guide/CR-004~006/USAGE）
> 用途：单一事实源快照 + 文档债清单 + 下一步建议

## 1. 项目一句话

**Prism = LLM 协议转换引擎**（MoonBit 实现）：任意厂商 JSON/SSE 先 decode 进中立的
Lucent IR，再 encode 到目标协议；无两两转换器。两类消费者：Agent 框架 SDK（单
provider）与中转 middleware（N provider，可审计/改写/路由/过滤）。

- 当前状态：**1426 tests passing**（native + wasm-gc，2026-10-24）；未覆盖行 203 / 阈值 204
- 最近交付：官方 schema 校验 oracle（Node + ajv，五组检查）上线，`node tools/conformance/run-all.mjs`
- 版本线索：CR-006 批次 1 = `0.1.5`（d41d6bc）、批次 2 = `0.2.0`（方案 A 获批）

## 2. 文档地图（按职能分类）

### A. 架构与协议规范（单一事实源）
| 文档 | 职能 |
|---|---|
| docs/architecture.md | 架构决策源：分层、包职责、依赖方向、Current decisions（lux/sdk 不拆包等裁决） |
| docs/architecture-packages.md | 包依赖 Mermaid 图 + 各包文件职责 |
| docs/lux-ir-design.md | Lucent IR 正式 schema 规范（与 schemas/lux-ir-v1.json 互为镜像） |
| docs/api-protocol-converter.md | 协议转换契约：4 端点对照 + 12-case 最小矩阵 + 6 函数契约 |
| docs/fidelity-matrix.md | 4×4 保真度矩阵（Exact/Degraded/Unsupported/Invalid），切流决策依据 |
| docs/provider-guide.md | 新增 provider adapter 指南（6 函数契约 + 文件布局） |
| docs/design/finish-reason-contract.md | finish_reason 封闭枚举「目标白名单裁决」模型（CR-005 配套设计） |

### B. 进度与验收
| 文档 | 职能 |
|---|---|
| docs/status.md | **当前状态总入口**：模块完成度、测试清单、已知限制、IR backlog（最后更新 2026-10-24） |
| docs/dod.md | CR-001 迭代 DoD 核销（all_passed: true，2026-09-21） |
| docs/test-report.md | CR-001 针对性测试 + 回归报告（1196/1201 为当时快照） |
| docs/reports/iteration-003-acceptance.md | 迭代 003 验收报告（未入索引） |

### C. 变更单（CR，治理流水）
| 单号 | 主题 | 状态 |
|---|---|---|
| CR-001 | 流式 usage 保真（D1–D4） | 已修复并核销 |
| CR-002 | 相邻缺口收敛（A1/D5/A4/A3/A5） | 已修复 |
| CR-003 | BlockDiscard 去留 | 已决策 B：保留 + deprecated |
| CR-004 | IR 字段级保真（malformed_tool_call 对齐 schema、LucentMediaSource schema 修复） | **位置异常：在根目录 cr/ 而非 docs/cr/** |
| CR-005 | stop_sequence IR 载体 | 已决策 B 并实施（含 finish_reason 收敛器） |
| CR-006 | 流式终止信息载体（Finish 载荷，破坏性） | 已全部落地（0.1.5 + 0.2.0） |

### D. 规则（硬门禁）
| 文档 | 职能 |
|---|---|
| docs/rules/lucent-ir-evolution.md | IR 变更治理：影响面声明、保真度硬约束、破坏性判定 |
| docs/rules/naming-conventions.md | 全仓命名规则 |
| docs/rules/conformance-oracle.md | 官方 schema 校验系统设计与豁免治理（未入索引） |

### E. 入口与使用
README.mbt.md（根 README.md 是 1 行指针）· USAGE.md（4 场景使用指南）·
src/lux/README.md、src/sdk/README.md（包内导航）· schemas/（含 vendored 官方
openai-openapi.yaml）· skills/prism-wasm/ · .githooks/

### F. 计划类（superpowers，未入索引）
docs/superpowers/{plans,specs}/2026-09-10-provider-metadata-single-source-*

### G. Agent 工作区（.agent-workplace，gitignored）
当前仅剩 `scratch/`（探针脚本 + cov.txt）。AGENTS.md 描述的
plan/spec/task/report/checkpoint.json 结构与 `.moonbit-pipeline.json`
**在当前快照不存在**。

## 3. 文档债清单（本次梳理发现）

| # | 发现 | 影响 | 建议 |
|---|---|---|---|
| 1 | docs/README.md 索引漂移：缺 CR-004、CR-006、rules/conformance-oracle.md、reports/、superpowers/ | 新成员按索引会漏读关键文档 | 补全索引 |
| 2 | CR-004.md 位于根 `cr/`，其余 5 个 CR 在 `docs/cr/` | 变更单存放不一致，检索易漏 | 移入 docs/cr/（git mv） |
| 3 | status.md 标题「Implemented Providers (9 adapters)」与表格 4 行不符 | 数字口径混乱 | 改为 4 adapters（azure/vllm 属运行时注册变体） |
| 4 | AGENTS.md 的上下文恢复流程指向不存在的 checkpoint.json / .moonbit-pipeline.json / plan/spec/task 目录 | 按 AGENTS.md 恢复会扑空 | 二选一：补建骨架，或修订 AGENTS.md 说明 |
| 5 | wrappers/ts、wrappers/go 不在本仓库快照（status.md 已 ⚠️ 自标注） | 接入前需确认仓库同步并纳入 CI | 待确认，登记风险 |
| 6 | 团队共享工作区 default-workspace/team-workspace/docs/（需求池/变更记录/风险登记）不存在 | 3-Agent 协作无单一事实源落点 | 如需团队协作，先建骨架文档 |

## 4. 下一步建议（按优先级）

1. **P1 修索引与归位**：补 docs/README.md 索引 + git mv cr/CR-004.md → docs/cr/ + 修 status.md 计数（#1/#2/#3）。
2. **P2 决策**：AGENTS.md 恢复流程与实际快照不一致（#4），需 TL 确认是重建 state 还是改文档。
3. **P3 团队协作骨架**：确认是否启用 team-workspace/docs（需求池、任务板、变更记录、风险登记）。

## 5. 执行结果（2026-10-24 二轮迭代）

| # | 项 | 结果 |
|---|---|---|
| P1 | CR-004 归位 + 索引补全 + adapter 计数修正 | ✅ commit `360a340`（rename 100%，无旧路径引用残留） |
| P2 | AGENTS.md 恢复流程改为以 docs/status.md / docs/README.md 为入口，`.agent-workplace` 标注「按需创建、勿假设存在」，并声明 `.moonbit-pipeline.json`/`modes/README.md` 在本快照不存在 | ✅ 已提交（采 TL 替代方案：改文档而非重建 state） |
| P3 | 团队协作骨架 `default-workspace/team-workspace/docs/`（00-需求池 / 01-调研与竞品 / 05-任务板 / 06-风险与依赖 / 09-变更记录） | ✅ 建于 DSH profile 侧（`C:\Users\Hanes\.dsh\profiles\desktop\default-workspace\team-workspace\docs\`），不污染 git 仓库 |
| #5 | wrappers/ts、wrappers/go 缺失 | 保留为风险（status.md 已自标注），接入前需用户确认仓库同步 |
