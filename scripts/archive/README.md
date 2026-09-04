# scripts/archive（已归档，DEPRECATED）

> ⚠️ 本目录仅用于存放历史一次性脚本，**不要**在此新增脚本、**不要**在 CI /
> 文档中引用本目录内容。新工具脚本请直接放在 `scripts/` 根目录。

## 内容（历史一次性任务脚本）

| 文件 | 原用途 |
|---|---|
| `add_wasm_exports.py` | WASM 导出符号批量添加（一次性迁移） |
| `agnes_probe.sh` | AGNES 探测脚本（历史调研） |
| `analyze_agnes.py` | AGNES 响应分析（历史调研） |
| `analyze_warn.py` / `analyze_warn2.py` | lint 警告统计（iteration-003 清理时的一次性工具） |
| `apply_warn_fixes.py` | unnecessary_annotation 机械修复（iteration-003 用后即弃） |

这些脚本对应的任务均已完结，保留仅为历史追溯；如确认不再需要，可整体删除。
