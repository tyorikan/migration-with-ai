---
name: workshop-db-migration
description: Assist with migrating Salesforce (SFDC) data architecture to Google Cloud databases like Cloud SQL (PostgreSQL) or AlloyDB. Use when the user mentions database migration, SQL conversion, schema migration strategies, or PostgreSQL setups.
---
# データベース移行 (Database Migration) スキル

このスキルは、SFDCにおけるデータ・アーキテクチャ（オブジェクトとリレーション）を、Google Cloudのフルマネージドデータベース（特に **Cloud SQL や AlloyDB などの PostgreSQL**）に移行するためのスキーマ設計、AIを活用したSQL・DDL変換、およびテストデータ移行戦略を支援します。

## スキーマ移行のベストプラクティス
PostgreSQL (Cloud SQL / AlloyDB) への移行において、以下の設計原則をお客様と共有してください。

1. **プライマリキーとデータ型のマッピング**
   - SFDC の `Id` (18桁の文字) は、PostgreSQL では UUIDv4 (`gen_random_uuid()`) などを活用して新規採番するか、既存の ID を維持する場合は `VARCHAR(18)` として主キーに設定し、検索パフォーマンス向上のために適切なインデックスを付与する設計を提案してください。
2. **外部キー制約と参照整合性の維持**
   - 取引先 (Account) と 連絡先 (Contact) のような親子リレーションシップについては、PostgreSQL標準の `FOREIGN KEY` 制約を用いてデータベース側で参照整合性を担保するように提案してください。

## AIを用いたDDL自動生成プロンプトと検証
Geminiを活用して、SFDCのスキーマ情報をPostgreSQLのDDLに変換します。

### 変換プロンプト例
```markdown
以下のSalesforceオブジェクト（AccountとContact）のスキーマメタデータを、PostgreSQL用のDDLに変換してください。
変換時の要件：
1. 主キーは UUID (`gen_random_uuid()`) とするか、既存IDを引き継ぐための `VARCHAR(18)` を適切に選択すること
2. AccountとContactには親子関係があるため、ContactのテーブルにはAccountへの外部キー(`FOREIGN KEY`)制約を設けること
3. カラムの型はPostgreSQLで推奨される型 (VARCHAR, TIMESTAMP, BOOLEAN, NUMERIC など) にマッピングすること

【SFDCメタデータ】
...(ここにJSONやCSV形式のスキーマ定義を記載)...
```

## スクリプト実装例: スキーマ変換パイプライン
簡単なPythonスクリプトで、Gemini APIを利用して大量のオブジェクトDDLを一括変換するサンプルです。

```python
import vertexai
from vertexai.generative_models import GenerativeModel

# Vertex AI Gemini の初期化
vertexai.init(project="your-project-id", location="asia-northeast1")
model = GenerativeModel("gemini-3.1-pro-preview")

def generate_ddl_from_sfdc(sfdc_schema_json: str) -> str:
    prompt = f"""
    以下のSFDCスキーマをPostgreSQLのDDLに変換してください。
    【PostgreSQLのベストプラクティス】
    - 主キーやデータ型をPostgreSQLの標準仕様に沿って適切に設定すること。
    - リレーションシップを解釈し、外部キー制約を付与すること。
    
    スキーマ:
    {sfdc_schema_json}
    """
    response = model.generate_content(prompt)
    return response.text

# 実行例
with open('sfdc_schema.json', 'r') as f:
    sfdc_data = f.read()

ddl_output = generate_ddl_from_sfdc(sfdc_data)
print("--- 生成されたDDL ---")
print(ddl_output)
```

このスキルを使って、お客様が「スキーマをどうやってPostgreSQL向けにリファクタリングすればいいか」の勘所を掴めるように支援してください。
