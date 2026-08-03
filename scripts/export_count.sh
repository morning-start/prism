#!/usr/bin/env bash
# 导出数清单 — 以 .mbti（moon info 生成的接口文件）为唯一真值。
# 用法：bash scripts/export_count.sh
# 文档中任何「N 个导出函数」的表述都应引用本脚本输出，杜绝手工维护漂移。
set -u

cd "$(dirname "$0")/.." || exit 1

pkgs=("lux" "sdk" "wasm" "cmd/main" "internal")
total=0
for pkg in "${pkgs[@]}"; do
  mbti="$pkg/pkg.generated.mbti"
  if [ -f "$mbti" ]; then
    count=$(grep -c "^pub fn " "$mbti")
  else
    count=0
  fi
  printf "%-10s %d\n" "$pkg" "$count"
  total=$((total + count))
done
printf "%-10s %d\n" "TOTAL" "$total"
