#!/bin/bash
# =============================================================
# Claude Code PostToolUse hook
#
# 目的:
#   Claude が workshop-state.json に触った直後にスキーマ検証を走らせ、
#   schema 違反になっていれば exit 2 で stderr を Claude に返し、
#   自己修正を促す。
#
# 監視対象:
#   - Write / Edit ツールが workshop-state.json を変更した
#   - Bash ツールが workshop-state.json または update-state.sh を含むコマンドを実行した
#
# 入力:
#   stdin から PostToolUse の JSON ペイロードを受け取る。
#   構造（抜粋）:
#     {
#       "tool_name": "Write" | "Edit" | "Bash" | ...,
#       "tool_input": {
#         "file_path": "...",     # Write/Edit の場合
#         "command": "..."         # Bash の場合
#       }
#     }
#
# 終了コード:
#   0 = 対象外 or 検証 PASS（Claude へのフィードバックなし）
#   2 = 対象 + 検証失敗（stderr が Claude のコンテキストに入り自己修正対象）
# =============================================================

set -uo pipefail

WORKSHOP_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
VALIDATE="$WORKSHOP_DIR/scripts/validate-state.sh"
STATE_FILE_BASENAME="workshop-state.json"

# stdin から JSON を読む（パイプ未提供なら何もしない）
if [ -t 0 ]; then
  exit 0
fi

payload=$(cat)
if [ -z "$payload" ]; then
  exit 0
fi

# jq が無ければスキップ（hook で環境を壊さない）
if ! command -v jq &>/dev/null; then
  exit 0
fi

tool_name=$(jq -r '.tool_name // empty' <<<"$payload" 2>/dev/null)
[ -z "$tool_name" ] && exit 0

# 対象判定
relevant=0
case "$tool_name" in
  Write|Edit|MultiEdit|NotebookEdit)
    file_path=$(jq -r '.tool_input.file_path // empty' <<<"$payload" 2>/dev/null)
    if [[ "$file_path" == *"$STATE_FILE_BASENAME" ]]; then
      relevant=1
    fi
    ;;
  Bash)
    command_str=$(jq -r '.tool_input.command // empty' <<<"$payload" 2>/dev/null)
    if echo "$command_str" | grep -qE "(${STATE_FILE_BASENAME}|update-state\.sh)"; then
      relevant=1
    fi
    ;;
esac

[ "$relevant" -eq 0 ] && exit 0

# validate-state.sh が無ければスキップ
if [ ! -x "$VALIDATE" ]; then
  exit 0
fi

# 検証実行（出力は捕捉して、失敗時のみ stderr へ）
if output=$("$VALIDATE" 2>&1); then
  # PASS（warning のみ含む exit=2 もここでは success 扱いとして無視）
  exit 0
fi

ec=$?

# exit 2（warning のみ）は致命的でないので飛ばす
if [ "$ec" -eq 2 ]; then
  exit 0
fi

# exit 1: schema 違反 → Claude に返す
{
  echo "❌ workshop-state.json が schema 違反になりました（PostToolUse hook 検知）"
  echo ""
  echo "■ きっかけのツール: $tool_name"
  case "$tool_name" in
    Write|Edit|MultiEdit|NotebookEdit)
      echo "■ 対象ファイル: $(jq -r '.tool_input.file_path // ""' <<<"$payload" 2>/dev/null)"
      ;;
    Bash)
      echo "■ 実行コマンド: $(jq -r '.tool_input.command // ""' <<<"$payload" 2>/dev/null)"
      ;;
  esac
  echo ""
  echo "■ validate-state.sh の出力:"
  echo "$output"
  echo ""
  echo "→ workshop-state.json を schema (workshop-state.schema.json) に適合する形に修正してください。"
  echo "  典型的な原因: スコアの誤ったパス（.steps.stepN.score → 正しくは .steps.stepN.review.score）、"
  echo "  status の enum 違反、必須キー欠落、score の範囲外（0〜5）など。"
} >&2

exit 2
