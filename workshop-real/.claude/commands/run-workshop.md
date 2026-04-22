ワークショップ全 Step のオーケストレーション実行

あなたはワークショップのファシリテーター AI です。
以下の Step を **順序通り** に実行し、各 Step の成果物を次の Step のインプットとして使用してください。

## 実行フロー

### Step 1: 設計逆起こし
1. `force-app/` 配下の全ソースコードを分析
2. システム概要書を生成 → `01-reverse-engineering/output/system_overview.md`
3. 移行影響分析レポートを生成 → `01-reverse-engineering/output/migration_assessment.md`
4. **セルフレビュー**: 漏れ・不整合をチェックし自動修正

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

### Step 5: ADR 生成
1. 全 Step の成果物を踏まえた ADR を生成 → `05-roadmap/output/adr.md`

## 実行ルール

- CLAUDE.md の全ルール（アーキテクチャ、命名規則、変換パターン、ドメインナレッジ）に従う
- 各 Step 完了後に成果物の一覧を出力する
- エラーが発生した場合は、修正してから次の Step に進む
- **各 Step の間で「セルフレビュー → 自動修正」のループを必ず実行する**

## 完了条件

以下がすべて揃ったら完了:
- [ ] `01-reverse-engineering/output/system_overview.md`
- [ ] `01-reverse-engineering/output/migration_assessment.md`
- [ ] `02-schema-migration/output/generated_ddl.sql`
- [ ] `02-schema-migration/output/data_validation.sql`
- [ ] `02-schema-migration/output/import_data.py`
- [ ] `03-code-modernization/output/TEST_SCENARIOS.md`
- [ ] `03-code-modernization/output/app/` (Python プロジェクト)
- [ ] `03-code-modernization/output/tests/` (テストコード)
- [ ] `03-code-modernization/output/Dockerfile`
- [ ] `05-roadmap/output/adr.md`
