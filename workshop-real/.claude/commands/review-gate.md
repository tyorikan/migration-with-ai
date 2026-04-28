独立コンテキストでの品質ゲートチェック

> **重要**: このコマンドは **`/clear` でコンテキストをリセットした後** に実行してください。
> builder の思考履歴を引き継がない、まっさらなコンテキストでレビューすることが品質の鍵です。

## 対象 Step
`$ARGUMENTS` (例: 1, 2, 3, all)

引数が空の場合は `all`（全 Step の成果物をレビュー）をデフォルトとします。

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

#### Step 4 をレビューする場合
1. `04-frontend-a2ui/output/agent/agent.py` — ADK Agent + A2UI 統合が正しいか
2. `04-frontend-a2ui/output/main.py` — `get_fast_api_app()` + `include_router()` で既存 Router がマージされているか
3. Agent の Tool 定義 — Step 3 の REST API を正しく呼び出しているか
4. `A2uiSchemaManager` — BasicCatalog + v0.8 スキーマが正しく設定されているか
5. Vertex AI 認証 — `GOOGLE_API_KEY` を使用していないか（ADC のみ）
6. Lit Renderer — `renderer/package.json` と `renderer/src/app.ts` が存在するか

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
- Step 4: `04-frontend-a2ui/output/review_report.md`

### 5. workshop-state.json の更新

```bash
# スコアを更新（例: Step 1 の平均スコアが 4.2 の場合）
./scripts/update-state.sh .steps.step1.review.score 4.2
./scripts/update-state.sh .steps.step1.review.gate_passed true
./scripts/update-state.sh .steps.step1.review.reviewed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)"

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
