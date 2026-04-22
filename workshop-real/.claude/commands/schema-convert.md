Step 2: SFDC メタデータ → PostgreSQL DDL 変換

## SFDX ソースディレクトリ
`$ARGUMENTS`

引数が空の場合は `./examples` をデフォルトとして使用してください。
以下、`<SOURCE>` は指定されたディレクトリを指します。

## 入力（自動参照）
- カスタムオブジェクト: `<SOURCE>/force-app/main/default/objects/*/*.object-meta.xml`
- カスタムフィールド: `<SOURCE>/force-app/main/default/objects/*/fields/*.field-meta.xml`
- Step 1 の設計書: `workshop-real/01-reverse-engineering/output/system_overview.md`（ER図・フィールド定義を参照）

## 変換ルール
CLAUDE.md の「SFDC → PostgreSQL 変換ルール」に厳密に従ってください。

## 生成物

### 1. DDL（CREATE TABLE）
- 外部キーの依存関係を考慮した作成順序で出力
- 全テーブルに `created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP`, `updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP` を追加
- Picklist は CHECK 制約で値を制限
- `<label>` の値を `COMMENT ON COLUMN` で付与
- 外部キー列、status/date 系カラムに `CREATE INDEX`
- 出力先: `workshop-real/02-schema-migration/output/generated_ddl.sql`

### 2. データ整合性検証 SQL
- レコード件数チェック（全テーブル）
- 孤立レコードチェック（FK 参照先が存在しない子レコード）
- NULL チェック（NOT NULL 制約のカラム）
- Picklist 値の妥当性チェック（CHECK 制約外の値がないか）
- 出力先: `workshop-real/02-schema-migration/output/data_validation.sql`

## セルフレビュー
生成後、以下を自己検証してください:
- Step 1 の ER 図とテーブル構造が一致しているか？
- Lookup → ON DELETE SET NULL、MasterDetail → ON DELETE CASCADE になっているか？
- Picklist の CHECK 制約値が `.field-meta.xml` の `<value>` と一致しているか？
修正が必要な場合は自動修正してください。
