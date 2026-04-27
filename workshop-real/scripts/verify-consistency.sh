#!/bin/bash
# =============================================================
# Step 間整合性チェックスクリプト
# AI の自己申告に依存せず、成果物間のデータ整合性を機械的に検証する
#
# 使い方: ./scripts/verify-consistency.sh [step_pair]
#   例: ./scripts/verify-consistency.sh       → 全チェック
#       ./scripts/verify-consistency.sh 1-2   → Step 1→2 のみ
#       ./scripts/verify-consistency.sh 2-3   → Step 2→3 のみ
# =============================================================

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

WORKSHOP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$WORKSHOP_DIR"

TOTAL_OK=0
TOTAL_FAIL=0

# -------------------------------------------------------
# Step 1 → Step 2: ER 図のオブジェクト ⊆ DDL のテーブル
# -------------------------------------------------------
check_step1_to_step2() {
  echo -e "\n${BLUE}━━━ Step 1 → Step 2: オブジェクト ⊆ テーブル ━━━${NC}"

  local overview="01-reverse-engineering/output/system_overview.md"
  local ddl="02-schema-migration/output/generated_ddl.sql"

  if [ ! -f "$overview" ]; then
    echo -e "  ${YELLOW}⚠️${NC}  $overview が存在しません（Step 1 未完了）"
    return
  fi
  if [ ! -f "$ddl" ]; then
    echo -e "  ${YELLOW}⚠️${NC}  $ddl が存在しません（Step 2 未完了）"
    return
  fi

  # system_overview.md から erDiagram 内のエンティティ名を抽出
  local er_entities
  er_entities=$(sed -n '/```mermaid/,/```/p' "$overview" \
    | grep -oP '^\s+(\w+)\s+(||--|}o)' \
    | awk '{print $1}' \
    | sort -u 2>/dev/null || true)

  # フォールバック: erDiagram がパースできない場合、オブジェクト名のヘッダーから抽出
  if [ -z "$er_entities" ]; then
    er_entities=$(grep -oP '(?<=### )\w+' "$overview" | sort -u 2>/dev/null || true)
  fi

  # DDL から CREATE TABLE 名を抽出
  local ddl_tables
  ddl_tables=$(grep -oiP '(?<=CREATE TABLE\s)(IF NOT EXISTS\s+)?(\w+)' "$ddl" \
    | awk '{print $NF}' \
    | tr '[:upper:]' '[:lower:]' \
    | sort -u 2>/dev/null || true)

  if [ -z "$er_entities" ]; then
    echo -e "  ${YELLOW}⚠️${NC}  ER 図からオブジェクト名を抽出できませんでした"
    return
  fi

  echo "  [ER 図のエンティティ]"
  echo "$er_entities" | while read -r e; do [ -n "$e" ] && echo "    - $e"; done

  echo "  [DDL のテーブル]"
  echo "$ddl_tables" | while read -r t; do [ -n "$t" ] && echo "    - $t"; done

  # 差分チェック
  local missing
  missing=$(comm -23 <(echo "$er_entities" | tr '[:upper:]' '[:lower:]' | sort -u) \
                     <(echo "$ddl_tables" | sort -u) 2>/dev/null || true)

  if [ -z "$missing" ]; then
    echo -e "  ${GREEN}✅${NC} 全エンティティに対応するテーブルが存在"
    ((TOTAL_OK++))
  else
    echo -e "  ${RED}❌${NC} 以下のエンティティに対応テーブルがありません:"
    echo "$missing" | while read -r m; do [ -n "$m" ] && echo "     - $m"; done
    ((TOTAL_FAIL++))
  fi

  # workshop-state.json を更新（jq がある場合）
  if command -v jq &>/dev/null && [ -f "workshop-state.json" ]; then
    local er_count ddl_count
    er_count=$(echo "$er_entities" | grep -c . 2>/dev/null || echo 0)
    ddl_count=$(echo "$ddl_tables" | grep -c . 2>/dev/null || echo 0)
    ./scripts/update-state.sh .steps.step2.consistency.objects_in_er "$er_count" 2>/dev/null || true
    ./scripts/update-state.sh .steps.step2.consistency.tables_in_ddl "$ddl_count" 2>/dev/null || true
    if [ -n "$missing" ]; then
      local missing_json
      missing_json=$(echo "$missing" | jq -R -s 'split("\n") | map(select(. != ""))' 2>/dev/null || echo "[]")
      ./scripts/update-state.sh .steps.step2.consistency.missing_tables "$missing_json" 2>/dev/null || true
    fi
  fi
}

# -------------------------------------------------------
# Step 2 → Step 3: DDL のテーブル ⊆ SQLAlchemy モデル
# -------------------------------------------------------
check_step2_to_step3() {
  echo -e "\n${BLUE}━━━ Step 2 → Step 3: テーブル ⊆ モデル ━━━${NC}"

  local ddl="02-schema-migration/output/generated_ddl.sql"
  local models_dir="03-code-modernization/output/app"

  if [ ! -f "$ddl" ]; then
    echo -e "  ${YELLOW}⚠️${NC}  $ddl が存在しません（Step 2 未完了）"
    return
  fi
  if [ ! -d "$models_dir" ]; then
    echo -e "  ${YELLOW}⚠️${NC}  $models_dir が存在しません（Step 3 未完了）"
    return
  fi

  # DDL のテーブル名
  local ddl_tables
  ddl_tables=$(grep -oiP '(?<=CREATE TABLE\s)(IF NOT EXISTS\s+)?(\w+)' "$ddl" \
    | awk '{print $NF}' \
    | tr '[:upper:]' '[:lower:]' \
    | sort -u 2>/dev/null || true)

  # SQLAlchemy モデルの __tablename__
  local model_tables
  model_tables=$(grep -rhoP '(?<=__tablename__\s=\s["\x27])\w+' "$models_dir" \
    | tr '[:upper:]' '[:lower:]' \
    | sort -u 2>/dev/null || true)

  if [ -z "$ddl_tables" ]; then
    echo -e "  ${YELLOW}⚠️${NC}  DDL からテーブル名を抽出できませんでした"
    return
  fi

  echo "  [DDL テーブル数]: $(echo "$ddl_tables" | grep -c . 2>/dev/null || echo 0)"
  echo "  [モデル数]: $(echo "$model_tables" | grep -c . 2>/dev/null || echo 0)"

  local missing
  missing=$(comm -23 <(echo "$ddl_tables") <(echo "$model_tables") 2>/dev/null || true)

  if [ -z "$missing" ]; then
    echo -e "  ${GREEN}✅${NC} 全テーブルに対応するモデルが存在"
    ((TOTAL_OK++))
  else
    echo -e "  ${RED}❌${NC} 以下のテーブルに対応モデルがありません:"
    echo "$missing" | while read -r m; do [ -n "$m" ] && echo "     - $m"; done
    ((TOTAL_FAIL++))
  fi
}

# -------------------------------------------------------
# Step 3: テスト品質チェック（pytest 実行）
# -------------------------------------------------------
check_step3_tests() {
  echo -e "\n${BLUE}━━━ Step 3: テスト実行結果 ━━━${NC}"

  local output_dir="03-code-modernization/output"

  if [ ! -d "$output_dir/tests" ]; then
    echo -e "  ${YELLOW}⚠️${NC}  テストディレクトリが存在しません"
    return
  fi

  if [ ! -f "$output_dir/requirements.txt" ]; then
    echo -e "  ${YELLOW}⚠️${NC}  requirements.txt が存在しません"
    return
  fi

  echo "  [pytest 実行]"
  local test_result
  if cd "$output_dir" && \
     python3 -m pytest tests/ -v --tb=short 2>&1; then
    echo -e "  ${GREEN}✅${NC} 全テスト PASS"
    ((TOTAL_OK++))
  else
    echo -e "  ${RED}❌${NC} テスト FAIL あり"
    ((TOTAL_FAIL++))
  fi
  cd "$WORKSHOP_DIR"

  # ruff チェック
  echo "  [ruff check]"
  if cd "$output_dir" && python3 -m ruff check app/ tests/ 2>&1; then
    echo -e "  ${GREEN}✅${NC} ruff エラーなし"
    ((TOTAL_OK++))
  else
    echo -e "  ${RED}❌${NC} ruff エラーあり"
    ((TOTAL_FAIL++))
  fi
  cd "$WORKSHOP_DIR"
}

# -------------------------------------------------------
# DDL psql 検証（Docker 起動中の場合）
# -------------------------------------------------------
check_ddl_psql() {
  echo -e "\n${BLUE}━━━ Step 2: DDL psql 検証 ━━━${NC}"

  local ddl="02-schema-migration/output/generated_ddl.sql"

  if [ ! -f "$ddl" ]; then
    echo -e "  ${YELLOW}⚠️${NC}  DDL が存在しません"
    return
  fi

  if ! docker compose ps --format '{{.Name}}' 2>/dev/null | grep -q 'db'; then
    echo -e "  ${YELLOW}⚠️${NC}  PostgreSQL コンテナが起動していません（docker compose up -d db で起動してください）"
    return
  fi

  echo "  [DDL 適用テスト]"
  if docker compose exec -T db psql -U app_user -d migration_db -f "/workspace/$(basename "$ddl")" 2>&1 | tail -5; then
    echo -e "  ${GREEN}✅${NC} DDL 適用成功"
    ((TOTAL_OK++))
  else
    echo -e "  ${RED}❌${NC} DDL 適用でエラー発生"
    ((TOTAL_FAIL++))
  fi
}

# -------------------------------------------------------
# メイン
# -------------------------------------------------------
echo -e "${BLUE}==========================================${NC}"
echo -e "${BLUE}  🔍 Step 間整合性チェック${NC}"
echo -e "${BLUE}==========================================${NC}"
echo -e "  ディレクトリ: ${WORKSHOP_DIR}"
echo -e "  実行日時: $(date '+%Y-%m-%d %H:%M:%S')"

CHECK="${1:-all}"

case "$CHECK" in
  1-2) check_step1_to_step2 ;;
  2-3) check_step2_to_step3 ;;
  3)   check_step3_tests ;;
  ddl) check_ddl_psql ;;
  all)
    check_step1_to_step2
    check_step2_to_step3
    check_step3_tests
    check_ddl_psql
    ;;
  *)
    echo "Usage: $0 [1-2|2-3|3|ddl|all]"
    exit 1
    ;;
esac

echo -e "\n${BLUE}━━━ 結果サマリ ━━━${NC}"
echo -e "  ${GREEN}${TOTAL_OK} passed${NC}, ${RED}${TOTAL_FAIL} failed${NC}"
echo -e "${BLUE}==========================================${NC}"

exit "$TOTAL_FAIL"
