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
#       ./scripts/verify-consistency.sh api   → API URL 契約整合のみ (Step 1↔3, Step 3↔4)
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
# Step 3 → Step 4: BFF Route Handler ↔ Backend エンドポイント整合
# -------------------------------------------------------
# Step 4 は独立した Next.js / TypeScript プロジェクトで、Backend は `app`
# サービスとして HTTP 経由で呼ばれる前提。整合性検証の観点:
#   1. Step 4 設計書（design/api-client.md 等）が存在するか
#   2. Backend Router の各 P0 エンドポイントが BFF 側に対応 Route Handler
#      を持つか（path を grep で確認）
#   3. Next.js プロジェクトの最低限の構成ファイル（package.json,
#      next.config.ts, app/layout.tsx, app/api/visits/route.ts, Dockerfile）
#      が揃っているか
#   4. Step 3 の Backend が Step 4 から触られていない（読み取り専用前提）
# -------------------------------------------------------
check_step3_to_step4() {
  echo -e "\n${BLUE}━━━ Step 3 → Step 4: BFF ↔ Backend 整合 ━━━${NC}"

  local step3_dir="03-code-modernization/output"
  local step4_dir="04-frontend-nextjs/output"

  if [ ! -d "$step3_dir/app/router" ]; then
    echo -e "  ${YELLOW}⚠️${NC}  $step3_dir/app/router が存在しません（Step 3 未完了）"
    return
  fi
  if [ ! -d "$step4_dir" ]; then
    echo -e "  ${YELLOW}⚠️${NC}  $step4_dir が存在しません（Step 4 未着手）"
    return
  fi

  # ── ① 設計書（Step 4-A）の存在 ────────────────────────────────────
  echo "  [Step 4-A 設計書 (design/) の存在]"
  local design_dir="$step4_dir/design"
  local design_ok=true
  for f in overview design-system api-client data-model; do
    if [ -f "$design_dir/$f.md" ]; then
      echo -e "    ${GREEN}✓${NC} design/$f.md"
    else
      echo -e "    ${YELLOW}⚠${NC}  design/$f.md がない"
      design_ok=false
    fi
  done
  local screens_count=0
  for s in dashboard visit-list visit-detail visit-create visit-edit visit-status-transition visit-delete-confirm; do
    if [ -f "$design_dir/screens/$s.md" ]; then
      screens_count=$((screens_count + 1))
    fi
  done
  echo -e "    [P0 画面 .md] ${screens_count}/7"
  if $design_ok && [ "$screens_count" -eq 7 ]; then
    echo -e "  ${GREEN}✅${NC} 設計書 11 ファイル揃っている"
    ((TOTAL_OK++)) || true
  else
    echo -e "  ${YELLOW}⚠️${NC}  設計書未完了（/design-frontend を実行してください）"
  fi

  # ── ② Next.js プロジェクト最小構成 ───────────────────────────────
  echo "  [Next.js プロジェクト構成]"
  local impl_ok=true
  for f in package.json next.config.ts app/layout.tsx app/page.tsx app/api/visits/route.ts Dockerfile; do
    if [ -f "$step4_dir/$f" ]; then
      echo -e "    ${GREEN}✓${NC} $f"
    else
      echo -e "    ${YELLOW}⚠${NC}  $f がない"
      impl_ok=false
    fi
  done
  if $impl_ok; then
    echo -e "  ${GREEN}✅${NC} Next.js 最低構成 OK"
    ((TOTAL_OK++)) || true
  else
    echo -e "  ${YELLOW}⚠️${NC}  実装未完了（/implement-frontend を実行してください）"
  fi

  # ── ③ BFF Route Handler ↔ Backend エンドポイント対応 ─────────────
  # Backend の P0 エンドポイント (Step 3 router から自動抽出)
  echo "  [BFF ↔ Backend エンドポイント対応]"
  local backend_paths
  backend_paths=$(grep -hoE '@router\.(get|post|patch|delete)\("[^"]+"' "$step3_dir/app/router/"*.py 2>/dev/null \
    | sed -E 's/@router\.(get|post|patch|delete)\("([^"]+)"/\U\1\E \2/' | sort -u)
  if [ -z "$backend_paths" ]; then
    echo -e "    ${YELLOW}⚠${NC}  Backend Router からエンドポイントを抽出できませんでした"
  else
    echo "$backend_paths" | while read -r line; do echo "    [Backend] $line"; done
  fi

  if [ -d "$step4_dir/app/api" ]; then
    local bff_count
    bff_count=$(find "$step4_dir/app/api" -name "route.ts" -type f 2>/dev/null | wc -l | tr -d ' ')
    echo -e "    [BFF Route Handler 数] ${bff_count}"

    # P0: GET /store-visits, GET /:id, POST /, PATCH /:id, DELETE /:id  → 5 件想定
    if [ "$bff_count" -ge 2 ]; then
      echo -e "  ${GREEN}✅${NC} BFF Route Handler が ${bff_count} 件存在（最低 2 ファイルは route.ts と [id]/route.ts）"
      ((TOTAL_OK++)) || true
    else
      echo -e "  ${YELLOW}⚠️${NC}  BFF Route Handler が不足（実装未完了）"
    fi

    # workshop-state.json の metrics 更新
    if command -v jq &>/dev/null && [ -f "workshop-state.json" ]; then
      ./scripts/update-state.sh .steps.step4.metrics.bff_route_handlers "$bff_count" 2>/dev/null || true
    fi
  else
    echo -e "  ${YELLOW}⚠️${NC}  $step4_dir/app/api ディレクトリなし"
  fi

  # ── ④ Backend (Step 3 app/) が Step 4 から侵されていない ─────────
  echo "  [Backend 改変禁止確認]"
  if [ -d "$step4_dir/app" ] && [ -f "$step4_dir/app/main.py" ] && [ ! -f "$step4_dir/app/layout.tsx" ]; then
    # 04-frontend-nextjs/output/app は Next.js App Router の app/。Python の main.py が
    # 入り込んでいたら Step 3 の Backend を誤ってコピーしている。
    echo -e "  ${RED}❌${NC} $step4_dir/app/ に Python ファイル (main.py) が混入。Next.js の app/ ディレクトリには入れない"
    ((TOTAL_FAIL++)) || true
  else
    echo -e "  ${GREEN}✅${NC} Step 4 が Backend Python コードを含んでいない"
    ((TOTAL_OK++)) || true
  fi

  # ── ⑤ healthz 疎通（コンテナ起動中の場合のみ）────────────────────
  echo "  [Backend healthz 疎通確認 (コンテナ起動時のみ)]"
  local healthz_reachable=false
  if docker compose ps --format '{{.Name}}' 2>/dev/null | grep -q 'sfdc-migration-app$'; then
    if docker compose exec -T app curl -fsS http://localhost:8080/healthz >/dev/null 2>&1; then
      echo -e "  ${GREEN}✅${NC} app:8080/healthz → 200"
      healthz_reachable=true
      ((TOTAL_OK++)) || true
    else
      echo -e "  ${YELLOW}⚠️${NC}  app コンテナ起動中だが /healthz が反応しない"
    fi
  else
    echo -e "  ${YELLOW}⚠${NC}  app コンテナ未起動（'docker compose --profile nextjs up -d' でチェック可能）"
  fi

  # ── workshop-state.json 更新 ──────────────────────────────────
  if command -v jq &>/dev/null && [ -f "workshop-state.json" ]; then
    ./scripts/update-state.sh .steps.step4.consistency.endpoint_mapping_complete \
      "$($impl_ok && echo true || echo false)" 2>/dev/null || true
    ./scripts/update-state.sh .steps.step4.consistency.healthz_reachable \
      "$($healthz_reachable && echo true || echo false)" 2>/dev/null || true
  fi
}

# -------------------------------------------------------
# Step 1 → Step 3: API URL 契約整合
# -------------------------------------------------------
# 過去事例 (2026-04-28): README.md は `/api/v1/store-visits` を仕様化していたが、
# Backend 実装は `/store-visits` のまま (`include_router(prefix=...)` 抜け) で
# Step 4 構築時まで誰も気付かなかった。再発防止のため:
#   1. Step 1 の system_overview.md / Step 3 の README.md から「公開 URL」を抽出
#   2. Backend の app/main.py + router の prefix を静的解析して実装側 path を求める
#   3. Backend が起動中なら /openapi.json も照合
#   4. 3 ソースの差分が 0 であることを確認
# -------------------------------------------------------
check_api_contract_step1_to_step3() {
  echo -e "\n${BLUE}━━━ Step 1 → Step 3: API URL 契約整合 ━━━${NC}"

  local sys_overview="01-reverse-engineering/output/system_overview.md"
  local step3_readme="03-code-modernization/README.md"
  local main_py="03-code-modernization/output/app/main.py"

  if [ ! -f "$step3_readme" ] && [ ! -f "$sys_overview" ]; then
    echo -e "  ${YELLOW}⚠️${NC}  Step 1 / Step 3 の仕様ドキュメントが見つかりません"
    return
  fi

  local spec_paths_file="/tmp/_verify_spec_paths.txt"
  local impl_paths_file="/tmp/_verify_impl_paths.txt"
  local oai_paths_file="/tmp/_verify_oai_paths.txt"

  # 1. 仕様ソースから path を抽出（バッククォート除去 + プレースホルダ正規化）
  {
    [ -f "$sys_overview" ] && grep -hoE '`/api/v[0-9]+/[a-z][a-z0-9/_{}-]*`|`/store-visits[a-z0-9/_{}-]*`' "$sys_overview" | tr -d '`'
    [ -f "$step3_readme" ] && grep -hoE '/api/v[0-9]+/[a-z][a-z0-9/_{}-]*|/store-visits[a-z0-9/_{}-]*' "$step3_readme"
  } 2>/dev/null \
    | grep -vE '\.html$|\.json$|\.xml$' \
    | sed -E 's|\{[^}]*\}|{ID}|g' \
    | sort -u > "$spec_paths_file"

  echo "  [仕様ソースの path 数] $(wc -l < "$spec_paths_file")"
  if [ ! -s "$spec_paths_file" ]; then
    echo -e "  ${YELLOW}⚠️${NC}  仕様ソースから API path を抽出できませんでした"
    return
  fi

  # 2. 実装側 path（main.py の include_router prefix + router prefix を合成）
  if [ -f "$main_py" ]; then
    # include_router(..., prefix="/api/v1") から prefix を抽出
    local include_prefix
    include_prefix=$(grep -oE 'include_router\([^)]*prefix=["'"'"'][^"'"'"']+["'"'"']' "$main_py" \
      | grep -oE 'prefix=["'"'"'][^"'"'"']+["'"'"']' | head -1 \
      | sed -E 's/prefix=["'"'"']//; s/["'"'"']$//')
    # router 側 APIRouter(prefix="...")
    local router_files
    router_files=$(find 03-code-modernization/output/app/router -name '*.py' ! -name '__init__.py' 2>/dev/null)
    : > "$impl_paths_file"
    for rf in $router_files; do
      local rp
      rp=$(grep -oE 'APIRouter\([^)]*prefix=["'"'"'][^"'"'"']+["'"'"']' "$rf" \
        | grep -oE 'prefix=["'"'"'][^"'"'"']+["'"'"']' | head -1 \
        | sed -E 's/prefix=["'"'"']//; s/["'"'"']$//')
      [ -n "$rp" ] && echo "${include_prefix}${rp}" | sed -E 's|\{[^}]*\}|{ID}|g' >> "$impl_paths_file"
    done
    sort -u "$impl_paths_file" -o "$impl_paths_file"
    echo "  [実装側 prefix 合成 path] $(wc -l < "$impl_paths_file")"
  else
    echo -e "  ${YELLOW}⚠️${NC}  $main_py が見つからない (Step 3 未実施?)"
    return
  fi

  # 3. Backend が起動中なら /openapi.json と照合
  if curl -fsS -m 3 http://localhost:8080/openapi.json > /tmp/_oai.json 2>/dev/null; then
    if command -v jq >/dev/null 2>&1; then
      jq -r '.paths | keys[]' /tmp/_oai.json \
        | sed -E 's|\{[^}]*\}|{ID}|g' \
        | grep -v '^/healthz$' \
        | sort -u > "$oai_paths_file"
      echo "  [OpenAPI paths] $(wc -l < "$oai_paths_file")"

      # 仕様 vs OpenAPI の前方一致照合
      local missing=0
      while IFS= read -r p; do
        # 仕様 path の prefix で始まる OpenAPI path があれば OK
        if ! grep -qE "^${p}(/|$)" "$oai_paths_file" && ! grep -qF "$p" "$oai_paths_file"; then
          echo -e "      ${RED}✗${NC} 仕様 path '$p' が OpenAPI に存在しない"
          missing=$((missing + 1))
        fi
      done < "$spec_paths_file"

      if [ "$missing" -eq 0 ]; then
        echo -e "  ${GREEN}✅${NC} 仕様 ↔ 実装 OpenAPI の URL 整合 OK"
        ((TOTAL_OK++)) || true
      else
        echo -e "  ${RED}❌${NC} 仕様と OpenAPI で ${missing} 件の URL 不整合"
        echo "      → README.md / system_overview.md と app/main.py の include_router(prefix=) を見直すこと"
        ((TOTAL_FAIL++)) || true
      fi
    fi
  else
    echo -e "  ${YELLOW}⚠️${NC}  Backend が未起動。静的解析のみで照合します"

    # 仕様 path が実装 path のいずれかに前方一致するか
    local missing=0
    while IFS= read -r p; do
      local hit=0
      while IFS= read -r ip; do
        case "$p" in "$ip"*) hit=1; break;; esac
      done < "$impl_paths_file"
      if [ "$hit" -eq 0 ]; then
        echo -e "      ${RED}✗${NC} 仕様 path '$p' が実装側 prefix 合成と不一致"
        missing=$((missing + 1))
      fi
    done < "$spec_paths_file"
    if [ "$missing" -eq 0 ]; then
      echo -e "  ${GREEN}✅${NC} 静的解析ベースで URL 整合 OK"
      ((TOTAL_OK++)) || true
    else
      echo -e "  ${RED}❌${NC} ${missing} 件の URL 不整合を検出"
      ((TOTAL_FAIL++)) || true
    fi
  fi
}

# -------------------------------------------------------
# Step 3 → Step 4: BFF が叩く path ↔ Backend OpenAPI 整合
# -------------------------------------------------------
# BFF lib/backend.ts の BACKEND_URL と Route Handler が組み立てる path が、
# 実 Backend の OpenAPI に存在することを保証する。
# -------------------------------------------------------
check_api_contract_step3_to_step4() {
  echo -e "\n${BLUE}━━━ Step 3 → Step 4: BFF が叩く path ↔ OpenAPI ━━━${NC}"

  local backend_ts="04-frontend-nextjs/output/lib/backend.ts"
  local route_dir="04-frontend-nextjs/output/app/api"

  if [ ! -f "$backend_ts" ]; then
    echo -e "  ${YELLOW}⚠️${NC}  $backend_ts が見つからない (Step 4-B 未実施?)"
    return
  fi

  # BACKEND_URL のデフォルト値（process.env の右辺）から prefix を抽出
  local backend_default
  backend_default=$(grep -oE 'BACKEND_URL[[:space:]]*=[[:space:]]*[^;]+' "$backend_ts" \
    | grep -oE '"http[^"]+"' | head -1 | tr -d '"')
  echo "  [BFF BACKEND_URL default] ${backend_default:-未検出}"

  # Route Handler が backend.{get|post|patch|delete}("/...") に渡す path 引数
  local bff_paths_file="/tmp/_verify_bff_paths.txt"
  grep -rhoE 'backend\.(get|post|patch|delete)\([[:space:]]*[`"]([^`"]+)[`"]' "$route_dir" 2>/dev/null \
    | grep -oE '[`"][/][^`"]+[`"]' | tr -d '`"' \
    | sed -E 's|\$\{[^}]*\}|{ID}|g; s|/$||' \
    | sort -u > "$bff_paths_file"
  echo "  [BFF が叩く Backend path 数] $(wc -l < "$bff_paths_file")"

  # Backend OpenAPI と照合
  if curl -fsS -m 3 http://localhost:8080/openapi.json > /tmp/_oai_step4.json 2>/dev/null \
     && command -v jq >/dev/null 2>&1; then
    local oai_full="/tmp/_verify_oai_full.txt"
    jq -r '.paths | keys[]' /tmp/_oai_step4.json \
      | sed -E 's|\{[^}]*\}|{ID}|g' | sort -u > "$oai_full"

    # backend_default から prefix 部分を除いた相対 path を OpenAPI と突き合わせる
    local prefix_path
    prefix_path=$(echo "$backend_default" | sed -E 's|^https?://[^/]+||')
    echo "  [Backend prefix from BACKEND_URL] ${prefix_path}"

    local missing=0
    while IFS= read -r bp; do
      local full_path="${prefix_path}${bp}"
      if ! grep -qF "$full_path" "$oai_full"; then
        echo -e "      ${RED}✗${NC} BFF が叩く '${full_path}' が OpenAPI に存在しない"
        missing=$((missing + 1))
      fi
    done < "$bff_paths_file"

    if [ "$missing" -eq 0 ]; then
      echo -e "  ${GREEN}✅${NC} BFF が叩く path がすべて OpenAPI に存在"
      ((TOTAL_OK++)) || true
    else
      echo -e "  ${RED}❌${NC} ${missing} 件不一致 — BACKEND_URL もしくは Route Handler の path を見直す"
      ((TOTAL_FAIL++)) || true
    fi
  else
    echo -e "  ${YELLOW}⚠️${NC}  Backend 未起動 or jq なし。詳細照合をスキップ"
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
  api) check_api_contract_step1_to_step3; check_api_contract_step3_to_step4 ;;
  all)
    check_step1_to_step2
    check_step2_to_step3
    check_step3_tests
    check_step3_to_step4
    check_ddl_psql
    check_api_contract_step1_to_step3
    check_api_contract_step3_to_step4
    ;;
  *)
    echo "Usage: $0 [1-2|2-3|3|3-4|ddl|api|all]"
    exit 1
    ;;
esac

echo -e "\n${BLUE}━━━ 結果サマリ ━━━${NC}"
echo -e "  ${GREEN}${TOTAL_OK} passed${NC}, ${RED}${TOTAL_FAIL} failed${NC}"
echo -e "${BLUE}==========================================${NC}"

exit "$TOTAL_FAIL"

