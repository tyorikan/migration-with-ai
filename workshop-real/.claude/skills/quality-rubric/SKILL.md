---
name: quality-rubric
description: 各 Step の成果物をスコアリングする評価基準。migration-reviewer Agent および /review-gate コマンドが使用する。独立コンテキストでの品質レビューを支えるルーブリック。
---

## 概要

このスキルは、各 Step の成果物を **1〜5 の数値スコア** で定量評価するための基準を定義する。
バイナリ判定（✅/❌）ではなく、段階的な品質評価により「動くけど品質が低い」成果物を見逃さない。

## 合格基準

- **全評価軸で 3 以上**（3 未満が 1 つでもあれば不合格）
- **平均スコア 3.5 以上**
- **CRITICAL 発見事項が 0 件**

---

## Step 1: 設計逆起こし — ルーブリック

### 評価軸

| 軸 | 1 (不合格) | 2 (不十分) | 3 (合格ライン) | 4 (良好) | 5 (優秀) |
|----|-----------|-----------|--------------|---------|---------|
| **網羅性** | ファイル数の50%未満しか分析されていない | 主要クラスのみ分析。テスト/ユーティリティが欠落 | 全ファイルが分析され、主要クラスの責務が記載 | 全ファイルの全 public メソッドが記載。依存関係もあり | 全メソッド + 依存関係（双方向）+ SFDC 依存 API が完備 |
| **ER図正確性** | ER 図なし、またはレンダリング不可 | オブジェクト名はあるがリレーション欠落 | 全 Lookup/MasterDetail が ER 図に反映 | リレーション + カーディナリティが正確 | 全フィールド + 型 + 制約まで ER 図に記載 |
| **ビジネスロジック** | クラス名だけの一覧 | 責務の概要のみ（1行レベル） | 主要クラスの責務 + 主要メソッドの説明 | ステータス遷移テーブル or バリデーションルール付き | 遷移テーブル + バリデーション + 副作用マップ + 計算ロジック完備 |
| **Mermaid品質** | 図なし | 図あるがレンダリングエラー | レンダリング可能なシンプルな図 | 色分け or 注釈付き | 複数種類（ER + flowchart + stateDiagram）+ スタイリング |
| **移行メモ** | なし | 「移行が必要」程度の記載 | 複雑度評価（L/M/H/C）付き | 複雑度 + 移行先パターン記載 | 複雑度 + 移行先 + 工数見積もり + リスク要因 |

### Few-shot 例（スコア 3 相当の成果物像）

> - 全 `.cls` ファイルと `.object-meta.xml` を分析済み
> - ER 図は全オブジェクト + Lookup/MasterDetail リレーション完備
> - 各クラスに「責務」「主要メソッド（名前 + 引数 + 概要）」が記載
> - Mermaid ER図が1つ、flowchart が1つ、どちらもレンダリング可能
> - 各オブジェクトに Low/Medium/High の複雑度評価あり

---

## Step 2: DB スキーマ移行 — ルーブリック

### 評価軸

| 軸 | 1 (不合格) | 2 (不十分) | 3 (合格ライン) | 4 (良好) | 5 (優秀) |
|----|-----------|-----------|--------------|---------|---------|
| **テーブル網羅性** | ER 図のオブジェクトの50%未満 | 主要オブジェクトのみ | ER 図の全オブジェクトに対応テーブルあり | 全テーブル + 監査カラム（created_at 等） | 全テーブル + 監査 + 適切なインデックス |
| **DDL正確性** | psql でエラー発生 | psql 通るが FK が一部欠落 | psql 通り、全 FK が正しい方向で定義 | 型マッピングが正確 + CHECK 制約あり | COMMENT ON COLUMN + Picklist の全値が制約に |
| **命名規則一貫性** | snake_case になっていないテーブルあり | 一部不統一（__c が残存等） | 全テーブル/カラムが snake_case + 複数形 | 一貫性100% + 日本語コメント | 一貫性 + SFDC 元名がコメントで併記 |
| **Step間整合性** | ER 図と DDL の対応がとれていない | 半分以上は対応 | 全オブジェクト⊆テーブル（漏れなし） | 全一致 + FK の参照方向も正確 | 全一致 + Picklist 値 + NOT NULL も一致 |
| **検証SQL** | 検証 SQL なし | 行数チェックのみ | 行数 + 孤立レコード + NULL チェック | 上記 + Picklist 値妥当性 | 全チェック + 統計サマリ出力付き |

---

## Step 3: TDD コードモダナイズ — ルーブリック

### 評価軸

| 軸 | 1 (不合格) | 2 (不十分) | 3 (合格ライン) | 4 (良好) | 5 (優秀) |
|----|-----------|-----------|--------------|---------|---------|
| **テスト品質** | テストなし or 全 FAIL | テストあるが50%未満 PASS | 全テスト PASS + **`pytest --cov` でカバレッジ 80%+ を機械的に確認** + 具象 Repo の DB 統合テスト 1 件以上 | Apex テストの全 assert が移植済み + Batch ジョブのテスト（`tests/test_jobs.py`）あり | パラメタライズ + エッジケース + エラーケース完備 + 冪等性検証あり |
| **アーキテクチャ** | 3層分離なし（全部1ファイル） | 一部分離だが DI なし | router/usecase/repository 3層 + Depends() + **ABC + 具象 SQLAlchemy 実装の両方が存在 + `get_usecase` が wire 済み（`NotImplementedError` なし）** | 上記 + 型ヒント完備 + `dependencies.py` で集約 | 3層 + DI + エラーハンドリング + structlog + `app/jobs/` で Batch も同じ DI パターン |
| **コード品質** | ruff/mypy で大量エラー | ruff PASS だが mypy エラー多数 | ruff + mypy エラーなし（**`requirements-dev.txt` に mypy/pytest-cov/bandit を収録し実行可能な状態**） | 上記 + Google docstring + 型ヒント全関数 | 上記 + bandit PASS（HIGH/MEDIUM 0、LOW のみ理由付き `# nosec`）+ 構造化エラーレスポンス |
| **Apex変換正確性** | ビジネスロジックが未実装 | CRUD のみ、ロジックなし | 主要ビジネスロジック + **対象 SFDC に Apex Batch クラスがある場合は `app/jobs/` に Python 実装あり**（無い場合は不問） | Trigger → usecase 明示化 + ガバナ制限削除 + Batch の冪等性 (`ON CONFLICT DO UPDATE`) 担保 | 全ロジック移植 + Batch → Cloud Run Jobs パターン + Cloud Scheduler 連携を README に記載 |
| **動作検証** | 起動しない | 起動するが API エラー | 全 API エンドポイントが正常レスポンス + **production 起動時に `get_usecase` が NotImplementedError を出さない（DI wire 完了）** | docker-compose でコンテナ間通信 OK | 上記 + データ投入→CRUD→検証の E2E パス + Batch を `python -m app.jobs.<name>` で実行確認 |

### Step 3 レビュー時の必須機械的確認

レビュアー（`/review-gate 3` または `migration-reviewer` Agent）は、スコアを付ける前に以下を **機械的に確認** すること:

```bash
cd 03-code-modernization/output

# A. 具象 Repository の存在（無ければアーキテクチャ ≤ 2、動作検証 ≤ 2）
test -n "$(find app/repository -name '*sqlalchemy*' -o -name '*_impl*' -type f)" \
  || echo "🔴 具象 Repository 実装なし"

# B. get_usecase が wire 済みか（無ければ動作検証 ≤ 2）
grep -rn "raise NotImplementedError" app/router app/dependencies.py app/main.py 2>/dev/null \
  && echo "🔴 production DI が未完成"

# C. Batch 移行の有無（対象 Apex に Batch がある場合のみ必須）
APEX_BATCH=$(grep -rln "Database.Batchable" examples/force-app 2>/dev/null | wc -l)
PY_BATCH=$(find app/jobs -name '*.py' ! -name '__init__.py' 2>/dev/null | wc -l)
if [ "$APEX_BATCH" -gt 0 ] && [ "$PY_BATCH" -eq 0 ]; then
  echo "🔴 Apex Batch ${APEX_BATCH} 件あるが Python 移植 0 件"
fi

# D. dev tools 収録（無ければコード品質 ≤ 2）
grep -E '^(mypy|pytest-cov|bandit)' requirements-dev.txt 2>/dev/null \
  || echo "🔴 requirements-dev.txt に mypy/pytest-cov/bandit が含まれない"

# E. 静的解析・カバレッジが PASS するか
.venv/bin/pip install -q -r requirements-dev.txt 2>/dev/null
.venv/bin/mypy app/
.venv/bin/pytest --cov=app --cov-fail-under=80
.venv/bin/bandit -r app/ -ll
```

A〜E のいずれかが ❌ の場合、関連評価軸のスコアを 1 段階ずつ下げる。

---

## Step 4-A: Next.js フロントエンド設計フェーズ — ルーブリック

`04-frontend-nextjs/output/design/` 配下の markdown 設計書を評価する。

### 評価軸

| 軸 | 1 (不合格) | 2 (不十分) | 3 (合格ライン) | 4 (良好) | 5 (優秀) |
|----|-----------|-----------|--------------|---------|---------|
| **網羅性** | design/ が空 | overview のみ | overview + design-system + api-client + data-model + screens 7 枚すべて存在 | 上記 + 各 screens で固定 8 セクション全部記載 | 上記 + P1 画面（店舗一覧・月次サマリー）も設計済み |
| **業務ルール表現** | ステータス遷移すら言及なし | 一部のみ | system_overview.md の主要ルール（ステータス遷移マトリクス・Approved 編集不可・Draft 削除のみ）が screens/*.md で UI 制御として明文化 | 上記 + 重複防止・メール通知・ロール別ボタン表示 も明文化 | 上記 + エラーケースの UX も全部記述（VISIT_NOT_FOUND / BUSINESS_ERROR / VALIDATION_ERROR） |
| **API 整合性** | api-client.md なし | 一部のみ記載 | Backend (`03-code-modernization/output/app/router/`) のすべての P0 エンドポイントが BFF Route Handler と 1:1 対応表で記載 | 上記 + エラーコードマッピング表あり | 上記 + リクエスト/レスポンスのサンプル JSON あり |
| **データモデル整合** | data-model.md なし | フィールド名が Backend と不一致 | data-model.md の Zod 案が Backend Pydantic と フィールド名・型・必須・enum すべて一致 | 上記 + camelCase ↔ snake_case の境界が明文化 | 上記 + `openapi-typescript` などの自動生成方針も記載 |
| **ワイヤー品質** | ワイヤーなし | テキスト羅列のみ | ASCII または Mermaid のワイヤーがあり、コンポーネントツリー・API と齟齬なく対応 | 上記 + 状態（loading/empty/error）ごとのワイヤー差分あり | 上記 + a11y（キーボード操作・ARIA）の指針あり |

### Step 4-A レビュー時の必須機械的確認

```bash
DESIGN_DIR=04-frontend-nextjs/output/design

# A. 5 種主要 .md の存在
for f in overview design-system api-client data-model; do
  test -f "$DESIGN_DIR/$f.md" || echo "🔴 $DESIGN_DIR/$f.md がない"
done

# B. P0 画面 7 枚分の screens/*.md の存在
for s in dashboard visit-list visit-detail visit-create visit-edit visit-status-transition visit-delete-confirm; do
  test -f "$DESIGN_DIR/screens/$s.md" || echo "🔴 $DESIGN_DIR/screens/$s.md がない"
done

# C. 各 screens/*.md に固定セクションが揃っているか
for f in "$DESIGN_DIR/screens/"*.md; do
  for sec in "目的" "ワイヤー" "状態" "バリデーション" "API 呼び出し" "コンポーネントツリー" "アクセシビリティ" "エラー時 UX"; do
    grep -q "## $sec" "$f" 2>/dev/null \
      || echo "🟡 $f に '## $sec' がない"
  done
done

# D. Backend エンドポイント全カバレッジ（grep で BFF 一覧の対応表をチェック）
grep -E "^\| /api/" "$DESIGN_DIR/api-client.md" | wc -l
# Backend のエンドポイント数（5: GET /store-visits, GET /:id, POST, PATCH /:id, DELETE /:id）と比較

# E. Mermaid のレンダリング（mermaid-cli が使える場合）
command -v mmdc >/dev/null 2>&1 && grep -l '```mermaid' "$DESIGN_DIR"/*.md "$DESIGN_DIR"/screens/*.md \
  | xargs -I {} mmdc -i {} -o /tmp/_mermaid_test.svg 2>&1 | grep -i error
```

A〜D のいずれかが ❌ の場合、関連評価軸を 1 段階ずつ下げる。

---

## Step 4-B: Next.js フロントエンド実装フェーズ — ルーブリック

`04-frontend-nextjs/output/` 配下の Next.js プロジェクト一式を評価する。

### 評価軸

| 軸 | 1 (不合格) | 2 (不十分) | 3 (合格ライン) | 4 (良好) | 5 (優秀) |
|----|-----------|-----------|--------------|---------|---------|
| **設計と実装の一致** | 実装が設計と乖離 | 一部の画面のみ実装 | design/screens/X.md の全 P0 画面に対応する `app/visits/.../page.tsx` が存在 + コンポーネントツリーが一致 | 上記 + ドメインコンポーネント名 (`VisitListTable` 等) が設計通り | 上記 + design-system.md の Tailwind トークンが実装に反映 |
| **業務ルール UI 制御** | Approved 編集ボタンが出る等、ルール違反 | 一部のみ守る | Approved 編集ボタン非表示 / Draft のみ削除可 / マネージャーのみ承認 が grep で確認できる | 上記 + 重複防止エラーの UX 表示 + Submitted の編集不可注記 | 上記 + ロール別ナビゲーション制御 |
| **テスト充足** | テスト 0 件 | unit のみ | Vitest 全 PASS + Playwright P0 4 シナリオ PASS + Route Handler / schemas のカバレッジ 70%+ | 上記 + ドメインコンポーネントの a11y テストあり | 上記 + Visual regression または Storybook 連携 |
| **静的解析** | typecheck エラー多数 | typecheck PASS だが lint エラー多数 | `pnpm typecheck` 0 エラー + `pnpm lint` 0 エラー | 上記 + `pnpm format` でフォーマット統一 | 上記 + biome/eslint の strict ルール採用 |
| **本番動作** | docker build 失敗 | build 通るが起動しない | `docker compose --profile nextjs up -d --build` で http://localhost:3000 が 200 + BFF が Backend にプロキシして JSON 返却 | 上記 + Server Component / Client Component の使い分けが適切 | 上記 + `next start` で SSR / SSG / ISR の最適化済み |

### Step 4-B レビュー時の必須機械的確認

```bash
cd 04-frontend-nextjs/output

# A. 必須ファイルの存在
for f in package.json next.config.ts tailwind.config.ts vitest.config.ts playwright.config.ts Dockerfile app/layout.tsx app/page.tsx; do
  test -f "$f" || echo "🔴 $f がない"
done

# B. BFF Route Handler の網羅
test -f app/api/visits/route.ts || echo "🔴 app/api/visits/route.ts がない"
test -f app/api/visits/\[id\]/route.ts || echo "🔴 app/api/visits/[id]/route.ts がない"

# C. server-only の遵守
grep -lE "from\s+['\"]@/lib/backend['\"]" components/ app/ 2>/dev/null \
  | grep -v "/api/" \
  && echo "🟡 client から lib/backend が import されている"

# D. 業務ルール UI 制御の grep
grep -rnE "(Approved|status\s*===\s*['\"]Approved)" components/ app/ 2>/dev/null \
  | head -5
# Approved 関連の分岐が見えれば OK

# E. typecheck / lint / unit / e2e
pnpm install --frozen-lockfile 2>&1 | tail -3
pnpm typecheck     # → エラー 0
pnpm lint          # → エラー 0
pnpm test          # Vitest 全 PASS
# E2E は dev server を起動する必要あり
docker compose --profile nextjs up -d --build
sleep 5
curl -fsS http://localhost:3000/healthz 2>&1 | head -1
curl -fsS http://localhost:3000/api/visits 2>&1 | head -1
pnpm e2e
docker compose --profile nextjs down
```

A〜E のいずれかが ❌ の場合、関連評価軸を 1 段階ずつ下げる。

---

## レビューレポート出力フォーマット

```markdown
# 品質レビューレポート — Step N

## レビュー概要
- **レビュー日時**: YYYY-MM-DD HH:MM
- **レビューモード**: 独立コンテキスト (/review-gate)
- **対象成果物**: (ファイル一覧)

## スコアリング結果

| 評価軸 | スコア | コメント |
|--------|-------|---------|
| 網羅性 | N/5 | ... |
| ... | N/5 | ... |

**平均スコア**: N.N/5
**判定**: ✅ PASS / ❌ FAIL

## 発見事項

### 🔴 CRITICAL（ブロッカー — 修正必須）
- ...

### 🟡 WARNING（要改善 — 次回修正推奨）
- ...

### 🟢 INFO（推奨 — 時間があれば対応）
- ...

## Step 間整合性チェック
| From → To | チェック項目 | 結果 | 詳細 |
|-----------|-----------|------|------|

## 修正指示（FAIL の場合のみ）
以下を修正してから再度 `/review-gate N` を実行してください:
1. ...
2. ...
```
