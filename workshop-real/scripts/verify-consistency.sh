#!/bin/bash
# =============================================================
# Step 間整合性チェックスクリプト
# AI の自己申告に依存せず、成果物間のデータ整合性を機械的に検証する
#
# 使い方: ./scripts/verify-consistency.sh [step_pair]
#   例: ./scripts/verify-consistency.sh       → 全チェック
#       ./scripts/verify-consistency.sh 1-2   → Step 1→2 のみ
#       ./scripts/verify-consistency.sh 2-3   → Step 2→3 のみ
#       ./scripts/verify-consistency.sh 3-4   → Step 3→4 のみ
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
# 抽出ロジック:
#   1. system_overview.md 内の `​```mermaid` フェンスのうち、
#      最初のトークンが `erDiagram` のブロックだけを対象とする。
#      （flowchart / stateDiagram / graph などは除外）
#   2. 対象ブロック内で以下の 2 種類の行からエンティティ名を取る:
#      - 関係行: `A ||--o{ B : "label"`  → $1 と $3 を採用（$2 が関係記号）
#      - 宣言行: `STORE {`               → $1 を採用（$2 が `{`）
#   3. SCREAMING_SNAKE_singular → snake_case_plural に変換し、DDL のテーブル
#      名と突き合わせる。プロジェクト命名規則のゆれ吸収のため、複数形が
#      見つからない場合は単数形でもフォールバック検索する。
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

  # ── ① erDiagram ブロックだけを抽出 ───────────────────────────────
  local er_block
  er_block=$(awk '
    /^```mermaid$/      { in_fence=1; in_er=0; next }
    /^```$/ && in_fence { in_fence=0; in_er=0; next }
    in_fence && $1 == "erDiagram" { in_er=1; next }
    in_er { print }
  ' "$overview")

  # ── ② エンティティ名抽出（関係行の両端 + 宣言行） ─────────────────
  # 関係記号セット: || }o }| ||--o{ }o--|| }|--|{ ||..|| 等
  # 文字としては | } { o . - のみで構成される
  local er_entities
  er_entities=$(echo "$er_block" | awk '
    # 関係行: $2 が関係記号らしき文字列
    $2 ~ /^[|}{o.\-]+$/ {
      if ($1 ~ /^[A-Za-z_][A-Za-z0-9_]*$/) print $1
      if ($3 ~ /^[A-Za-z_][A-Za-z0-9_]*$/) print $3
    }
    # 宣言行: `NAME {`
    $2 == "{" && $1 ~ /^[A-Za-z_][A-Za-z0-9_]*$/ { print $1 }
  ' | sort -u)

  if [ -z "$er_entities" ]; then
    echo -e "  ${RED}❌${NC} ER 図 (erDiagram) からエンティティを抽出できませんでした"
    echo -e "      ${YELLOW}→${NC} $overview に \`\`\`mermaid + erDiagram ブロックが存在するか確認してください"
    ((TOTAL_FAIL++)) || true
    return
  fi

  # ── ③ DDL のテーブル名抽出 ────────────────────────────────────────
  local ddl_tables
  ddl_tables=$(grep -oiP '(?<=CREATE TABLE\s)(IF NOT EXISTS\s+)?\w+' "$ddl" \
    | awk '{print $NF}' \
    | tr '[:upper:]' '[:lower:]' \
    | sort -u)

  # ── ④ ER エンティティ → 期待テーブル名（snake_case + 複数形） ────
  # ルール:
  #   - [子音]y$        → ies   (例: SUMMARY → summaries)
  #   - s|x|z|sh|ch$    → +es   (例: ADDRESS → addresses)
  #   - その他          → +s    (例: STORE → stores)
  # 注意: 不規則複数形（person→people 等）は未対応。
  #       SFDC オブジェクト名は通常規則変化のため実用上問題なし。
  pluralize_awk='
    function pluralize(n,    out) {
      out = tolower(n)
      if (out ~ /[bcdfghjklmnpqrstvwxz]y$/) {
        sub(/y$/, "ies", out)
      } else if (out ~ /(s|x|z|sh|ch)$/) {
        out = out "es"
      } else {
        out = out "s"
      }
      return out
    }
  '

  echo "  [ER 図 → 期待テーブル名]"
  while IFS= read -r ent; do
    [ -z "$ent" ] && continue
    local expected
    expected=$(echo "$ent" | awk "$pluralize_awk"'{ print pluralize($0) }')
    echo "    - $ent → $expected"
  done <<< "$er_entities"

  echo "  [DDL のテーブル]"
  echo "$ddl_tables" | while read -r t; do [ -n "$t" ] && echo "    - $t"; done

  # ── ⑤ 差分チェック（複数形 → 単数形 の順でフォールバック） ────────
  local missing=""
  while IFS= read -r ent; do
    [ -z "$ent" ] && continue
    local lc plural
    lc=$(echo "$ent" | tr '[:upper:]' '[:lower:]')
    plural=$(echo "$ent" | awk "$pluralize_awk"'{ print pluralize($0) }')
    if echo "$ddl_tables" | grep -qx "$plural"; then continue; fi
    if echo "$ddl_tables" | grep -qx "$lc";     then continue; fi
    missing+="${ent} (期待: ${plural} または ${lc})"$'\n'
  done <<< "$er_entities"

  local er_count
  er_count=$(echo "$er_entities" | grep -c .)

  if [ -z "$missing" ]; then
    echo -e "  ${GREEN}✅${NC} 全エンティティに対応するテーブルが存在 (${er_count} 件)"
    ((TOTAL_OK++)) || true
  else
    echo -e "  ${RED}❌${NC} 以下のエンティティに対応テーブルがありません:"
    echo "$missing" | while read -r m; do [ -n "$m" ] && echo "     - $m"; done
    ((TOTAL_FAIL++)) || true
  fi

  # ── ⑥ workshop-state.json を更新（jq がある場合） ─────────────────
  if command -v jq &>/dev/null && [ -f "workshop-state.json" ]; then
    local ddl_count
    ddl_count=$(echo "$ddl_tables" | grep -c .)
    ./scripts/update-state.sh .steps.step2.consistency.objects_in_er "$er_count" 2>/dev/null || true
    ./scripts/update-state.sh .steps.step2.consistency.tables_in_ddl "$ddl_count" 2>/dev/null || true
    if [ -n "$missing" ]; then
      local missing_json
      missing_json=$(echo "$missing" | jq -R -s 'split("\n") | map(select(. != ""))' 2>/dev/null || echo "[]")
      ./scripts/update-state.sh .steps.step2.consistency.missing_tables "$missing_json" 2>/dev/null || true
    else
      ./scripts/update-state.sh .steps.step2.consistency.missing_tables '[]' 2>/dev/null || true
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
    ((TOTAL_OK++)) || true
  else
    echo -e "  ${RED}❌${NC} 以下のテーブルに対応モデルがありません:"
    echo "$missing" | while read -r m; do [ -n "$m" ] && echo "     - $m"; done
    ((TOTAL_FAIL++)) || true
  fi
}

# -------------------------------------------------------
# Step 3: テスト品質チェック（pytest 実行）
# -------------------------------------------------------
# Python 解決順:
#   1. 03-code-modernization/output/.venv/bin/python があればそれを使う
#   2. なければシステム python3 にフォールバック
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

  local py
  if [ -x "$WORKSHOP_DIR/$output_dir/.venv/bin/python" ]; then
    py="$WORKSHOP_DIR/$output_dir/.venv/bin/python"
    echo "  [Python] $output_dir/.venv/bin/python (venv)"
  else
    py="python3"
    echo "  [Python] python3 (system) — venv 未検出"
  fi

  echo "  [pytest 実行]"
  if cd "$output_dir" && "$py" -m pytest tests/ -v --tb=short 2>&1; then
    echo -e "  ${GREEN}✅${NC} 全テスト PASS"
    ((TOTAL_OK++)) || true
  else
    echo -e "  ${RED}❌${NC} テスト FAIL あり"
    ((TOTAL_FAIL++)) || true
  fi
  cd "$WORKSHOP_DIR"

  # ruff チェック
  echo "  [ruff check]"
  if cd "$output_dir" && "$py" -m ruff check app/ tests/ 2>&1; then
    echo -e "  ${GREEN}✅${NC} ruff エラーなし"
    ((TOTAL_OK++)) || true
  else
    echo -e "  ${RED}❌${NC} ruff エラーあり"
    ((TOTAL_FAIL++)) || true
  fi
  cd "$WORKSHOP_DIR"
}

# -------------------------------------------------------
# DDL psql 検証（Docker 起動中の場合）
# -------------------------------------------------------
# 検証戦略:
#   - DDL を BEGIN; ... ROLLBACK; で囲んで stdin 経由で psql に流す。
#     → 構文と実行可能性を検証しつつ、データ破壊を防ぐ。
#       (DDL 冒頭の `DROP TABLE IF EXISTS ... CASCADE` で投入済み
#        データが消失する事故を避ける)
#   - ON_ERROR_STOP=1 で最初のエラーで停止。
#   - ファイルパスのマウント設定に依存しない。
# -------------------------------------------------------
check_ddl_psql() {
  echo -e "\n${BLUE}━━━ Step 2: DDL psql 検証 ━━━${NC}"

  local ddl="02-schema-migration/output/generated_ddl.sql"

  if [ ! -f "$ddl" ]; then
    echo -e "  ${YELLOW}⚠️${NC}  DDL が存在しません"
    return
  fi

  if ! docker compose ps --format '{{.Name}}' 2>/dev/null | grep -q 'sfdc-migration-db'; then
    echo -e "  ${YELLOW}⚠️${NC}  PostgreSQL コンテナが起動していません（docker compose up -d db で起動してください）"
    return
  fi

  # 投入前のレコード総数（データ保護の事後確認用）
  # DO ブロック内で全テーブルを動的に走査し RAISE NOTICE で結果を返す
  # （NOTICE は stderr に出るので 2>&1 でマージ）
  local count_sql='DO $$
DECLARE r record; total bigint := 0; cnt bigint;
BEGIN
  FOR r IN SELECT table_name FROM information_schema.tables WHERE table_schema = '"'"'public'"'"' LOOP
    EXECUTE format('"'"'SELECT count(*) FROM %I'"'"', r.table_name) INTO cnt;
    total := total + cnt;
  END LOOP;
  RAISE NOTICE '"'"'TOTAL_ROWS=%'"'"', total;
END $$;'
  local rows_before
  rows_before=$(docker compose exec -T db psql -U app_user -d migration_db \
    -c "$count_sql" 2>&1 | grep -oP 'TOTAL_ROWS=\K\d+' || echo "?")

  echo "  [DDL 適用テスト（トランザクション内 → ROLLBACK で巻き戻し）]"

  # BEGIN/ROLLBACK でラップして stdin 経由で投入（マウントパス非依存）
  local psql_output psql_exit
  psql_output=$(
    {
      echo "BEGIN;"
      cat "$ddl"
      echo "ROLLBACK;"
    } | docker compose exec -T db psql -U app_user -d migration_db \
        -v ON_ERROR_STOP=1 -q 2>&1
  )
  psql_exit=$?

  if [ "$psql_exit" -eq 0 ]; then
    echo -e "  ${GREEN}✅${NC} DDL 適用成功（ROLLBACK で巻き戻し済み）"
    ((TOTAL_OK++)) || true
  else
    echo -e "  ${RED}❌${NC} DDL 適用でエラー発生:"
    echo "$psql_output" | sed 's/^/      /' | tail -10
    ((TOTAL_FAIL++)) || true
  fi

  # データ保護の事後確認
  local rows_after
  rows_after=$(docker compose exec -T db psql -U app_user -d migration_db \
    -c "$count_sql" 2>&1 | grep -oP 'TOTAL_ROWS=\K\d+' || echo "?")

  if [ "$rows_before" != "?" ] && [ "$rows_after" != "?" ]; then
    if [ "$rows_before" = "$rows_after" ]; then
      echo -e "      ${GREEN}✓${NC} データ保護 OK (件数: ${rows_before} → ${rows_after})"
    else
      echo -e "      ${RED}✗${NC} データが変動しました (件数: ${rows_before} → ${rows_after})"
      ((TOTAL_FAIL++)) || true
    fi
  fi
}

# -------------------------------------------------------
# Step 3 → Step 4: Backend 同一性 + A2UI 拡張チェック
# -------------------------------------------------------
# 検証ポイント:
#   1. Step 3 の app/ が Step 4 に同一内容でコピーされているか (diff -rq)
#   2. Step 3 の tests/ が Step 4 に同一内容でコピーされているか
#   3. A2UI Agent ファイル (agent/*, main.py) が存在するか
#   4. main.py が get_fast_api_app() を使っているか
#   5. requirements.txt に google-adk, a2ui-agent-sdk が追加されているか
#   6. Renderer ディレクトリが存在するか
#   7. tools.py が HTTP クライアントではなく UseCase 直接呼び出しか
# 除外: __pycache__, *.pyc, .pytest_cache
# -------------------------------------------------------
check_step3_to_step4() {
  echo -e "\n${BLUE}━━━ Step 3 → Step 4: Backend 同一性 + A2UI Agent ━━━${NC}"

  local step3_dir="03-code-modernization/output"
  local step4_dir="04-frontend-a2ui/output"
  local diff_exclude="--exclude=__pycache__ --exclude=*.pyc --exclude=.pytest_cache"

  if [ ! -d "$step3_dir/app" ]; then
    echo -e "  ${YELLOW}⚠️${NC}  $step3_dir/app が存在しません（Step 3 未完了）"
    return
  fi
  if [ ! -d "$step4_dir" ]; then
    echo -e "  ${YELLOW}⚠️${NC}  $step4_dir が存在しません（Step 4 未完了）"
    return
  fi

  # ── ① app/ のバイトレベル同一性チェック ──────────────────────────
  echo "  [Step 3 app/ → Step 4 app/ 同一性]"
  if [ -d "$step4_dir/app" ]; then
    local app_diff
    app_diff=$(diff -rq $diff_exclude "$step3_dir/app" "$step4_dir/app" 2>/dev/null || true)
    if [ -z "$app_diff" ]; then
      local file_count
      file_count=$(find "$step3_dir/app" -name "*.py" -not -path "*__pycache__*" -type f | wc -l | tr -d ' ')
      echo -e "  ${GREEN}✅${NC} app/ が完全一致 (${file_count} ファイル)"
      ((TOTAL_OK++)) || true
    else
      echo -e "  ${RED}❌${NC} app/ に差分あり（Step 4 で破壊的変更の可能性）:"
      echo "$app_diff" | head -10 | while read -r m; do echo "     $m"; done
      ((TOTAL_FAIL++)) || true
    fi
  else
    echo -e "  ${RED}❌${NC} $step4_dir/app が存在しません（Backend 未コピー）"
    ((TOTAL_FAIL++)) || true
  fi

  # ── ② tests/ のバイトレベル同一性チェック ────────────────────────
  echo "  [Step 3 tests/ → Step 4 tests/ 同一性]"
  if [ -d "$step3_dir/tests" ]; then
    if [ -d "$step4_dir/tests" ]; then
      local tests_diff
      tests_diff=$(diff -rq $diff_exclude "$step3_dir/tests" "$step4_dir/tests" 2>/dev/null || true)
      if [ -z "$tests_diff" ]; then
        local test_count
        test_count=$(find "$step3_dir/tests" -name "*.py" -not -path "*__pycache__*" -type f | wc -l | tr -d ' ')
        echo -e "  ${GREEN}✅${NC} tests/ が完全一致 (${test_count} ファイル)"
        ((TOTAL_OK++)) || true
      else
        echo -e "  ${RED}❌${NC} tests/ に差分あり:"
        echo "$tests_diff" | head -10 | while read -r m; do echo "     $m"; done
        ((TOTAL_FAIL++)) || true
      fi
    else
      echo -e "  ${RED}❌${NC} $step4_dir/tests が存在しません"
      ((TOTAL_FAIL++)) || true
    fi
  else
    echo -e "  ${YELLOW}⚠️${NC}  $step3_dir/tests が存在しません（Step 3 テスト未生成）"
  fi

  # ── ③ A2UI Agent ファイル存在チェック ──────────────────────────
  # Agent ディレクトリ名は実装依存（agent/ または agent/<agent_name>/）のため
  # find で柔軟に検出する
  echo "  [A2UI Agent ファイル確認]"
  local agent_ok=true

  # main.py（エントリポイント）
  if [ -f "$step4_dir/main.py" ]; then
    echo -e "    ${GREEN}✓${NC} main.py"
  else
    echo -e "    ${RED}✗${NC} main.py が存在しません"
    agent_ok=false
  fi

  # agent.py（Agent 定義、サブディレクトリ内の場合あり）
  local agent_py
  agent_py=$(find "$step4_dir" -path "*/agent*" -name "agent.py" -type f 2>/dev/null | head -1)
  if [ -n "$agent_py" ]; then
    echo -e "    ${GREEN}✓${NC} ${agent_py#$step4_dir/}"
  else
    echo -e "    ${RED}✗${NC} agent.py が見つかりません（agent/ 配下に必要）"
    agent_ok=false
  fi

  # tools.py（Tool 定義）
  local tools_py
  tools_py=$(find "$step4_dir" -path "*/agent*" -name "tools.py" -type f 2>/dev/null | head -1)
  if [ -n "$tools_py" ]; then
    echo -e "    ${GREEN}✓${NC} ${tools_py#$step4_dir/}"
  else
    echo -e "    ${RED}✗${NC} tools.py が見つかりません（agent/ 配下に必要）"
    agent_ok=false
  fi

  if $agent_ok; then
    echo -e "  ${GREEN}✅${NC} A2UI Agent ファイル完備"
    ((TOTAL_OK++)) || true
  else
    echo -e "  ${RED}❌${NC} A2UI Agent ファイル不足"
    ((TOTAL_FAIL++)) || true
  fi

  # ── ④ main.py が get_fast_api_app() を使っているか ─────────────
  echo "  [main.py パターン確認]"
  if [ -f "$step4_dir/main.py" ]; then
    if grep -q "get_fast_api_app" "$step4_dir/main.py"; then
      echo -e "  ${GREEN}✅${NC} main.py に get_fast_api_app() 使用を確認"
      ((TOTAL_OK++)) || true
    else
      echo -e "  ${RED}❌${NC} main.py に get_fast_api_app() がありません"
      ((TOTAL_FAIL++)) || true
    fi
  fi

  # ── ⑤ requirements.txt に A2UI 依存が含まれるか ────────────────
  echo "  [依存パッケージ確認]"
  if [ -f "$step4_dir/requirements.txt" ]; then
    local deps_ok=true
    for dep in "google-adk" "a2ui-agent-sdk"; do
      if grep -qi "$dep" "$step4_dir/requirements.txt"; then
        echo -e "    ${GREEN}✓${NC} $dep"
      else
        echo -e "    ${RED}✗${NC} $dep が requirements.txt にありません"
        deps_ok=false
      fi
    done
    if $deps_ok; then
      echo -e "  ${GREEN}✅${NC} A2UI 依存パッケージ完備"
      ((TOTAL_OK++)) || true
    else
      echo -e "  ${RED}❌${NC} A2UI 依存パッケージ不足"
      ((TOTAL_FAIL++)) || true
    fi
  else
    echo -e "  ${YELLOW}⚠️${NC}  $step4_dir/requirements.txt が存在しません"
  fi

  # ── ⑥ Renderer ディレクトリ確認 ────────────────────────────────
  echo "  [Lit Renderer 確認]"
  if [ -d "$step4_dir/renderer" ] && [ -f "$step4_dir/renderer/package.json" ]; then
    echo -e "  ${GREEN}✅${NC} Lit Renderer ディレクトリ存在"
    ((TOTAL_OK++)) || true
  else
    echo -e "  ${YELLOW}⚠️${NC}  renderer/ が未セットアップ（Phase 2 未完了の可能性）"
  fi

  # ── ⑦ Tool が REST ではなく UseCase 直接呼び出しか ─────────────
  echo "  [Tool 実装パターン確認]"
  if [ -n "$tools_py" ]; then
    if grep -q "httpx\|requests\.get\|requests\.post" "$tools_py"; then
      echo -e "  ${RED}❌${NC} tools.py が HTTP クライアントを使用（UseCase 直接呼び出しにすべき）"
      ((TOTAL_FAIL++)) || true
    elif grep -q "usecase\|repository\|UseCase\|Repository" "$tools_py"; then
      echo -e "  ${GREEN}✅${NC} tools.py が UseCase/Repository を直接呼び出し"
      ((TOTAL_OK++)) || true
    else
      echo -e "  ${YELLOW}⚠️${NC}  tools.py の実装パターンを判別できません"
    fi
  fi

  # ── workshop-state.json 更新 ──────────────────────────────────
  if command -v jq &>/dev/null && [ -f "workshop-state.json" ]; then
    ./scripts/update-state.sh .steps.step4.consistency.app_identical \
      "$([ -z "${app_diff:-}" ] && echo true || echo false)" 2>/dev/null || true
    ./scripts/update-state.sh .steps.step4.consistency.tests_identical \
      "$([ -z "${tests_diff:-}" ] && echo true || echo false)" 2>/dev/null || true
    ./scripts/update-state.sh .steps.step4.consistency.agent_files_present \
      "$($agent_ok && echo true || echo false)" 2>/dev/null || true
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
  3-4) check_step3_to_step4 ;;
  ddl) check_ddl_psql ;;
  all)
    check_step1_to_step2
    check_step2_to_step3
    check_step3_tests
    check_step3_to_step4
    check_ddl_psql
    ;;
  *)
    echo "Usage: $0 [1-2|2-3|3|3-4|ddl|all]"
    exit 1
    ;;
esac

echo -e "\n${BLUE}━━━ 結果サマリ ━━━${NC}"
echo -e "  ${GREEN}${TOTAL_OK} passed${NC}, ${RED}${TOTAL_FAIL} failed${NC}"
echo -e "${BLUE}==========================================${NC}"

exit "$TOTAL_FAIL"

