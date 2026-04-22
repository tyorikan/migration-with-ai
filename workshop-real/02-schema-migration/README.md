# Step 2: DB スキーマ移行設計 + データ検証（13:00 – 13:45）

> [!NOTE]
> Step 1 で生成したデータモデル仕様書（ER 図、フィールド定義一覧）をインプットに、
> **PostgreSQL DDL の生成 → docker-compose でデータ投入 → クエリ変換・実行検証** まで行う。

## 🎯 ゴール

| 成果物 | 出力先 |
|--------|--------|
| PostgreSQL DDL | `02-schema-migration/output/generated_ddl.sql` |
| シードデータ SQL | `02-schema-migration/output/seed_data.sql` |
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

## 2-2. docker-compose で PostgreSQL 起動 + DDL 適用 + データ投入（15分）

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
# 期待結果: 変換対象の全テーブルが表示される

# テーブル定義の詳細確認（代表1テーブル）
docker compose exec db psql -U app_user -d migration_db -c "\d target_table_name"
```

### シードデータの生成と投入

Claude Code に「Step 1 で生成した ER 図とフィールド定義に基づき、テスト用のシードデータ SQL を生成してください」と指示。

```bash
# シードデータを投入
docker compose exec db psql -U app_user -d migration_db \
  -f /workspace/02-schema-migration/output/seed_data.sql

# 投入結果の確認
docker compose exec db psql -U app_user -d migration_db \
  -c "SELECT tablename, n_tup_ins FROM pg_stat_user_tables ORDER BY tablename;"
```

> [!TIP]
> `docker-compose.yml` でワークショップディレクトリを `/workspace` にマウントしているため、
> `output/` に新しい SQL ファイルを置くだけで、コンテナ内から即実行可能。

---

## 2-3. SOQL → SQL 変換 + 実行検証（10分）

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
# 変換後 SQL を実行（シードデータに対して）
docker compose exec db psql -U app_user -d migration_db \
  -f /workspace/02-schema-migration/output/converted_queries.sql

# 個別クエリのテスト（例）
docker compose exec db psql -U app_user -d migration_db \
  -c "SELECT ... FROM ... JOIN ... WHERE ... ORDER BY ...;"
```

---

## 2-4. データ移行戦略の議論（5分）

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
for f in generated_ddl.sql seed_data.sql converted_queries.sql; do
  if [ -f "02-schema-migration/output/$f" ]; then
    echo "  ✅ $f"
  else
    echo "  ❌ $f (missing)"
  fi
done

# テーブルとデータの存在確認
docker compose exec db psql -U app_user -d migration_db \
  -c "SELECT schemaname, tablename FROM pg_tables WHERE schemaname='public';"
```
