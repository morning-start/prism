#!/usr/bin/env bash
# agnes API reasoning 探测脚本
#
# 用法（在你的 shell 中，key 从本地 .env 读取，不经任何中转）：
#   export AGNES_API_KEY=$(grep -oP '^AGNES_API_KEY=\K.*' .env 2>/dev/null || grep -o '=.*' .env | head -1 | tr -d '=')
#   bash scripts/agnes_probe.sh
#
# 输出：
#   tmp/agnes_resp.json  非流式响应（含 message 字段，探测 reasoning）
#   tmp/agnes_sse.txt    流式响应（含 delta 字段，探测 delta.reasoning）

set -e
cd "$(dirname "$0")/.."
mkdir -p tmp

# 自动从 .env 读取 key（本脚本由你本地执行，key 只在你的进程里展开）
if [ -z "$AGNES_API_KEY" ]; then
  AGNES_API_KEY=$(grep -E '^[A-Za-z_]*KEY.*=' .env 2>/dev/null | head -1 | sed 's/^[^=]*=//' | tr -d '\r"'"'"' ')
  AGNES_API_KEY=${AGNES_API_KEY:-$(grep -oE 'sk-[A-Za-z0-9]+' .env 2>/dev/null | head -1)}
fi

if [ -z "$AGNES_API_KEY" ]; then
  echo "ERROR: 无法从 .env 读到 AGNES_API_KEY"
  exit 1
fi

URL="https://apihub.agnes-ai.com/v1/chat/completions"
PROMPT='请详细推理：9.11 和 9.8 哪个大？请先展示思考过程'

echo "==> 非流式请求..."
curl -s "$URL" \
  -H "Authorization: Bearer $AGNES_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"model\":\"agnes-2.0-flash\",\"messages\":[{\"role\":\"user\",\"content\":\"$PROMPT\"}]}" \
  > tmp/agnes_resp.json

echo "==> 流式请求..."
curl -s "$URL" \
  -H "Authorization: Bearer $AGNES_API_KEY" \
  -H "Content-Type: application/json" \
  -d "{\"model\":\"agnes-2.0-flash\",\"stream\":true,\"messages\":[{\"role\":\"user\",\"content\":\"$PROMPT\"}]}" \
  > tmp/agnes_sse.txt

echo "DONE: tmp/agnes_resp.json ($(wc -c < tmp/agnes_resp.json) bytes), tmp/agnes_sse.txt ($(wc -c < tmp/agnes_sse.txt) bytes)"
