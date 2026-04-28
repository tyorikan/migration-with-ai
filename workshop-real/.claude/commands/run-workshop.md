ワークショップ全 Step のオーケストレーション実行

あなたはワークショップのファシリテーター AI です。
以下の Step を **順序通り** に実行し、各 Step の成果物を次の Step のインプットとして使用してください。

## SFDX ソースディレクトリ
`$ARGUMENTS`

引数が空の場合は `./examples` をデフォルトとして使用してください。
以下、`<SOURCE>` は指定されたディレクトリを指します。

## 品質モードの選択

> [!IMPORTANT]
> **品質優先モード**（推奨）: 各 Step 完了後に `/clear` → `/review-gate N` で独立コンテキストレビューを実施。
> **速度優先モード**: セルフレビューのみで次の Step に進む。

## 初期化
実行開始時に `workshop-state.json` を更新してください:
```bash
./scripts/update-state.sh .started_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
./scripts/update-state.sh .source_dir "<SOURCE>"
```

## 実行フロー

### Step 1: 設計逆起こし
1. **Phase 0: 再帰探索 + ナレッジ抽出**
   - `<SOURCE>` を再帰的に走査し Tree 構造を生成 → `01-reverse-engineering/output/source_tree.md`
   - SFDC 依存 API + ビジネスロジックパターンを検出 → `01-reverse-engineering/output/knowledge_catalog.md`
2. **Phase 1: Code Wiki 生成**
   - 全ソースファイルを1ファイル1ページで Wiki 化 → `01-reverse-engineering/output/wiki/`
   - index.md（全体概要）+ architecture.md（依存関係）+ data-model.md（ER図）+ 各モジュールページ
3. Code Wiki を参照し、統合設計書を生成 → `01-reverse-engineering/output/system_overview.md`
4. 移行影響分析レポートを生成 → `01-reverse-engineering/output/migration_assessment.md`
5. **セルフレビュー**: Wiki のページ数と設計書のカバレッジを突合し、漏れ・不整合をチェックし自動修正

### Step 2: DB スキーマ移行 + データ投入
1. Step 1 の ER 図 + フィールド定義を参照して DDL 生成 → `02-schema-migration/output/generated_ddl.sql`
2. データ整合性検証 SQL を生成 → `02-schema-migration/output/data_validation.sql`
3. CSV データ投入スクリプトを生成 → `02-schema-migration/output/import_data.py`
4. **セルフレビュー**: DDL と ER 図の整合性、FK 制約の方向を確認

### Step 3: TDD コードモダナイズ
1. Apex ソースコード + テストクラスの assert からテストシナリオ抽出 → `03-code-modernization/output/TEST_SCENARIOS.md`
2. pytest テストコード + スタブ構造を生成（🔴 RED）
3. 全テスト PASS する実装を生成（🟢 GREEN）
4. Dockerfile + requirements.txt を生成
5. **セルフレビュー**: テストシナリオの全項目がテストコードにカバーされているか確認

### Step 4: A2UI フロントエンド生成 🆕
1. Step 1 の `system_overview.md` + Step 3 の `app/router/` + `app/model/schemas.py` を参照
2. ADK Agent を `a2ui-agent-sdk` + `A2uiSchemaManager` で構築 → `04-frontend-a2ui/output/agent/`
3. `get_fast_api_app()` で既存 FastAPI Router をマージ → `04-frontend-a2ui/output/main.py`
4. Lit Renderer をセットアップ → `04-frontend-a2ui/output/renderer/`
5. **セルフレビュー**: Agent が A2UI JSON を正しく生成し、既存 REST API が引き続き動作することを確認

### Step 6: ADR + ロードマップ + アクションアイテム生成
1. 全 Step の成果物を踏まえた ADR を生成 → `06-roadmap/output/adr.md`
2. 本日の実績ベースの移行ロードマップを生成 → `06-roadmap/output/roadmap.md`
3. ワークショップ後のアクションアイテム一覧を生成 → `06-roadmap/output/action_items.md`

## 実行ルール

- CLAUDE.md の全ルール（アーキテクチャ、命名規則、変換パターン、ドメインナレッジ）に従う
- 各 Step 完了後に成果物の一覧を出力する
- エラーが発生した場合は、修正してから次の Step に進む
- **各 Step の間で「セルフレビュー → 自動修正」のループを必ず実行する**
- **各 Step 完了時に `workshop-state.json` を更新する**
- **各 Step 完了時に `./scripts/verify-consistency.sh` を実行する**

### 品質優先モードの運用手順

品質を最大化したい場合は、各 Step 完了後に以下を実施してください:

```
# ① builder として Step N を実行
/reverse-engineer ./examples

# ② コンテキストをリセット
/clear

# ③ 独立コンテキストで品質チェック
/review-gate 1

# ④ PASS したらリセットして次の Step へ
/clear
/schema-convert ./examples

# ... Step 4 の場合
/clear
/generate-a2ui-frontend
/clear
/review-gate 4
```

## 完了条件

以下がすべて揃ったら完了:
- [ ] `01-reverse-engineering/output/source_tree.md`
- [ ] `01-reverse-engineering/output/knowledge_catalog.md`
- [ ] `01-reverse-engineering/output/wiki/index.md`（Code Wiki トップ）
- [ ] `01-reverse-engineering/output/wiki/architecture.md`
- [ ] `01-reverse-engineering/output/wiki/data-model.md`
- [ ] `01-reverse-engineering/output/system_overview.md`
- [ ] `01-reverse-engineering/output/migration_assessment.md`
- [ ] `02-schema-migration/output/generated_ddl.sql`
- [ ] `02-schema-migration/output/data_validation.sql`
- [ ] `02-schema-migration/output/import_data.py`
- [ ] `03-code-modernization/output/TEST_SCENARIOS.md`
- [ ] `03-code-modernization/output/app/` (Python プロジェクト)
- [ ] `03-code-modernization/output/tests/` (テストコード)
- [ ] `03-code-modernization/output/Dockerfile`
- [ ] `04-frontend-a2ui/output/agent/agent.py`
- [ ] `04-frontend-a2ui/output/main.py`
- [ ] `04-frontend-a2ui/output/renderer/package.json`
- [ ] `06-roadmap/output/adr.md`
- [ ] `06-roadmap/output/roadmap.md`
- [ ] `06-roadmap/output/action_items.md`
