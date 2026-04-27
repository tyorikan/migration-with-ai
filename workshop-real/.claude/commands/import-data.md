Step 2 (続き): SFDC エクスポート CSV → PostgreSQL データ投入

## SFDX ソースディレクトリ
`$ARGUMENTS`

引数が空の場合は `./examples` をデフォルトとして使用してください。
以下、`<SOURCE>` は指定されたディレクトリを指します。

## 入力（自動参照）
- SFDC エクスポート CSV: `<SOURCE>/data/*.csv`（または `./data/*.csv`）
- 生成済み DDL: `02-schema-migration/output/generated_ddl.sql`

## 指示

以下の **3ステップを自律的に** 実行してください。スクリプト生成だけでなく、実行と検証まで完了させること。

### ステップ 1: スクリプト + 依存定義の生成

#### `02-schema-migration/output/requirements-import.txt`
```
psycopg2-binary>=2.9
```

#### `02-schema-migration/output/import_data.py`
CSV → PostgreSQL 投入スクリプトを生成する。

### ステップ 2: 依存インストール + スクリプト実行

```bash
# 依存インストール
pip install -r 02-schema-migration/output/requirements-import.txt

# スクリプト実行（docker-compose の PostgreSQL に接続）
docker compose exec -T db psql -U app_user -d migration_db -c "SELECT 1;" && \
python3 02-schema-migration/output/import_data.py
```

### ステップ 3: 投入結果の検証

```bash
# テーブル別レコード数を確認
docker compose exec db psql -U app_user -d migration_db -c "
SELECT 'stores' AS table_name, COUNT(*) FROM stores
UNION ALL SELECT 'store_visits', COUNT(*) FROM store_visits
UNION ALL SELECT 'visit_details', COUNT(*) FROM visit_details;
"
```

CSV の行数（ヘッダー除く）と PostgreSQL のレコード数が一致していることを確認する。
不一致の場合はエラーログを分析し、スクリプトを修正して再実行する。

---

## 変換ルール

1. カラム名: SFDC API 名（例: `StoreCode__c`）→ snake_case（例: `store_code`）
2. `__c` サフィックスは除去
3. SFDC の Id（18桁）はそのまま `VARCHAR(18)` として格納
4. 日付: SFDC 形式（`YYYY-MM-DDThh:mm:ss.000+0000`）→ PostgreSQL `TIMESTAMPTZ`
5. Checkbox: `"true"`/`"false"` → `BOOLEAN`
6. NULL/空文字列の適切な処理
7. 外部キー制約を考慮した投入順序（親テーブル → 子テーブル）

## 技術要件

- Python 3.12 + psycopg2-binary
- 環境変数で DB 接続情報を取得（`DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME`）
- docker-compose 環境のデフォルト値をフォールバックとして持つ:
  ```python
  DB_HOST = os.getenv("DB_HOST", "localhost")
  DB_PORT = os.getenv("DB_PORT", "5432")
  DB_USER = os.getenv("DB_USER", "app_user")
  DB_PASSWORD = os.getenv("DB_PASSWORD", "app_password")
  DB_NAME = os.getenv("DB_NAME", "migration_db")
  ```
- バッチ INSERT（1000件ずつ）
- エラー時のロールバック + エラーログ出力
- 投入前後の件数サマリー出力
- DDL ファイルを読み込んでカラム名マッピングを自動生成（ハードコードしない）

## 出力先

```
02-schema-migration/output/
├── requirements-import.txt    ← 依存定義
├── import_data.py             ← CSV → PostgreSQL 投入スクリプト
└── data_validation.sql        ← 整合性チェッククエリ
```

## セルフレビュー

- DDL のカラム名と CSV のヘッダーのマッピングが正しいか？
- 投入順序が FK 制約を満たしているか？
- **スクリプトが実行され、全レコードが正常に投入されたか？**
- 投入後のレコード数が CSV の行数と一致しているか？
