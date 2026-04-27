#!/bin/bash
# =============================================================
# ワークショップ進行チェックスクリプト
# 使い方: ./scripts/check-progress.sh [step_number]
#   例: ./scripts/check-progress.sh       → 全 Step チェック
#       ./scripts/check-progress.sh 2     → Step 2 のみ
# =============================================================

set -euo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

WORKSHOP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$WORKSHOP_DIR"

check_file() {
  if [ -f "$1" ]; then
    echo -e "  ${GREEN}✅${NC} $(basename "$1")"
    return 0
  else
    echo -e "  ${RED}❌${NC} $(basename "$1") ${RED}(missing)${NC}"
    return 1
  fi
}

check_dir() {
  if [ -d "$1" ] && [ "$(ls -A "$1" 2>/dev/null)" ]; then
    local count
    count=$(find "$1" -type f | wc -l | tr -d ' ')
    echo -e "  ${GREEN}✅${NC} $(basename "$1")/ (${count} files)"
    return 0
  else
    echo -e "  ${RED}❌${NC} $(basename "$1")/ ${RED}(empty or missing)${NC}"
    return 1
  fi
}

# -------------------------------------------------------
step0() {
  echo -e "\n${BLUE}━━━ Step 0: 事前準備 ━━━${NC}"
  local ok=0 fail=0

  echo "  [ソースコード]"
  if check_dir "examples/force-app"; then ((ok++)); else ((fail++)); fi

  echo "  [データ]"
  local csv_count=0
  shopt -s nullglob
  local csv_files=(data/*.csv examples/data/*.csv)
  shopt -u nullglob
  csv_count=${#csv_files[@]}
  if [ "$csv_count" -gt 0 ]; then
    echo -e "  ${GREEN}✅${NC} CSV ファイル: ${csv_count} 件"
    for f in "${csv_files[@]}"; do
      echo "     $(basename "$f"): $(tail -n +2 "$f" | wc -l | tr -d ' ') レコード"
    done
    ((ok++))
  else
    echo -e "  ${RED}❌${NC} CSV ファイルが見つかりません"
    ((fail++))
  fi

  echo "  [ツール]"
  if command -v claude &>/dev/null; then
    echo -e "  ${GREEN}✅${NC} Claude Code: $(claude --version 2>/dev/null || echo 'installed')"
    ((ok++))
  else
    echo -e "  ${RED}❌${NC} Claude Code が見つかりません"
    ((fail++))
  fi

  if command -v docker &>/dev/null; then
    echo -e "  ${GREEN}✅${NC} Docker: $(docker --version 2>/dev/null | head -1)"
    ((ok++))
  else
    echo -e "  ${RED}❌${NC} Docker が見つかりません"
    ((fail++))
  fi

  echo -e "\n  ${GREEN}${ok} passed${NC}, ${RED}${fail} failed${NC}"
}

# -------------------------------------------------------
step1() {
  echo -e "\n${BLUE}━━━ Step 1: AI 設計逆起こし ━━━${NC}"
  local ok=0 fail=0

  if check_file "01-reverse-engineering/output/system_overview.md"; then ((ok++)); else ((fail++)); fi
  if check_file "01-reverse-engineering/output/migration_assessment.md"; then ((ok++)); else ((fail++)); fi

  # 内容チェック（Mermaid 図が含まれているか）
  if [ -f "01-reverse-engineering/output/system_overview.md" ]; then
    local mermaid_count
    mermaid_count=$(grep -c '```mermaid' "01-reverse-engineering/output/system_overview.md" 2>/dev/null || echo 0)
    if [ "$mermaid_count" -gt 0 ]; then
      echo -e "  ${GREEN}✅${NC} Mermaid 図: ${mermaid_count} 個"
      ((ok++))
    else
      echo -e "  ${YELLOW}⚠️${NC}  Mermaid 図が見つかりません"
      ((fail++))
    fi
  fi

  echo -e "\n  ${GREEN}${ok} passed${NC}, ${RED}${fail} failed${NC}"
}

# -------------------------------------------------------
step2() {
  echo -e "\n${BLUE}━━━ Step 2: DB スキーマ移行 + 実データ投入 ━━━${NC}"
  local ok=0 fail=0

  if check_file "02-schema-migration/output/generated_ddl.sql"; then ((ok++)); else ((fail++)); fi
  if check_file "02-schema-migration/output/import_data.py"; then ((ok++)); else ((fail++)); fi
  if check_file "02-schema-migration/output/data_validation.sql"; then ((ok++)); else ((fail++)); fi

  # Docker チェック
  if docker compose ps --format '{{.Name}}' 2>/dev/null | grep -q 'sfdc-migration-db'; then
    echo -e "  ${GREEN}✅${NC} PostgreSQL コンテナ: 起動中"
    ((ok++))

    # テーブル数チェック
    local table_count
    table_count=$(docker compose exec -T db psql -U app_user -d migration_db -t \
      -c "SELECT count(*) FROM pg_tables WHERE schemaname='public';" 2>/dev/null | tr -d ' ' || echo 0)
    if [ "$table_count" -gt 0 ]; then
      echo -e "  ${GREEN}✅${NC} テーブル数: ${table_count}"
      ((ok++))

      # レコード数
      echo "  [テーブル別レコード数]"
      docker compose exec -T db psql -U app_user -d migration_db -t \
        -c "SELECT tablename || ': ' || n_tup_ins || ' rows' FROM pg_stat_user_tables ORDER BY tablename;" \
        2>/dev/null | while read -r line; do
        [ -n "$line" ] && echo "     $line"
      done
    else
      echo -e "  ${YELLOW}⚠️${NC}  テーブルが作成されていません"
    fi
  else
    echo -e "  ${YELLOW}⚠️${NC}  PostgreSQL コンテナが起動していません"
  fi

  echo -e "\n  ${GREEN}${ok} passed${NC}, ${RED}${fail} failed${NC}"
}

# -------------------------------------------------------
step3() {
  echo -e "\n${BLUE}━━━ Step 3: TDD コードモダナイズ ━━━${NC}"
  local ok=0 fail=0

  if check_file "03-code-modernization/output/TEST_SCENARIOS.md"; then ((ok++)); else ((fail++)); fi
  if check_file "03-code-modernization/output/Dockerfile"; then ((ok++)); else ((fail++)); fi
  if check_file "03-code-modernization/output/requirements.txt"; then ((ok++)); else ((fail++)); fi

  for f in app/main.py app/config.py app/model/schemas.py app/router/resource.py app/usecase/resource.py app/repository/resource.py; do
    if check_file "03-code-modernization/output/$f"; then ((ok++)); else ((fail++)); fi
  done

  for f in tests/conftest.py tests/test_model.py tests/test_usecase.py tests/test_router.py; do
    if check_file "03-code-modernization/output/$f"; then ((ok++)); else ((fail++)); fi
  done

  # テスト実行結果
  if docker compose ps --format '{{.Name}}' 2>/dev/null | grep -q 'sfdc-migration-app'; then
    echo -e "  ${GREEN}✅${NC} App コンテナ: 起動中"
    ((ok++))
  else
    echo -e "  ${YELLOW}⚠️${NC}  App コンテナが起動していません"
  fi

  echo -e "\n  ${GREEN}${ok} passed${NC}, ${RED}${fail} failed${NC}"
}

# -------------------------------------------------------
step4() {
  echo -e "\n${BLUE}━━━ Step 4: 品質評価 ━━━${NC}"
  echo "  (議論ベースの Step — 成果物チェックなし)"
}

# -------------------------------------------------------
step5() {
  echo -e "\n${BLUE}━━━ Step 5: ロードマップ ━━━${NC}"
  local ok=0 fail=0

  if check_file "05-roadmap/output/adr.md"; then ((ok++)); else ((fail++)); fi
  if check_file "05-roadmap/output/roadmap.md"; then ((ok++)); else ((fail++)); fi
  if check_file "05-roadmap/output/action_items.md"; then ((ok++)); else ((fail++)); fi

  echo -e "\n  ${GREEN}${ok} passed${NC}, ${RED}${fail} failed${NC}"
}

# -------------------------------------------------------
# メイン
# -------------------------------------------------------
echo -e "${BLUE}==========================================${NC}"
echo -e "${BLUE}  🚀 SFDC モダナイゼーション WS 進捗チェック${NC}"
echo -e "${BLUE}==========================================${NC}"
echo -e "  ディレクトリ: ${WORKSHOP_DIR}"
echo -e "  実行日時: $(date '+%Y-%m-%d %H:%M:%S')"

STEP="${1:-all}"

case "$STEP" in
  0) step0 ;;
  1) step1 ;;
  2) step2 ;;
  3) step3 ;;
  4) step4 ;;
  5) step5 ;;
  all)
    step0
    step1
    step2
    step3
    step4
    step5
    ;;
  *)
    echo "Usage: $0 [0|1|2|3|4|5|all]"
    exit 1
    ;;
esac

echo -e "\n${BLUE}==========================================${NC}"
