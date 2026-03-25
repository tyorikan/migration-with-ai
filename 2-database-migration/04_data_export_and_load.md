# 04. データ移行手順とロード戦略 (Data Export & Load)

スキーマ定義（DDL）が Google Cloud の Cloud SQL または AlloyDB に作成された後の、Salesforce (SFDC) からの実データの移行アプローチについて解説します。

## 1. データ抽出 (Extract): どうやって SFDC からデータを取り出すか？

SFDC からデータを抽出するには、データベースに対する直接の SELECT はできないため、SFDC が提供する API を介して行います。

### 抽出手法 (How) と出力形式のバリエーション
1. **Salesforce Data Loader (標準 GUI ツール):**
   - **対象:** 非エンジニアや、手動で数百万件までのデータをエクスポートしたい場合の手軽なアプローチ。
   - **出力:** ローカルマシンに **CSV** 形式で出力。
   - **手順:** Data Loader を起動 → Export → オブジェクト選択 → SOQL 指定 → CSV 保存。
2. **Salesforce Bulk API 2.0 (プログラム経由・大規模向け推奨):**
   - **対象:** 数百万〜数千万件、あるいは夜間バッチ等で自動抽出パイプラインを組む場合。
   - **出力:** SFDC 側でジョブを非同期実行し、結果を **CSV** でダウンロード（Python / REST API 等で実装）。
3. **SOQL (Salesforce Object Query Language) 経由の REST API:**
   - **対象:** 抽出条件が複雑、あるいはリアルタイムに近い小ロットのデータ連携。
   - **出力:** **JSON** 形式。
   - *補足:* RDB の SQL に似ていますが、`SELECT Id, Name FROM Account` のようにオブジェクトを指定します。

**【ワークショップでの推奨パス】:**
Google Cloud の RDB (Cloud SQL / AlloyDB) への一括ロードを考慮すると、Cloud SQL がネイティブで高速なインポートをサポートしている **CSV** で抽出するパス（Data Loader または Bulk API の利用）を推奨アプローチとします。

### 抽出順序の考慮
リレーションによる親オブジェクトが存在するテーブルがある場合、**抽出・挿入の順序** を親→子の依存関係に沿って実施する必要があります。

**例: 推奨抽出順序**
```
1. Account   (親 - 他の多くのオブジェクトから参照される)
2. Contact   (Account を参照)
3. Opportunity (Account を参照)
4. OpportunityLineItem (Opportunity を参照)
5. Task / Event (ポリモーフィック - 最後に処理)
```

## 2. データ変換・クレンジング (Transform)

SFDC から抽出された CSV をそのまま投入すると、文字コードの不一致や NULL の扱いの違いによりエラーになる場合があります。

### 変換チェック項目

| # | 確認事項 | 対応方法 |
| :--- | :--- | :--- |
| 1 | **文字コード** | UTF-8 に統一されているか確認。SFDC Data Loader は UTF-8 出力がデフォルト。 |
| 2 | **改行コード** | CSV 内の文字列に含まれる CRLF / LF のハンドリング（特に Long Text Area）。 |
| 3 | **Boolean 変換** | SFDC は `true` / `false`。PostgreSQL はそのまま解釈可能。 |
| 4 | **日時フォーマット** | SFDC の ISO 8601 形式は `TIMESTAMPTZ` にそのままインポート可能。 |
| 5 | **NULL / 空文字** | SFDC の空フィールドが CSV で空文字 `""` になる場合、PostgreSQL の NULL として扱うか判断。 |
| 6 | **カスタム項目名** | CSV ヘッダの `__c` サフィックスを DDL のカラム名に合わせてリネーム。 |
| 7 | **Picklist 値** | SFDC の API 値と表示ラベルの違いに注意。API 値を格納する。 |

### CSV ヘッダのマッピング例

SFDC のエクスポート CSV のヘッダ名は API 参照名（CamelCase）になります。PostgreSQL のカラム名（snake_case）に合わせて変換が必要です。

```
SFDC CSV ヘッダ:   Id, AccountId, LastName, FirstName, Email, DoNotCall
PostgreSQL カラム: id, account_id, last_name, first_name, email, do_not_call
```

簡易的な変換スクリプト例（Python）:
```python
import csv, re

def camel_to_snake(name):
    """CamelCase を snake_case に変換"""
    s = re.sub(r'(?<=[a-z0-9])([A-Z])', r'_\1', name)
    return s.lower().replace('__c', '')

# CSVヘッダを変換
with open('contacts_sfdc.csv', 'r') as infile, open('contacts_pg.csv', 'w', newline='') as outfile:
    reader = csv.reader(infile)
    writer = csv.writer(outfile)
    headers = next(reader)
    writer.writerow([camel_to_snake(h) for h in headers])
    for row in reader:
        writer.writerow(row)
```

## 3. Google Cloud へのロード (Load)

### アプローチ A: Cloud Storage + Cloud SQL Import (中〜大規模向け・推奨)
最も確実で高速にデータをロードするアプローチです。

**Step 1: GCS にアップロード**
```bash
# GCS バケット作成（初回のみ）
gcloud storage buckets create gs://${GOOGLE_CLOUD_PROJECT}-migration-data \
  --location=asia-northeast1

# CSV をアップロード
gcloud storage cp accounts.csv gs://${GOOGLE_CLOUD_PROJECT}-migration-data/
gcloud storage cp contacts.csv gs://${GOOGLE_CLOUD_PROJECT}-migration-data/
```

**Step 2: Cloud SQL インスタンスのサービスアカウントに GCS アクセス権限を付与**
```bash
# Cloud SQL インスタンスのサービスアカウントを取得
SA=$(gcloud sql instances describe sfdc-migration-db \
  --format='value(serviceAccountEmailAddress)' \
  --project=${GOOGLE_CLOUD_PROJECT})

# GCS バケットへの読み取り権限を付与
gcloud storage buckets add-iam-policy-binding \
  gs://${GOOGLE_CLOUD_PROJECT}-migration-data \
  --member="serviceAccount:${SA}" \
  --role="roles/storage.objectViewer"
```

**Step 3: Cloud SQL へのインポート（親テーブルから順に実行）**
```bash
# 1. accounts テーブルのインポート
gcloud sql import csv sfdc-migration-db \
  gs://${GOOGLE_CLOUD_PROJECT}-migration-data/accounts.csv \
  --project=${GOOGLE_CLOUD_PROJECT} \
  --database=sfdc_app \
  --table=accounts

# 2. contacts テーブルのインポート（accounts の後に実行）
gcloud sql import csv sfdc-migration-db \
  gs://${GOOGLE_CLOUD_PROJECT}-migration-data/contacts.csv \
  --project=${GOOGLE_CLOUD_PROJECT} \
  --database=sfdc_app \
  --table=contacts
```

### アプローチ B: psql コマンドの \copy 利用 (小規模向け、ローカル検証用)
手元のローカルマシンから直接データを流し込みます。

```bash
# Cloud SQL Auth Proxy 経由で接続し \copy を実行
psql "host=127.0.0.1 port=5432 dbname=sfdc_app user=app_user" \
  -c "\copy accounts FROM 'accounts.csv' WITH CSV HEADER"
psql "host=127.0.0.1 port=5432 dbname=sfdc_app user=app_user" \
  -c "\copy contacts FROM 'contacts.csv' WITH CSV HEADER"
```

### アプローチ C: Dataflow などの ETL パイプライン (大規模・変換処理必須)
変換ロジックが複雑な場合や、大量なファイルのオーケストレーションが必要な場合は Serverless な Dataflow や Dataproc を展開します。

## 4. ロード後の検証

データロードが完了したら、以下の観点で整合性を検証します。

### 検証チェックリスト

| # | 検証項目 | 確認方法 | 完了 |
| :--- | :--- | :--- | :--- |
| 1 | **件数一致** | SFDC 側の `COUNT()` と PostgreSQL 側の `COUNT(*)` を比較 | ☐ |
| 2 | **参照整合性** | 外部キー制約違反がないことを確認 | ☐ |
| 3 | **サンプリング検証** | 主要テーブルからランダムに 10〜50 件を抽出し、SFDC の値と目視照合 | ☐ |
| 4 | **NULL 値の整合性** | `SELECT COUNT(*) FROM contacts WHERE account_id IS NULL` 等で NULL 件数が想定通りか確認 | ☐ |
| 5 | **日時のタイムゾーン** | `TIMESTAMPTZ` で格納されたデータが正しい UTC / JST で表示されるか確認 | ☐ |
| 6 | **文字化け確認** | 日本語を含むレコードが正しく格納されているか（特に Long Text Area） | ☐ |

### 検証用 SQL 例

```sql
-- 1. 件数確認
SELECT 'accounts' AS table_name, COUNT(*) AS row_count FROM accounts
UNION ALL
SELECT 'contacts', COUNT(*) FROM contacts
UNION ALL
SELECT 'opportunities', COUNT(*) FROM opportunities;

-- 2. 外部キー整合性: contacts.account_id が accounts.id に存在するか
SELECT c.id, c.account_id
FROM contacts c
LEFT JOIN accounts a ON c.account_id = a.id
WHERE c.account_id IS NOT NULL AND a.id IS NULL;

-- 3. NULL 件数の確認
SELECT
    COUNT(*) AS total,
    COUNT(account_id) AS with_account,
    COUNT(*) - COUNT(account_id) AS without_account
FROM contacts;
```

## 5. 移行全体チェックリスト

全フェーズを通しての完了確認用チェックリストです。

| フェーズ | タスク | 完了 |
| :--- | :--- | :--- |
| **準備** | 移行対象オブジェクトの棚卸し完了 | ☐ |
| **準備** | Cloud SQL / AlloyDB インスタンス作成完了 | ☐ |
| **スキーマ** | DDL を Gemini で生成し、人間がレビュー完了 | ☐ |
| **スキーマ** | DDL を対象 DB に適用完了 | ☐ |
| **抽出** | 全対象オブジェクトの CSV エクスポート完了 | ☐ |
| **変換** | CSV ヘッダの snake_case 変換完了 | ☐ |
| **変換** | 文字コード・NULL・日時フォーマットの確認完了 | ☐ |
| **ロード** | GCS へのアップロード完了 | ☐ |
| **ロード** | 親テーブルから順にインポート完了 | ☐ |
| **検証** | 件数一致確認完了 | ☐ |
| **検証** | 参照整合性確認完了 | ☐ |
| **検証** | サンプリング検証完了 | ☐ |
