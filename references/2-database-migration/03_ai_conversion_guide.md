# 03. AI を活用したスキーマ変換・SQL 生成ガイド

本ドキュメントでは、Gemini を活用して Salesforce (SFDC) のオブジェクトメタデータから PostgreSQL 用の DDL（スキーマ定義）を自動生成するアプローチ、および SOQL を SQL に書き換えるアプローチについて解説します。

## 1. 生成 AI (Gemini) を活用する理由

レガシーシステムからモダンな環境へ移行する際、既存の数百にも及ぶスキーマ定義を手動でマッピングするのは多大なリソースを消費し、人為的エラーの原因となります。テキストやコードの生成に長けた Gemini を活用することで、ルールに基づいた DDL の生成やクエリ変換の時間を劇的に削減できます。

### AI 活用の対象範囲と AI に任せるべきでない範囲

| 🟢 AI に任せる（効果的） | 🔴 人間が判断する |
| :--- | :--- |
| データ型マッピングの一括変換 | ビジネス要件に基づくテーブル分割・統合戦略 |
| 命名規則の自動適用（CamelCase → snake_case） | パフォーマンス要件に基づくインデックス戦略の最終決定 |
| COMMENT 文の自動付与 | セキュリティ要件に基づくアクセス制御設計 |
| SOQL → SQL の構文変換 | データ整合性ルールの取捨選択 |

## 2. DDL 生成のプロンプトエンジニアリング

以下のプロンプトテンプレートを活用して、SFDC のオブジェクト情報を PostgreSQL の DDL に変換させます。

**プロンプト例：**
```markdown
あなたは Google Cloud の Data Architect および PostgreSQL 環境のスペシャリストです。
以下の Salesforce (SFDC) のオブジェクトメタデータ情報を元に、PostgreSQL 向けの DDL を作成してください。

【制約・ルール】
1. プライマリキー (ID): SFDC の `Id` は `VARCHAR(18) PRIMARY KEY` で定義してください。
2. テーブル名・カラム名: スネークケース（小文字 + アンダースコア）に変換してください。
   カスタムオブジェクト名の末尾 `__c` は除去してください。
3. リレーションシップ構造: 参照項目は `FOREIGN KEY` 制約として PostgreSQL 上にマッピングしてください。
   - Lookup 関係: `ON DELETE SET NULL`
   - Master-Detail 関係: `ON DELETE CASCADE`
4. データ型マッピング:
   - テキスト型: `VARCHAR(N)` (N は SFDC の maxLength に対応)
   - チェックボックス: `BOOLEAN`
   - 数値・通貨: `NUMERIC`
   - 日付: `DATE`
   - 日時: `TIMESTAMPTZ` (タイムゾーン込みのタイムスタンプ)
   - メール: `VARCHAR(254)`
5. 全てのテーブルとカラムに対して、元の label 情報を使って COMMENT を追加してください。
6. 外部キーカラムには B-tree インデックスを作成してください。

【SFDCメタデータ】
{ここに JSON のメタデータ定義を入力}
```

### プロンプトを改善するコツ
- **Few-Shot で例示する:** 期待する DDL の出力例を 1 つ添えると、フォーマットのブレが減る。
- **制約を箇条書きで明示:** 曖昧な指示（「適切に」「最適な」）より、具体的なルール（「ON DELETE CASCADE」「VARCHAR(18)」）を指定する。
- **メタデータ形式を統一:** JSON で渡すことで、Gemini がフィールド名・型・長さを正確にパースできる。

## 3. SOQL から SQL への変換

Salesforce のクエリ言語である SOQL は、標準 SQL と似ていますが独自の記法があります。

### SOQL と SQL の主要な違い

| 項目 | SOQL | PostgreSQL SQL |
| :--- | :--- | :--- |
| テーブル指定 | `FROM Account` (オブジェクト名) | `FROM accounts` (テーブル名) |
| リレーション参照 | `Account.Name` (ドット記法) | `JOIN` + `ON` 句 |
| 日付リテラル | `THIS_YEAR`, `LAST_N_DAYS:30` | `date_trunc('year', CURRENT_DATE)`, `CURRENT_DATE - INTERVAL '30 days'` |
| 集計 | `SELECT COUNT() FROM ...` | `SELECT COUNT(*) FROM ...` |
| サブクエリ | `WHERE Id IN (SELECT ...)` は制限あり | 標準のサブクエリが利用可能 |
| LIMIT | `LIMIT 100` | `LIMIT 100` (同一) |

### 変換プロンプト例 1: リレーション参照の展開

```markdown
以下の SOQL クエリを、PostgreSQL に最適化された標準 SQL に変換してください。

【変換要件】
1. リレーション (`Account.Name` などのドット記法) は `JOIN` に展開し、`ON` 句を適切に指定。
2. SFDC 固有の日付関数は PostgreSQL の標準関数に置き換え。
3. テーブル名・カラム名はスネークケースに変換。
4. パフォーマンス最適化のための CREATE INDEX 文も提案。

【対象の SOQL】
SELECT Id, Name, Amount, CloseDate, StageName, Account.Name
FROM Opportunity
WHERE CloseDate >= THIS_YEAR AND StageName = 'Closed Won'
```

**期待される変換結果の例:**
```sql
SELECT
    o.id,
    o.name,
    o.amount,
    o.close_date,
    o.stage_name,
    a.name AS account_name
FROM opportunities o
LEFT JOIN accounts a ON o.account_id = a.id
WHERE o.close_date >= date_trunc('year', CURRENT_DATE)
  AND o.stage_name = 'Closed Won';

-- 推奨インデックス
CREATE INDEX idx_opportunities_close_date_stage ON opportunities(close_date, stage_name);
```

### 変換プロンプト例 2: 集計クエリ（ロールアップ相当）

```markdown
以下の SOQL をPostgreSQLのSQLに変換してください。

【対象の SOQL】
SELECT AccountId, Account.Name, COUNT(Id), SUM(Amount)
FROM Opportunity
WHERE StageName = 'Closed Won'
GROUP BY AccountId, Account.Name
HAVING SUM(Amount) > 1000000
ORDER BY SUM(Amount) DESC
```

### 変換プロンプト例 3: 日付リテラルの変換

SFDC の日付リテラルは PostgreSQL の関数で置き換えます。

| SOQL 日付リテラル | PostgreSQL 変換 |
| :--- | :--- |
| `TODAY` | `CURRENT_DATE` |
| `THIS_WEEK` | `date_trunc('week', CURRENT_DATE)` |
| `THIS_MONTH` | `date_trunc('month', CURRENT_DATE)` |
| `THIS_YEAR` | `date_trunc('year', CURRENT_DATE)` |
| `LAST_N_DAYS:30` | `CURRENT_DATE - INTERVAL '30 days'` |
| `NEXT_N_DAYS:7` | `CURRENT_DATE + INTERVAL '7 days'` |

## 4. プログラマティックな変換（スクリプト実行）

一度に多くの処理を行うため、**Google Gen AI SDK (`google-genai`)** を使って Python スクリプト経由で Gemini を呼び出し、一括処理することをお勧めします。

### スクリプトの実行フロー

```
1. SFDC メタデータ JSON を準備
   └─→ sample_sfdc_schema.json

2. Python スクリプトを実行
   └─→ gemini_ddl_generator.py
       ├─ google-genai SDK 経由で Gemini API を呼び出し
       └─ プロンプト + メタデータ JSON を送信

3. 生成された DDL を確認 & 適用
   └─→ output_generated.sql
       └─ psql / Cloud SQL Studio で実行
```

具体的なサンプル実装については [`scripts/` フォルダのプログラム](scripts/README.md) を参照して実行してみてください。

## 5. 生成結果のレビューポイント

AI が生成した DDL は必ず人間がレビューしてから適用します。

- [ ] テーブル名・カラム名がプロジェクトの命名規則に準拠しているか
- [ ] データ型が [02_schema_design.md](02_schema_design.md) のマッピング表と一致しているか
- [ ] 外部キー制約の `ON DELETE` 動作が業務要件に沿っているか
- [ ] NOT NULL 制約が適切に設定されているか（SFDC の「必須」項目は NOT NULL にする）
- [ ] インデックスが主要な検索パターンをカバーしているか
