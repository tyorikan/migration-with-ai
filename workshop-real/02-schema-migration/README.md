# Step 2: DB スキーマ移行設計 + 実データ移行（13:00 – 13:45）

> [!NOTE]
> Step 1 で生成したデータモデル仕様書（ER 図、フィールド定義一覧）をインプットに、
> **PostgreSQL DDL の生成 → 実データ変換・投入 → クエリ変換・実行検証** まで行う。

## 🎯 ゴール

| 成果物 | 出力先 |
|--------|--------|
| PostgreSQL DDL | `02-schema-migration/output/generated_ddl.sql` |
| データ変換スクリプト | `02-schema-migration/output/import_data.py` |
| 変換後 SQL（SOQL → SQL） | `02-schema-migration/output/converted_queries.sql` |
| データ整合性検証 SQL | `02-schema-migration/output/data_validation.sql` |

---

## 2-1. SFDC メタデータ → PostgreSQL DDL 変換（15分）

### プロンプト実行

`templates/schema-conversion-prompt.md` のテンプレートを使い、Claude Code に DDL を生成させます。

```bash
# Claude Code に指示
# 入力: .object-meta.xml + .field-meta.xml
# 出力: workshop-real/02-schema-migration/output/generated_ddl.sql
```

### 変換ルール（プロンプトに含まれる）

| SFDC 型 | PostgreSQL 型 |
|---------|---------------|
| Id | `VARCHAR(18) PRIMARY KEY` |
| Text | `VARCHAR(length)` |
| LongTextArea | `TEXT` |
| Checkbox | `BOOLEAN` |
| Number | `INTEGER` or `NUMERIC(p, s)` |
| Date | `DATE` |
| DateTime | `TIMESTAMPTZ` |
| Picklist | `VARCHAR(length)` + CHECK 制約 |
| Lookup | `FOREIGN KEY ... ON DELETE SET NULL` |
| MasterDetail | `FOREIGN KEY ... ON DELETE CASCADE` |

### 🤖 AI セルフレビュー

```
生成した DDL をレビューしてください。
チェック項目:
1. テーブル名・カラム名が snake_case で __c が除去されているか
2. PRIMARY KEY / FOREIGN KEY が正しいか
3. NOT NULL が SFDC の必須フィールドに設定されているか
4. CHECK 制約が Picklist 値を含んでいるか
5. COMMENT ON で日本語ラベルが付与されているか
```

---

## 2-2. docker-compose で PostgreSQL 起動 + DDL 適用（5分）

### PostgreSQL コンテナの起動

```bash
cd workshop-real

# Step 0 で起動済みならスキップ
docker compose up -d db

# 起動確認
docker compose exec db psql -U app_user -d migration_db -c "SELECT version();"
```

### DDL の適用

```bash
# 生成された DDL を適用
docker compose exec db psql -U app_user -d migration_db \
  -f /workspace/02-schema-migration/output/generated_ddl.sql

# テーブルが作成されたか確認
docker compose exec db psql -U app_user -d migration_db -c "\dt"

# テーブル定義の詳細確認（代表1テーブル）
docker compose exec db psql -U app_user -d migration_db -c "\d target_table_name"
```

---

## 2-3. SFDC 実データの変換・投入・検証（15分）

> [!IMPORTANT]
> 事前準備で SFDC からエクスポートした CSV を PostgreSQL に投入する。
> AI にデータ変換スクリプトを生成させ、カラム名マッピング・データ型変換を自動化する。

### データ変換スクリプトの生成

Claude Code に以下を指示：

```markdown
# 指示
以下の CSV ファイル（SFDC エクスポート）を PostgreSQL にインポートするための
Python スクリプトを生成してください。

# 入力 CSV（data/ 配下）
- data/Store__c.csv
- data/StoreVisit__c.csv
- data/VisitDetail__c.csv

# 変換ルール
1. カラム名: SFDC API 名（例: StoreCode__c）→ snake_case（例: store_code）
2. __c サフィックスは除去
3. SFDC の Id（18桁）はそのまま VARCHAR(18) として格納
4. 日付: SFDC 形式（YYYY-MM-DDThh:mm:ss.000+0000）→ PostgreSQL TIMESTAMPTZ
5. Checkbox: "true"/"false" → BOOLEAN
6. NULL/空文字列の適切な処理
7. 外部キー制約を考慮した投入順序（Store → StoreVisit → VisitDetail）

# 技術要件
- Python 3.12 + psycopg2（または asyncpg）
- 環境変数で DB 接続情報を取得（DB_HOST, DB_PORT, DB_USER, DB_PASSWORD, DB_NAME）
- バッチ INSERT（1000件ずつ COPY コマンドで高速投入）
- エラー時のロールバック + エラーログ出力
- 投入前後の件数サマリー出力

# 出力先
workshop-real/02-schema-migration/output/import_data.py
```

### データ投入の実行

```bash
# CSV ファイルをコンテナにマウント済み（docker-compose.yml の /workspace）

# 方法A: AI が生成した Python スクリプトで投入
docker compose run --rm app python /workspace/02-schema-migration/output/import_data.py

# 方法B: PostgreSQL の COPY コマンドで直接投入（シンプルな場合）
# ※ カラム名の変換が不要な場合のみ
docker compose exec db psql -U app_user -d migration_db \
  -c "\COPY stores FROM '/workspace/data/Store__c.csv' WITH (FORMAT csv, HEADER true)"
```

### 投入結果の検証

```bash
# --- 件数チェック ---
# SFDC 側の件数と PostgreSQL 側の件数を比較
echo "=== レコード件数比較 ==="
echo "SFDC 側（CSV の行数）:"
for f in data/*.csv; do
  echo "  $(basename $f): $(tail -n +2 $f | wc -l | tr -d ' ') 件"
done

echo "PostgreSQL 側:"
docker compose exec db psql -U app_user -d migration_db \
  -c "SELECT tablename, n_tup_ins as inserted_rows FROM pg_stat_user_tables ORDER BY tablename;"

# --- データサンプル確認 ---
docker compose exec db psql -U app_user -d migration_db \
  -c "SELECT * FROM stores LIMIT 5;"
docker compose exec db psql -U app_user -d migration_db \
  -c "SELECT * FROM store_visits LIMIT 5;"

# --- 外部キー整合性チェック ---
# 孤立レコード（親が存在しない子レコード）の検出
docker compose exec db psql -U app_user -d migration_db -c "
SELECT 'store_visits: 孤立レコード' as check_name,
       COUNT(*) as count
FROM store_visits sv
LEFT JOIN stores s ON sv.store_id = s.id
WHERE s.id IS NULL
UNION ALL
SELECT 'visit_details: 孤立レコード',
       COUNT(*)
FROM visit_details vd
LEFT JOIN store_visits sv ON vd.store_visit_id = sv.id
WHERE sv.id IS NULL;
"
```

> [!TIP]
> `docker-compose.yml` でワークショップディレクトリを `/workspace` にマウントしているため、
> `data/` に置いた CSV も `output/` に生成したスクリプトも、コンテナ内から即アクセス可能。

---

## 2-4. SOQL → SQL 変換 + 実行検証（10分）

### SOQL の自動抽出

Claude Code に「Apex ソースコード内の全 SOQL クエリを抽出して一覧化してください」と指示。

### SQL 変換

代表的な 3-5 本を PostgreSQL SQL に変換：

| SOQL 構文 | PostgreSQL 変換 |
|-----------|----------------|
| `Account__r.Name` | `JOIN ... ON ...; alias.name` |
| `THIS_MONTH` | `date_trunc('month', CURRENT_DATE)` |
| `LAST_N_DAYS:30` | `CURRENT_DATE - INTERVAL '30 days'` |
| `TODAY` | `CURRENT_DATE` |
| サブクエリ（子レコード） | `JOIN` or 別クエリ |

### 変換した SQL の実行検証

```bash
# 変換後 SQL を実データに対して実行
docker compose exec db psql -U app_user -d migration_db \
  -f /workspace/02-schema-migration/output/converted_queries.sql

# 個別クエリのテスト（例）
docker compose exec db psql -U app_user -d migration_db \
  -c "SELECT ... FROM ... JOIN ... WHERE ... ORDER BY ...;"
```

---

## 2-5. データ移行戦略の議論（5分）

### 議論ポイント

| 項目 | 選択肢 | 考慮事項 |
|------|--------|---------|
| **移行方式** | ビッグバン / 段階移行 | ダウンタイム許容度、データ量 |
| **エクスポート** | Data Loader / Bulk API 2.0 / sf CLI | レコード件数で選択 |
| **差分移行** | 移行期間中の更新分の扱い | CDC / タイムスタンプベース |
| **ID マッピング** | SFDC ID をそのまま使う / UUID 採番 | 参照整合性の維持 |

---

## ✅ Step 2 完了チェック

```bash
echo "=== Step 2 成果物チェック ==="
for f in generated_ddl.sql import_data.py converted_queries.sql data_validation.sql; do
  if [ -f "02-schema-migration/output/$f" ]; then
    echo "  ✅ $f"
  else
    echo "  ❌ $f (missing)"
  fi
done

# テーブルとデータの存在確認
docker compose exec db psql -U app_user -d migration_db \
  -c "SELECT tablename, n_tup_ins as rows FROM pg_stat_user_tables ORDER BY tablename;"

# SFDC CSV vs PostgreSQL の件数一致確認
echo "=== 件数一致チェック ==="
for f in data/*.csv; do
  table=$(basename $f .csv | sed 's/__c//' | tr '[:upper:]' '[:lower:]')
  csv_count=$(tail -n +2 $f | wc -l | tr -d ' ')
  echo "  $(basename $f): CSV=${csv_count} 件"
done
```

