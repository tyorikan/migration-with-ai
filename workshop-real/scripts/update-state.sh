#!/bin/bash
# =============================================================
# workshop-state.json 更新スクリプト
# 使い方:
#   ./scripts/update-state.sh <json_path> <value>
#
# 例:
#   ./scripts/update-state.sh .steps.step1.status completed
#   ./scripts/update-state.sh .steps.step1.phases.discover.status completed
#   ./scripts/update-state.sh .steps.step1.metrics.objects_found 8
#   ./scripts/update-state.sh .steps.step1.review.score 4.2
#   ./scripts/update-state.sh .steps.step1.review.gate_passed true
#   ./scripts/update-state.sh .started_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
# =============================================================

set -euo pipefail

WORKSHOP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
STATE_FILE="$WORKSHOP_DIR/workshop-state.json"

if [ ! -f "$STATE_FILE" ]; then
  echo "❌ workshop-state.json が見つかりません: $STATE_FILE"
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "❌ jq がインストールされていません。brew install jq でインストールしてください。"
  exit 1
fi

if [ "$#" -lt 2 ]; then
  echo "Usage: $0 <json_path> <value>"
  echo ""
  echo "Examples:"
  echo "  $0 .steps.step1.status completed"
  echo "  $0 .steps.step1.metrics.objects_found 8"
  echo "  $0 .steps.step1.review.gate_passed true"
  exit 1
fi

JSON_PATH="$1"
VALUE="$2"

# 値の型を自動判定して設定
if [[ "$VALUE" == "true" || "$VALUE" == "false" ]]; then
  # boolean
  jq "${JSON_PATH} = ${VALUE}" "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
elif [[ "$VALUE" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
  # number
  jq "${JSON_PATH} = ${VALUE}" "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
elif [[ "$VALUE" == "null" ]]; then
  # null
  jq "${JSON_PATH} = null" "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
elif [[ "$VALUE" == \[* ]]; then
  # array (JSON literal)
  jq "${JSON_PATH} = ${VALUE}" "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
else
  # string
  jq "${JSON_PATH} = \"${VALUE}\"" "$STATE_FILE" > "${STATE_FILE}.tmp" && mv "${STATE_FILE}.tmp" "$STATE_FILE"
fi

echo "✅ Updated ${JSON_PATH} = ${VALUE}"
