---
name: sfdc-schema-migration
description: SFDC オブジェクトメタデータ → PostgreSQL DDL の変換スキル。命名規則、データ型マッピング、外部キー依存関係の順序解決、データ移行戦略を定義。
---

SFDC のオブジェクト定義（.object-meta.xml / JSON）を PostgreSQL の CREATE TABLE 文に変換するルール集。

## When to Activate
- SFDC メタデータから DDL を生成するとき
- スキーマ変換の正しさを検証するとき
- データ移行スクリプトを作成するとき
- 外部キー依存関係を解決するとき

## 命名規則

| SFDC | PostgreSQL | 例 |
|------|-----------|-----|
| オブジェクト名 | `__c` 除去 → snake_case → **複数形** | `StoreVisit__c` → `store_visits` |
| カラム名 | `__c` 除去 → snake_case | `StoreCode__c` → `store_code` |
| 標準フィールド | そのまま snake_case | `CreatedDate` → `created_date` |
| リレーション名 | `__r` 除去 → `_id` サフィックス | `Account__r` → `account_id` |

### 複数形変換の注意点
- `y` → `ies`（例: `category` → `categories`）
- `s`, `x`, `z`, `ch`, `sh` → `es`（例: `batch` → `batches`）
- 不規則形はそのまま定義（例: `person` → `people`）

## データ型マッピング

| SFDC 型 | PostgreSQL 型 | 備考 |
|---------|-------------|------|
| `Id` | `VARCHAR(18) PRIMARY KEY` | SFDC の 18桁 case-insensitive Id |
| `Text(n)` | `VARCHAR(n)` | 長さ制約をそのまま移行 |
| `LongTextArea` | `TEXT` | 長さ制限なし |
| `RichTextArea` | `TEXT` | HTML タグを含む可能性あり |
| `Checkbox` | `BOOLEAN DEFAULT false` | デフォルト値を必ず設定 |
| `Number(p, s)` | `INTEGER` or `NUMERIC(p, s)` | 小数点 0 なら INTEGER |
| `Currency(p, s)` | `NUMERIC(p, s)` | 通貨は常に NUMERIC |
| `Percent` | `NUMERIC(5, 2)` | 0.00 ～ 100.00 |
| `Date` | `DATE` | |
| `DateTime` | `TIMESTAMPTZ` | タイムゾーン付き |
| `Time` | `TIME` | |
| `Email` | `VARCHAR(255)` | CHECK 制約でフォーマット検証推奨 |
| `Phone` | `VARCHAR(40)` | |
| `Url` | `VARCHAR(255)` | |
| `Picklist` | `VARCHAR(255)` | CHECK 制約 or ENUM 型 |
| `MultiselectPicklist` | `TEXT[]` | PostgreSQL 配列型 |
| `Lookup` | FK `ON DELETE SET NULL` | NULL 許容 |
| `MasterDetail` | FK `ON DELETE CASCADE NOT NULL` | NULL 不許容 |
| `Formula` | DDL に含めない | コメントとして記録し、計算戦略を別途決定 |
| `Rollup Summary` | DDL に含めない | トリガーまたはアプリ層で計算 |

## 外部キー依存関係の解決

DDL 生成時は **トポロジカルソート** で依存関係を解決する。

### ルール
1. 参照先テーブルを先に CREATE
2. 自己参照は `ALTER TABLE ADD CONSTRAINT` で後から追加
3. 循環参照は片方を `ALTER TABLE` で分離

```sql
-- ✅ 正しい順序
CREATE TABLE accounts (...);
CREATE TABLE contacts (
    account_id VARCHAR(18) REFERENCES accounts(sfdc_id)
);

-- ❌ 逆順はエラー
CREATE TABLE contacts (
    account_id VARCHAR(18) REFERENCES accounts(sfdc_id)  -- accounts がまだない！
);
CREATE TABLE accounts (...);
```

## 標準フィールドの処理

すべてのテーブルに以下の監査フィールドを含める：

```sql
-- 既存 SFDC レコード用
sfdc_id         VARCHAR(18) UNIQUE,           -- 元の SFDC Id（移行データ用）

-- 新規レコード用
id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),

-- 監査フィールド（SFDC CreatedDate/LastModifiedDate 相当）
created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
created_by      VARCHAR(255),
updated_by      VARCHAR(255),

-- 論理削除（SFDC IsDeleted 相当）
is_deleted      BOOLEAN NOT NULL DEFAULT false,
deleted_at      TIMESTAMPTZ
```

## DDL テンプレート

```sql
-- =================================================================
-- テーブル: {table_name}
-- 元 SFDC オブジェクト: {sfdc_object_name}
-- 生成日: {date}
-- =================================================================
CREATE TABLE {table_name} (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sfdc_id         VARCHAR(18) UNIQUE,

    -- ビジネスフィールド
    {columns}

    -- 監査フィールド
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    is_deleted      BOOLEAN NOT NULL DEFAULT false
);

-- インデックス
CREATE INDEX idx_{table_name}_sfdc_id ON {table_name}(sfdc_id);
{additional_indexes}

-- コメント
COMMENT ON TABLE {table_name} IS '{sfdc_object_name} から移行';
{column_comments}
```

## データ移行チェックリスト

- [ ] 全テーブルの行数が SFDC と一致
- [ ] NOT NULL カラムに NULL データがないか事前検証
- [ ] 外部キー参照先のレコードが存在するか検証
- [ ] Picklist の値が CHECK 制約の範囲内か検証
- [ ] Date/DateTime のタイムゾーン変換が正しいか確認
- [ ] SFDC Id の 15桁→18桁変換が済んでいるか確認
- [ ] Formula / Rollup Summary フィールドの移行戦略を決定済みか

## データ移行スクリプトテンプレート

```python
"""SFDC CSV → PostgreSQL データ移行スクリプト"""
import csv
import asyncio
from sqlalchemy.ext.asyncio import AsyncSession

BATCH_SIZE = int(os.getenv("BATCH_SIZE", "1000"))

async def import_csv(
    session: AsyncSession,
    csv_path: str,
    model_class,
    field_mapping: dict[str, str],
) -> dict:
    """
    CSV ファイルからデータをバッチ INSERT する。

    Args:
        session: SQLAlchemy セッション
        csv_path: CSV ファイルパス
        model_class: SQLAlchemy モデルクラス
        field_mapping: {CSV列名: DBカラム名} のマッピング
    """
    imported = 0
    errors = []

    with open(csv_path, "r", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        batch = []

        for row in reader:
            try:
                record = {}
                for csv_col, db_col in field_mapping.items():
                    record[db_col] = transform_value(
                        row.get(csv_col), db_col
                    )
                batch.append(model_class(**record))
            except Exception as e:
                errors.append({"row": imported + len(batch), "error": str(e)})
                continue

            if len(batch) >= BATCH_SIZE:
                session.add_all(batch)
                await session.commit()
                imported += len(batch)
                batch = []

        if batch:
            session.add_all(batch)
            await session.commit()
            imported += len(batch)

    return {"imported": imported, "errors": errors}
```
