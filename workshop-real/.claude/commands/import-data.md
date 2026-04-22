Step 2 (続き): SFDC エクスポート CSV → PostgreSQL データ投入スクリプト生成

## 入力（自動参照）
- SFDC エクスポート CSV: `data/*.csv`（または `examples/data/*.csv`）
- 生成済み DDL: `workshop-real/02-schema-migration/output/generated_ddl.sql`

## 指示
上記 CSV ファイルを PostgreSQL にインポートするための Python スクリプトを生成してください。

## 変換ルール
1. カラム名: SFDC API 名（例: `StoreCode__c`）→ snake_case（例: `store_code`）
2. `__c` サフィックスは除去
3. SFDC の Id（18桁）はそのまま `VARCHAR(18)` として格納
4. 日付: SFDC 形式（`YYYY-MM-DDThh:mm:ss.000+0000`）→ PostgreSQL `TIMESTAMPTZ`
5. Checkbox: `"true"`/`"false"` → `BOOLEAN`
6. NULL/空文字列の適切な処理
7. 外部キー制約を考慮した投入順序（親テーブル → 子テーブル）

## 技術要件
- Python 3.12 + psycopg2
- 環境変数で DB 接続情報を取得（`DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME`）
- バッチ INSERT（1000件ずつ）
- エラー時のロールバック + エラーログ出力
- 投入前後の件数サマリー出力
- DDL ファイルを読み込んでカラム名マッピングを自動生成（ハードコードしない）

## 出力先
`workshop-real/02-schema-migration/output/import_data.py`

## セルフレビュー
- DDL のカラム名と CSV のヘッダーのマッピングが正しいか？
- 投入順序が FK 制約を満たしているか？
