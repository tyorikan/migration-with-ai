# 02. スキーマ設計とマッピングのベストプラクティス

SFDC（Salesforce）は独自のオブジェクト・データモデルを採用しています。これを Google Cloud 上の PostgreSQL (Cloud SQL または AlloyDB) に移行する際は、RDB の標準的な設計原則に基づいた変換・再設計が必要です。

## 0. SFDC と RDB の考え方の根本的な違い (非 SFDC エンジニア向け)

Salesforce (SFDC) に詳しくないエンジニアが移行を取り扱う上で、まず **データがどのような形式で保持され、RDB とどう違うのか** を理解することが重要です。

### アーキテクチャの違い: メタデータ駆動型 vs 物理テーブル型
- **RDB (Cloud SQL / AlloyDB など):**
  開発者が `CREATE TABLE` で物理的なテーブルを作成し、カラムの型（`VARCHAR`, `INTEGER` など）を明示的に定義します。データのサイズや制約は DB 層で厳格に管理されます。
- **SFDC (メタデータアーキテクチャ):**
  内部的には少数の巨大な物理データベーステーブル（マルチテナントアーキテクチャ）に全顧客のデータが混在して保存されています。ユーザーが画面上で「オブジェクト（RDB でいうテーブル）」や「項目（RDB でいうカラム）」を作成すると、それは **メタデータ** として登録され、アプリケーション層（Apex や画面）で仮想的なテーブル・単一のデータストアとして振る舞います。

### オブジェクトとフィールドの命名規則
- **標準オブジェクト:** あらかじめ用意されている組み込みのオブジェクト。`Account` (取引先), `Contact` (連絡先), `Opportunity` (商談) など。
- **カスタムオブジェクト / カスタム項目:** ユーザーが独自に追加したもの。API 参照名には必ず末尾に `__c` (アンダースコア 2 つ＋c) が付与されます。（例: `Invoice__c`, `TotalAmount__c`）
- **リレーション:** 参照関係を示すカスタム項目は `__r` を用いて親オブジェクトのデータを引っ張るなど、独自のリレーション参照の仕組みを持ちます。

**移行への影響:**
SFDC のメタデータによって定義されている仮想的なオブジェクト（`__c` を含む）を抽出し、移行先の Cloud SQL / AlloyDB に向けて物理的な DDL（`CREATE TABLE ...`）として明示的な RDB のスキーマを再構築する作業がデータ移行における必須のプロセスとなります。

## 1. プライマリキー（主キー）の設計

SFDC では、全てのレコードが一意の `Id` (15 桁または 18 桁の英数字) を持ちます。

移行先の PostgreSQL における主キーの扱いは 2 つのアプローチがあります。

### アプローチ A: 既存の SFDC ID をそのまま主キーとする
- **型:** `VARCHAR(18)`
- **メリット:** 外部システムや旧アプリ側で既に保持している ID との連携が容易。
- **推奨設定:** 検索パフォーマンスを担保するため、`PRIMARY KEY` に設定し適切なインデックスを付与する。

### アプローチ B: PostgreSQL ネイティブの UUID に切り替える
- **型:** `UUID` (例: `gen_random_uuid()`)
- **メリット:** 完全な分散採番が可能になり、モダンなアプリケーションの要件に合致する。
- **推奨設定:** 新たに `id UUID PRIMARY KEY` を定義し、旧 SFDC ID は `sfdc_id VARCHAR(18) UNIQUE` として保持する（移行・連携のトレーサビリティ用）。

**ワークショップでの推奨:** 段階的移行ではまず **アプローチ A（SFDC ID をそのまま使用）** を採用し、データの連携・検証を容易にします。将来のフルカットオーバー後にアプローチ B へのリファクタリングを検討する形がリスクが小さいです。

## 2. リレーションシップと参照整合性

SFDC における「参照関係 (Lookup)」や「主従関係 (Master-Detail)」は、PostgreSQL では標準の **外部キー (Foreign Key) 制約** を用いてデータベース層で担保します。

### SFDC のリレーション種別と PostgreSQL のマッピング

| SFDC リレーション | PostgreSQL での表現 | 特記事項 |
| :--- | :--- | :--- |
| **Lookup (参照関係)** | `FOREIGN KEY ... ON DELETE SET NULL` | 子レコードは独立して存在可能 |
| **Master-Detail (主従関係)** | `FOREIGN KEY ... ON DELETE CASCADE` | 親が削除されると子も連鎖削除 |
| **Many-to-Many (多対多)** | 中間テーブル (Junction Table) | SFDC のカスタム結合オブジェクトに相当 |

**例: 取引先 (Account) と 連絡先 (Contact) のリレーション**
```sql
-- 取引先 (親)
CREATE TABLE accounts (
    id VARCHAR(18) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT CURRENT_TIMESTAMP
);

-- 連絡先 (子): Lookup 関係
CREATE TABLE contacts (
    id VARCHAR(18) PRIMARY KEY,
    account_id VARCHAR(18),
    first_name VARCHAR(100),
    last_name VARCHAR(100) NOT NULL,
    FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE SET NULL
);
```

### ポリモーフィックリレーションの解決
SFDC Task 等の「関連先 (WhatId)」のようなポリモーフィック（どのオブジェクトの親か実行時まで決まらない）カラムは RDB の外部キー制約と相性が悪いです。運用シナリオに応じて以下のいずれかで設計します。
1. **結合テーブル (Junction Table)** を作成し、明示的に N:N や関連を表現する。
2. 参照可能なオブジェクト（Account, Opportunity など）ごとに別々の外部キーカラム（`account_id`, `opportunity_id`）を用意する。

## 3. データ型のマッピング

主要な SFDC データ型を PostgreSQL のデータ型に変換する基準です。

| SFDC データ型 | PostgreSQL データ型 | 備考 |
| :--- | :--- | :--- |
| Id | `VARCHAR(18)` | SFDC の一意識別子。PRIMARY KEY として利用。 |
| Text, Text Area | `VARCHAR(N)` | N は最大文字数に合わせて設定。 |
| Long Text Area | `TEXT` | 長文やリッチテキストの場合。 |
| Number | `NUMERIC(p,s)` | 精度の指定（全体 p 桁、小数点以下 s 桁）が必要。 |
| Currency | `NUMERIC(p,s)` | 金額情報を扱うため、NUMERIC 型を使用する。 |
| Percent | `NUMERIC(5,2)` | 0.00〜100.00 の範囲。CHECK 制約を推奨。 |
| Checkbox | `BOOLEAN` | `true`, `false` で扱う。 |
| Date | `DATE` | 日付のみ。 |
| Date/Time | `TIMESTAMPTZ` | タイムゾーン込みのタイムスタンプを**推奨**。 |
| Email | `VARCHAR(254)` | RFC 5321 準拠の最大長。CHECK 制約やドメイン型も検討可。 |
| Phone | `VARCHAR(40)` | 電話番号は文字列として格納。 |
| URL | `TEXT` | URL 長は可変のため TEXT を使用。 |
| Picklist | `VARCHAR` | Enum 型の使用も検討できるが、後からの値追加要件などを考慮して `VARCHAR` を推奨。値の制約を担保する場合は `CHECK` 制約を追加する。 |
| Multi-Select Picklist | `TEXT[]` | PostgreSQL の配列型。または正規化して別テーブルに分離。 |
| Reference (Lookup) | `VARCHAR(18)` | 参照先オブジェクトの ID。`FOREIGN KEY` 制約を付与。 |
| Auto Number | `VARCHAR` or `SERIAL` | 既存値を移行する場合は `VARCHAR`。新規採番は `SERIAL` / `GENERATED ALWAYS AS IDENTITY`。 |

## 4. SFDC 固有概念の RDB 移行パターン

SFDC にはカラムとして存在するが、RDB ではそのまま表現できない概念があります。

### 数式項目 (Formula Field)
SFDC では「他の項目の値を元に自動計算される仮想的なカラム」が存在します。

**PostgreSQL での対応パターン:**
- **Generated Column (PostgreSQL 12+):** 単純な計算式の場合。
  ```sql
  ALTER TABLE opportunities ADD COLUMN
    discount_amount NUMERIC GENERATED ALWAYS AS (amount * discount_rate / 100) STORED;
  ```
- **VIEW / Materialized View:** 複数テーブルを横断する計算の場合。
- **アプリケーション層:** 複雑なビジネスロジックはアプリ側で実装。

### ロールアップ集計項目 (Roll-Up Summary)
SFDC の Master-Detail 関係で子レコードの合計・件数・最大・最小を親レコード上に表示する機能。

**PostgreSQL での対応パターン:**
- **View + 集計関数:** `SELECT account_id, COUNT(*), SUM(amount) FROM opportunities GROUP BY account_id`
- **Materialized View:** パフォーマンスが必要な場合にキャッシュとして利用。
- **トリガー:** リアルタイム更新が必要な場合。

### レコードタイプ (Record Type)
同じオブジェクトで異なるページレイアウトやピックリスト値を使い分ける仕組み。

**PostgreSQL での対応パターン:**
- `record_type VARCHAR(100)` カラムを追加し、アプリケーション側で制御。
- 大きく構造が異なる場合は、テーブル継承（`INHERITS`）やポリモーフィックテーブルを検討。

## 5. インデックス設計の推奨

パフォーマンスを確保するため、以下のインデックスを設計時に検討します。

| インデックス対象 | 種別 | 理由 |
| :--- | :--- | :--- |
| 主キー (`id`) | PRIMARY KEY (B-tree, 自動) | 一意検索 |
| 外部キー (`account_id` 等) | B-tree | JOIN / WHERE 句でのフィルタリング高速化 |
| 検索頻度が高いカラム (`email`, `name` 等) | B-tree | アプリからの検索最適化 |
| 全文検索対象 (`description` 等) | GIN (tsvector) | PostgreSQL 全文検索 |
| ステータス / 種別 (低カーディナリティ) | 部分インデックス | `WHERE status = 'active'` のような絞り込み |

```sql
-- 外部キーへのインデックス例
CREATE INDEX idx_contacts_account_id ON contacts(account_id);

-- 部分インデックス例
CREATE INDEX idx_opportunities_open ON opportunities(close_date)
  WHERE stage_name != 'Closed Won' AND stage_name != 'Closed Lost';
```

## 6. 次のステップ
このマッピング規約を手動ですべて適用するのは大変です。AI を活用し、このルールに基づく DDL を一括生成する検証については、[AI を活用したスキーマ変換 (03_ai_conversion_guide.md)](03_ai_conversion_guide.md) をご参照ください。
