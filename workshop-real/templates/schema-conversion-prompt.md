# プロンプトテンプレート: SFDC メタデータ → PostgreSQL DDL 変換

> **用途**: SFDX の `.object-meta.xml` + `.field-meta.xml` から PostgreSQL DDL を生成する
> **対象 AI**: Claude Code via Vertex AI

---

## プロンプト本文

```markdown
# 指示

あなたは Salesforce から PostgreSQL への移行スペシャリストです。
以下の SFDX プロジェクトのカスタムオブジェクト定義（XML メタデータ）を入力として受け取り、
PostgreSQL 用の DDL（CREATE TABLE 文）を生成してください。

# 入力ファイル
- カスタムオブジェクト: `force-app/main/default/objects/*/*.object-meta.xml`
- カスタムフィールド: `force-app/main/default/objects/*/fields/*.field-meta.xml`

# 変換ルール（厳守）

## 命名規則
1. **テーブル名**: オブジェクト名を snake_case に変換。`__c` サフィックスは除去。
   - 例: `DailyReport__c` → `daily_reports`（複数形に）
2. **カラム名**: フィールド名を snake_case に変換。`__c` サフィックスは除去。
   - 例: `ReportDate__c` → `report_date`

## データ型マッピング
| SFDC 型 (XML の `<type>`) | PostgreSQL 型 |
|--------------------------|---------------|
| Id | `VARCHAR(18) PRIMARY KEY` |
| Text | `VARCHAR(length)` ※ `<length>` タグの値 |
| LongTextArea / TextArea | `TEXT` |
| Checkbox | `BOOLEAN DEFAULT false` |
| Number | `INTEGER` or `NUMERIC(precision, scale)` |
| Currency / Percent | `NUMERIC(precision, scale)` |
| Date | `DATE` |
| DateTime | `TIMESTAMPTZ` |
| Email | `VARCHAR(254)` |
| Phone | `VARCHAR(40)` |
| Url | `VARCHAR(255)` |
| Picklist | `VARCHAR(255)` + CHECK 制約 |
| MultiselectPicklist | `TEXT[]` |
| AutoNumber | `VARCHAR(20) NOT NULL` |
| Formula | コメントとして記載（カラムは作成しない） |

## リレーション
- `<type>Lookup</type>` → `FOREIGN KEY ... ON DELETE SET NULL`
- `<type>MasterDetail</type>` → `FOREIGN KEY ... ON DELETE CASCADE`, `NOT NULL`

## その他
3. **必須フィールド**: `<required>true</required>` → `NOT NULL`
4. **全テーブルに追加**: `created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP`, `updated_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP`
5. **インデックス**: 外部キー列、`status` や `date` 系のカラムに `CREATE INDEX`
6. **コメント**: `<label>` タグの値を `COMMENT ON COLUMN` で付与
7. **テーブル作成順序**: 外部キーの依存関係を考慮した順序で出力

# 出力形式
- 純粋な SQL のみ（説明は SQL コメントとして記述）
- UTF-8
- テーブル間の依存関係を考慮した作成順序で出力

# 追加生成物
DDL に加えて、以下も生成してください：
1. **データ整合性検証 SQL**: レコード件数チェック、孤立レコードチェック、NULL チェック、Picklist 値妥当性チェック

※ 実データの投入は `/import-data` コマンドで別途行います。シードデータの生成は不要です。

# 出力先
- DDL: `workshop-real/02-schema-migration/output/generated_ddl.sql`
- 検証 SQL: `workshop-real/02-schema-migration/output/data_validation.sql`
```
