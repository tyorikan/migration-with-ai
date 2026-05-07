#!/bin/bash
# =============================================================
# workshop-state.json バリデーションスクリプト
#
# workshop-state.schema.json と照合して以下を検証する:
#   - 必須トップレベルキーの存在
#   - 各 Step の必須キー（status / phases / review）
#   - review.{score, gate_passed, reviewed_at, feedback_file} の存在と型
#   - status / review.mode の enum 適合
#   - review.score の範囲（0〜5）
#   - 不明キー（型崩れ早期検知）
#
# 使い方:
#   ./scripts/validate-state.sh                    # 既定の workshop-state.json を検証
#   ./scripts/validate-state.sh path/to/state.json # 任意ファイルを指定
#
# 終了コード:
#   0 = OK（警告のみは含む）
#   1 = エラー（必須キー欠落 / 型不一致 / enum 違反 / 範囲外）
#   2 = 警告のみ（不明キー検出など）
# =============================================================

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

WORKSHOP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
STATE_FILE="${1:-$WORKSHOP_DIR/workshop-state.json}"
SCHEMA_FILE="$WORKSHOP_DIR/workshop-state.schema.json"

errors=0
warnings=0

err()  { echo -e "  ${RED}❌${NC} $*"; errors=$((errors+1)); }
warn() { echo -e "  ${YELLOW}⚠️${NC}  $*"; warnings=$((warnings+1)); }
ok()   { echo -e "  ${GREEN}✅${NC} $*"; }

# -------------------------------------------------------
# 前提チェック
# -------------------------------------------------------
echo -e "${BLUE}━━━ workshop-state.json バリデーション ━━━${NC}"
echo "  対象: $STATE_FILE"
echo "  スキーマ: $SCHEMA_FILE"
echo ""

if ! command -v jq &>/dev/null; then
  err "jq がインストールされていません"
  exit 1
fi

if [ ! -f "$STATE_FILE" ]; then
  err "state ファイルが存在しません: $STATE_FILE"
  exit 1
fi

if [ ! -f "$SCHEMA_FILE" ]; then
  warn "schema ファイルが存在しません: $SCHEMA_FILE （構造チェックは続行）"
fi

if ! jq empty "$STATE_FILE" 2>/dev/null; then
  err "JSON としてパースできません: $STATE_FILE"
  exit 1
fi

# -------------------------------------------------------
# 1. トップレベル必須キー
# -------------------------------------------------------
echo "[1] トップレベル必須キー"
required_top=("workshop_id" "target_model" "source_dir" "started_at" "steps")
for key in "${required_top[@]}"; do
  if jq -e "has(\"$key\")" "$STATE_FILE" >/dev/null; then
    ok "$key"
  else
    err "必須キー欠落: $key"
  fi
done

# 不明トップレベルキー（警告）
known_top_pattern='^(workshop_id|target_model|source_dir|started_at|steps)$'
unknown_top=$(jq -r 'keys[]' "$STATE_FILE" | grep -vE "$known_top_pattern" || true)
if [ -n "$unknown_top" ]; then
  while IFS= read -r key; do
    [ -n "$key" ] && warn "不明なトップレベルキー: $key"
  done <<< "$unknown_top"
fi

# -------------------------------------------------------
# 2. target_model / source_dir の型
# -------------------------------------------------------
echo ""
echo "[2] トップレベル値の型"
target_model_type=$(jq -r '.target_model | type' "$STATE_FILE")
if [ "$target_model_type" = "string" ]; then
  ok "target_model is string ($(jq -r '.target_model' "$STATE_FILE"))"
else
  err "target_model は string であるべき（現在: $target_model_type）"
fi

source_dir_type=$(jq -r '.source_dir | type' "$STATE_FILE")
if [ "$source_dir_type" = "string" ]; then
  ok "source_dir is string ($(jq -r '.source_dir' "$STATE_FILE"))"
else
  err "source_dir は string であるべき（現在: $source_dir_type）"
fi

# started_at: string or null
started_at_type=$(jq -r '.started_at | type' "$STATE_FILE")
if [ "$started_at_type" = "string" ] || [ "$started_at_type" = "null" ]; then
  ok "started_at type ok ($started_at_type)"
else
  err "started_at は string か null であるべき（現在: $started_at_type）"
fi

# -------------------------------------------------------
# 3. 各 Step の構造
# -------------------------------------------------------
echo ""
echo "[3] 各 Step の構造"

allowed_status='not_started pending in_progress completed failed skipped'
allowed_review_modes='independent_context self_review manual'

steps=$(jq -r '.steps | keys[]' "$STATE_FILE")

if [ -z "$steps" ]; then
  warn ".steps が空"
fi

while IFS= read -r step; do
  [ -z "$step" ] && continue
  echo ""
  echo "  ─ $step"

  # 必須キー
  for k in status phases review; do
    if jq -e ".steps.\"$step\" | has(\"$k\")" "$STATE_FILE" >/dev/null; then
      ok "  $step.$k"
    else
      err "  $step.$k が欠落"
    fi
  done

  # 不明キー（step 直下）
  known_step_pattern='^(status|phases|metrics|consistency|review)$'
  unknown_step=$(jq -r ".steps.\"$step\" | keys[]" "$STATE_FILE" 2>/dev/null | grep -vE "$known_step_pattern" || true)
  if [ -n "$unknown_step" ]; then
    while IFS= read -r k; do
      [ -n "$k" ] && warn "  $step に不明キー: $k"
    done <<< "$unknown_step"
  fi

  # status enum
  if jq -e ".steps.\"$step\" | has(\"status\")" "$STATE_FILE" >/dev/null; then
    status_val=$(jq -r ".steps.\"$step\".status" "$STATE_FILE")
    if echo "$allowed_status" | tr ' ' '\n' | grep -qx "$status_val"; then
      ok "  $step.status = $status_val"
    else
      err "  $step.status は enum 違反: $status_val（許容: $allowed_status）"
    fi
  fi

  # phases.*.status
  if jq -e ".steps.\"$step\".phases" "$STATE_FILE" >/dev/null 2>&1; then
    phases=$(jq -r ".steps.\"$step\".phases | keys[]" "$STATE_FILE" 2>/dev/null || true)
    while IFS= read -r ph; do
      [ -z "$ph" ] && continue
      if jq -e ".steps.\"$step\".phases.\"$ph\" | has(\"status\")" "$STATE_FILE" >/dev/null; then
        ph_status=$(jq -r ".steps.\"$step\".phases.\"$ph\".status" "$STATE_FILE")
        if ! echo "$allowed_status" | tr ' ' '\n' | grep -qx "$ph_status"; then
          err "  $step.phases.$ph.status は enum 違反: $ph_status"
        fi
      else
        err "  $step.phases.$ph に status が欠落"
      fi
    done <<< "$phases"
  fi

  # review 必須キー / 型
  if jq -e ".steps.\"$step\".review" "$STATE_FILE" >/dev/null 2>&1; then
    for k in score gate_passed reviewed_at feedback_file; do
      if ! jq -e ".steps.\"$step\".review | has(\"$k\")" "$STATE_FILE" >/dev/null; then
        err "  $step.review.$k が欠落"
      fi
    done

    # score: number|null, 0-5
    score_type=$(jq -r ".steps.\"$step\".review.score | type" "$STATE_FILE")
    if [ "$score_type" = "number" ]; then
      score_val=$(jq -r ".steps.\"$step\".review.score" "$STATE_FILE")
      in_range=$(jq -n --argjson s "$score_val" '($s >= 0 and $s <= 5)')
      if [ "$in_range" = "true" ]; then
        ok "  $step.review.score = $score_val"
      else
        err "  $step.review.score 範囲外: $score_val (0〜5)"
      fi
    elif [ "$score_type" = "null" ]; then
      ok "  $step.review.score = null"
    else
      err "  $step.review.score は number か null であるべき（現在: $score_type）"
    fi

    # gate_passed: boolean
    gp_type=$(jq -r ".steps.\"$step\".review.gate_passed | type" "$STATE_FILE")
    if [ "$gp_type" != "boolean" ]; then
      err "  $step.review.gate_passed は boolean であるべき（現在: $gp_type）"
    fi

    # reviewed_at: string|null
    ra_type=$(jq -r ".steps.\"$step\".review.reviewed_at | type" "$STATE_FILE")
    if [ "$ra_type" != "string" ] && [ "$ra_type" != "null" ]; then
      err "  $step.review.reviewed_at は string か null であるべき（現在: $ra_type）"
    fi

    # feedback_file: string|null
    ff_type=$(jq -r ".steps.\"$step\".review.feedback_file | type" "$STATE_FILE")
    if [ "$ff_type" != "string" ] && [ "$ff_type" != "null" ]; then
      err "  $step.review.feedback_file は string か null であるべき（現在: $ff_type）"
    fi

    # mode（任意）
    if jq -e ".steps.\"$step\".review | has(\"mode\")" "$STATE_FILE" >/dev/null; then
      mode_val=$(jq -r ".steps.\"$step\".review.mode" "$STATE_FILE")
      if ! echo "$allowed_review_modes" | tr ' ' '\n' | grep -qx "$mode_val"; then
        err "  $step.review.mode は enum 違反: $mode_val（許容: $allowed_review_modes）"
      fi
    fi

    # review 直下の不明キー
    known_review_pattern='^(score|gate_passed|reviewed_at|feedback_file|mode|report_path)$'
    unknown_review=$(jq -r ".steps.\"$step\".review | keys[]" "$STATE_FILE" 2>/dev/null | grep -vE "$known_review_pattern" || true)
    if [ -n "$unknown_review" ]; then
      while IFS= read -r k; do
        [ -n "$k" ] && warn "  $step.review に不明キー: $k"
      done <<< "$unknown_review"
    fi
  fi
done <<< "$steps"

# -------------------------------------------------------
# サマリ
# -------------------------------------------------------
echo ""
echo -e "${BLUE}━━━ バリデーション結果 ━━━${NC}"
if [ "$errors" -gt 0 ]; then
  echo -e "  ${RED}❌ ${errors} errors${NC}, ${YELLOW}${warnings} warnings${NC}"
  exit 1
elif [ "$warnings" -gt 0 ]; then
  echo -e "  ${GREEN}✅ 0 errors${NC}, ${YELLOW}⚠️  ${warnings} warnings${NC}"
  exit 2
else
  echo -e "  ${GREEN}✅ 0 errors, 0 warnings — schema 適合${NC}"
  exit 0
fi
