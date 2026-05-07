Step 6: ADR + ロードマップ + アクションアイテムの自動生成

## 入力（自動参照）
- 全 Step の成果物:
  - `01-reverse-engineering/output/`（設計書、影響分析）
  - `02-schema-migration/output/`（DDL、データ移行）
  - `03-code-modernization/output/`（Python プロジェクト、テスト）
  - `04-frontend-nextjs/output/`（Next.js 設計書 + 実装、BFF Route Handler、Vitest/Playwright テスト）
  - `05-quality-and-delivery/output/`（品質評価）
- `06-roadmap/README.md`（議論テンプレート: Phase 分割、アクションアイテム雛形）
- `workshop-state.json`（Step 別スコア、メトリクス、所要時間）

## 指示
本日のワークショップで決定した（または検討すべき）アーキテクチャ方針について、以下の **3 つの成果物** を生成してください。

1. **ADR** — `06-roadmap/output/adr.md`
2. **移行ロードマップ** — `06-roadmap/output/roadmap.md`
3. **アクションアイテム一覧** — `06-roadmap/output/action_items.md`

---

## 成果物 1: ADR（`06-roadmap/output/adr.md`）

### ADR フォーマット（各 ADR ごと）
```
## ADR-XXX: [タイトル]
- **ステータス**: 承認済 / 検討中
- **日付**: YYYY-MM-DD
- **コンテキスト**: なぜこの決定が必要だったか
- **決定**: 何を決定したか
- **代替案**: 検討した他の選択肢
- **理由**: なぜその選択肢を採用したか
- **結果**: この決定による影響・トレードオフ
```

### 生成すべき ADR
1. ADR-001: Backend 言語選定（Python / FastAPI） — 代替: Go, TypeScript
2. ADR-002: DB エンジン選定（Cloud SQL PostgreSQL） — 代替: AlloyDB, Spanner
3. ADR-003: コンテナ基盤選定（Cloud Run） — 代替: GKE Autopilot
4. ADR-004: AI 駆動開発の品質保証方針 — TDD + 多層品質ゲート
5. ADR-005: データ移行方式 — sf CLI / Data Loader / Bulk API
6. ADR-006: フロントエンド技術選定（Next.js (App Router) + shadcn/ui + Tailwind + BFF Route Handler） — 代替: Remix, SvelteKit, Nuxt, Vue + Vite

### 追加で生成
- アーキテクチャ全体図（Mermaid `graph TD`）— SFDC 構成 vs Google Cloud 構成を対比
- SFDC → Google Cloud サービスマッピング図（Mermaid `graph LR`）

---

## 成果物 2: 移行ロードマップ（`06-roadmap/output/roadmap.md`）

`06-roadmap/README.md` の Phase 分割テンプレートをベースに、**本日の実績値**（Step 1-4 のメトリクス、スコア）を反映させた **顧客固有のロードマップ** を生成してください。

### 含めるべき要素
1. **Mermaid `gantt` 図** — Phase 0 〜 Phase 3 の期間（本日の生産性実績から推定）
2. **Phase 別の詳細テーブル** — 期間目安、内容、主な成果物
3. **Phase 0 タスク一覧** — 全量アセスメント / DDL 変換 / 優先度決定 / GCP 環境構築 / CI-CD / パイロット選定
4. **Phase 1 で再利用できるワークショップ成果物テーブル** — `.claude/commands/`、`.claude/skills/`、`.claude/agents/`、`docker-compose.yml`、`workshop-state.json` 等
5. **本日の実績ベースの推定** — 「本日 Apex N 行を Y 時間で移行 → 全量 M 行は約 Z 週間」のような定量的な見立て

> **重要**: README にある汎用テンプレートをそのままコピーするのではなく、**本日のワークショップ実績**（`workshop-state.json` の `metrics` / `score` / 所要時間）を反映した顧客固有版にすること。

---

## 成果物 3: アクションアイテム一覧（`06-roadmap/output/action_items.md`）

ワークショップ後のネクストステップを **実行可能な粒度** で列挙してください。

### フォーマット
```
| # | アクションアイテム | 担当ロール | 期限目安 | 優先度 | 依存 | ステータス |
|---|-------------------|----------|---------|--------|------|-----------|
| 1 | 全量アセスメントの実施 | SE + AI | +1週 | 高 | - | ☐ |
| 2 | パイロットアプリの最終選定 | PM + アーキテクト | +1週 | 高 | #1 | ☐ |
| ... |
```

### 含めるべきアクションアイテム
1. 全量アセスメント実施（Step 1 を全 Apex に拡大）
2. パイロットアプリの最終選定（Step 1 影響分析の難易度ランクから抽出）
3. GCP プロジェクトの本番環境構築（Terraform）
4. データ移行計画の詳細化（Bulk API or Data Loader の選定 + 移行ウィンドウ）
5. `.claude/` 資産のカスタマイズ（顧客固有の命名規則、コーディング規約）
6. CI/CD パイプライン構築（Cloud Build + ruff/mypy/pytest ゲート）
7. 受入テスト計画の作成（業務シナリオ別）
8. ステークホルダー説明資料の作成（本日の ADR + ロードマップから抜粋）

### 追加メタ情報
- 各アクションアイテムごとに「本日のどの成果物を入力にするか」を明示（例: `01-reverse-engineering/output/migration_assessment.md`）
- Phase 0 完了報告会 / Phase 1 キックオフのマイルストーン日程枠を提示

---

## 出力先まとめ
- `06-roadmap/output/adr.md`
- `06-roadmap/output/roadmap.md`
- `06-roadmap/output/action_items.md`

## 完了後の確認
生成完了後に以下を実行し、3 ファイルすべての存在を確認してください:
```bash
./scripts/check-progress.sh 6
```
