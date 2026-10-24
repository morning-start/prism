#!/usr/bin/env bash
# Prism 本地全量校验 —— 与 CI 完全一致，一条命令跑完。
#
#   ./scripts/verify.sh              # 全部
#   ./scripts/verify.sh --oracle     # 仅官方 schema 校验（快速迭代时用）
#   ./scripts/verify.sh --no-oracle  # 跳过 Node 层（纯 MoonBit 检查）
#
# 前置：moon 已在 PATH；Node 层首次运行需 `cd tools/conformance && npm install`。
set -euo pipefail

cd "$(dirname "$0")/.."

RUN_MOON=1
RUN_ORACLE=1
for arg in "$@"; do
  case "$arg" in
    --oracle)    RUN_MOON=0 ;;
    --no-oracle) RUN_ORACLE=0 ;;
    *) echo "unknown flag: $arg"; exit 2 ;;
  esac
done

pass=0; fail=0
step() {
  local name="$1"; shift
  echo ""
  echo "▶ $name"
  if "$@"; then
    echo "  ✓ $name"; pass=$((pass+1))
  else
    echo "  ✗ $name"; fail=$((fail+1))
  fi
}

if [ "$RUN_MOON" = 1 ]; then
  step "moon fmt --check"                        moon fmt --check
  step "moon check --warn-list +73 --deny-warn"  moon check --warn-list +73 --deny-warn
  step "moon test --target native"               moon test --target native
  step "moon test --target wasm-gc"              moon test --target wasm-gc
fi

if [ "$RUN_ORACLE" = 1 ]; then
  if [ ! -d tools/conformance/node_modules ]; then
    echo ""
    echo "✗ tools/conformance/node_modules 不存在"
    echo "  请先运行: cd tools/conformance && npm install"
    fail=$((fail+1))
  else
    step "官方 schema 校验（Node oracle）" node tools/conformance/run-all.mjs
  fi
fi

echo ""
echo "════════════════════════════════════════"
echo "  通过 $pass 组，失败 $fail 组"
if [ "$fail" -gt 0 ]; then exit 1; fi
echo "  ✓ 全部校验通过"
