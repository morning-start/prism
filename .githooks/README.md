# Git Hooks

## Pre-commit Hook

L1 快速门禁：格式化 + 编译检查。

- `moon fmt --check` — 格式检查
- `moon check --target native` — 编译检查
- 安全扫描：检测 staged 文件中的密钥/凭证

## Pre-push Hook

L2 深度门禁：接口 + 编译 + 测试。

- `moon info --target native` — 接口变更检查
- `moon check --warn-list +73 --deny-warn` — 编译检查（deny-warn）
- `moon test --target native` — 完整测试
- `moon-audit` — 依赖审计（如已安装）

### Usage Instructions

1. Make the hooks executable if they aren't already:
   ```bash
   chmod +x .githooks/pre-commit .githooks/pre-push
   ```

2. Configure Git to use the hooks in the .githooks directory:
   ```bash
   git config core.hooksPath .githooks
   ```

3. The hooks will automatically run when you execute `git commit` and `git push`
