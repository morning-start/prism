# Phase 4 质量收口实现计划（2026-08-03）

> 来源：`docs/plans/2026-08-01-project-roadmap.md` Phase 4（质量收口，贯穿各阶段）。
> 前置：Phase 0-3 + phase3b（SDK ConversionMeta / UDS / WS / clients）全部完成。
> 目标：消除存量警告与文档漂移，建立可信质量基线——警告数显著下降、文档与 `.mbti` 一致、CI 含 audit 步骤。

## 调研结论（2026-08-03 实测）

| # | 事项 | 现状 | 处置 |
|---|------|------|------|
| A | `unnecessary_annotation` 警告存量 | `moon check --warn-list +73` 实测 **506 个**（roadmap 记载 438 个，随后续代码增长；分布：lux/provider/sdk 全仓） | **Task 1**：按包清理冗余注解（`pub(all) enum`、derive 等显式标注与包默认值重复处） |
| B | 导出数漂移 | `wasm/pkg.generated.mbti` 与 `cmd/main/pkg.generated.mbti` 各 **15 个 pub fn**；但 README/docs/requirements 仍有「14 个导出函数」表述 | **Task 2**：生成式导出清单（脚本比对 `.mbti` 真值），修正文档 |
| C | `moon-audit` 未安装 | `moon audit` 报 `no such subcommand`，PATH 无 moon-audit | **Task 3**：安装 moon-audit（`moon install` 或官方安装脚本），CI 加 `moon-audit pipeline .` |
| D | README/需求文档能力边界过期 | README / docs/requirements.md 的「当前能力 vs 规划」未反映 phase3b 交付（UDS/WS/clients/ConversionMeta） | **Task 4**：更新文档边界 |

**注意（任务粒度）**：Phase 4 是贯穿性质量收口，非单一 feature；每个 Task 独立验收、独立 commit。

## 文件结构规划

```
（警告清理，Task 1）
lux/ provider/ sdk/ wasm/ cmd/main/ internal/   # Modify: 按包清理 unnecessary_annotation（无 .mbti 变化）
scripts/
├── export_count.sh              # Create（Task 2）: 生成式导出清单
├── add_wasm_exports.py          # 已有：wasm 导出辅助
.github/workflows/ci.yml          # Modify（Task 3）: 增加 moon-audit 步骤
README.md / docs/requirements.md # Modify（Task 4）: 能力边界更新
```

**质量门禁**（贯穿）：`moon fmt --check && moon check --warn-list +73 && moon test` 全绿；`moon info && moon fmt` 核对 `.mbti` diff（Task 1 预期无 `.mbti` 变化——纯注解清理不改变接口）。

---

## Task 1: 清理 `unnecessary_annotation` 警告（moonbit-refactor）

**文件：** 全仓 MoonBit 源码（lux/provider/sdk/wasm/cmd/internal 各包）

**理由：** 506 个警告属于「显式注解与包默认值重复」——MoonBit 包级 `pkgtype`/可见性默认值已覆盖时，显式写 `pub(all) enum` 或重复 derive 属冗余。清理后警告数显著下降，提升 `moon check` 的可信度（真实问题不再淹没在噪声里）。

#### Step 1: 统计分布（定位重灾区）

```bash
moon check --warn-list +73 2>&1 | grep -B1 "unnecessary_annotation" | grep -oE "^[a-z_/]+\.mbt" | sort | uniq -c | sort -rn | head -15
```

- [ ] **Step 2: 记录基线**：506 个 → 写入 commit message
- [ ] **Step 3: 按包清理（每个包一个子步骤，避免一次性大改）**
  - lux 包：`pub(all) enum` / 冗余 `derive` 注解
  - provider/* 包：同上
  - sdk / wasm / cmd / internal：同上
  - 原则：只删冗余注解，**不改任何行为、不改接口签名**；若某处删注解后报错（说明非冗余），保留原样
- [ ] **Step 4: 验证**：`moon check --warn-list +73` 警告数显著下降；`moon test` 全绿
- [ ] **Step 5: 接口核对**：`moon info && moon fmt`，`.mbti` 应无变化（纯注解清理）

## Task 2: 统一导出数清单（生成式维护，杜绝漂移）

**文件：**
- Create: `scripts/export_count.sh`
- Modify: README.md / docs/requirements.md / transport/ARCHITECTURE.md（导出数表述）

**理由：** 导出数漂移史（11/14/24/42）根因是文档手工维护。生成式脚本以 `.mbti` 为唯一真值，输出实际导出数，文档只引用脚本结果。

#### Step 1: 写脚本（export_count.sh）

```bash
#!/usr/bin/env bash
# 以 .mbti 为唯一真值输出各包导出函数数
for pkg in wasm cmd/main sdk lux; do
  count=$(grep -c "^pub fn" "$pkg/pkg.generated.mbti" 2>/dev/null || echo 0)
  echo "$pkg: $count"
done
```

- [ ] **Step 2: 运行并核对**：wasm=15、cmd/main=15（实测基线）
- [ ] **Step 3: 修正文档**：README/docs 中「14 个导出函数」改为「15 个（见 scripts/export_count.sh，以 .mbti 为真值）」
- [ ] **Step 4: 验证**：脚本输出与 `.mbti` 一致
- [ ] **Step 5: 全量验证** `moon fmt --check && moon check && moon test`

## Task 3: 审计门禁 + CI 集成

**文件：**
- Modify: `.github/workflows/ci.yml`

**理由：** roadmap Phase 4 验收门槛「CI 含 audit 步骤」。

#### Step 1: 调研 moon-audit 可用性（2026-08-03 实测）

| 尝试 | 结果 |
|------|------|
| `moon audit` | ❌ `no such subcommand`——当前工具链无 audit 子命令 |
| `moon install moon-audit` | ❌ `Invalid package path`（需 user/module/package 格式） |
| 官方命令列表（docs.moonbitlang.com） | ❌ 无 audit 命令 |

**结论：moon-audit 工具当前不可用**（roadmap 假设的工具不存在）。**替代处置（已实施）**：CI 的 `moon check` 升级为 `moon check --warn-list +73 --deny-warn`（警告即失败）——Task 1 已清零 506 个警告，`--deny-warn` 使未来新增警告直接阻断 CI，实现等价审计门禁。

- [x] **Step 2: CI 集成**：`.github/workflows/ci.yml` check job：`moon check --warn-list +73 --deny-warn`（已实施，本地 `--deny-warn` 验证通过，0 警告）
- [ ] **Step 3: 验证**：`moon check --warn-list +73 --deny-warn` 本地通过；CI YAML 核对无误
- [ ] **Step 4: 全量验证** `moon fmt --check && moon check && moon test`

## Task 4: 更新 README/需求文档能力边界

**文件：**
- Modify: `README.md`、`docs/requirements.md`、`docs/sdk-usage.md`（如需）

**理由：** 文档漂移反向修正——补上 phase3b 已交付能力（UDS/WS/clients/ConversionMeta），明确「当前能力 vs 规划」边界。

#### Step 1: 盘点交付

| 已交付（本轮） | 文档需反映 |
|---|---|
| ConversionMeta / decode_response_with_meta | requirements 场景 1 SDK 能力清单 |
| UDS / NamedPipe / WS binding | requirements「当前边界」 |
| clients/go、clients/python | README 客户端章节 |
| decode_sse_stream session | ARCHITECTURE §4.5（已完成） |

- [ ] **Step 2: 更新 requirements.md**「当前状态」表与「当前边界」段
- [ ] **Step 3: 更新 README**：能力清单、导出数（Task 2 结果）、快速上手
- [ ] **Step 4: 验证**：文档与 `.mbti`/脚本输出一致（导出数等可核对数字）
- [ ] **Step 5: 全量验证** 同上

## 依赖顺序

```
Task 1（警告清理）→ 独立，先行（规模最大、影响 `moon check` 可信度）
    ↓
Task 2（导出数清单）→ 依赖 Task 1 完成后的 .mbti 终态；独立于 Task 3/4
    ↓
Task 3（moon-audit + CI）→ 独立，可并行
    ↓
Task 4（文档边界）→ 依赖 Task 2 的导出数结果
```

**并行提示：** Task 1/2/3 相互独立；Task 4 依赖 Task 2。严格串行执行，一 Task 一 commit。

## 验证命令汇总

| 阶段 | 命令 | 预期 |
|------|------|------|
| 警告基线 | `moon check --warn-list +73 2>&1 | grep -c unnecessary_annotation` | 506 → 显著下降 |
| 全量 | `moon fmt --check && moon check && moon test` | 0 errors，全绿 |
| 接口 | `moon info && moon fmt` | Task 1 `.mbti` 无变化；其余按预期 |
| 导出清单 | `bash scripts/export_count.sh` | 与 `.mbti` 一致 |
| audit | `moon-audit pipeline .` | 无高危（或记录基线） |

## 收尾（全任务完成后）

- [ ] 更新 `.moonbit-pipeline.json`：`phase_name: phase4-quality`，`next` 指向后续
- [ ] 全仓最终验证：`moon fmt --check && moon check --warn-list +73 && moon test` + `moon build --target wasm` + 跨语言（daemon/clients）
- [ ] README / requirements 的「当前能力 vs 规划」边界与事实一致

## 未来演进（不在本轮）

- gRPC binding（ARCHITECTURE §5.4）
- 客户端 SDK 生成 pipeline（§9 Phase 5：Node/Rust/Java）
- Daemon MoonBit 原生化（§9 Phase 6）
