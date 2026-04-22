# SFDC→PostgreSQL データマッピング仕様書テンプレート

## 概要
このテンプレートは、SFDC（Salesforce）のオブジェクト定義を Google Cloud 上の PostgreSQL テーブルに変換する際の、詳細なマッピング仕様を記述するためのものです。

[02_schema_design.md](../../2-database-migration/02_schema_design.md) のデータ型マッピング規約に基づいて記述してください。

---

## マッピングルール

- **テーブル名:** SFDC オブジェクト名を `snake_case` の複数形に変換（例: `Account` → `accounts`）
- **カラム名:** SFDC 項目の API 参照名を `snake_case` に変換（例: `AnnualRevenue` → `annual_revenue`）
- **`__c` サフィックス:** カスタム項目の `__c` は除去し `snake_case` に変換
- **主キー戦略:** 段階的移行ではアプローチ A（SFDC ID をそのまま使用）を採用

---

## 記入例 1: Account (取引先)

### オブジェクト基本情報

| 項目 | 値 |
| :--- | :--- |
| **SFDC オブジェクト名** | Account |
| **SFDC ラベル** | 取引先 |
| **PostgreSQL テーブル名** | `accounts` |
| **主キー戦略** | アプローチ A: SFDC ID (`VARCHAR(18)`) |
| **レコード件数 (見込み)** | 〜50,000 件 |

### フィールドマッピング

| # | SFDC 項目名 (API) | SFDC 型 | PostgreSQL カラム名 | PostgreSQL 型 | NOT NULL | 制約 / インデックス | 備考 |
| :---: | :--- | :--- | :--- | :--- | :---: | :--- | :--- |
| 1 | `Id` | Id | `id` | `VARCHAR(18)` | ✅ | `PRIMARY KEY` | SFDC 一意識別子 |
| 2 | `Name` | Text(255) | `name` | `VARCHAR(255)` | ✅ | `INDEX` | 取引先名 |
| 3 | `Type` | Picklist | `account_type` | `VARCHAR(100)` | | | 種別。CHECK 制約は要件次第 |
| 4 | `Industry` | Picklist | `industry` | `VARCHAR(100)` | | | 業種 |
| 5 | `AnnualRevenue` | Currency | `annual_revenue` | `NUMERIC(18,2)` | | | 年間売上 |
| 6 | `NumberOfEmployees` | Number | `number_of_employees` | `INTEGER` | | | 従業員数 |
| 7 | `Phone` | Phone | `phone` | `VARCHAR(40)` | | | 電話番号 |
| 8 | `Website` | URL | `website` | `TEXT` | | | Web サイト |
| 9 | `BillingCity` | Text | `billing_city` | `VARCHAR(255)` | | | 請求先都市 |
| 10 | `OwnerId` | Reference | `owner_id` | `VARCHAR(18)` | | `FK → users(id)` | 所有者 |
| 11 | `CreatedDate` | DateTime | `created_at` | `TIMESTAMPTZ` | ✅ | | SFDC の作成日時を移行 |
| 12 | `LastModifiedDate` | DateTime | `updated_at` | `TIMESTAMPTZ` | ✅ | | SFDC の更新日時を移行 |
| 13 | `IsDeleted` | Checkbox | `is_deleted` | `BOOLEAN` | ✅ | `DEFAULT false` | 論理削除フラグ |

### 生成される DDL

```sql
CREATE TABLE accounts (
    id                   VARCHAR(18) PRIMARY KEY,
    name                 VARCHAR(255) NOT NULL,
    account_type         VARCHAR(100),
    industry             VARCHAR(100),
    annual_revenue       NUMERIC(18,2),
    number_of_employees  INTEGER,
    phone                VARCHAR(40),
    website              TEXT,
    billing_city         VARCHAR(255),
    owner_id             VARCHAR(18),
    created_at           TIMESTAMPTZ NOT NULL,
    updated_at           TIMESTAMPTZ NOT NULL,
    is_deleted           BOOLEAN NOT NULL DEFAULT false
);

-- パフォーマンス用インデックス
CREATE INDEX idx_accounts_name ON accounts(name);
CREATE INDEX idx_accounts_owner_id ON accounts(owner_id);
CREATE INDEX idx_accounts_industry ON accounts(industry);
```

---

## 記入例 2: Contact (連絡先 / 責任者)

### オブジェクト基本情報

| 項目 | 値 |
| :--- | :--- |
| **SFDC オブジェクト名** | Contact |
| **SFDC ラベル** | 責任者 |
| **PostgreSQL テーブル名** | `contacts` |
| **主キー戦略** | アプローチ A: SFDC ID (`VARCHAR(18)`) |
| **レコード件数 (見込み)** | 〜200,000 件 |
| **リレーション** | → `accounts` (Lookup: `ON DELETE SET NULL`) |

### フィールドマッピング

| # | SFDC 項目名 (API) | SFDC 型 | PostgreSQL カラム名 | PostgreSQL 型 | NOT NULL | 制約 / インデックス | 備考 |
| :---: | :--- | :--- | :--- | :--- | :---: | :--- | :--- |
| 1 | `Id` | Id | `id` | `VARCHAR(18)` | ✅ | `PRIMARY KEY` | |
| 2 | `AccountId` | Reference | `account_id` | `VARCHAR(18)` | | `FK → accounts(id) ON DELETE SET NULL`, `INDEX` | Lookup 関係 |
| 3 | `LastName` | Text(80) | `last_name` | `VARCHAR(80)` | ✅ | | 姓 |
| 4 | `FirstName` | Text(40) | `first_name` | `VARCHAR(40)` | | | 名 |
| 5 | `Email` | Email | `email` | `VARCHAR(254)` | | `UNIQUE INDEX` | RFC 5321 準拠 |
| 6 | `Phone` | Phone | `phone` | `VARCHAR(40)` | | | |
| 7 | `DoNotCall` | Checkbox | `do_not_call` | `BOOLEAN` | ✅ | `DEFAULT false` | 電話拒否 |
| 8 | `CreatedDate` | DateTime | `created_at` | `TIMESTAMPTZ` | ✅ | | |
| 9 | `LastModifiedDate` | DateTime | `updated_at` | `TIMESTAMPTZ` | ✅ | | |

### 生成される DDL

```sql
CREATE TABLE contacts (
    id          VARCHAR(18) PRIMARY KEY,
    account_id  VARCHAR(18),
    last_name   VARCHAR(80) NOT NULL,
    first_name  VARCHAR(40),
    email       VARCHAR(254),
    phone       VARCHAR(40),
    do_not_call BOOLEAN NOT NULL DEFAULT false,
    created_at  TIMESTAMPTZ NOT NULL,
    updated_at  TIMESTAMPTZ NOT NULL,
    FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE SET NULL
);

CREATE INDEX idx_contacts_account_id ON contacts(account_id);
CREATE UNIQUE INDEX idx_contacts_email ON contacts(email) WHERE email IS NOT NULL;
```

---

## 空テンプレート（コピーして使用）

### オブジェクト基本情報

| 項目 | 値 |
| :--- | :--- |
| **SFDC オブジェクト名** | |
| **SFDC ラベル** | |
| **PostgreSQL テーブル名** | |
| **主キー戦略** | |
| **レコード件数 (見込み)** | |
| **リレーション** | |

### フィールドマッピング

| # | SFDC 項目名 (API) | SFDC 型 | PostgreSQL カラム名 | PostgreSQL 型 | NOT NULL | 制約 / インデックス | 備考 |
| :---: | :--- | :--- | :--- | :--- | :---: | :--- | :--- |
| 1 | | | | | | | |

### 特記事項 / 移行時の考慮点

- *（数式項目、ロールアップ集計、レコードタイプなどの特殊な変換ルールがあれば記載）*
