独立コンテキストでの品質ゲートチェック

> **重要**: このコマンドは **`/clear` でコンテキストをリセットした後** に実行してください。
> builder の思考履歴を引き継がない、まっさらなコンテキストでレビューすることが品質の鍵です。

## 対象 Step
`$ARGUMENTS` (例: 1, 2, 3, 4-A, 4-B, 4, all)

引数が空の場合は `all`（全 Step の成果物をレビュー）をデフォルトとします。

Step 4 は二段構成（設計フェーズと実装フェーズ）のため、引数で指定する:
- `4-A` … 設計レビュー（`/design-frontend` 完了後）
- `4-B` … 実装レビュー（`/implement-frontend` 完了後）
- `4`   … `4-A` と `4-B` を順に実施

---

## あなたの役割

あなたは **migration-reviewer Agent** として、**独立した視点** で成果物をレビューします。

- builder がどのような判断をしたか、なぜそうしたかは **一切知りません**
- 成果物のファイルのみを読み込み、ルーブリック基準で評価します
- 「おそらく意図があるのだろう」という推測は **しません** — 成果物に書かれていることだけが事実です

---

## レビュー手順

### 1. 状態ファイルの読み込み
```bash
cat workshop-state.json
```
対象 Step の成果物パスとメトリクスを確認する。

### 2. 成果物の読み込みとスコアリング

スキル `quality-rubric` のルーブリックに基づき、各評価軸を 1-5 でスコアリングしてください。

#### Step 1 をレビューする場合
1. `01-reverse-engineering/output/source_tree.md` — ファイル数と統計を確認
2. `01-reverse-engineering/output/wiki/` — Wiki ページ数と source_tree.md のファイル数が一致しているか
3. `01-reverse-engineering/output/system_overview.md` — 5軸評価:
   - 網羅性: Wiki の全ファイルがカバーされているか
   - ER図正確性: Mermaid erDiagram のリレーション数 ≥ オブジェクト間関係数
   - ビジネスロジック: 主要クラスの責務 + メソッドが記載されているか
   - Mermaid品質: レンダリング可能か、種類が複数あるか
   - 移行メモ: 複雑度評価が全オブジェクトにあるか

#### Step 2 をレビューする場合
1. `02-schema-migration/output/generated_ddl.sql` — DDL の構文をチェック
2. `system_overview.md` のオブジェクト名 ⊆ DDL のテーブル名（漏れチェック）
3. FK 制約の方向: Lookup → SET NULL、MasterDetail → CASCADE
4. 命名規則: 全テーブル/カラムが snake_case + 複数形
5. 検証 SQL の有無と網羅性

#### Step 3 をレビューする場合
1. テストシナリオ（TEST_SCENARIOS.md）の件数とカバレッジ
2. 3層アーキテクチャ: router/ → usecase/ → repository/ の分離
3. テストコードの品質: mock の使い方、parametrize の有無
4. Apex テストの assert がすべて pytest に移植されているか
5. ruff / mypy でエラーがないか（`check-progress.sh 3` を実行）

#### Step 4-A（設計レビュー）をレビューする場合

`04-frontend-nextjs/output/design/` 配下の 11 ファイル（overview / design-system / api-client / data-model / screens × 7）を全部読み、`quality-rubric` の Step 4-A セクションに従って評価:

1. **網羅性**: P0 画面 7 枚分（dashboard / list / detail / create / edit / status-transition / delete-confirm）の screens/*.md が揃っているか
2. **業務ルール表現**: `system_overview.md` のステータス遷移マトリクス・Approved 編集不可・Draft 削除のみ・Submitted 承認はマネージャーのみ・重複防止 が、いずれかの screens/*.md で UI 制御として明文化されているか
3. **API 整合**: api-client.md の BFF Route Handler 一覧が Backend (`03-code-modernization/output/app/router/`) のすべての P0 エンドポイントと 1:1 対応しているか
4. **データモデル整合**: data-model.md の Zod スキーマ案が Backend Pydantic スキーマ (`03-code-modernization/output/app/model/schemas.py`) のフィールド名・型・必須・enum と一致するか
5. **ワイヤー / コンポーネントツリー / API のトリプル整合**: 各 screens/*.md でワイヤー上のボタンやリストが、コンポーネントツリーとも、API 呼び出しとも齟齬なく対応しているか

#### Step 4-B（実装レビュー）をレビューする場合

`04-frontend-nextjs/output/` 配下のソースコードを `quality-rubric` の Step 4-B セクションに従って評価:

1. **設計と実装の一致**: 各 screens/*.md のコンポーネントツリーと、対応するページ実装 (`app/visits/.../page.tsx`) のコンポーネント階層が一致しているか
2. **業務ルールの UI 制御**: Approved 編集ボタン非表示、Draft 削除のみ、マネージャーのみ承認ボタン、が実装されているか（grep で確認）
3. **テスト充足**: `pnpm test`（Vitest）と `pnpm e2e`（Playwright）の結果、カバレッジ、Route Handler / schemas のテスト網羅性
4. **静的解析**: `pnpm typecheck` と `pnpm lint` でエラー 0
5. **BFF セキュリティ**: Backend エラーを生で漏らさない、ロール権限を `requireManager()` で BFF 層で確認しているか
6. **Docker ビルド**: `docker compose --profile nextjs up -d --build` で `http://localhost:3000` が 200 を返すか

### 3. 機械的検証の実行

```bash
# Step 間整合性チェック
./scripts/verify-consistency.sh

# 進捗チェック
./scripts/check-progress.sh
```

結果をレポートに含めてください。

### 4. レビューレポートの出力

スキル `quality-rubric` の「レビューレポート出力フォーマット」に従い、以下に出力:
- Step 1: `01-reverse-engineering/output/review_report.md`
- Step 2: `02-schema-migration/output/review_report.md`
- Step 3: `03-code-modernization/output/review_report.md`
- Step 4-A（設計）: `04-frontend-nextjs/output/DESIGN_REPORT.md`
- Step 4-B（実装）: `04-frontend-nextjs/output/review_report.md`

### 5. workshop-state.json の更新

```bash
# Step 1〜3: 通常パターン
./scripts/update-state.sh .steps.step1.review.score 4.2
./scripts/update-state.sh .steps.step1.review.gate_passed true
./scripts/update-state.sh .steps.step1.review.reviewed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Step 4-A（設計フェーズの review は phases.design.review に書く）
./scripts/update-state.sh .steps.step4.phases.design.review.score 4.0
./scripts/update-state.sh .steps.step4.phases.design.review.gate_passed true
./scripts/update-state.sh .steps.step4.phases.design.review.reviewed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
./scripts/update-state.sh .steps.step4.phases.design.review.feedback_file "04-frontend-nextjs/output/DESIGN_REPORT.md"

# Step 4-B（実装フェーズの review は phases.implement.review と step4.review の両方を更新）
./scripts/update-state.sh .steps.step4.phases.implement.review.score 4.0
./scripts/update-state.sh .steps.step4.phases.implement.review.gate_passed true
./scripts/update-state.sh .steps.step4.phases.implement.review.reviewed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
./scripts/update-state.sh .steps.step4.phases.implement.review.feedback_file "04-frontend-nextjs/output/review_report.md"
./scripts/update-state.sh .steps.step4.review.score 4.0          # ステップ全体ゲート
./scripts/update-state.sh .steps.step4.review.gate_passed true
./scripts/update-state.sh .steps.step4.review.reviewed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# 不合格の場合
./scripts/update-state.sh .steps.step1.review.gate_passed false
./scripts/update-state.sh .steps.step1.review.feedback_file "01-reverse-engineering/output/review_report.md"
```

---

## 合格基準

- **全評価軸で 3/5 以上**
- **平均スコア 3.5/5 以上**
- **CRITICAL 発見事項が 0 件**
- **機械的検証（verify-consistency.sh）で FAIL が 0 件**

## 不合格の場合

レビューレポートの「修正指示」セクションに、具体的な修正内容を記載してください。
修正者は **別のセッション** でレポートを読み、修正を実施した後、再度 `/clear` → `/review-gate N` を実行します。
